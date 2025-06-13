#!/bin/bash

# All-in-One Installation Script for AppDeploy Platform
# This script automates the entire installation process from system preparation to deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
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

info() {
    echo -e "${CYAN}[INFO] $1${NC}"
}

print_header() {
    echo -e "\n${CYAN}====================================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}====================================================================${NC}\n"
}

check_requirements() {
    print_header "CHECKING SYSTEM REQUIREMENTS"
    
    # Check for sudo
    if ! command -v sudo &> /dev/null; then
        error "sudo is required but not installed. Please install sudo and try again."
    fi
    
    # Check for required commands
    for cmd in curl wget git kubectl; do
        if ! command -v $cmd &> /dev/null; then
            warn "$cmd not found, will attempt to install it..."
            
            if [ "$cmd" = "kubectl" ]; then
                log "Will install kubectl later with K3s..."
            else
                log "Installing $cmd..."
                sudo apt-get update && sudo apt-get install -y $cmd
            fi
        else
            log "$cmd is installed ✓"
        fi
    done
    
    # Check RAM
    total_ram=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$total_ram" -lt 4096 ]; then
        warn "System has less than 4GB RAM ($total_ram MB). Performance may be degraded."
    else
        log "RAM check passed: $total_ram MB available ✓"
    fi
    
    # Check CPU
    cpu_cores=$(grep -c ^processor /proc/cpuinfo)
    if [ "$cpu_cores" -lt 2 ]; then
        warn "System has less than 2 CPU cores. Performance may be degraded."
    else
        log "CPU check passed: $cpu_cores cores available ✓"
    fi
    
    # Check disk space
    free_space=$(df -BG --output=avail / | tail -n 1 | tr -d 'G')
    if [ "$free_space" -lt 30 ]; then
        warn "Less than 30GB free disk space available ($free_space GB). This may not be sufficient."
    else
        log "Disk space check passed: $free_space GB available ✓"
    fi
}

apply_system_optimizations() {
    print_header "APPLYING SYSTEM OPTIMIZATIONS"
    
    # Check if this is a Dell PowerEdge system
    if [ -f /sys/class/dmi/id/product_name ]; then
        product_name=$(cat /sys/class/dmi/id/product_name)
        if [[ "$product_name" == *"PowerEdge"* ]]; then
            log "Detected Dell PowerEdge system: $product_name"
            log "Applying Dell-specific optimizations..."
            
            # Run Dell optimizations script if available
            if [ -f "./bootstrap/dell-optimizations.sh" ]; then
                log "Running Dell optimizations script..."
                bash ./bootstrap/dell-optimizations.sh
            else
                warn "Dell optimizations script not found, skipping Dell-specific optimizations"
            fi
        else
            log "Not a Dell PowerEdge system, applying generic optimizations..."
        fi
    fi
    
    # Apply generic system optimizations
    log "Setting CPU governor to performance mode..."
    if command -v cpupower &> /dev/null; then
        sudo cpupower frequency-set -g performance
    else
        warn "cpupower not available, skipping CPU governor configuration"
    fi
    
    log "Optimizing disk I/O scheduler..."
    for disk in /sys/block/sd*; do
        if [ -f "$disk/queue/scheduler" ]; then
            echo mq-deadline | sudo tee "$disk/queue/scheduler" >/dev/null 2>&1 || true
        fi
    done
    
    log "Optimizing network settings..."
    # Apply network optimizations to sysctl
    cat << EOF | sudo tee /etc/sysctl.d/99-network-tuning.conf
# Network tuning for Kubernetes workloads
net.core.somaxconn = 32768
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_congestion_control = bbr
EOF
    sudo sysctl -p /etc/sysctl.d/99-network-tuning.conf
    
    log "System optimizations applied successfully ✓"
}

