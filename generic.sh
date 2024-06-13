#!/bin/bash
sed -i 's/^PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl reload sshd
#yum install ansible -y
# yum -y upgrade
# yum -y groupinstall "Development Tools"
# sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
# sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
# sudo yum install fontconfig java-17-openjdk -y
# sudo yum install jenkins -y
# sudo systemctl start jenkins
# sudo systemctl daemon-reload