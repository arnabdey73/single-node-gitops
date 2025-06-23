#!/bin/bash

# Health Check Enhancements Script for AppDeploy Platform
# This script adds enhanced checks for the corner cases we've mitigated

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

print_header() {
    echo -e "\n${CYAN}====================================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}====================================================================${NC}\n"
}

# Check for our enhanced health check functions
check_enhanced_health_functions() {
    print_header "CHECKING FOR ENHANCED HEALTH CHECKS"
    
    # Path to health-check.sh
    local health_check_script="./scripts/health-check.sh"
    
    if [ ! -f "$health_check_script" ]; then
        error "Health check script not found at $health_check_script"
    fi
    
    log "Checking for enhanced health check functions in $health_check_script..."
    
    # Check for our enhanced function definitions
    local enhanced_functions=(
        "check_network_connectivity"
        "check_dns_resolution"
        "check_persistent_volumes"
        "check_certificates"
        "check_systemd_services"
        "check_log_rotation"
    )
    
    local missing_functions=()
    for func in "${enhanced_functions[@]}"; do
        if ! grep -q "^# Function to $func" "$health_check_script" && ! grep -q "^${func}()" "$health_check_script"; then
            missing_functions+=("$func")
        fi
    done
    
    # Add enhancement functions if missing
    if [ ${#missing_functions[@]} -gt 0 ]; then
        log "Adding the following enhanced health check functions:"
        for func in "${missing_functions[@]}"; do
            echo "  - $func"
        done
        
        log "Creating enhanced-health-checks.sh with the new functions..."
        
        cat > enhanced-health-checks.sh << 'EOF'
#!/bin/bash

# Enhanced Health Checks for AppDeploy Platform
# Add these functions to your health-check.sh script to check for corner cases

# Function to check network connectivity
check_network_connectivity() {
    log_section "Network Connectivity"
    
    # Test connectivity to key services
    local sites=("get.k3s.io" "github.com" "k8s.io" "registry.k8s.io")
    for site in "${sites[@]}"; do
        if curl -s --connect-timeout 5 --max-time 10 -I "https://$site" &> /dev/null; then
            log_success "Connectivity to $site: OK"
        else
            log_warning "Connectivity to $site: FAILED"
        fi
    done
    
    # Check for proxy environment
    if [[ ! -z "$http_proxy" || ! -z "$https_proxy" || ! -z "$no_proxy" ]]; then
        log_info "Proxy environment detected:"
        log_info "  http_proxy: ${http_proxy:-not set}"
        log_info "  https_proxy: ${https_proxy:-not set}"
        log_info "  no_proxy: ${no_proxy:-not set}"
        
        # Check if containerd has proxy config
        if [ -f "/etc/systemd/system/containerd.service.d/proxy.conf" ]; then
            log_success "Containerd proxy configuration found"
        else
            log_warning "Containerd proxy configuration not found"
        fi
    else
        log_info "No proxy environment detected"
    fi
}

# Function to check DNS resolution
check_dns_resolution() {
    log_section "DNS Resolution"
    
    # Create a DNS test pod
    cat << EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: batch/v1
kind: Job
metadata:
  name: dns-test-health
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
    
    # Give the job time to run
    sleep 10
    
    # Check internal DNS resolution
    if kubectl logs job/dns-test-health -n default 2>/dev/null | grep -q "kubernetes.default.svc.cluster.local"; then
        log_success "Internal DNS resolution: OK"
    else
        log_error "Internal DNS resolution: FAILED"
    fi
    
    # Check external DNS resolution
    if kubectl logs job/dns-test-health -n default 2>/dev/null | grep -q "github.com"; then
        log_success "External DNS resolution: OK"
    else
        log_error "External DNS resolution: FAILED"
    fi
    
    # Clean up
    kubectl delete job dns-test-health -n default >/dev/null 2>&1
}

# Function to check persistent volumes
check_persistent_volumes() {
    log_section "Persistent Volumes"
    
    # Check volume path exists
    local volume_path="/var/lib/rancher/k3s/storage"
    if [ -d "$volume_path" ]; then
        log_success "Local storage path exists: $volume_path"
        
        # Check permissions
        if [ -w "$volume_path" ]; then
            log_success "Storage path is writable"
        else
            log_error "Storage path is not writable"
        fi
    else
        log_error "Storage path does not exist: $volume_path"
    fi
    
    # Check for stuck PVs or PVCs
    local stuck_pvs=$(kubectl get pv 2>/dev/null | grep -c "Terminating")
    if [ "$stuck_pvs" -eq 0 ]; then
        log_success "No stuck persistent volumes"
    else
        log_error "Found $stuck_pvs stuck persistent volumes"
    fi
    
    local stuck_pvcs=$(kubectl get pvc --all-namespaces 2>/dev/null | grep -c "Terminating")
    if [ "$stuck_pvcs" -eq 0 ]; then
        log_success "No stuck persistent volume claims"
    else
        log_error "Found $stuck_pvcs stuck persistent volume claims"
    fi
}

# Function to check certificate expiry
check_certificates() {
    log_section "Certificate Expiry"
    
    # Get all TLS secrets
    local cert_secrets=$(kubectl get secrets --field-selector type=kubernetes.io/tls --all-namespaces -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name --no-headers 2>/dev/null)
    
    if [ -z "$cert_secrets" ]; then
        log_info "No TLS certificates found"
        return
    fi
    
    # Check each certificate
    echo "$cert_secrets" | while read -r namespace name; do
        if [ -n "$namespace" ] && [ -n "$name" ]; then
            # Get certificate data
            local cert_data=$(kubectl get secret "$name" -n "$namespace" -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d)
            
            if [ -n "$cert_data" ]; then
                # Create temp file
                local temp_cert=$(mktemp)
                echo "$cert_data" > "$temp_cert"
                
                # Get expiry date
                local not_after=$(openssl x509 -in "$temp_cert" -enddate -noout 2>/dev/null | cut -d= -f2)
                local expiry_date=$(date -d "$not_after" +%s 2>/dev/null)
                local current_date=$(date +%s)
                local days_left=$(( (expiry_date - current_date) / 86400 ))
                
                # Clean up
                rm -f "$temp_cert"
                
                if [ "$days_left" -lt 0 ]; then
                    log_error "Certificate $namespace/$name has EXPIRED ($days_left days)"
                elif [ "$days_left" -lt 30 ]; then
                    log_warning "Certificate $namespace/$name expires soon ($days_left days left)"
                else
                    log_success "Certificate $namespace/$name is valid ($days_left days left)"
                fi
            else
                log_warning "Could not decode certificate data for $namespace/$name"
            fi
        fi
    done
}

# Function to check systemd services
check_systemd_services() {
    log_section "Systemd Services"
    
    # Check k3s service
    if systemctl is-active --quiet k3s; then
        log_success "K3s service is running"
        
        # Check if enabled at boot
        if systemctl is-enabled --quiet k3s; then
            log_success "K3s service is enabled at boot"
        else
            log_warning "K3s service is not enabled at boot"
        fi
    else
        log_error "K3s service is not running"
    fi
    
    # Check containerd service
    if systemctl is-active --quiet containerd; then
        log_success "Containerd service is running"
    else
        log_error "Containerd service is not running"
    fi
}

# Function to check log rotation
check_log_rotation() {
    log_section "Log Rotation"
    
    # Check logrotate configuration
    if [ -f "/etc/logrotate.d/containerd" ]; then
        log_success "Containerd log rotation is configured"
    else
        log_warning "Containerd log rotation is not configured"
    fi
    
    # Check for the cleanup cronjob
    if kubectl get cronjob -n kube-system system-cleanup &>/dev/null; then
        log_success "System cleanup cronjob exists"
    else
        log_warning "System cleanup cronjob not found"
    fi
    
    # Check log volume usage
    if [ -d "/var/log/containers" ]; then
        local log_usage=$(df -h /var/log | tail -n 1 | awk '{print $5}' | tr -d '%')
        if [ "$log_usage" -gt 90 ]; then
            log_error "Log volume is critically full: ${log_usage}%"
        elif [ "$log_usage" -gt 80 ]; then
            log_warning "Log volume is getting full: ${log_usage}%"
        else
            log_success "Log volume usage: ${log_usage}%"
        fi
    fi
}

# Add these calls to your main() function in health-check.sh:
#
# check_network_connectivity
# check_dns_resolution
# check_persistent_volumes
# check_certificates
# check_systemd_services
# check_log_rotation
EOF
        
        log "Enhanced health checks created. Add these functions to your health-check.sh script."
        log "See enhanced-health-checks.sh for the new functions and integration instructions."
    else
        log "Enhanced health check functions are already present in the health-check.sh script ✓"
    }
}

# Check if node-recovery.sh exists
check_node_recovery_script() {
    print_header "CHECKING FOR NODE RECOVERY SCRIPT"
    
    if [ -f "./scripts/node-recovery.sh" ]; then
        log "Node recovery script found ✓"
        
        # Make it executable
        chmod +x ./scripts/node-recovery.sh
    else
        error "Node recovery script not found at ./scripts/node-recovery.sh"
    fi
}

# Run all checks
main() {
    print_header "CHECKING FOR ENHANCED MONITORING COMPONENTS"
    
    # Check for health check enhancements
    check_enhanced_health_functions
    
    # Check for node recovery script
    check_node_recovery_script
    
    print_header "ENHANCED MONITORING CHECK COMPLETE"
    log "Your platform now has enhanced monitoring capabilities for corner cases ✓"
    log "Use ./scripts/health-check.sh to run a comprehensive health check"
    log "Use ./scripts/node-recovery.sh if you need to recover from a node failure or reboot"
}

# Run main function
main
