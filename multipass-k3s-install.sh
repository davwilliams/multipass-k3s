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
    w) NUM_AGENTS=${OPTARG};;
    c) NUM_CPUS=${OPTARG};;
    m) MEM_SIZE=${OPTARG};;
    d) DISK_SIZE=${OPTARG};;
  esac
done

provision_agents () {
    COUNTER=1
    until [ $COUNTER -gt $NUM_AGENTS ]; do
      multipass launch focal --name k3s-agent-$COUNTER --cpus $NUM_CPUS --mem ${MEM_SIZE}M --disk ${DISK_SIZE}G
      let COUNTER+=1
    done
}

install_k3s_agents () {
    COUNTER=1
    until [ $COUNTER -gt $NUM_AGENTS ]; do
      echo && multipass exec k3s-agent-$COUNTER \
        -- /bin/bash -c "curl -sfL https://get.k3s.io | K3S_TOKEN=${K3S_TOKEN} K3S_URL=${K3S_NODEIP_SERVER} sh -"
      let COUNTER+=1
    done
}

# Provision nodes for K3s server, Rancher management server, and Minio object storage
echo "Lauching K3s lab nodes..."
multipass launch focal --name k3s-server --cpus 2 --mem 4096M --disk 20G
#multipass launch focal --name rancher --cpus 2 --mem 4096M --disk 20G

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
echo "  k3s-server IP is: " $K3S_NODEIP_SERVER
K3S_TOKEN="$(multipass exec k3s-server -- /bin/bash -c "sudo cat /var/lib/rancher/k3s/server/node-token")"
echo "  Join token for this K3s cluster is: " $K3S_TOKEN

# Deploy K3s on agent nodes
echo && echo "Deploying K3s on the agent nodes..."
install_k3s_agents

# Check cluster status
echo && echo "Verifying cluster status..."
sleep 20  # Give enough time for agend nodes to become ready
multipass exec k3s-server kubectl get nodes --sort-by={.metadata.labels."kubernetes\.io\/hostname"} -o wide

# Install Rancher
echo && echo "Installing Rancher..."

echo && echo "Installing Helm:"
multipass exec k3s-server curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
multipass exec k3s-server chmod 700 get_helm.sh
multipass exec k3s-server ./get_helm.sh

echo && echo "Adding Rancher Helm chart repository:"
multipass exec k3s-server helm repo add rancher-latest https://releases.rancher.com/server-charts/latest

echo && echo "Creating a namespace for Rancher:"
multipass exec k3s-server kubectl create namespace cattle-system

echo && echo "Install Cert-Manager:"
multipass exec k3s-server kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v1.0.4/cert-manager.crds.yaml
multipass exec k3s-server kubectl create namespace cert-manager
multipass exec k3s-server helm repo add jetstack https://charts.jetstack.io
multipass exec k3s-server helm repo update
multipass exec k3s-server helm install cert-manager jetstack/cert-manager --namespace cert-manager --version v1.0.4

echo && echo "Verifying installation of Cert-Manager"
multipass exec k3s-server kubectl get pods --namespace cert-manager

echo && echo "Installing Rancher with Helm a generated certs:"
multipass exec k3s-server helm install rancher rancher-latest/rancher --namespace cattle-system --set hostname=rancher.${K3S_NODEIP_SERVER}.xip.io
multipass exec k3s-server kubectl -n cattle-system rollout status deploy/rancher
multipass exec k3s-server kubectl -n cattle-system get deploy rancher

echo && echo "Verifying "

# multipass exec rancher -- /bin/bash -c "sudo apt-get update && sudo apt-get install -y docker.io"
# multipass exec rancher -- /bin/bash -c "sudo systemctl enable docker"
# multipass exec rancher -- /bin/bash -c "sudo docker run -d --restart=unless-stopped -p 80:80 -p 443:443 --name rancher --privileged rancher/rancher"