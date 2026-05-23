#!/usr/bin/env bash
# Basic FCOS provisioner: enable password auth so OKD tooling can reach the host.
set -euo pipefail

# Append sshd override — /etc is writable on FCOS
cat >> /etc/ssh/sshd_config <<'EOF'

# Vagrant provisioner: enable password auth for OKD installer access
PasswordAuthentication yes
EOF

systemctl reload sshd

# Set a known password for the core user
echo 'core:vagrant' | chpasswd
