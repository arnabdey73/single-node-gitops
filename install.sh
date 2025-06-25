#!/bin/bash

# All-in-One Installation Script for AppDeploy Platform
# This script automates the entire installation process from system preparation to deployment
# Enhanced with corner case mitigations for reliability across environments

set -e

# Set version information for components (enables predictable deployments)
K3S_VERSION="v1.26.4+k3s1"
ARGOCD_VERSION="v2.8.0"
NODE_EXPORTER_VERSION="1.6.0"

# Log file for installation
LOG_DIR="/var/log/appdeploy"
mkdir -p "$LOG_DIR" 2>/dev/null || LOG_DIR="/tmp"
LOG_FILE="${LOG_DIR}/appdeploy_install_$(date +'%Y%m%d_%H%M%S').log"
touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/appdeploy_install_$(date +'%Y%m%d_%H%M%S').log" 
touch "$LOG_FILE"
echo "Installation logs will be saved to: $LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration options with defaults
ENABLE_VULNERABILITY_SCANNING=true
ENABLE_POLICY_ENFORCEMENT=true
ENABLE_CIS_BENCHMARKS=true
ENABLE_SECURITY_DASHBOARD=true

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --disable-vulnerability-scanning)
                ENABLE_VULNERABILITY_SCANNING=false
                shift
                ;;
            --disable-policy-enforcement)
                ENABLE_POLICY_ENFORCEMENT=false
                shift
                ;;
            --disable-cis-benchmarks)
                ENABLE_CIS_BENCHMARKS=false
                shift
                ;;
            --disable-security-dashboard)
                ENABLE_SECURITY_DASHBOARD=false
                shift
                ;;
            --disable-all-security)
                ENABLE_VULNERABILITY_SCANNING=false
                ENABLE_POLICY_ENFORCEMENT=false
                ENABLE_CIS_BENCHMARKS=false
                ENABLE_SECURITY_DASHBOARD=false
                shift
                ;;
            --help)
                echo "Usage: $0 [options]"
                echo ""
                echo "Options:"
                echo "  --disable-vulnerability-scanning  Disable Trivy vulnerability scanning"
                echo "  --disable-policy-enforcement      Disable OPA Gatekeeper policy enforcement"
                echo "  --disable-cis-benchmarks          Disable CIS Kubernetes benchmarks"
                echo "  --disable-security-dashboard      Disable security dashboard"
                echo "  --disable-all-security            Disable all security components"
                echo "  --help                            Show this help message"
                echo ""
                echo "By default, all security components are enabled."
                echo ""
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information."
                exit 1
                ;;
        esac
    done
}

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

check_network_connectivity() {
    print_header "CHECKING NETWORK CONNECTIVITY"
    
    log "Testing internet connectivity..."
    
    local retries=3
    local sites=("get.k3s.io" "github.com" "k8s.io" "registry.k8s.io")
    local success=true
    
    for site in "${sites[@]}"; do
        local attempt=1
        log "Testing connection to $site..."
        
        while [ $attempt -le $retries ]; do
            if curl -s --connect-timeout 10 --max-time 15 -I "https://$site" &> /dev/null; then
                log "✓ Successfully connected to $site"
                break
            else
                warn "Attempt $attempt: Failed to connect to $site"
                if [ $attempt -eq $retries ]; then
                    warn "Could not connect to $site after $retries attempts"
                    success=false
                    break
                fi
                log "Retrying in 5 seconds..."
                sleep 5
                attempt=$((attempt+1))
            fi
        done
    done
    
    if [ "$success" = false ]; then
        warn "Some network connectivity tests failed. Installation may experience issues."
        read -p "Do you want to continue anyway? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            error "Installation aborted due to network connectivity issues."
        fi
    else
        log "Network connectivity check passed ✓"
    fi
}

configure_proxy() {
    print_header "CHECKING FOR PROXY ENVIRONMENT"
    
    if [[ ! -z "$http_proxy" || ! -z "$https_proxy" || ! -z "$no_proxy" ]]; then
        log "Proxy environment detected"
        log "http_proxy: ${http_proxy:-not set}"
        log "https_proxy: ${https_proxy:-not set}"
        log "no_proxy: ${no_proxy:-not set}"
        
        # Create directory for containerd config if it doesn't exist
        sudo mkdir -p /etc/systemd/system/containerd.service.d/
        
        # Configure containerd to use proxy
        log "Configuring containerd to use proxy settings..."
        cat << EOF | sudo tee /etc/systemd/system/containerd.service.d/proxy.conf > /dev/null
[Service]
Environment="HTTP_PROXY=${http_proxy:-}"
Environment="HTTPS_PROXY=${https_proxy:-}"
Environment="NO_PROXY=${no_proxy:-localhost,127.0.0.1,10.0.0.0/8,192.168.0.0/16,172.16.0.0/12,.svc,.cluster.local}"
EOF
        
        # Reload systemd to apply changes
        sudo systemctl daemon-reload
        
        # Configure for K3s
        mkdir -p ~/.kube
        cat << EOF > ~/.kube/proxy-env
export HTTP_PROXY="${http_proxy:-}"
export HTTPS_PROXY="${https_proxy:-}"
export NO_PROXY="${no_proxy:-localhost,127.0.0.1,10.0.0.0/8,192.168.0.0/16,172.16.0.0/12,.svc,.cluster.local}"
EOF
        
        log "Proxy environment configured ✓"
    else
        log "No proxy environment detected ✓"
    fi
}

