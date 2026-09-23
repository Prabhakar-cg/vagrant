#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
# Ubuntu cloud images ship a drop-in that disables password auth and is
# included before the rest of sshd_config, so it wins over the line above
# unless it's patched too.
sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config.d/*.conf 2>/dev/null
echo "vagrant:vagrant" | chpasswd
systemctl restart ssh
# apt-get update
# apt-get -y upgrade
apt-get -y install build-essential
