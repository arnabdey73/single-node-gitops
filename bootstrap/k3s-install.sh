#!/bin/bash

# K3s Installation Script for Single Node GitOps Platform
# This script installs and configures K3s with optimized settings for single-node deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   error "This script should not be run as root. Please run as a regular user with sudo privileges."
fi

# Check for sudo privileges
if ! sudo -n true 2>/dev/null; then
    error "This script requires sudo privileges. Please run: sudo -v"
fi

log "Starting K3s installation for single-node GitOps platform..."

# System requirements check
log "Checking system requirements..."

# Check minimum RAM (4GB)
TOTAL_RAM=$(free -m | awk 'NR==2{printf "%.0f", $2/1024}')
if [ "$TOTAL_RAM" -lt 4 ]; then
    warn "System has ${TOTAL_RAM}GB RAM. Minimum 4GB recommended."
fi

# Check available disk space (20GB minimum)
AVAILABLE_SPACE=$(df / | awk 'NR==2 {printf "%.0f", $4/1024/1024}')
if [ "$AVAILABLE_SPACE" -lt 20 ]; then
    warn "Available disk space: ${AVAILABLE_SPACE}GB. Minimum 20GB recommended."
fi

# Disable swap if enabled
if swapon --show | grep -q "/"; then
    log "Disabling swap..."
    sudo swapoff -a
    sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
    log "Swap disabled permanently"
fi

# Install required packages
log "Installing required packages..."
sudo apt update
sudo apt install -y curl wget git unzip jq

# Configure firewall if UFW is active
if sudo ufw status | grep -q "Status: active"; then
    log "Configuring firewall for K3s..."
    sudo ufw allow 6443/tcp  # K3s API server
    sudo ufw allow 80/tcp    # HTTP
    sudo ufw allow 443/tcp   # HTTPS
    sudo ufw allow 8080/tcp  # ArgoCD UI
fi

# Set K3s configuration
export INSTALL_K3S_CHANNEL=stable
export K3S_KUBECONFIG_MODE="644"

# K3s installation with optimized flags for single node
log "Installing K3s..."
curl -sfL https://get.k3s.io | sh -s - \
    --write-kubeconfig-mode 644 \
    --disable traefik \
    --disable servicelb \
    --disable metrics-server \
    --node-taint CriticalAddonsOnly=true:NoExecute \
    --node-label node-role.kubernetes.io/master=true

# Wait for K3s to be ready
log "Waiting for K3s to be ready..."
sleep 30

# Check if K3s is running
if ! sudo systemctl is-active --quiet k3s; then
    error "K3s failed to start. Check logs with: sudo journalctl -u k3s -f"
fi

# Set up kubeconfig for current user
log "Configuring kubectl access..."
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
export KUBECONFIG=~/.kube/config

# Add kubeconfig to shell profile
if ! grep -q "KUBECONFIG" ~/.bashrc; then
    echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
    echo 'alias k=kubectl' >> ~/.bashrc
    echo 'complete -F __start_kubectl k' >> ~/.bashrc
fi

# Wait for node to be ready
log "Waiting for node to be ready..."
timeout=300
while ! kubectl get nodes | grep -q "Ready"; do
    sleep 5
    timeout=$((timeout - 5))
    if [ $timeout -le 0 ]; then
        error "Node failed to become ready within 5 minutes"
    fi
done

# Remove node taint to allow scheduling on control plane
log "Configuring node for single-node deployment..."
kubectl taint nodes --all node-role.kubernetes.io/master-
kubectl taint nodes --all CriticalAddonsOnly-

# Label node for single-node deployment
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl label node $NODE_NAME node-role.kubernetes.io/worker=true --overwrite

# Install Helm (needed for some applications)
log "Installing Helm..."
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify installation
log "Verifying K3s installation..."
kubectl cluster-info
kubectl get nodes -o wide
kubectl get pods -A

log "K3s installation completed successfully!"
log "Next steps:"
log "1. Run: source ~/.bashrc"
log "2. Deploy ArgoCD: kubectl apply -f bootstrap/argocd-bootstrap.yaml"
log "3. Deploy applications: kubectl apply -f applications/"

log "Useful commands:"
log "- Check cluster: kubectl cluster-info"
log "- View all pods: kubectl get pods -A"
log "- Check logs: sudo journalctl -u k3s -f"