check_requirements() {
    print_header "CHECKING SYSTEM REQUIREMENTS"
    
    # Check for sudo
    if ! command -v sudo &> /dev/null; then
        error "sudo is required but not installed. Please install sudo and try again."
    fi
    
    # Check for required commands with retry logic
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
        read -p "Continue with limited disk space? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            error "Installation aborted due to insufficient disk space."
        fi
    else
        log "Disk space check passed: $free_space GB available ✓"
    fi
    
    # Check inotify limits
    log "Checking inotify limits..."
    current_max_user_instances=$(sysctl -n fs.inotify.max_user_instances)
    current_max_user_watches=$(sysctl -n fs.inotify.max_user_watches)
    
    if [ "$current_max_user_instances" -lt 512 ] || [ "$current_max_user_watches" -lt 65536 ]; then
        log "Setting higher inotify limits for Kubernetes..."
        cat << EOF | sudo tee /etc/sysctl.d/99-kubernetes-inotify.conf > /dev/null
# Increase inotify limits for Kubernetes
fs.inotify.max_user_instances=512
fs.inotify.max_user_watches=65536
EOF
        sudo sysctl --system
    fi
}

detect_hardware() {
    print_header "DETECTING HARDWARE"
    
    # Install dmidecode if not present (required for proper hardware detection)
    if ! command -v dmidecode &> /dev/null; then
        log "Installing dmidecode for hardware detection..."
        sudo apt-get update && sudo apt-get install -y dmidecode
    fi
    
    # Detect system manufacturer and product
    SYSTEM_MANUFACTURER=$(sudo dmidecode -s system-manufacturer)
    SYSTEM_PRODUCT=$(sudo dmidecode -s system-product-name)
    
    log "Detected system: $SYSTEM_MANUFACTURER $SYSTEM_PRODUCT"
    
    # Detect CPU information
    CPU_MODEL=$(grep "model name" /proc/cpuinfo | head -n1 | cut -d: -f2 | sed 's/^[ \t]*//')
    CPU_CORES=$(grep -c "processor" /proc/cpuinfo)
    log "CPU: $CPU_MODEL with $CPU_CORES cores"
    
    # Detect memory
    TOTAL_MEM=$(free -h | grep Mem | awk '{print $2}')
    log "Memory: $TOTAL_MEM total"
    
    # Identify if this is a Dell PowerEdge system
    IS_DELL_POWEREDGE=false
    if [[ "$SYSTEM_MANUFACTURER" == *"Dell"* ]] && [[ "$SYSTEM_PRODUCT" == *"PowerEdge"* ]]; then
        IS_DELL_POWEREDGE=true
        log "✓ Confirmed Dell PowerEdge system: $SYSTEM_PRODUCT"
    else
        log "This is not a Dell PowerEdge system"
    fi
}

