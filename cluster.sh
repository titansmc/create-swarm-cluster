#!/bin/bash

# Save number of arguments
ARG=$#

function printerror {
    # Start
    echo "Usage: clushter <options>"
    echo "Options: "
    echo "       [-h | --hosts] Clush group of hosts or single hostname [ @docker:test | clust01 ]"
    echo "       [-i | --install] Define installation mode, either [ cluster | single]"
    echo "       [-u | --user] Username to connect to the cluster [test]"
    echo "       [-p | --password] Password to connect to the cluster [password]"
    echo "       [-j | --public-key] Public Key [mykey.pub]"
    echo "       [-k | --private-key] Public Key [mykey]"
    echo "       [-n | --network-name] Network name [apps]"
    echo "       [-t | --network-type] Network type [ overlay | host ....] "
    echo "       [-r | --reboot] If this option is set, installation will resume after reboot"
    echo "       [-m1 | --manager1] Docker Swarm Manager node1 [clust01]"
    echo "       [-m2 | --manager2] Docker Swarm Manager node2 [clust01]"
    echo "       [-m3 | --manager3] Docker Swarm Manager node3 [clust01]"
    echo "       [-ip | --swarmip] Docker Swarm IP of the first Manager  [192.168.10.1]"
    echo "       [-g | --registry] Docker registry address to log in"
    echo "       [-gp | --registry-passwd] Docker registry password to log in"
    echo "       [-ur | --registry-user] Docker registry user to log in"
    
    echo ""
}

# Function that copies the public ssh key into autorizhed keys
function ssh-key {
echo "--------------------------------"
echo "Copies ssh-keys"
echo "--------------------------------"
	for i in $(nodeset --expand $1)
	do
	    ssh-copy-id -oStrictHostKeyChecking=no -i $KEYPUB $USRSRV@$i
	done
}

# Function that modifies sudoers to allow 'user' to sudo without passwd
function sudoers {
echo "--------------------------------"
echo "Modify sudoers"
echo "--------------------------------"
	#clush -w $1 "echo $PASS | sudo -S /bin/bash -c 'cp /etc/sudoers /etc/sudoers.tmp'"
	#clush -w $1 "echo $PASS | sudo -S /bin/bash -c 'chmod 777 /etc/sudoers.tmp'"
	#clush -w $1 "echo $PASS | sudo -S /bin/bash -c ' echo -e \"deploy ALL=(ALL) NOPASSWD: ALL\"" >> /etc/sudoers.tmp"
	#clush -w $1 "echo $PASS | sudo -S /bin/bash -c 'chmod 440 /etc/sudoers.tmp'"
	#clush -w $1 "echo $PASS | sudo -S /bin/bash -c 'mv /etc/sudoers.tmp /etc/sudoers'"
}

# Function that sets the correct timezone
function timezone {
echo "--------------------------------"
echo "Set the timezone properly"
echo "--------------------------------"
	clush -w $1 'sudo timedatectl set-timezone Europe/Madrid'
}


# Disable IP v6
function ipv6dis {
echo "--------------------------------"
echo "Disable IP v6"
echo "--------------------------------"

	clush -w $1 'echo -e "net.ipv6.conf.all.disable_ipv6 = 1 \nnet.ipv6.conf.default.disable_ipv6 = 1 \nnet.ipv6.conf.lo.disable_ipv6 = 1 \nvm.max_map_count=262144" | sudo tee --append /etc/sysctl.conf'
}

# Installs NTP
function installNTP {
echo "--------------------------------"
echo "Installs NTPdate"
echo "--------------------------------"
	clush -w $1 'sudo apt-get install -y ntpdate'
}

# Generate locales
function locales {
echo "--------------------------------"
echo "Configure locales"
echo "--------------------------------"
	clush -w $1 'sudo locale-gen es_ES.UTF-8'
}

