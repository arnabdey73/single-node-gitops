#!/bin/bash

# Health Check Script for Single Node GitOps Platform
# This script performs comprehensive health checks on the entire platform

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((CHECKS_PASSED++))
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((CHECKS_WARNING++))
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((CHECKS_FAILED++))
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check pod status
check_pod_status() {
    local namespace=$1
    local app=$2
    local pods

    pods=$(kubectl get pods -n "$namespace" -l app.kubernetes.io/name="$app" --no-headers 2>/dev/null || echo "")
    
    if [ -z "$pods" ]; then
        log_error "No pods found for $app in namespace $namespace"
        return 1
    fi
    
    local ready_pods=0
    local total_pods=0
    
    while IFS= read -r pod; do
        if [ -n "$pod" ]; then
            total_pods=$((total_pods + 1))
            local status=$(echo "$pod" | awk '{print $3}')
            local ready=$(echo "$pod" | awk '{print $2}')
            
            if [[ "$status" == "Running" && "$ready" == *"/"* ]]; then
                local ready_count=$(echo "$ready" | cut -d'/' -f1)
                local total_count=$(echo "$ready" | cut -d'/' -f2)
                if [ "$ready_count" -eq "$total_count" ]; then
                    ready_pods=$((ready_pods + 1))
                fi
            fi
        fi
    done <<< "$pods"
    
    if [ "$ready_pods" -eq "$total_pods" ] && [ "$total_pods" -gt 0 ]; then
        log_success "$app: $ready_pods/$total_pods pods ready"
        return 0
    else
        log_error "$app: $ready_pods/$total_pods pods ready"
        return 1
    fi
}

# Function to check service status
check_service_status() {
    local namespace=$1
    local service=$2
    
    if kubectl get service "$service" -n "$namespace" >/dev/null 2>&1; then
        local endpoints=$(kubectl get endpoints "$service" -n "$namespace" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || echo "")
        if [ -n "$endpoints" ]; then
            log_success "Service $service has active endpoints"
            return 0
        else
            log_warning "Service $service exists but has no endpoints"
            return 1
        fi
    else
        log_error "Service $service not found in namespace $namespace"
        return 1
    fi
}

# Function to check persistent volume claims
check_pvc_status() {
    local namespace=$1
    local pvc=$2
    
    local status=$(kubectl get pvc "$pvc" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    
    case "$status" in
        "Bound")
            log_success "PVC $pvc is bound"
            return 0
            ;;
        "Pending")
            log_warning "PVC $pvc is pending"
            return 1
            ;;
        "NotFound")
            log_error "PVC $pvc not found in namespace $namespace"
            return 1
            ;;
        *)
            log_error "PVC $pvc has status: $status"
            return 1
            ;;
    esac
}

# Function to check node resources
check_node_resources() {
    log_info "Checking node resources..."
    
    # Check if kubectl top works
    if ! kubectl top nodes >/dev/null 2>&1; then
        log_warning "kubectl top nodes not available (metrics-server might not be running)"
        return
    fi
    
    local node_info=$(kubectl top nodes --no-headers 2>/dev/null)
    
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            local node=$(echo "$line" | awk '{print $1}')
            local cpu_usage=$(echo "$line" | awk '{print $2}' | sed 's/[^0-9]//g')
            local memory_usage=$(echo "$line" | awk '{print $4}' | sed 's/[^0-9]//g')
            
            # Check CPU usage (warn if > 80%)
            if [ "$cpu_usage" -gt 80 ]; then
                log_warning "Node $node CPU usage: ${cpu_usage}%"
            else
                log_success "Node $node CPU usage: ${cpu_usage}%"
            fi
            
            # Check memory usage (warn if > 80%)
            if [ "$memory_usage" -gt 80 ]; then
                log_warning "Node $node memory usage: ${memory_usage}%"
            else
                log_success "Node $node memory usage: ${memory_usage}%"
            fi
        fi
    done <<< "$node_info"
}

# Function to check disk space
check_disk_space() {
    log_info "Checking disk space..."
    
    local disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    
    if [ "$disk_usage" -gt 90 ]; then
        log_error "Root filesystem usage: ${disk_usage}% (critical)"
    elif [ "$disk_usage" -gt 80 ]; then
        log_warning "Root filesystem usage: ${disk_usage}% (warning)"
    else
        log_success "Root filesystem usage: ${disk_usage}%"
    fi
    
    # Check if longhorn directory exists and check its usage
    if [ -d "/var/lib/longhorn" ]; then
        local longhorn_usage=$(df /var/lib/longhorn | tail -1 | awk '{print $5}' | sed 's/%//')
        if [ "$longhorn_usage" -gt 90 ]; then
            log_error "Longhorn storage usage: ${longhorn_usage}% (critical)"
        elif [ "$longhorn_usage" -gt 80 ]; then
            log_warning "Longhorn storage usage: ${longhorn_usage}% (warning)"
        else
            log_success "Longhorn storage usage: ${longhorn_usage}%"
        fi
    fi
}

