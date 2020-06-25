#!/bin/bash

# -------------------------------------------------------------------------------------
# Script: k3s-multipass-install.sh
# Author: David Williams (david.williams@thinkahead.com)
#
# Highly functional K3s lab for Linux or macOS via Ubuntu Multipass
#
# Usage:
# ./k3s-multipass-install.sh -w <num_workers> -c <num_cpus> -m <mem_size -d <disk_size>
#
# Example:
# ./k3s-multipass-install.sh -w 3 -c 2 -m 4096 -d 20
#
# ToDo: Error handling
#
# Governed under the MIT license. 
# -------------------------------------------------------------------------------------

while getopts w:c:m:d: flag; do
  case "${flag}" in
    w) NUM_WORKERS=${OPTARG};;
    c) NUM_CPUS=${OPTARG};;
    m) MEM_SIZE=${OPTARG};;
    d) DISK_SIZE=${OPTARG};;
  esac
done

deploy_workers () {
    COUNTER=1
    until [ $COUNTER -eq $NUM_WORKERS ]; do
      multipass launch --name k3s-worker-$COUNTER --cpus $NUM_CPUS --mem ${MEM_SIZE}M --disk ${DISK_SIZE}G
      let COUNTER+=1
    done
}

install_k3s_workers () {
    COUNTER=1
    until [ $COUNTER -eq $NUM_WORKERS ]; do
      echo && multipass exec k3s-worker-$COUNTER \
        -- /bin/bash -c "curl -sfL https://get.k3s.io | K3S_TOKEN=${K3S_TOKEN} K3S_URL=${K3S_NODEIP_manager} sh -"
      let COUNTER+=1
    done
}

# Deploy K3s manager and two K3s Workers nodes
echo "Lauching K3s lab nodes..."
multipass launch --name k3s-manager --cpus 2 --mem 4096M --disk 20G
deploy_workers
multipass launch --name rancher --cpus 2 --mem 4096M --disk 5G
multipass launch --name minio --cpus 1 --mem 2048M --disk 25G


# K3s Installation
# Note: This script installs a statically defined three-node cluster with the following attributes:
#       - Single-manager, two workers
#       - sqlite DB backend (via Kine)

# Deploy K3s on Manager node
echo && echo "Deploying latest release of K3s on the Manager node..."
multipass exec k3s-manager -- /bin/bash -c "curl -sfL https://get.k3s.io | K3S_KUBECONFIG_MODE="644" sh -"

# Prep for deployment on Workers
echo && echo "Retrieving information preparatory to deploying K3s to the Worker nodes..."
K3S_NODEIP_manager="https://$(multipass info k3s-manager | grep "IPv4" | awk -F' ' '{print $2}'):6443"
echo "  k3s-manager IP is: " $K3S_NODEIP_manager
K3S_TOKEN="$(multipass exec k3s-manager -- /bin/bash -c "sudo cat /var/lib/rancher/k3s/server/node-token")"
echo "  Join token for this K3s cluster is: " $K3S_TOKEN

# Deploy K3s on Worker nodes
echo && echo "Deploying K3s on the Worker nodes..."
install_k3s_workers

# Check cluster status
echo && echo "Verifying cluster status..."
sleep 15
multipass exec k3s-manager kubectl get nodes

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