# Update apt cache
function update {
echo "--------------------------------"
echo "Update OS"
echo "--------------------------------"
	clush -w $1 'sudo apt-get update'
}
# Upgrade nodes
function upgrade {
echo "--------------------------------"
echo "Upgrade OS"
echo "--------------------------------"
# Quan cridem aquesta funció hem de veure com manejem el reboot

	clush -w $1 'sudo dpkg --configure -a'
	clush -w $1 'sudo apt -y autoremove'
	clush -w $1 'sudo DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade'
	clush -w $1 'sudo uname -a'
}

function reboot-now {
echo "--------------------------------"
echo "Function that reboots de sistem"
echo "--------------------------------"
	clush -w $1 'sudo reboot'
	echo "Waitting 30 seconds to make sure reboot is in progress"
	sleep 30
}

# Docker installation
function dockerinstall {
echo "--------------------------------"
echo "Docker installation"
echo "--------------------------------"
	clush -w $1 'sudo apt-get install -y curl linux-image-extra-$(uname -r) linux-image-extra-virtual apt-transport-https ca-certificates'
	clush -w $1 'curl -fsSL https://get.docker.com/ | sh'
}

# Swarm creation
function swarmcreate {
echo "--------------------------------"
echo "Swarm creation"
echo "--------------------------------"
	clush -w $MANAGER1 "sudo docker swarm init --advertise-addr $SWARMIP"
}

# Get Token Worker - We still need to | awk '{ print $3; }' because it has output from clush
function getTokenWorker {
echo "--------------------------------"
echo "Get Token Worker"
echo "--------------------------------"
	TOKEN_WORKER=$(clush -w $MANAGER1 "sudo docker swarm join-token worker | grep '\-\-token'" | awk '{ print $3}')
}

# Get Token Manager - We still need to | awk '{ print $3; }' because it has output from clush
function getTokenManager {
echo "--------------------------------"
echo "Get Token Manager"
echo "--------------------------------"
        TOKEN_MANAGER=$(clush -w $MANAGER1 "sudo docker swarm join-token manager | grep '\-\-token'" | awk '{ print $3}')
}

# Join nodes to cluster
function joinWorker {
echo "--------------------------------"
echo "Join Workers"
echo "--------------------------------"
	clush -w $1 "sudo docker swarm join --token ${TOKEN_WORKER} $SWARMIP:2377" 	
}

# Promote nodes to master
function promote {
echo "--------------------------------"
echo "Promote workers to master"
echo "--------------------------------"
	clush -w $MANAGER1 "sudo docker node promote $MANAGER2"
	clush -w $MANAGER1 "sudo docker node promote $MANAGER3"
}


# Print status of the cluster
function printCluster {
echo "--------------------------------"
echo "Print cluster information"
echo "--------------------------------"
	clush -w $MANAGER1 "sudo docker node ls"
}

# Create the first network
function createNet {
echo "--------------------------------"
echo "Create net docker"
echo "--------------------------------"
	clush -w $MANAGER1 "sudo docker network create -d $NETTYPE $NETNAME"
}

# Wait until reboot completed
function reboot-servers {
echo "--------------------------------"
echo "Active waiting for servers to reboot"
echo "--------------------------------"
	STATUS=255
	#clush -w $1 "hostname" | awk '{ print $1}' | sed 's/.$//' > hosts.tmp
	echo "We are going to wait for the servers to be rebooted"
	while [ $STATUS != 0 ]
	do
	    for i in $(nodeset --expand $1)
	    do
		ssh $i exit
		a=$?
		if [ $a != 0 ]; then
		  STATUS=255
		else
		  STATUS=0
		fi

            done
	
	    sleep 10
	    echo "" 
	    echo "One more loop"
	    echo "" 
	done

	echo "" 
	echo "We are able to ssh into all the nodes, we go ahead....."
	echo "" 
}

# Add user to docker group
function adduser {
echo "--------------------------------"
echo "Add user to docker group"
echo "--------------------------------"
	clush -w $1 "sudo usermod -a -G docker deploy"
}

