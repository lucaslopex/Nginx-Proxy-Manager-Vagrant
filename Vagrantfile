$script_docker = <<-SCRIPT
sudo apt-get update -y && \
sudo apt-get install ca-certificates curl gnupg lsb-release -y && \
sudo apt-get remove docker docker-engine docker.io containerd runc && \
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-compose -y && \
docker version >> /vagrant/docker-version.txt
SCRIPT


$script_gpgdocker = <<-SCRIPT
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
SCRIPT

$script_echodocker = <<-SCRIPT
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
SCRIPT

$script_build_nginx = <<-SCRIPT
cd /opt/nginxproxymanager/
docker-compose up -d
SCRIPT

Vagrant.configure("2") do |config|
config.vm.box = "ubuntu/focal64"

config.vm.define "srvdocker" do |srvdocker|
 #IP da rede externa
 srvdocker.vm.network "public_network", ip: "10.0.17.70"
 #Instalacao do docker
 srvdocker.vm.provision "shell", inline: "sudo cp /vagrant/archive/docker-install.sh /opt/"
 srvdocker.vm.provision "shell", inline: "sudo chmod +x /opt/docker-install.sh"
 #Instalacao do certificado
 #srvdocker.vm.provision "shell", inline: "cat /vagrant/archive/ubuntu.pub >> .ssh/authorized_keys"
 #Instalacao do NGINX Manager
 srvdocker.vm.provision "shell", inline: "mkdir /opt/nginxproxymanager"
 srvdocker.vm.provision "shell", inline: "cp /vagrant/archive/docker-compose.yaml /opt/nginxproxymanager/"
 #Rodar script da instalação do docker
 srvdocker.vm.provision "shell", inline: $script_echodocker
 srvdocker.vm.provision "shell", inline: $script_gpgdocker
 srvdocker.vm.provision "shell", inline: $script_docker
 srvdocker.vm.provision "shell", inline: $script_build_nginx
#Liberacao de portas
 srvdocker.vm.network "forwarded_port", guest: 80, host: 80
 srvdocker.vm.network "forwarded_port", guest: 81, host: 81
 srvdocker.vm.network "forwarded_port", guest: 443, host: 443
end
end