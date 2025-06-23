#!/bin/bash

# Node Recovery Script for AppDeploy Platform
# This script helps recover from node failures or reboots

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

print_header() {
    echo -e "\n${CYAN}====================================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}====================================================================${NC}\n"
}

# Check if K3s service is running
check_k3s_service() {
    print_header "CHECKING K3S SERVICE"
    
    if systemctl is-active --quiet k3s; then
        log "K3s service is running ✓"
    else
        warn "K3s service is not running"
        log "Starting K3s service..."
        sudo systemctl start k3s
        
        # Wait for service to start
        local timeout=60
        local start_time=$(date +%s)
        
        while ! systemctl is-active --quiet k3s; do
            local current_time=$(date +%s)
            local elapsed_time=$((current_time - start_time))
            
            if [ $elapsed_time -ge $timeout ]; then
                error "Failed to start K3s service within ${timeout} seconds"
            fi
            
            log "Waiting for K3s service to start... (${elapsed_time}s elapsed)"
            sleep 5
        done
        
        log "K3s service started successfully ✓"
    fi
}

# Check for stuck resources
check_stuck_resources() {
    print_header "CHECKING FOR STUCK RESOURCES"
    
    # Check for pods in Terminating state
    log "Checking for stuck pods..."
    STUCK_PODS=$(kubectl get pods -A | grep Terminating)
    
    if [ -n "$STUCK_PODS" ]; then
        warn "Found pods stuck in Terminating state:"
        echo "$STUCK_PODS"
        
        read -p "Do you want to force delete these pods? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log "Force deleting stuck pods..."
            kubectl get pods -A | grep Terminating | awk '{print $1 " " $2}' | while read ns pod; do
                kubectl delete pod $pod -n $ns --grace-period=0 --force
            done
        fi
    else
        log "No stuck pods found ✓"
    fi
    
    # Check for stuck PVCs
    log "Checking for stuck PVCs..."
    STUCK_PVCS=$(kubectl get pvc -A | grep Terminating)
    
    if [ -n "$STUCK_PVCS" ]; then
        warn "Found PVCs stuck in Terminating state:"
        echo "$STUCK_PVCS"
        
        read -p "Do you want to force delete these PVCs? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log "Force deleting stuck PVCs..."
            kubectl get pvc -A | grep Terminating | awk '{print $1 " " $2}' | while read ns pvc; do
                kubectl patch pvc $pvc -n $ns -p '{"metadata":{"finalizers":null}}'
                kubectl delete pvc $pvc -n $ns --grace-period=0 --force
            done
        fi
    else
        log "No stuck PVCs found ✓"
    fi
}

# Restart critical services
restart_critical_services() {
    print_header "RESTARTING CRITICAL SERVICES"
    
    # Restart ArgoCD components
    log "Restarting ArgoCD components..."
    kubectl -n argocd rollout restart deployment argocd-server argocd-repo-server argocd-application-controller || true
    
    # Restart other critical components
    log "Restarting monitoring components..."
    kubectl -n monitoring rollout restart deployment prometheus-server || true
    kubectl -n monitoring rollout restart deployment grafana || true
    
    # Wait for components to be ready
    log "Waiting for components to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s || true
    
    log "Critical services restarted ✓"
}

# Fix DNS issues
fix_dns_issues() {
    print_header "CHECKING FOR DNS ISSUES"
    
    log "Testing DNS resolution inside the cluster..."
    
    # Create a test pod to check DNS
    cat << EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: dns-test
  namespace: default
spec:
  ttlSecondsAfterFinished: 300
  template:
    spec:
      containers:
      - name: dns-test
        image: busybox:1.34.1
        command:
        - sh
        - -c
        - |
          echo "Testing internal DNS..."
          nslookup kubernetes.default.svc.cluster.local
          echo "Testing external DNS..."
          nslookup github.com
      restartPolicy: Never
  backoffLimit: 1
EOF
    
    # Wait for job to complete
    sleep 10
    kubectl logs job/dns-test -n default || true
    
    # Check CoreDNS pods
    log "Checking CoreDNS pods..."
    COREDNS_PODS=$(kubectl get pods -n kube-system -l k8s-app=kube-dns -o name)
    
    if [ -z "$COREDNS_PODS" ]; then
        warn "No CoreDNS pods found"
    else
        log "Found CoreDNS pods: $COREDNS_PODS"
        
        # Restart CoreDNS if needed
        read -p "Do you want to restart CoreDNS pods? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log "Restarting CoreDNS pods..."
            kubectl delete pods -n kube-system -l k8s-app=kube-dns
            sleep 5
            kubectl get pods -n kube-system -l k8s-app=kube-dns
        fi
    fi
    
    log "DNS check complete ✓"
}

# Fix storage issues
fix_storage_issues() {
    print_header "CHECKING FOR STORAGE ISSUES"
    
    log "Checking local-path provisioner..."
    kubectl get pods -n kube-system -l app=local-path-provisioner
    
    # Check storage path
    log "Verifying local storage path..."
    if [ -d "/var/lib/rancher/k3s/storage" ]; then
        log "Storage path exists ✓"
        
        # Check permissions
        if [ -w "/var/lib/rancher/k3s/storage" ]; then
            log "Storage path is writable ✓"
        else
            warn "Storage path is not writable"
            log "Fixing storage path permissions..."
            sudo chmod 755 /var/lib/rancher/k3s/storage
        fi
    else
        warn "Storage path does not exist"
        log "Creating storage path..."
        sudo mkdir -p /var/lib/rancher/k3s/storage
        sudo chmod 755 /var/lib/rancher/k3s/storage
    fi
    
    log "Storage check complete ✓"
}

# Sync all applications
sync_applications() {
    print_header "SYNCING APPLICATIONS"
    
    log "Refreshing all ArgoCD applications..."
    for app in $(kubectl get applications -n argocd -o name); do
        log "Refreshing $app..."
        kubectl patch $app -n argocd --type merge -p '{"spec": {"syncPolicy": {"automated": {"prune": true}}}}'
    done
    
    log "Applications synced ✓"
}

# Function to check and update DNS configs
check_dns_config() {
    print_header "CHECKING DNS CONFIGURATION"
    
    # Create a ConfigMap with host DNS config
    log "Reading host DNS configuration..."
    cat << EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: host-dns-config
  namespace: kube-system
data:
  resolv.conf: |
$(cat /etc/resolv.conf | sed 's/^/    /')
EOF
    
    log "DNS configuration updated ✓"
}

# Main recovery flow
main() {
    print_header "STARTING NODE RECOVERY"
    
    check_k3s_service
    check_stuck_resources
    fix_dns_issues
    fix_storage_issues
    restart_critical_services
    check_dns_config
    sync_applications
    
    print_header "NODE RECOVERY COMPLETE"
    log "The AppDeploy platform should now be operational"
    log "Run './scripts/health-check.sh' to verify system health"
}

# Start recovery process
main