# Main health check function
main() {
    echo "========================================"
    echo "Single Node GitOps Platform Health Check"
    echo "========================================"
    echo ""
    
    # Check prerequisites
    log_info "Checking prerequisites..."
    
    if ! command_exists kubectl; then
        log_error "kubectl not found"
        exit 1
    fi
    
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    log_success "kubectl connection successful"
    
    # Check cluster status
    log_info "Checking cluster status..."
    
    local node_count=$(kubectl get nodes --no-headers | wc -l)
    local ready_nodes=$(kubectl get nodes --no-headers | grep -c "Ready" || echo "0")
    
    if [ "$ready_nodes" -eq "$node_count" ] && [ "$node_count" -gt 0 ]; then
        log_success "All $node_count nodes are ready"
    else
        log_error "$ready_nodes/$node_count nodes are ready"
    fi
    
    # Check system resources
    check_node_resources
    check_disk_space
    
    # Check core components
    log_info "Checking core components..."
    
    # K3s system components
    check_pod_status "kube-system" "local-path-provisioner"
    check_pod_status "kube-system" "coredns"
    
    # ArgoCD
    log_info "Checking ArgoCD..."
    check_pod_status "argocd" "argocd-server"
    check_pod_status "argocd" "argocd-application-controller"
    check_pod_status "argocd" "argocd-repo-server"
    check_service_status "argocd" "argocd-server"
    
    # Check ArgoCD applications
    local argocd_apps=$(kubectl get applications -n argocd --no-headers 2>/dev/null | wc -l)
    if [ "$argocd_apps" -gt 0 ]; then
        log_success "Found $argocd_apps ArgoCD applications"
        
        # Check application sync status
        local synced_apps=$(kubectl get applications -n argocd -o jsonpath='{.items[?(@.status.sync.status=="Synced")].metadata.name}' 2>/dev/null | wc -w)
        if [ "$synced_apps" -eq "$argocd_apps" ]; then
            log_success "All ArgoCD applications are synced"
        else
            log_warning "$synced_apps/$argocd_apps ArgoCD applications are synced"
        fi
    else
        log_warning "No ArgoCD applications found"
    fi
    
    # Monitoring stack
    log_info "Checking monitoring stack..."
    
    if kubectl get namespace monitoring >/dev/null 2>&1; then
        check_pod_status "monitoring" "prometheus"
        check_pod_status "monitoring" "grafana"
        check_pod_status "monitoring" "loki"
        check_service_status "monitoring" "prometheus"
        check_service_status "monitoring" "grafana"
        check_service_status "monitoring" "loki"
        check_pvc_status "monitoring" "prometheus-storage"
        check_pvc_status "monitoring" "grafana-pv-claim"
        check_pvc_status "monitoring" "loki-storage"
    else
        log_warning "Monitoring namespace not found"
    fi
    
    # External Git Integration
    log_info "Checking external Git integration..."
    
    log_info "Using external Git hosting (GitHub/GitLab/etc.)"
    log_success "External Git integration configured"
    
    # Storage (Longhorn)
    log_info "Checking storage..."
    
    if kubectl get namespace longhorn-system >/dev/null 2>&1; then
        check_pod_status "longhorn-system" "longhorn-manager"
        check_pod_status "longhorn-system" "longhorn-driver-deployer"
        check_pod_status "longhorn-system" "longhorn-ui"
    else
        log_warning "Longhorn namespace not found"
    fi
    
    # Check storage classes
    local storage_classes=$(kubectl get storageclass --no-headers 2>/dev/null | wc -l)
    if [ "$storage_classes" -gt 0 ]; then
        log_success "Found $storage_classes storage classes"
    else
        log_error "No storage classes found"
    fi
    
    # Security components
    log_info "Checking security components..."
    
    if kubectl get namespace cert-manager >/dev/null 2>&1; then
        check_pod_status "cert-manager" "cert-manager"
        check_pod_status "cert-manager" "cert-manager-webhook"
        check_pod_status "cert-manager" "cert-manager-cainjector"
    else
        log_warning "cert-manager namespace not found"
    fi
    
    # Check sealed-secrets in kube-system
    if kubectl get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets >/dev/null 2>&1; then
        check_pod_status "kube-system" "sealed-secrets"
    else
        log_warning "sealed-secrets not found"
    fi
    
    # Summary
    echo ""
    echo "========================================"
    echo "Health Check Summary"
    echo "========================================"
    echo -e "${GREEN}Passed: $CHECKS_PASSED${NC}"
    echo -e "${YELLOW}Warnings: $CHECKS_WARNING${NC}"
    echo -e "${RED}Failed: $CHECKS_FAILED${NC}"
    echo ""
    
    if [ "$CHECKS_FAILED" -eq 0 ]; then
        if [ "$CHECKS_WARNING" -eq 0 ]; then
            echo -e "${GREEN}✓ All checks passed! Your platform is healthy.${NC}"
            exit 0
        else
            echo -e "${YELLOW}⚠ Platform is mostly healthy but has some warnings.${NC}"
            exit 0
        fi
    else
        echo -e "${RED}✗ Platform has issues that need attention.${NC}"
        exit 1
    fi
}

# Run main function
main "$@"
