#!/bin/bash

# Dashboard Access Script for Single Node GitOps Platform
# This script provides easy access to all dashboard URLs and credentials

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

header() {
    echo -e "${CYAN}$1${NC}"
}

# Function to check if service is running
check_service() {
    local namespace=$1
    local service=$2
    
    if kubectl get service "$service" -n "$namespace" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to get service URL
get_service_url() {
    local namespace=$1
    local service=$2
    local port=$3
    
    local server_ip=$(hostname -I | awk '{print $1}' || echo "localhost")
    local node_port=$(kubectl get service "$service" -n "$namespace" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "$port")
    
    echo "http://${server_ip}:${node_port}"
}

# Function to check if kubectl is available
check_kubectl() {
    if ! command -v kubectl >/dev/null 2>&1; then
        error "kubectl is not available. Please ensure K3s is installed and configured."
        exit 1
    fi
    
    if ! kubectl cluster-info >/dev/null 2>&1; then
        error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
        exit 1
    fi
}

# Function to get dashboard token
get_dashboard_token() {
    if kubectl get serviceaccount admin-user -n kubernetes-dashboard >/dev/null 2>&1; then
        local token=$(kubectl -n kubernetes-dashboard create token admin-user 2>/dev/null || echo "Token creation failed")
        echo "$token"
    else
        echo "ServiceAccount not found"
    fi
}

# Function to get ArgoCD password
get_argocd_password() {
    local password=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "Not available")
    echo "$password"
}

# Main function
main() {
    clear
    header "🖥️  ====================================="
    header "   Single Node GitOps Dashboard Access"
    header "====================================="
    echo
    
    # Check prerequisites
    check_kubectl
    
    local server_ip=$(hostname -I | awk '{print $1}' || echo "localhost")
    
    # Grafana Dashboard
    header "📊 Grafana (Monitoring & Metrics)"
    if check_service "monitoring" "grafana"; then
        local grafana_url=$(get_service_url "monitoring" "grafana" "3000")
        success "Status: Running"
        info "URL: $grafana_url"
        info "Default Login: admin / admin (change on first login)"
        info "Features: Cluster metrics, Dell hardware monitoring, application metrics"
        info "Dashboards: K3s Overview, Dell Hardware Monitor, Custom metrics"
    else
        warn "Grafana service not found or not running"
    fi
    echo
    
    # ArgoCD Dashboard
    header "🔄 ArgoCD (GitOps Management)"
    if check_service "argocd" "argocd-server"; then
        local argocd_url=$(get_service_url "argocd" "argocd-server" "8081")
        local argocd_password=$(get_argocd_password)
        success "Status: Running"
        info "URL: $argocd_url"
        info "Login: admin / $argocd_password"
        info "Features: Application deployments, Git sync status, GitOps workflows"
        info "Use: Manage application lifecycle and monitor sync status"
    else
        warn "ArgoCD service not found or not running"
    fi
    echo
    
    # Kubernetes Dashboard
    header "☸️  Kubernetes Dashboard (Cluster Management)"
    if check_service "kubernetes-dashboard" "kubernetes-dashboard"; then
        local k8s_url=$(get_service_url "kubernetes-dashboard" "kubernetes-dashboard" "8443")
        local dashboard_token=$(get_dashboard_token)
        success "Status: Running"
        info "URL: $k8s_url"
        if [ "$dashboard_token" != "ServiceAccount not found" ] && [ "$dashboard_token" != "Token creation failed" ]; then
            info "Access Token: ${dashboard_token:0:50}..."
            info "Full Token: $dashboard_token"
        else
            warn "Token: Run 'kubectl -n kubernetes-dashboard create token admin-user'"
        fi
        info "Features: Cluster overview, resource management, pod logs, yaml editing"
    else
        warn "Kubernetes Dashboard not found or not running"
        info "Deploy with: kubectl apply -f applications/dashboard/"
    fi
    echo
    
    # Storage Dashboard section 
    header "💾 Storage (Local-path)"
    info "Using local-path provisioner for storage (no UI available)"
    info "PVs are stored in /var/lib/rancher/k3s/storage on the node"
    info "Features: Simple local storage without management overhead"
    info "Use: Check storage usage with: df -h /var/lib/rancher/k3s/storage"
    echo
    
    # Prometheus (Direct Access)
    header "📈 Prometheus (Metrics Collection)"
    if check_service "monitoring" "prometheus"; then
        local prometheus_url=$(get_service_url "monitoring" "prometheus" "9090")
        success "Status: Running"
        info "URL: $prometheus_url"
        info "Features: Raw metrics, query interface, alerting rules"
        info "Use: Debug metrics, create custom queries, test alerts"
    else
        warn "Prometheus service not found or not running"
    fi
    echo
    
    # Dell OpenManage (if available)
    header "🔧 Dell OpenManage (Hardware Monitoring)"
    if systemctl is-active --quiet dsm_om_connsvc 2>/dev/null; then
        success "Status: Running"
        info "URL: https://${server_ip}:1311"
        info "Login: root / (system root password)"
        info "Features: Hardware health, IPMI sensors, system logs, firmware updates"
        info "Use: Monitor server hardware, check temperatures, manage RAID"
    else
        warn "Dell OpenManage not running or not installed"
        info "Install with: ./bootstrap/dell-optimizations.sh"
    fi
    echo
    
    # Quick Access Commands
    header "🚀 Quick Access Commands"
    echo "# Get all dashboard URLs"
    echo "./scripts/dashboard-access.sh"
    echo
    echo "# Check system health"
    echo "./scripts/health-check.sh"
    echo
    echo "# Validate Dell optimizations"
    echo "./scripts/validate-dell-optimizations.sh"
    echo
    echo "# Create Kubernetes Dashboard token"
    echo "kubectl -n kubernetes-dashboard create token admin-user"
    echo
    echo "# Port forward services (if needed)"
    echo "kubectl port-forward -n monitoring svc/grafana 3000:3000"
    echo "kubectl port-forward -n argocd svc/argocd-server 8081:8081"
    echo
    
    # System Status Summary
    header "📋 System Status Summary"
    local running_services=0
    local total_services=5
    
    check_service "monitoring" "grafana" && ((running_services++)) || true
    check_service "argocd" "argocd-server" && ((running_services++)) || true
    check_service "kubernetes-dashboard" "kubernetes-dashboard" && ((running_services++)) || true
    # Local-path provisioner doesn't have a UI service
    check_service "monitoring" "prometheus" && ((running_services++)) || true
    
    if [ $running_services -eq $total_services ]; then
        success "All dashboard services are running ($running_services/$total_services)"
    else
        warn "Some services may not be running ($running_services/$total_services)"
        info "Run './scripts/health-check.sh' for detailed status"
    fi
    
    echo
    header "====================================="
    info "Dashboard access information generated at $(date)"
    info "Server IP: $server_ip"
    info "Bookmark these URLs for easy access!"
    header "====================================="
}

# Run main function
main "$@"
