Vagrant.configure("2") do |config|
#   config.vm.synced_folder "../../sync", "/sync"
   config.vm.synced_folder ".", "/vagrant"
 #  config.vm.provision "shell", path: "generic.sh"
   config.vm.provision "ansible_local" do |ansible|
      ansible.playbook = "playbook.yml"
      ansible.install_mode = "default"
      ansible.verbose = true
      ansible.become = true
      ansible.version = "latest"
   config.vm.define :ansible do |dev|
     dev.vm.box = "generic/centos9s"
     dev.vm.hostname = "2c8.dev.com"
     dev.vm.disk :disk, size: "40GB", primary: true
     dev.vm.network "forwarded_port", guest: 22, host: 221, host_ip: "127.0.0.1"
     dev.vm.network "private_network", ip: "192.168.56.12", hostname: true
    # dev.vm.provision "shell", path: "payload.sh"
     dev.vm.provider "virtualbox" do |ansible|
        ansible.name = "Ansible dev2_c8"
        ansible.gui = false
        ansible.cpus = "2"
        ansible.memory = "4000"
	   end
   end
   end
end
