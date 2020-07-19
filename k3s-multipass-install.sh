#!/bin/bash

# -------------------------------------------------------------------------------------
# Script: k3s-multipass-install.sh
# Highly functional K3s lab for Linux or macOS via Ubuntu Multipass
#
# Usage:
# ./k3s-multipass-install.sh -w <num_agents> -c <num_cpus> -m <mem_size -d <disk_size>
#
# Example:
# ./k3s-multipass-install.sh -w 3 -c 2 -m 4096 -d 20
#
# ToDo: Error handling, support for advanced server and agent customizations
#
# Governed under the MIT license. 
# -------------------------------------------------------------------------------------

while getopts w:c:m:d: flag; do
  case "${flag}" in
    w) NUM_agentS=${OPTARG};;
    c) NUM_CPUS=${OPTARG};;
    m) MEM_SIZE=${OPTARG};;
    d) DISK_SIZE=${OPTARG};;
  esac
done

provision_agents () {
    COUNTER=1
    until [ $COUNTER -eq $NUM_agentS ]; do
      multipass launch focal --name k3s-agent-$COUNTER --cpus $NUM_CPUS --mem ${MEM_SIZE}M --disk ${DISK_SIZE}G
      let COUNTER+=1
    done
}

install_k3s_agents () {
    COUNTER=1
    until [ $COUNTER -eq $NUM_agentS ]; do
      echo && multipass exec k3s-agent-$COUNTER \
        -- /bin/bash -c "curl -sfL https://get.k3s.io | K3S_TOKEN=${K3S_TOKEN} K3S_URL=${K3S_NODEIP_SERVER} sh -"
      let COUNTER+=1
    done
}

# Provision nodes for K3s server, Rancher management server, and Minio object storage
echo "Lauching K3s lab nodes..."
multipass launch focal --name k3s-server --cpus 2 --mem 4096M --disk 20G
multipass launch focal --name rancher --cpus 2 --mem 4096M --disk 20G
multipass launch focal --name minio --cpus 1 --mem 2048M --disk 25G

# Provision nodes for K3s agent nodes
provision_agents

# K3s Installation
# Note: This script installs a dynamically-defined cluster with the following attributes:
#       - Single-server (non-HA)
#       - sqlite DB backend (via Kine, also non-HA)
#       - Flannel CNI with default configuration (VXLAN backend)


# Deploy K3s on Server node
echo && echo "Deploying latest release of K3s on the Server node..."
multipass exec k3s-server -- /bin/bash -c "curl -sfL https://get.k3s.io | K3S_KUBECONFIG_MODE="644" sh -"

# Prep for deployment on agents
echo && echo "Retrieving information preparatory to deploying K3s to the agent nodes..."
K3S_NODEIP_SERVER="https://$(multipass info k3s-server | grep "IPv4" | awk -F' ' '{print $2}'):6443"
echo "  k3s-server IP is: " $K3S_NODEIP_server
K3S_TOKEN="$(multipass exec k3s-server -- /bin/bash -c "sudo cat /var/lib/rancher/k3s/server/node-token")"
echo "  Join token for this K3s cluster is: " $K3S_TOKEN

# Deploy K3s on agent nodes
echo && echo "Deploying K3s on the agent nodes..."
install_k3s_agents

# Check cluster status
echo && echo "Verifying cluster status..."
sleep 20  # Give enough time for agend nodes to become ready
multipass exec k3s kubectl get nodes -o wide

# Install Rancher
echo && echo "Installing Rancher Server..."
multipass exec rancher -- /bin/bash -c "sudo apt-get update && sudo apt-get install -y docker.io"
multipass exec rancher -- /bin/bash -c "sudo systemctl enable docker"
multipass exec rancher -- /bin/bash -c "sudo docker run -d --restart=unless-stopped -p 80:80 -p 443:443 --name rancher -v /opt/rancher:/var/lib/rancher rancher/rancher"

# Install Minio
echo && echo "Installing Minio Object Storage server..."
multipass exec minio -- /bin/bash -c "sudo apt-get update && sudo apt-get install -y docker.io"
multipass exec minio -- /bin/bash -c "sudo systemctl enable docker"
multipass exec minio -- /bin/bash -c "sudo docker run -d --restart=unless-stopped -p 9000:9000 --name minio -v /mnt/data:/data minio/minio server /data"