# Log in to Registry
function registry {
echo "--------------------------------"
echo "Login to registry"
echo "--------------------------------"
	clush -w $1 "sudo docker login -u $REGISTRYUSR -p $REGISTRYPWD $REGISTRY"
}
##########################
# Here the program starts#
##########################



# Do the requirements
while [[ $# -gt 1 ]]
do
key="$1"

case $key in
    -h|--hosts)
    HOSTS="$2"
    shift # past argument
    ;;
    -i|--install)
    INSTALL="$2"
    shift # past argument
    ;;
    -u|--user)
    USRSRV="$2"
    shift # past argument
    ;;
    -p|--password)
    PASS="$2"
    shift # past argument
    ;;
    -k|--private-key)
    KEYPRIV="$2"
    shift # past argument
    ;;
    -j|--public-key)
    KEYPUB="$2"
    shift # past argument
    ;;
    -n|--network)
    NETNAME="$2"
    shift # past argument
    ;;
    -t|--network-type)
    NETTYPE="$2"
    shift # past argument
    ;;
    -m1|--manager1)
    MANAGER1="$2"
    shift # past argument
    ;;
    -m2|--manager2)
    MANAGER2="$2"
    shift # past argument
    ;;
    -m3|--manager3)
    MANAGER3="$2"
    shift # past argument
    ;;
    -ip|--swarmip)
    SWARMIP="$2"
    shift # past argument
    ;;
    -g|--registry)
    REGISTRY="$2"
    shift # past argument
    ;;
    -gp|--registry-passwd)
    REGISTRYPWD="$2"
    shift # past argument
    ;;
    -ur|--registry-user)
    REGISTRYUSR="$2"
    shift # past argument
    ;;
    -r|--reboot)
    REBOOT="NO"
    shift # past argument
    ;;
    *)
            # unknown option
esac
shift # past argument or value
done

echo " $INSTALL node "
if [[ "$INSTALL" == "cluster" ]]
then
    # Ensure that has the needed arguments
    if [[ $ARG -eq 29 ]] && [[ "$REBOOT" == "YES" ]]
    then
      echo ""
      echo "Install 29 arg i reboot yes"
      echo "We go ahead"
    elif [[ $ARG -eq 28 ]] && [[ "$REBOOT" == "" ]]
    then
      echo ""
      echo "We go ahead installing a cluster."
    
    else
      printerror
      echo " $ARG arguments "
      echo " $REBOOT reboot "
      echo "Please, execute clushter with all the mandatory arguments"
      exit 0
    fi
elif [[ $INSTALL -eq "node" ]]
then
    if [[ $ARG -eq 22 ]]
    then
      echo ""
      echo "We go ahead installing nodes."
    else
      printerror
      echo " $ARG arguments "
      echo "Please, execute clushter with all the mandatory arguments"
      exit 0
    fi    
fi

# This if will proceed when set hostname as the whole cluster

if [[ $REBOOT != 'YES' ]]
then
    ssh-key $HOSTS
    sudoers $HOSTS
    timezone $HOSTS
    ipv6dis $HOSTS
    installNTP $HOSTS
    locales $HOSTS
    update $HOSTS
    upgrade $HOSTS
    reboot-now $HOSTS
    reboot-servers $HOSTS
fi

# If user has input clush group of servers, something like: @dock-cluster   
if  [[ $HOSTS == @* ]] && [[ $INSTALL == "cluster" ]] 
then
  # We are going to build the cluster
  dockerinstall $HOSTS  
  adduser $HOSTS
  swarmcreate 
  createNet
  getTokenWorker
  getTokenManager
  joinWorker $HOSTS
  promote
  registry $HOSTS
  reboot-now $HOSTS
  reboot-servers $HOSTS
  printCluster
fi

if  [[ $INSTALL == "node" ]]
then
  # We are going to add nodes to the cluster
  dockerinstall $HOSTS
  adduser $HOSTS
  getTokenWorker
  joinWorker $HOSTS
  registry $HOSTS
  reboot-now $HOSTS
  reboot-servers $HOSTS 
  printCluster
fi
