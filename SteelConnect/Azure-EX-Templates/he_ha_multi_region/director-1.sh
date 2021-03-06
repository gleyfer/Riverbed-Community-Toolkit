#!/bin/bash
log_path="/etc/bootLog.txt"
if [ -f "$log_path" ]
then
    echo "Cloud Init script already ran earlier during first time boot.." >> $log_path
else
    touch $log_path
SSHKey="${sshkey}"
KeyDir="/home/Administrator/.ssh"
KeyFile="/home/Administrator/.ssh/authorized_keys"
Address="Match Address"
SSH_Conf="/etc/ssh/sshd_config"
echo "Starting cloud init script...." > $log_path

echo "Modifying /etc/network/interface file.." >> $log_path
cp /etc/network/interfaces /etc/network/interfaces.bak
cat > /etc/network/interfaces << EOF
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
auto eth0
iface eth0 inet dhcp

# The secondary network interface
auto eth1
iface eth1 inet dhcp
post-up ip route add ${ctrl_master_net} via ${south_master_gw} dev eth1
post-up ip route add ${ctrl_slave_net} via ${south_master_gw} dev eth1
post-up ip route add ${south_slave_net} via ${south_master_gw} dev eth1
post-up ip route add ${overlay_net} via ${router1_dir_ip} dev eth1

EOF
echo -e "Modified /etc/network/interface file. Refer below new interface file content:\n`cat /etc/network/interfaces`" >> $log_path

echo "Modifying /etc/hosts file.." >> $log_path
cp /etc/hosts /etc/hosts.bak
cat > /etc/hosts << EOF
127.0.0.1	localhost
${dir_master_mgmt_ip}	${hostname_dir_master}
${dir_slave_mgmt_ip}	${hostname_dir_slave}
%{ for host, ip in analytics_host_map ~}
${ip}	${host}
%{ endfor ~}
%{ for host, ip in forwarder_host_map ~}
${ip}	${host}
%{ endfor ~}

# The following lines are desirable for IPv6 capable hosts cloudeinit
::1localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF
echo -e "Modified /etc/hosts file. Refer below new hosts file content:\n`cat /etc/hosts`" >> $log_path

echo "Modifying /etc/hostname file.." >> $log_path
hostname ${hostname_dir_master}
cp /etc/hostname /etc/hostname.bak
cat > /etc/hostname << EOF
${hostname_dir_master}
EOF
echo "Hostname modified to : `hostname`" >> $log_path

echo -e "Injecting ssh key into Administrator user.\n" >> $log_path
if [ ! -d "$KeyDir" ]; then
	echo -e "Creating the .ssh directory and injecting the SSH Key.\n" >> $log_path
	sudo mkdir $KeyDir
	sudo echo $SSHKey >> $KeyFile
	sudo chown Administrator:versa $KeyDir
	sudo chown Administrator:versa $KeyFile
	sudo chmod 600 $KeyFile
elif ! grep -Fq "$SSHKey" $KeyFile; then
	echo -e "Key not found. Injecting the SSH Key.\n" >> $log_path
	sudo echo $SSHKey >> $KeyFile
	sudo chown Administrator:versa $KeyDir
	sudo chown Administrator:versa $KeyFile
	sudo chmod 600 $KeyFile
else
	echo -e "SSH Key already present in file: $KeyFile.." >> $log_path
fi

echo -e "Enabling ssh login using password." >> $log_path
if ! grep -Fq "$Address" $SSH_Conf; then
	echo -e "Adding the match address exception for Analytics Management IP to install certificate.\n" >> $log_path
	%{ for ip in analytics_host_map }
	sed -i.bak "\$a\Match Address ${ip}\n  PasswordAuthentication yes\n" $SSH_Conf
	%{ endfor }
	sed -i.bak "\$a\Match all" $SSH_Conf
	sudo service ssh restart
else
	echo -e "Analytics Management IP address is alredy present in file $SSH_Conf.\n" >> $log_path
fi

echo -e "Generating director self signed certififcates. Refer detail below:\n" >> $log_path
sudo rm -rf /var/versa/vnms/data/certs/
sudo -u versa /opt/versa/vnms/scripts/vnms-certgen.sh --cn ${hostname_dir_master} --san ${hostname_dir_slave} --storepass versa123 >> $log_path
sudo chown -R versa:versa /var/versa/vnms/data/certs/

echo "Adding north bond and south bond interface in setup.json file.." >> $log_path
cat > /opt/versa/etc/setup.json << EOF
{
	"input":{
		"version": "1.0",
		"south-bound-interface":[
		  "eth1"
		],
		"hostname": "${hostname_dir_master}"
	 }
}
EOF
echo -e "Got below data from setup.json file:\n `cat /opt/versa/etc/setup.json`" >> $log_path
echo "Executing the startup script in non interactive mode.." >> $log_path
sudo -u Administrator /opt/versa/vnms/scripts/vnms-startup.sh --non-interactive
fi
