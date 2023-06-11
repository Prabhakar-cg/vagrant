Vagrant.configure("2") do |config|
   config.vm.synced_folder "../../sync", "/sync"
   config.vm.provision "shell", path: "generic.sh"
   config.vm.define :ansible do |dev|
     dev.vm.box = "generic/centos8"
     dev.vm.hostname = "c8.dev.com"
     dev.vm.disk :disk, size: "40GB", primary: true
     dev.vm.network "forwarded_port", guest: 22, host: 22, host_ip: "127.0.0.1"
     dev.vm.network "private_network", ip: "192.168.56.11", hostname: true
     dev.vm.provision "shell", path: "payload.sh"
     dev.vm.provider "virtualbox" do |ansible|
        ansible.name = "Ansible dev_c8"
        ansible.gui = false
        ansible.cpus = "2"
        ansible.memory = "8000"
	   end
   end
end