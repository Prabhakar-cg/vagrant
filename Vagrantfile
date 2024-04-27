Vagrant.require_version ">= 2.4.1"
image      =  "generic/centos8"
cpus       =  "1"
memory     =  "1024"
gui        =  false
count      =  1

Vagrant.configure("2") do |multi|
  multi.vm.provision "shell", path: "generic.sh"
  # multi.vm.provision "ansible" do |ansible|  ##this code assumes that your vagrant host is installed with ansible
  #   ansible.playbook = "playbook.yml"
  #   compatibility_mode = "2.0"
  #   ansible.verbose = true
  # end
  
  (1..count).each do |i|
    private_ip = "192.168.56.1#{i}"
    host_name  =  "vault#{i}.vbox"
    guest_name =  "vault_ha#{i}"

    multi.vm.define "vault_#{i}" do | multi_node |
      multi_node.vm.box      = image
      multi_node.vm.hostname = host_name
      multi_node.vm.network "private_network", ip: private_ip, hostname: true

      multi_node.vm.provider "virtualbox" do | node |
        node.name    = guest_name
        node.gui     = gui
        node.cpus    = cpus
        node.memory  = memory
      end
    end
  end  
end
