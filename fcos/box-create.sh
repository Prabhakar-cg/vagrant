#!/usr/bin/env bash
# Creates a VirtualBox Vagrant box from the latest Fedora CoreOS QEMU image.
# Inspired by https://github.com/basvdlei/fedora-coreos-vagrant-box-builder
#
# Dependencies (WSL2 Ubuntu):
#   sudo apt-get install -y curl jq xz-utils qemu-utils
#   No coreos-installer, podman, or docker required.
#
# Usage:
#   ./box-create.sh
#   STREAM=next ./box-create.sh
#   BOX_NAME=fcos/custom ./box-create.sh
set -euo pipefail

STREAM="${STREAM:-stable}"
ARCH="${ARCH:-x86_64}"
BOX_NAME="${BOX_NAME:-fedora/coreos-stable}"

WORK_DIR=$(mktemp -d)   # small files only: ignition.json, OVF, metadata
LOOP=""
MOUNT_DIR=""

cleanup() {
  [[ -n "${MOUNT_DIR}" ]] && { sudo umount "${MOUNT_DIR}" 2>/dev/null; sudo rmdir "${MOUNT_DIR}" 2>/dev/null; } || true
  [[ -n "${LOOP}" ]] && sudo losetup -d "${LOOP}" 2>/dev/null || true
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

# ── 1. Resolve latest version ────────────────────────────────────────────────

VERSION=$(curl -fsSL \
  "https://builds.coreos.fedoraproject.org/prod/streams/${STREAM}/builds/builds.json" | \
  jq -r --arg arch "${ARCH}" \
    'first(.builds[] | select(.arches[] | contains($arch))) | .id')

echo "==> FCOS ${STREAM} ${VERSION} (${ARCH})"

QCOW2_XZ="fedora-coreos-${VERSION}-qemu.${ARCH}.qcow2.xz"
QCOW2="${QCOW2_XZ%.xz}"
RAW="fedora-coreos-${VERSION}.raw"
URL="https://builds.coreos.fedoraproject.org/prod/streams/${STREAM}/builds/${VERSION}/${ARCH}/${QCOW2_XZ}"

# ── 2. Ignition config: inject Vagrant insecure public key ───────────────────

VAGRANT_KEY=$(curl -fsSL \
  "https://raw.githubusercontent.com/hashicorp/vagrant/main/keys/vagrant.pub")

cat > "${WORK_DIR}/ignition.json" <<IGNEOF
{
  "ignition": { "version": "3.4.0" },
  "passwd": {
    "users": [{
      "name": "core",
      "sshAuthorizedKeys": ["${VAGRANT_KEY}"]
    }]
  }
}
IGNEOF

# ── 3. Download and decompress the FCOS QEMU image ───────────────────────────

if [[ -f "${QCOW2}" ]]; then
  echo "==> Using cached ${QCOW2}"
else
  echo "==> Downloading FCOS QEMU image (~800 MB compressed)..."
  # -C - resumes a partial download automatically (safe to re-run after Ctrl+C)
  curl -fL -C - --progress-bar -o "${QCOW2_XZ}" "${URL}"
  echo "==> Decompressing..."
  xz -dk "${QCOW2_XZ}"
fi

# ── 4. Convert qcow2 → raw so loopback partitions are visible ────────────────

if [[ ! -f "${RAW}" ]]; then
  echo "==> Converting qcow2 → raw (needs ~4 GB free space in $(pwd))..."
  qemu-img convert -f qcow2 -O raw "${QCOW2}" "${RAW}"
fi

# ── 5. Inject Ignition config without mounting XFS ───────────────────────────
# WSL2's kernel lacks the XFS module, so we cannot mount the boot partition.
# Instead:
#   a) grep -a reads BLS entry lines as text straight from the raw block device
#      (small XFS files are contiguous on disk, so grep -a reliably finds them)
#   b) We write a static grub.cfg onto the EFI partition (FAT32, always mountable)
#      that overrides the BLS autoloader with our patched kernel cmdline.

LOOP=$(sudo losetup --find --show --partscan "${RAW}")
echo "==> Loop device: ${LOOP}"

BOOT_PART=$(sudo blkid "${LOOP}p"* 2>/dev/null \
  | awk -F: '$0 ~ /LABEL="boot"/ {print $1; exit}')
EFI_PART=$(sudo blkid "${LOOP}p"* 2>/dev/null \
  | awk -F: '$0 ~ /TYPE="vfat"/ {print $1; exit}')

[[ -z "${BOOT_PART}" ]] && { echo "ERROR: LABEL=boot partition not found on ${LOOP}"; exit 1; }
[[ -z "${EFI_PART}"  ]] && { echo "ERROR: EFI (vfat) partition not found on ${LOOP}"; exit 1; }

echo "==> Boot partition: ${BOOT_PART}"
echo "==> EFI  partition: ${EFI_PART}"

# Pull the three relevant lines from the BLS entry on the XFS partition.
# grep -a treats the raw block device as text; small XFS files are stored
# contiguously so every line of the entry is found in a single pass.
BLS_LINUX=$(  sudo grep -am1 "^linux "                       "${BOOT_PART}" | tr -d '\r')
BLS_INITRD=$( sudo grep -am1 "^initrd "                      "${BOOT_PART}" | tr -d '\r')
BLS_OPTIONS=$(sudo grep -am1 "^options.*ignition\.platform"  "${BOOT_PART}" | tr -d '\r')

[[ -z "${BLS_LINUX}"   ]] && { echo "ERROR: 'linux' line not found in ${BOOT_PART}";   exit 1; }
[[ -z "${BLS_INITRD}"  ]] && { echo "ERROR: 'initrd' line not found in ${BOOT_PART}";  exit 1; }
[[ -z "${BLS_OPTIONS}" ]] && { echo "ERROR: 'options' line not found in ${BOOT_PART}"; exit 1; }

echo "==> Kernel : $(echo "${BLS_LINUX}"  | awk '{print $2}')"
echo "==> Initrd : $(echo "${BLS_INITRD}" | awk '{print $2}')"

# Build the patched cmdline:
#   • swap ignition.platform.id=qemu → metal (VirtualBox has no QEMU fw_cfg)
#   • embed Ignition JSON as an inline data: URI
#   NOTE: IGN_URL is kept separate and quoted in grub.cfg because GRUB treats
#   ';' as a command separator — quoting the value prevents the split at
#   the ';' between "text/plain" and "base64,...".
IGN_B64=$(base64 -w0 "${WORK_DIR}/ignition.json")
IGN_URL="ignition.config.url=data:text/plain;base64,${IGN_B64}"
REST_CMDLINE="${BLS_OPTIONS#options }"
REST_CMDLINE="${REST_CMDLINE/ignition.platform.id=qemu/ignition.platform.id=metal}"

KERNEL_PATH="${BLS_LINUX#linux }"
INITRD_PATH="${BLS_INITRD#initrd }"

# Overwrite grub.cfg on the EFI (FAT32) partition with a static menu entry.
# GRUB has its own built-in XFS driver so ($root) resolves correctly to the
# "boot"-labelled XFS partition at runtime — no kernel XFS module needed here.
MOUNT_DIR=$(mktemp -d)
sudo mount -t vfat "${EFI_PART}" "${MOUNT_DIR}"

sudo tee "${MOUNT_DIR}/EFI/fedora/grub.cfg" > /dev/null <<GRUBEOF
search --no-floppy --label --set=root boot
set timeout=0
set default=0
menuentry "Fedora CoreOS" {
    linux (\$root)${KERNEL_PATH} "${IGN_URL}" ${REST_CMDLINE}
    initrd (\$root)${INITRD_PATH}
}
GRUBEOF

echo "==> Patched EFI grub.cfg (Ignition config: $(wc -c < "${WORK_DIR}/ignition.json") bytes inline)."

sudo umount "${MOUNT_DIR}"
sudo rmdir  "${MOUNT_DIR}"
MOUNT_DIR=""

sudo losetup -d "${LOOP}"
LOOP=""

# ── 6. Convert raw → VMDK (streamOptimized, VirtualBox-compatible) ───────────

echo "==> Converting raw → VMDK..."
qemu-img convert -f raw -O vmdk -o subformat=streamOptimized \
  "${RAW}" "${WORK_DIR}/box.vmdk"

DISK_CAPACITY=$(qemu-img info --output json "${RAW}" | jq '.["virtual-size"]')

rm -f "${RAW}"   # raw is large (~4 GB); vmdk is the keeper

# ── 7. Create OVF descriptor ─────────────────────────────────────────────────

echo "==> Writing OVF descriptor..."
cat > "${WORK_DIR}/box.ovf" <<OVFEOF
<?xml version="1.0"?>
<Envelope
    xmlns="http://schemas.dmtf.org/ovf/envelope/1"
    xmlns:cim="http://schemas.dmtf.org/wbem/wscim/1/common"
    xmlns:ovf="http://schemas.dmtf.org/ovf/envelope/1"
    xmlns:rasd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData"
    xmlns:vbox="http://www.virtualbox.org/ovf/machine"
    xmlns:vssd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_VirtualSystemSettingData"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <References>
    <File ovf:id="file1" ovf:href="box.vmdk"/>
  </References>
  <DiskSection>
    <Info>List of the virtual disks used in the package</Info>
    <Disk
        ovf:capacity="${DISK_CAPACITY}"
        ovf:diskId="vmdisk1"
        ovf:fileRef="file1"
        ovf:format="http://www.vmware.com/interfaces/specifications/vmdk.html#streamOptimized"/>
  </DiskSection>
  <NetworkSection>
    <Info>Logical networks used in the package</Info>
    <Network ovf:name="NAT">
      <Description>NAT network adapter on eth0</Description>
    </Network>
  </NetworkSection>
  <VirtualSystem ovf:id="fedora-coreos">
    <Info>Fedora CoreOS ${VERSION}</Info>
    <OperatingSystemSection ovf:id="101">
      <Info>The kind of installed guest operating system</Info>
      <Description>Fedora_64</Description>
      <vbox:OSType ovf:required="false">Fedora_64</vbox:OSType>
    </OperatingSystemSection>
    <VirtualHardwareSection>
      <Info>Virtual hardware requirements</Info>
      <System>
        <vssd:ElementName>Virtual Hardware Family</vssd:ElementName>
        <vssd:InstanceID>0</vssd:InstanceID>
        <vssd:VirtualSystemIdentifier>fedora-coreos</vssd:VirtualSystemIdentifier>
        <vssd:VirtualSystemType>virtualbox-2.2</vssd:VirtualSystemType>
      </System>
      <Item>
        <rasd:Caption>2 virtual CPUs</rasd:Caption>
        <rasd:Description>Number of virtual CPUs</rasd:Description>
        <rasd:ElementName>2 virtual CPUs</rasd:ElementName>
        <rasd:InstanceID>1</rasd:InstanceID>
        <rasd:ResourceType>3</rasd:ResourceType>
        <rasd:VirtualQuantity>2</rasd:VirtualQuantity>
      </Item>
      <Item>
        <rasd:AllocationUnits>MegaBytes</rasd:AllocationUnits>
        <rasd:Caption>2048 MB of memory</rasd:Caption>
        <rasd:Description>Memory Size</rasd:Description>
        <rasd:ElementName>2048 MB of memory</rasd:ElementName>
        <rasd:InstanceID>2</rasd:InstanceID>
        <rasd:ResourceType>4</rasd:ResourceType>
        <rasd:VirtualQuantity>2048</rasd:VirtualQuantity>
      </Item>
      <Item>
        <rasd:Caption>AHCI</rasd:Caption>
        <rasd:Description>SATA Controller</rasd:Description>
        <rasd:ElementName>AHCI</rasd:ElementName>
        <rasd:InstanceID>3</rasd:InstanceID>
        <rasd:ResourceSubType>AHCI</rasd:ResourceSubType>
        <rasd:ResourceType>20</rasd:ResourceType>
      </Item>
      <Item>
        <rasd:AddressOnParent>0</rasd:AddressOnParent>
        <rasd:Caption>disk1</rasd:Caption>
        <rasd:Description>Disk Image</rasd:Description>
        <rasd:ElementName>disk1</rasd:ElementName>
        <rasd:HostResource>ovf:/disk/vmdisk1</rasd:HostResource>
        <rasd:InstanceID>4</rasd:InstanceID>
        <rasd:Parent>3</rasd:Parent>
        <rasd:ResourceType>17</rasd:ResourceType>
      </Item>
      <Item>
        <rasd:AutomaticAllocation>true</rasd:AutomaticAllocation>
        <rasd:Caption>Ethernet adapter on 'NAT'</rasd:Caption>
        <rasd:Connection>NAT</rasd:Connection>
        <rasd:ElementName>Ethernet adapter on 'NAT'</rasd:ElementName>
        <rasd:InstanceID>5</rasd:InstanceID>
        <rasd:ResourceSubType>E1000</rasd:ResourceSubType>
        <rasd:ResourceType>10</rasd:ResourceType>
      </Item>
    </VirtualHardwareSection>
  </VirtualSystem>
</Envelope>
OVFEOF

# ── 8. Create box metadata and embedded Vagrantfile ──────────────────────────

echo '{"provider":"virtualbox"}' > "${WORK_DIR}/metadata.json"

cat > "${WORK_DIR}/Vagrantfile" <<'VAGEOF'
Vagrant.configure("2") do |config|
  config.ssh.insert_key = false
  config.ssh.username   = "core"
  config.vm.synced_folder ".", "/vagrant", disabled: true
end
VAGEOF

# ── 9. Package and register with Vagrant ─────────────────────────────────────

BOX_FILE="fedora-coreos-${VERSION}-virtualbox.box"
echo "==> Packaging ${BOX_FILE}..."
tar -czf "${BOX_FILE}" -C "${WORK_DIR}" box.vmdk box.ovf metadata.json Vagrantfile

echo "==> Adding box '${BOX_NAME}' to Vagrant..."
vagrant box add --name "${BOX_NAME}" --force "${BOX_FILE}"

rm -f "${BOX_FILE}"
echo ""
echo "==> Done. Box '${BOX_NAME}' is ready."
echo "    Cached image: ${QCOW2} (safe to delete to free ~4 GB)"
echo "    Next step:    vagrant up"
