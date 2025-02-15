#!/bin/bash
sed -i 's/^PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl reload sshd
yum -y upgrade
yum -y groupinstall "Development Tools"