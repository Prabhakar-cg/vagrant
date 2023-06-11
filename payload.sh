#!/bin/bash
curl -fsSL https://get.docker.com -o get-docker.sh
DRY_RUN=1 sudo sh ./get-docker.sh
sudo groupadd docker
sudo usermod -aGdocker vagrant
newgrp docker
systemctl enable docker;systemctl start docker
pip install --upgrade pip wheel