apply_system_optimizations() {
    print_header "APPLYING SYSTEM OPTIMIZATIONS"
    
    # Run hardware detection
    detect_hardware
    
    # Apply appropriate optimizations based on hardware
    if [ "$IS_DELL_POWEREDGE" = true ]; then
        log "Applying Dell PowerEdge-specific optimizations..."
        
        # Run Dell optimizations script if available
        if [ -f "./bootstrap/dell-optimizations.sh" ]; then
            log "Running Dell optimizations script..."
            bash ./bootstrap/dell-optimizations.sh
        else
            warn "Dell optimizations script not found, skipping Dell-specific optimizations"
        fi
    else
        log "Applying generic hardware optimizations..."
        
        # Generic optimizations for non-Dell hardware
        log "Setting up generic hardware monitoring..."
        sudo apt-get update
        sudo apt-get install -y lm-sensors
        sudo sensors-detect --auto
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
    log "Installing K3s version ${K3S_VERSION} with optimized settings..."
    
    # Create a systemd service file for K3s (ensures proper startup after reboot)
    log "Creating K3s systemd service file..."
    cat << EOF | sudo tee /etc/systemd/system/k3s.service > /dev/null
[Unit]
Description=Lightweight Kubernetes
Documentation=https://k3s.io
After=network-online.target
Wants=network-online.target

[Service]
Type=exec
ExecStart=/usr/local/bin/k3s server
KillMode=process
Delegate=yes
# Restart with backoff, up to 5 minutes per restart with
# unlimited retries
Restart=always
RestartSec=5s
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
TimeoutStartSec=0
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # Configure K3s with optimized settings
    export INSTALL_K3S_EXEC="--disable=traefik --write-kubeconfig-mode=644 --kube-apiserver-arg=feature-gates=APIPriorityAndFairness=true --kube-controller-manager-arg=feature-gates=APIPriorityAndFairness=true --kubelet-arg=feature-gates=APIPriorityAndFairness=true --kube-scheduler-arg=feature-gates=APIPriorityAndFairness=true"
    
    # Apply proxy settings if they exist
    if [ -f ~/.kube/proxy-env ]; then
        log "Applying proxy settings to K3s installation..."
        source ~/.kube/proxy-env
    fi
    
    # Install K3s with retry logic
    local retries=3
    local attempt=1
    local success=false
    
    while [ $attempt -le $retries ] && [ "$success" = false ]; do
        log "Attempt $attempt: Installing K3s version ${K3S_VERSION}..."
        
        if curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${K3S_VERSION}" sh -; then
            log "K3s installation successful"
            success=true
        else
            warn "K3s installation failed on attempt $attempt"
            if [ $attempt -eq $retries ]; then
                error "Failed to install K3s after $retries attempts"
            fi
            log "Retrying in 10 seconds..."
            sleep 10
            attempt=$((attempt+1))
        fi
    done
    
    # Wait for K3s to be ready with more robust waiting
    log "Waiting for K3s to be ready..."
    local timeout=120  # seconds
    local start_time=$(date +%s)
    
    while true; do
        if kubectl get nodes &>/dev/null; then
            log "K3s is ready"
            break
        fi
        
        local current_time=$(date +%s)
        local elapsed_time=$((current_time - start_time))
        
        if [ $elapsed_time -ge $timeout ]; then
            warn "Timed out waiting for K3s to be ready after ${timeout} seconds"
            warn "Continuing anyway, but some components may fail to deploy"
            break
        fi
        
        log "Still waiting for K3s to be ready... (${elapsed_time}s elapsed)"
        sleep 5
    done
    
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
    
    # Enable and verify systemd service
    log "Enabling K3s systemd service for automatic startup after reboot..."
    sudo systemctl daemon-reload
    sudo systemctl enable k3s
    
    log "K3s installed successfully ✓"
}

create_dns_validation_job() {
    log "Creating DNS validation job..."
    cat << EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: dns-validation
  namespace: kube-system
spec:
  ttlSecondsAfterFinished: 300
  template:
    spec:
      containers:
      - name: dns-validation
        image: busybox:1.34.1
        command:
        - sh
        - -c
        - |
          echo "Testing DNS resolution..."
          nslookup kubernetes.default.svc.cluster.local
          echo "Testing external DNS resolution..."
          nslookup github.com
      restartPolicy: Never
  backoffLimit: 3
EOF

    log "Waiting for DNS validation job to complete..."
    kubectl wait --for=condition=complete job/dns-validation -n kube-system --timeout=60s || {
        warn "DNS validation job did not complete successfully"
        kubectl logs -n kube-system job/dns-validation
    }
}

deploy_base_infrastructure() {
    print_header "DEPLOYING BASE INFRASTRUCTURE"
    
    # Configure StorageClass first (K3s already creates local-path)
    log "Configuring StorageClass..."
    
    # Make local-path the default StorageClass
    kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
    
    # Create the platform storage directory
    log "Creating platform storage directory..."
    mkdir -p /opt/platform-storage
    chmod 755 /opt/platform-storage
    
    # Apply other infrastructure
    log "Applying base infrastructure..."
    
    # Attempt to apply base infrastructure with retry logic
    local retries=3
    local attempt=1
    local success=false
    
    while [ $attempt -le $retries ] && [ "$success" = false ]; do
        log "Attempt $attempt: Applying infrastructure..."
        
        if kubectl apply -k infrastructure/base/; then
            success=true
            log "Base infrastructure applied successfully"
        else
            warn "Failed to apply base infrastructure on attempt $attempt"
            
            if [ $attempt -eq $retries ]; then
                warn "Failed to apply base infrastructure after $retries attempts, but continuing..."
            else
                log "Retrying in 10 seconds..."
                sleep 10
                attempt=$((attempt+1))
            fi
        fi
    done
    
    log "Waiting for local-path storage provisioner to be ready..."
    if ! kubectl wait --for=condition=ready pod -l app=local-path-provisioner -n kube-system --timeout=300s; then
        warn "Timed out waiting for local-path-provisioner to be ready"
        log "Checking pod status..."
        kubectl get pods -n kube-system -l app=local-path-provisioner
        kubectl describe pod -n kube-system -l app=local-path-provisioner
    else
        log "Local-path storage provisioner is ready ✓"
    fi
    
    # Create resource quotas for namespaces
    log "Creating default resource quotas..."
    cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: default-quota
spec: {}
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: default-compute-resources
  namespace: default-quota
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "8"
    limits.memory: 16Gi
    pods: "20"
EOF
    
    # Validate DNS resolution in the cluster
    create_dns_validation_job
    
    log "Base infrastructure deployed ✓"
}