install_k3s() {
    print_header "INSTALLING K3S"
    
    if kubectl get nodes &>/dev/null; then
        log "K3s appears to be already installed and running"
        return 0
    fi
    
    # Run the K3s installation script with optimized settings
    log "Installing K3s with optimized settings..."
    
    export INSTALL_K3S_EXEC="--disable=traefik --write-kubeconfig-mode=644 --kube-apiserver-arg=feature-gates=APIPriorityAndFairness=true --kube-controller-manager-arg=feature-gates=APIPriorityAndFairness=true --kubelet-arg=feature-gates=APIPriorityAndFairness=true --kube-scheduler-arg=feature-gates=APIPriorityAndFairness=true"
    
    curl -sfL https://get.k3s.io | sh -
    
    # Wait for K3s to be ready
    log "Waiting for K3s to be ready..."
    sleep 10
    
    # Set up kubeconfig for regular user
    log "Setting up kubeconfig..."
    mkdir -p ~/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    sudo chown $(id -u):$(id -g) ~/.kube/config
    export KUBECONFIG=~/.kube/config
    
    # Add to shell profile for persistence
    echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
    
    # Verify installation
    log "Verifying K3s installation..."
    kubectl get nodes
    
    log "K3s installed successfully ✓"
}

deploy_base_infrastructure() {
    print_header "DEPLOYING BASE INFRASTRUCTURE"
    
    log "Applying base infrastructure..."
    kubectl apply -k infrastructure/base/
    
    log "Waiting for components to be ready..."
    kubectl wait --for=condition=ready pod -l app=local-path-provisioner -n kube-system --timeout=300s || true
    
    log "Base infrastructure deployed successfully ✓"
}

deploy_argocd() {
    print_header "DEPLOYING ARGOCD"
    
    log "Deploying ArgoCD..."
    kubectl apply -f bootstrap/argocd-bootstrap.yaml
    
    log "Waiting for ArgoCD to be ready (this may take a few minutes)..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s || true
    
    # Get ArgoCD admin password
    log "Retrieving ArgoCD admin password..."
    ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    
    log "ArgoCD deployed successfully ✓"
    info "ArgoCD admin credentials:"
    info "  Username: admin"
    info "  Password: $ARGOCD_PASSWORD"
    info "  URL: https://localhost:8080 (after running kubectl port-forward)"
}

deploy_applications() {
    print_header "DEPLOYING APPLICATIONS"
    
    log "Deploying applications..."
    kubectl apply -f applications/app-of-apps.yaml
    
    log "Applications deployment initiated ✓"
    log "ArgoCD will now handle the progressive deployment of all components"
    
    info "To monitor deployment status:"
    info "  kubectl get applications -n argocd"
}

setup_access() {
    print_header "SETTING UP ACCESS"
    
    log "Setting up scripts for easy access..."
    
    # Make all scripts executable
    chmod +x scripts/*.sh
    
    # Set up aliases for common operations
    cat << EOF >> ~/.bashrc

# AppDeploy platform aliases
alias ad-dashboard='$(pwd)/scripts/dashboard-access.sh open'
alias ad-status='kubectl get applications -n argocd'
alias ad-health='$(pwd)/scripts/health-check.sh'
alias ad-backup='$(pwd)/scripts/backup.sh'
alias ad-restore='$(pwd)/scripts/restore.sh'
EOF
    
    # Source bashrc to apply changes immediately
    source ~/.bashrc
    
    log "Access setup complete ✓"
    info "You can use the following aliases:"
    info "  ad-dashboard - Open the AppDeploy dashboard"
    info "  ad-status   - Check application deployment status"
    info "  ad-health   - Run a system health check"
    info "  ad-backup   - Backup system configuration"
    info "  ad-restore  - Restore system configuration"
}

print_completion() {
    print_header "INSTALLATION COMPLETE"
    
    cat << EOF
${GREEN}
AppDeploy Platform has been successfully installed!
${NC}

${CYAN}Next Steps:${NC}
1. Access the AppDeploy dashboard:
   ${YELLOW}./scripts/dashboard-access.sh open${NC}

2. Access the ArgoCD UI:
   ${YELLOW}kubectl port-forward svc/argocd-server -n argocd 8080:443${NC}
   Then open: https://localhost:8080
   Username: admin
   Password: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

3. Monitor application deployments:
   ${YELLOW}kubectl get applications -n argocd${NC}

4. Check system health:
   ${YELLOW}./scripts/health-check.sh${NC}

For more information, refer to the documentation:
- Installation Guide: docs/installation.md
- Architecture: docs/platform-architecture.md
- Troubleshooting: docs/troubleshooting.md

EOF
}

# Main installation flow
main() {
    print_header "STARTING INSTALLATION OF APPDEPLOY PLATFORM"
    
    check_requirements
    apply_system_optimizations
    install_k3s
    deploy_base_infrastructure
    deploy_argocd
    deploy_applications
    setup_access
    print_completion
}

# Start installation
main