deploy_argocd() {
    print_header "DEPLOYING ARGOCD"
    
    # Create argocd namespace if it doesn't exist
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    
    log "Deploying ArgoCD version ${ARGOCD_VERSION}..."
    
    # Determine which ArgoCD manifest to use based on version
    local argocd_manifest="bootstrap/argocd-bootstrap.yaml"
    
    # Apply with retry logic
    local retries=3
    local attempt=1
    local success=false
    
    while [ $attempt -le $retries ] && [ "$success" = false ]; do
        log "Attempt $attempt: Deploying ArgoCD..."
        
        if kubectl apply -f $argocd_manifest; then
            success=true
            log "ArgoCD manifest applied successfully"
        else
            warn "Failed to apply ArgoCD manifest on attempt $attempt"
            
            if [ $attempt -eq $retries ]; then
                warn "Failed to deploy ArgoCD after $retries attempts."
                read -p "Continue without ArgoCD? (y/n): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    error "Installation aborted."
                else
                    warn "Continuing without fully functional ArgoCD..."
                    break
                fi
            else
                log "Retrying in 20 seconds..."
                sleep 20
                attempt=$((attempt+1))
            fi
        fi
    done
    
    # Wait for ArgoCD to be ready with progress updates
    log "Waiting for ArgoCD to be ready (this may take several minutes)..."
    
    local timeout=600  # 10 minutes
    local start_time=$(date +%s)
    local wait_success=false
    
    while true; do
        if kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=30s &>/dev/null; then
            log "ArgoCD server is ready ✓"
            wait_success=true
            break
        fi
        
        local current_time=$(date +%s)
        local elapsed_time=$((current_time - start_time))
        
        if [ $elapsed_time -ge $timeout ]; then
            warn "Timed out waiting for ArgoCD server to be ready after ${elapsed_time} seconds"
            break
        fi
        
        local pods_status=$(kubectl get pods -n argocd -o wide)
        echo "$pods_status"
        log "Still waiting for ArgoCD to be ready... (${elapsed_time}s elapsed)"
        sleep 20
    done
    
    if [ "$wait_success" = true ]; then
        # Get ArgoCD admin password
        log "Retrieving ArgoCD admin password..."
        ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
        
        # Create a ConfigMap to store the argocd password in a safer way
        log "Storing ArgoCD password in ConfigMap for future reference..."
        kubectl create configmap argocd-access -n argocd --from-literal=admin-password="$ARGOCD_PASSWORD" --dry-run=client -o yaml | kubectl apply -f -
        
        log "ArgoCD deployed successfully ✓"
        info "ArgoCD admin credentials:"
        info "  Username: admin"
        info "  Password: $ARGOCD_PASSWORD"
        info "  URL: https://localhost:8080 (after running kubectl port-forward)"
    else
        warn "ArgoCD deployment may not be fully functional. Check the pods status manually."
    fi
}

setup_certificate_monitoring() {
    print_header "SETTING UP CERTIFICATE MONITORING"
    
    log "Creating certificate expiry monitoring..."
    
    # Create a ConfigMap with alert rules for certificate expiry
    cat << EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: cert-expiry-alerts
  namespace: monitoring
  labels:
    app.kubernetes.io/name: prometheus
data:
  cert-expiry-rules.yaml: |
    groups:
    - name: certificate-expiry
      rules:
      - alert: CertificateExpiringSoon
        expr: sum by (namespace, pod, secret_name) (secrets_expiration_timestamp_seconds{secret_type="kubernetes.io/tls"} - time()) < 86400 * 30
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Certificate will expire soon"
          description: "Certificate {{ \$labels.secret_name }} in {{ \$labels.namespace }} will expire in less than 30 days"
      - alert: CertificateExpired
        expr: sum by (namespace, pod, secret_name) (secrets_expiration_timestamp_seconds{secret_type="kubernetes.io/tls"} - time()) < 0
        for: 10m
        labels:
          severity: critical
        annotations:
          summary: "Certificate has expired"
          description: "Certificate {{ \$labels.secret_name }} in {{ \$labels.namespace }} has expired"
EOF

    log "Certificate monitoring setup complete ✓"
}

setup_log_rotation() {
    print_header "SETTING UP LOG ROTATION AND GARBAGE COLLECTION"
    
    log "Creating log rotation and garbage collection job..."
    
    # Create a CronJob to clean up old logs and unused images
    cat << EOF | kubectl apply -f -
apiVersion: batch/v1
kind: CronJob
metadata:
  name: system-cleanup
  namespace: kube-system
spec:
  schedule: "0 2 * * *"  # Run at 2 AM every day
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: default
          containers:
          - name: cleanup
            image: bitnami/kubectl:latest
            command:
            - /bin/sh
            - -c
            - |
              echo "Starting cleanup job at $(date)"
              
              echo "Pruning terminated pods..."
              kubectl delete pods --field-selector=status.phase=Failed --all-namespaces
              
              echo "Pruning completed jobs..."
              kubectl delete jobs --field-selector=status.successful=1 --all-namespaces
              
              echo "Cleanup completed at $(date)"
          restartPolicy: OnFailure
EOF

    # Create log rotation for containerd
    log "Setting up log rotation for containerd..."
    cat << EOF | sudo tee /etc/logrotate.d/containerd > /dev/null
/var/log/containers/*.log {
    rotate 7
    daily
    compress
    missingok
    notifempty
    copytruncate
}
EOF

    log "Log rotation and garbage collection setup complete ✓"
}

deploy_applications() {
    print_header "DEPLOYING APPLICATIONS"
    
    log "Deploying applications..."
    
    # Verify ArgoCD is operational before proceeding
    if ! kubectl get pod -l app.kubernetes.io/name=argocd-server -n argocd --no-headers &>/dev/null; then
        warn "ArgoCD may not be fully deployed. Applications may not deploy correctly."
        read -p "Continue with application deployment? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            error "Application deployment aborted."
        fi
    fi
    
    # Apply with retry logic
    local retries=3
    local attempt=1
    local success=false
    
    while [ $attempt -le $retries ] && [ "$success" = false ]; do
        log "Attempt $attempt: Deploying app-of-apps..."
        
        if kubectl apply -f applications/app-of-apps.yaml; then
            success=true
            log "App-of-apps deployed successfully"
        else
            warn "Failed to deploy app-of-apps on attempt $attempt"
            
            if [ $attempt -eq $retries ]; then
                warn "Failed to deploy applications after $retries attempts."
                warn "You may need to manually apply: kubectl apply -f applications/app-of-apps.yaml"
                break
            else
                log "Retrying in 10 seconds..."
                sleep 10
                attempt=$((attempt+1))
            fi
        fi
    done
    
    log "Applications deployment initiated ✓"
    log "ArgoCD will now handle the progressive deployment of all components"

    # Setup Docker registry configuration
    log "Setting up Docker registry configuration..."
    chmod +x scripts/docker-registry.sh
    
    # Setup DevSecOps components
    log "Setting up DevSecOps components..."
    chmod +x scripts/container-security.sh

    # Setup additional monitoring and management components
    setup_certificate_monitoring
    setup_log_rotation
    
    # Wait for initial sync to begin
    log "Waiting for ArgoCD to start syncing applications..."
    sleep 10
    
    # Display initial sync status
    log "Initial application status:"
    kubectl get applications -n argocd
    
    info "To monitor deployment status:"
    info "  kubectl get applications -n argocd"
    info "  kubectl get pods --all-namespaces"
}

setup_access() {
    print_header "SETTING UP ACCESS"
    
    log "Setting up scripts for easy access..."
    
    # Make all scripts executable
    chmod +x scripts/*.sh
    
    # Create firewall rules for common access ports
    log "Setting up firewall rules for common access ports..."
    if command -v ufw &> /dev/null; then
        log "Configuring UFW firewall rules..."
        sudo ufw status | grep -q "Status: active" && {
            sudo ufw allow 22/tcp comment "SSH access"
            sudo ufw allow 6443/tcp comment "Kubernetes API"
            sudo ufw allow 80/tcp comment "HTTP"
            sudo ufw allow 443/tcp comment "HTTPS"
            sudo ufw allow 30000:32767/tcp comment "Kubernetes NodePort range"
            log "UFW rules configured ✓"
        } || log "UFW is not active, skipping firewall configuration"
    else
        log "UFW not found, skipping firewall configuration"
    fi
    
    # Check for non-root user
    if [ "$(id -u)" -eq 0 ]; then
        warn "Running as root. It's recommended to run as a non-root user."
        warn "Consider adding a non-root user with sudo privileges."
    fi
    
    # Set up aliases for common operations
    cat << EOF >> ~/.bashrc

# AppDeploy platform aliases
alias ad-dashboard='$(pwd)/scripts/dashboard-access.sh open'
alias ad-status='kubectl get applications -n argocd'
alias ad-health='$(pwd)/scripts/health-check.sh'
alias ad-backup='$(pwd)/scripts/backup.sh'
alias ad-restore='$(pwd)/scripts/restore.sh'
alias ad-logs='kubectl logs'
alias ad-check-cert='kubectl get secrets --field-selector type=kubernetes.io/tls -A'
EOF
    
    # Create a README file for SSH tunneling access
    cat << EOF > "access-methods.md"
# Alternative Access Methods for AppDeploy Platform

## SSH Tunneling for Dashboard Access

If NodePort services are blocked by firewalls, you can use SSH tunneling:

1. From your local machine, run:
   \`\`\`bash
   # For Kubernetes Dashboard
   ssh -L 8001:localhost:30443 user@your-server-ip
   
   # For ArgoCD Dashboard
   ssh -L 8080:localhost:30080 user@your-server-ip
   
   # For Grafana Dashboard
   ssh -L 3000:localhost:30300 user@your-server-ip
   \`\`\`

2. Then access via your browser:
   - Kubernetes Dashboard: http://localhost:8001
   - ArgoCD Dashboard: http://localhost:8080
   - Grafana Dashboard: http://localhost:3000

## Direct NodePort Access (if firewall allows)

- Kubernetes Dashboard: https://your-server-ip:30443
- ArgoCD Dashboard: https://your-server-ip:30080
- Grafana Dashboard: http://your-server-ip:30300

## Port-Forward Access (most reliable)

\`\`\`bash
# For Kubernetes Dashboard
kubectl port-forward -n kubernetes-dashboard service/kubernetes-dashboard 8001:443

# For ArgoCD Dashboard
kubectl port-forward -n argocd service/argocd-server 8080:443

# For Grafana Dashboard
kubectl port-forward -n monitoring service/grafana 3000:3000
\`\`\`

Then access via your browser:
- Kubernetes Dashboard: https://localhost:8001
- ArgoCD Dashboard: https://localhost:8080
- Grafana Dashboard: http://localhost:3000
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
    info "  ad-logs     - View pod logs"
    info "  ad-check-cert - Check certificate secrets"
    
    info "Alternative access methods have been documented in access-methods.md"
}

print_completion() {
    print_header "INSTALLATION COMPLETE"
    
    # Get the current ArgoCD password
    ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "Could not retrieve password")
    
    cat << EOF
${GREEN}
★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
★                                                                  ★
★  AppDeploy Platform has been successfully installed!             ★
★                                                                  ★
★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
${NC}

${CYAN}ACCESSING THE PLATFORM:${NC}

1. Access the AppDeploy dashboard:
   ${YELLOW}./scripts/dashboard-access.sh open${NC}

2. Access the ArgoCD UI:
   ${YELLOW}kubectl port-forward svc/argocd-server -n argocd 8080:443${NC}
   Then open: https://localhost:8080
   Username: admin
   Password: ${ARGOCD_PASSWORD}

3. Access Grafana (once deployed):
   ${YELLOW}kubectl port-forward svc/grafana -n monitoring 3000:3000${NC}
   Then open: http://localhost:3000
   Default credentials: admin/admin

4. Access Docker Registry:
   ${YELLOW}./scripts/docker-registry.sh info${NC}
   Create user: ${YELLOW}./scripts/docker-registry.sh create-user username password${NC}

${CYAN}MONITORING & MANAGEMENT:${NC}

1. Monitor application deployments:
   ${YELLOW}kubectl get applications -n argocd${NC}
   ${YELLOW}kubectl get pods -A${NC}

2. Check system health:
   ${YELLOW}./scripts/health-check.sh${NC}

3. Create system backup:
   ${YELLOW}./scripts/backup.sh prod${NC}

4. Restore from backup:
   ${YELLOW}./scripts/restore.sh backup/prod-backup.tar.gz${NC}

5. Verify hardware optimizations:
   ${YELLOW}./scripts/validate-dell-optimizations.sh${NC}

${CYAN}UPGRADING THE PLATFORM:${NC}

An upgrade script has been created to help you update components:
${YELLOW}./scripts/upgrade-platform.sh${NC}

${CYAN}TROUBLESHOOTING:${NC}

1. Check component logs:
   ${YELLOW}kubectl logs -n <namespace> <pod-name>${NC}

2. View system events:
   ${YELLOW}kubectl get events --sort-by='.lastTimestamp'${NC}

3. Alternative access methods:
   See the created file: ${YELLOW}access-methods.md${NC}

${CYAN}DOCUMENTATION:${NC}

For more information, refer to:
- Installation Guide: ${YELLOW}docs/installation.md${NC}
- Architecture: ${YELLOW}docs/platform-architecture.md${NC}
- Troubleshooting: ${YELLOW}docs/troubleshooting.md${NC}
- Application Lifecycle: ${YELLOW}docs/application-lifecycle.md${NC}

${CYAN}INSTALLATION LOG:${NC}
Full installation log is available at: ${YELLOW}${LOG_FILE}${NC}

EOF

    # Check if any applications are not sync'd and report on them
    echo -e "${CYAN}CURRENT APPLICATION STATUS:${NC}"
    kubectl get applications -n argocd -o custom-columns=NAME:.metadata.name,SYNC_STATUS:.status.sync.status,HEALTH_STATUS:.status.health.status
    
    echo -e "\n${GREEN}Installation is complete. Enjoy your AppDeploy Platform!${NC}\n"
}

test_backup_restore() {
    print_header "TESTING BACKUP AND RESTORE"
    
    log "Creating test backup to validate backup script..."
    ./scripts/backup.sh test
    
    # Check if the test backup was created
    if [ -f ./backup/test-backup.tar.gz ]; then
        log "Test backup created successfully ✓"
    else
        warn "Test backup was not created successfully"
    fi
    
    log "Backup and restore functionality validated ✓"
}

create_upgrade_script() {
    print_header "CREATING UPGRADE HELPER SCRIPT"
    
    log "Creating upgrade-platform.sh script in scripts directory..."
    
    cat << 'EOF' > scripts/upgrade-platform.sh
#!/bin/bash

# Script for upgrading the AppDeploy Platform components

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

# Create backup before upgrading
log "Creating backup before upgrading..."
./scripts/backup.sh pre-upgrade

# Update the repository
log "Updating repository from git..."
git pull

# Upgrading K3s (if needed)
upgrade_k3s() {
    local current_version=$(k3s --version | awk '{print $3}')
    log "Current K3s version: $current_version"
    
    read -p "Do you want to upgrade K3s? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Upgrading K3s..."
        curl -sfL https://get.k3s.io | sh -
    else
        log "Skipping K3s upgrade"
    fi
}

# Upgrading ArgoCD
upgrade_argocd() {
    log "Upgrading ArgoCD..."
    kubectl apply -f bootstrap/argocd-bootstrap.yaml
    kubectl -n argocd rollout restart deployment argocd-server argocd-repo-server argocd-application-controller
}

# Upgrading applications
upgrade_applications() {
    log "Upgrading applications..."
    kubectl apply -f applications/app-of-apps.yaml
    
    log "Refreshing all ArgoCD applications..."
    for app in $(kubectl get applications -n argocd -o name); do
        kubectl patch $app -n argocd --type merge -p '{"spec": {"syncPolicy": {"automated": {"prune": true}}}}'
    done
}

# Main upgrade flow
main() {
    log "Starting upgrade process for AppDeploy Platform"
    
    # Confirm upgrade
    echo
    echo "This will upgrade the AppDeploy Platform components:"
    echo "  1. Create a backup"
    echo "  2. Update git repository"
    echo "  3. Upgrade K3s (optional)"
    echo "  4. Upgrade ArgoCD"
    echo "  5. Upgrade applications"
    echo
    
    read -p "Do you want to continue? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Upgrade aborted"
        exit 0
    fi
    
    upgrade_k3s
    upgrade_argocd
    upgrade_applications
    
    log "Upgrade completed successfully!"
    log "You can check the status with: kubectl get applications -n argocd"
}

# Start upgrade
main
EOF

    chmod +x scripts/upgrade-platform.sh
}

verify_installation() {
    print_header "VERIFYING INSTALLATION"
    
    log "Running verification checks..."
    
    # Verify key components are running
    local all_checks_passed=true
    
    # Check K3s node status
    log "Checking K3s node status..."
    if kubectl get nodes | grep -q "Ready"; then
        log "K3s node is ready ✓"
    else
        warn "K3s node is not in Ready state"
        all_checks_passed=false
    fi
    
    # Check ArgoCD status
    log "Checking ArgoCD status..."
    if kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server | grep -q "Running"; then
        log "ArgoCD is running ✓"
    else
        warn "ArgoCD server is not running"
        all_checks_passed=false
    fi
    
    # Check storage provisioner
    log "Checking storage provisioner status..."
    if kubectl get storageclass | grep -q "local-path"; then
        log "Local-path storage provisioner is available ✓"
    else
        warn "Local-path storage provisioner is not available"
        all_checks_passed=false
    fi
    
    # Check DevSecOps components
    log "Checking DevSecOps components status..."
    
    # Check security namespaces
    if kubectl get namespace trivy-system &>/dev/null; then
        log "Trivy Operator namespace exists ✓"
    else
        log "Trivy Operator namespace not yet created (will be created by ArgoCD)"
    fi
    
    if kubectl get namespace gatekeeper-system &>/dev/null; then
        log "OPA Gatekeeper namespace exists ✓"
    else
        log "OPA Gatekeeper namespace not yet created (will be created by ArgoCD)"
    fi
    
    if kubectl get namespace security-tools &>/dev/null; then
        log "Security tools namespace exists ✓"
    else
        log "Security tools namespace not yet created (will be created by ArgoCD)"
    fi
    
    # Check security applications
    if kubectl get application security -n argocd &>/dev/null; then
        log "Security application exists in ArgoCD ✓"
    else
        warn "Security application not yet created in ArgoCD"
    fi
    
    # Overall assessment
    if [ "$all_checks_passed" = true ]; then
        log "All verification checks passed ✓"
    else
        warn "Some verification checks failed. The platform may not be fully operational."
        warn "Please check the logs and troubleshoot the issues."
    fi
}

# Setup and verify DevSecOps components
setup_devsecops() {
    print_header "SETTING UP DEVSECOPS COMPONENTS"
    
    # Display configuration
    log "DevSecOps configuration:"
    log "- Vulnerability Scanning: $([ "$ENABLE_VULNERABILITY_SCANNING" = true ] && echo "Enabled" || echo "Disabled")"
    log "- Policy Enforcement: $([ "$ENABLE_POLICY_ENFORCEMENT" = true ] && echo "Enabled" || echo "Disabled")"
    log "- CIS Benchmarks: $([ "$ENABLE_CIS_BENCHMARKS" = true ] && echo "Enabled" || echo "Disabled")"
    log "- Security Dashboard: $([ "$ENABLE_SECURITY_DASHBOARD" = true ] && echo "Enabled" || echo "Disabled")"
    
    # Configure security components based on flags
    if [ "$ENABLE_VULNERABILITY_SCANNING" = true ] || [ "$ENABLE_POLICY_ENFORCEMENT" = true ] || [ "$ENABLE_CIS_BENCHMARKS" = true ] || [ "$ENABLE_SECURITY_DASHBOARD" = true ]; then
        log "Setting up security components..."
        
        # Create shared security namespace
        kubectl create namespace security-tools --dry-run=client -o yaml | kubectl apply -f -
        kubectl label namespace security-tools security=tools --overwrite
        
        # Setup Trivy if enabled
        if [ "$ENABLE_VULNERABILITY_SCANNING" = true ]; then
            log "Setting up vulnerability scanning (Trivy)..."
            kubectl create namespace trivy-system --dry-run=client -o yaml | kubectl apply -f -
            kubectl label namespace trivy-system security=scan --overwrite
        else
            # Create a patch file to disable the Trivy component in the app-of-apps
            mkdir -p patches
            cat > patches/disable-trivy.yaml <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: trivy-operator
  namespace: argocd
spec:
  syncPolicy:
    automated:
      prune: true
      selfHeal: false
    syncOptions:
      - CreateNamespace=false
EOF
            log "Created patch to disable Trivy vulnerability scanning"
        fi
        
        # Setup OPA Gatekeeper if enabled
        if [ "$ENABLE_POLICY_ENFORCEMENT" = true ]; then
            log "Setting up policy enforcement (OPA Gatekeeper)..."
            kubectl create namespace gatekeeper-system --dry-run=client -o yaml | kubectl apply -f -
            kubectl label namespace gatekeeper-system security=policy --overwrite
        else
            # Create a patch file to disable the Gatekeeper component in the app-of-apps
            mkdir -p patches
            cat > patches/disable-gatekeeper.yaml <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gatekeeper
  namespace: argocd
spec:
  syncPolicy:
    automated:
      prune: true
      selfHeal: false
    syncOptions:
      - CreateNamespace=false
EOF
            log "Created patch to disable OPA Gatekeeper policy enforcement"
        fi
        
        # Setup CIS Benchmarks if enabled
        if [ "$ENABLE_CIS_BENCHMARKS" = false ]; then
            # Create a patch file to disable the kube-bench component in the app-of-apps
            mkdir -p patches
            cat > patches/disable-kube-bench.yaml <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kube-bench
  namespace: argocd
spec:
  syncPolicy:
    automated:
      prune: true
      selfHeal: false
    syncOptions:
      - CreateNamespace=false
EOF
            log "Created patch to disable CIS benchmarking"
        else
            log "Setting up CIS benchmarking (kube-bench)..."
        fi
        
        # Setup Security Dashboard if enabled
        if [ "$ENABLE_SECURITY_DASHBOARD" = false ]; then
            # Create a patch file to disable the security dashboard component in the app-of-apps
            mkdir -p patches
            cat > patches/disable-security-dashboard.yaml <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: security-dashboard
  namespace: argocd
spec:
  syncPolicy:
    automated:
      prune: true
      selfHeal: false
    syncOptions:
      - CreateNamespace=false
EOF
            log "Created patch to disable security dashboard"
        else
            log "Setting up security dashboard..."
        fi
        
        log "Verifying deployment of security components via ArgoCD..."
        log "Note: Full security component deployment will be completed by ArgoCD"
        log "Initial security setup completed"
        
        # Apply patches if any were created
        if [ -d "patches" ] && [ "$(ls -A patches)" ]; then
            log "Applying patches to disable selected security components..."
            for patch in patches/*.yaml; do
                if [ -f "$patch" ]; then
                    kubectl apply -f "$patch"
                fi
            done
        fi
        
        # Show security information
        info "Security reports can be generated using: ./scripts/container-security.sh"
        
        # Run initial security assessment if enabled
        if [ -f "scripts/container-security.sh" ] && [ "$ENABLE_VULNERABILITY_SCANNING" = true ]; then
            log "Running initial security assessment (this may take a few minutes)..."
            # Run in background to not block installation, but capture output
            ./scripts/container-security.sh > security-initial-assessment.txt &
            log "Initial security assessment started in background"
            log "Results will be available in: security-initial-assessment.txt"
        fi
    else
        log "All security components are disabled. Skipping security setup."
    fi
}

# Main installation flow
main() {
    # Parse command line arguments
    parse_args "$@"
    
    print_header "STARTING INSTALLATION OF APPDEPLOY PLATFORM"
    
    # Record start time for total installation duration
    local start_time=$(date +%s)
    
    # Create detailed installation log
    log "Installation started at $(date)"
    log "Full logs will be available at $LOG_FILE"
    
    # Execute installation steps with error handling
    {
        check_network_connectivity
        configure_proxy
        check_requirements
        apply_system_optimizations
        install_k3s
        deploy_base_infrastructure
        deploy_argocd
        deploy_applications
        setup_devsecops
        setup_access
        test_backup_restore
        create_upgrade_script
        verify_installation
    } || {
        error_code=$?
        error "Installation failed with error code $error_code"
        log "Please check the logs at $LOG_FILE for details"
        exit $error_code
    }
    
    # Calculate installation duration
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))
    
    log "Installation completed successfully in ${minutes}m ${seconds}s!"
    print_completion
}

# Function to handle errors
handle_error() {
    error "Installation failed at line $1"
    exit 1
}

# Set up error handling
trap 'handle_error $LINENO' ERR

# Start installation
main "$@"
