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
    echo -    # Storage (local-path)
    log_section "Storage"
    
    # Verify local-path storage class exists
    if kubectl get storageclass local-path >/dev/null 2>&1; then
        log_success "Local-path storage class ready"
    else
        log_warning "Local-path storage class not found"
    fi
    
    # Check PVCs and PVs
    local pvc_count=$(kubectl get pvc --all-namespaces -o json | jq '.items | length')
    local pv_count=$(kubectl get pv -o json | jq '.items | length')
    log_info "PVCs: ${pvc_count}, PVs: ${pv_count}"}[PASS]${NC} $1"
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
    
    # Get node info and process
    kubectl top nodes --no-headers 2>/dev/null | while read -r line; do
        if [ -n "$line" ]; then
            # Extract node name, CPU and memory usage
            node=$(echo "$line" | awk '{print $1}')
            cpu_usage=$(echo "$line" | awk '{print $2}' | sed 's/[^0-9]//g')
            memory_usage=$(echo "$line" | awk '{print $4}' | sed 's/[^0-9]//g')
            
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
    done
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
    
    # Check if local-path storage directory exists and check its usage
    if [ -d "/var/lib/rancher/k3s/storage" ]; then
        local storage_usage=$(df /var/lib/rancher/k3s/storage | tail -1 | awk '{print $5}' | sed 's/%//')
        if [ "$storage_usage" -gt 90 ]; then
            log_error "Local storage usage: ${storage_usage}% (critical)"
        elif [ "$storage_usage" -gt 80 ]; then
            log_warning "Local storage usage: ${storage_usage}% (warning)"
        else
            log_success "Local storage usage: ${storage_usage}%"
        fi
    fi
}

# Function to check Dell hardware status
check_dell_hardware() {
    log_info "Checking Dell hardware status..."
    
    # Check if Dell OpenManage is installed and running
    if command_exists omreport; then
        # Check system health
        local system_health=$(omreport system summary 2>/dev/null | grep "Main System Chassis" | awk '{print $NF}' || echo "Unknown")
        if [ "$system_health" = "Ok" ]; then
            log_success "Dell system health: $system_health"
        elif [ "$system_health" = "Unknown" ]; then
            log_warning "Dell system health: Unable to determine status"
        else
            log_error "Dell system health: $system_health"
        fi
        
        # Check storage controller health
        local storage_health=$(omreport storage controller 2>/dev/null | grep "Status" | head -1 | awk '{print $NF}' || echo "Unknown")
        if [ "$storage_health" = "Ok" ]; then
            log_success "Dell storage controller: $storage_health"
        elif [ "$storage_health" = "Unknown" ]; then
            log_warning "Dell storage controller: Unable to determine status"
        else
            log_error "Dell storage controller: $storage_health"
        fi
        
        # Check memory health
        local memory_errors=$(omreport chassis memory 2>/dev/null | grep -c "Correctable" || echo "0")
        if [ "$memory_errors" -eq 0 ]; then
            log_success "No memory errors detected"
        else
            log_warning "Memory correctable errors detected: $memory_errors"
        fi
    else
        log_warning "Dell OpenManage tools not installed - run ./bootstrap/dell-optimizations.sh"
    fi
    
    # Check IPMI functionality
    if command_exists ipmitool; then
        if sudo ipmitool sensor list >/dev/null 2>&1; then
            local temp_sensors=$(sudo ipmitool sensor list | grep -i temp | grep -c "ok" || echo "0")
            local fan_sensors=$(sudo ipmitool sensor list | grep -i fan | grep -c "ok" || echo "0")
            
            if [ "$temp_sensors" -gt 0 ]; then
                log_success "Temperature sensors functional: $temp_sensors sensors OK"
            else
                log_warning "No temperature sensors detected or accessible"
            fi
            
            if [ "$fan_sensors" -gt 0 ]; then
                log_success "Fan sensors functional: $fan_sensors sensors OK"
            else
                log_warning "No fan sensors detected or accessible"
            fi
        else
            log_warning "IPMI sensors not accessible - may need configuration"
        fi
    else
        log_warning "IPMI tools not installed - run ./bootstrap/dell-optimizations.sh"
    fi
    
    # Check CPU temperature thresholds
    if [ -d "/sys/class/thermal" ]; then
        local thermal_zones=$(find /sys/class/thermal -name "thermal_zone*" | wc -l)
        if [ "$thermal_zones" -gt 0 ]; then
            log_success "Thermal monitoring available: $thermal_zones thermal zones"
            
            # Check for critical temperatures
            local critical_temp=false
            for zone in /sys/class/thermal/thermal_zone*/temp; do
                if [ -f "$zone" ]; then
                    local temp=$(cat "$zone" 2>/dev/null || echo "0")
                    local temp_celsius=$((temp / 1000))
                    if [ "$temp_celsius" -gt 80 ]; then
                        critical_temp=true
                        break
                    fi
                fi
            done
            
            if [ "$critical_temp" = "true" ]; then
                log_error "Critical CPU temperature detected (>80°C)"
            else
                log_success "CPU temperatures within normal range"
            fi
        else
            log_warning "No thermal zones detected"
        fi
    fi
}

# Function to check hardware performance optimizations
check_hardware_optimizations() {
    log_info "Checking hardware performance optimizations..."
    
    # Check CPU governor
    if [ -f "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor" ]; then
        local governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "unknown")
        if [ "$governor" = "performance" ]; then
            log_success "CPU governor set to performance"
        else
            log_warning "CPU governor is '$governor', recommend 'performance' for this workload"
        fi
    else
        log_warning "CPU frequency scaling not available or not configured"
    fi
    
    # Check disk scheduler
    local optimized_disks=0
    local total_disks=0
    for disk in /sys/block/sd*/queue/scheduler; do
        if [ -f "$disk" ]; then
            total_disks=$((total_disks + 1))
            local scheduler=$(cat "$disk" 2>/dev/null | grep -o '\[.*\]' | tr -d '[]' || echo "unknown")
            if [ "$scheduler" = "mq-deadline" ] || [ "$scheduler" = "deadline" ]; then
                optimized_disks=$((optimized_disks + 1))
            fi
        fi
    done
    
    if [ "$total_disks" -gt 0 ]; then
        if [ "$optimized_disks" -eq "$total_disks" ]; then
            log_success "All $total_disks disks using optimized scheduler"
        else
            log_warning "$optimized_disks/$total_disks disks using optimized scheduler"
        fi
    fi
    
    # Check system limits
    local nofile_limit=$(ulimit -n)
    if [ "$nofile_limit" -ge 65536 ]; then
        log_success "Open file limit optimized: $nofile_limit"
    else
        log_warning "Open file limit may be too low: $nofile_limit (recommend 65536+)"
    fi
}

# Function to check security dashboard components
check_security_dashboard() {
    log_info "Checking security dashboard..."
    
    if kubectl get namespace security-dashboard >/dev/null 2>&1; then
        check_pod_status "security-dashboard" "security-dashboard"
        check_service_status "security-dashboard" "security-dashboard"
        
        # Check ConfigMap exists
        if kubectl get configmap -n security-dashboard security-dashboard-config >/dev/null 2>&1; then
            log_success "Security dashboard config exists"
        else
            log_warning "Security dashboard config not found"
        fi
        
        # Check ingress
        if kubectl get ingress -n security-dashboard security-dashboard-ingress >/dev/null 2>&1; then
            local ingress_host=$(kubectl get ingress -n security-dashboard security-dashboard-ingress -o jsonpath='{.spec.rules[0].host}' 2>/dev/null)
            if [ -n "$ingress_host" ]; then
                log_success "Security dashboard ingress configured with host: $ingress_host"
            else
                log_warning "Security dashboard ingress has no host configured"
            fi
        else
            log_warning "Security dashboard ingress not found"
        fi
    else
        if kubectl get configmap -n monitoring security-dashboard-config >/dev/null 2>&1; then
            log_success "Security dashboard integrated with monitoring"
        else
            log_warning "Security dashboard not found in dedicated or monitoring namespace"
        fi
    fi
    
    # Check Prometheus metrics/alerts for security
    if kubectl get namespace monitoring >/dev/null 2>&1; then
        if kubectl get configmap -n monitoring prometheus-security-rules >/dev/null 2>&1; then
            log_success "Security alerts configured in Prometheus"
        else
            log_warning "Security alerts not configured in Prometheus"
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
    
    # Dell Hardware Monitoring
    check_dell_hardware
    
    # Hardware Performance Optimizations
    check_hardware_optimizations
    
    # Storage (local-path)
    log_info "Checking storage..."
    
    # Check if local-path storage class exists
    if kubectl get storageclass local-path >/dev/null 2>&1; then
        log_success "Local-path storage class exists"
    else
        log_warning "Local-path storage class not found"
    fi
    
    # Check storage classes
    local storage_classes=$(kubectl get storageclass --no-headers 2>/dev/null | wc -l)
    if [ "$storage_classes" -gt 0 ]; then
        log_success "Found $storage_classes storage classes"
    else
        log_error "No storage classes found"
    fi
    
    # Docker Registry
    log_info "Checking Docker registry..."
    
    if kubectl get namespace registry >/dev/null 2>&1; then
        check_pod_status "registry" "docker-registry"
        check_service_status "registry" "docker-registry"
        
        # Check if registry service is exposed via NodePort
        local registry_nodeport=$(kubectl get svc docker-registry -n registry -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
        if [ -n "$registry_nodeport" ] && [ "$registry_nodeport" -eq 30500 ]; then
            log_success "Docker registry exposed on NodePort 30500"
        elif [ -n "$registry_nodeport" ]; then
            log_success "Docker registry exposed on NodePort $registry_nodeport"
        else
            log_warning "Docker registry not exposed via NodePort"
        fi
        
        # Check registry PVC if exists
        if kubectl get pvc -n registry registry-docker-registry >/dev/null 2>&1; then
            check_pvc_status "registry" "registry-docker-registry"
        fi
    else
        log_warning "Docker registry namespace not found"
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
    
    # Check Trivy Operator
    if kubectl get namespace trivy-system >/dev/null 2>&1; then
        check_pod_status "trivy-system" "trivy-operator"
        log_info "Checking vulnerabilities reports..."
        local vuln_reports=$(kubectl get vulnerabilityreports --all-namespaces 2>/dev/null | grep -v "NAME" | wc -l)
        if [ "$vuln_reports" -gt 0 ]; then
            log_success "Found $vuln_reports vulnerability reports"
            
            # Check for critical vulnerabilities
            local critical_vulns=$(kubectl get vulnerabilityreports --all-namespaces -o json 2>/dev/null | 
                jq -r '.items[] | select(.report.summary.criticalCount > 0) | .metadata.name' | wc -l)
            
            if [ "$critical_vulns" -gt 0 ]; then
                log_warning "Found $critical_vulns reports with critical vulnerabilities"
            else
                log_success "No critical vulnerabilities detected"
            fi
        else
            log_warning "No vulnerability reports found - Trivy may still be scanning"
        fi
    else
        log_warning "trivy-system namespace not found"
    fi
    
    # Check OPA Gatekeeper
    if kubectl get namespace gatekeeper-system >/dev/null 2>&1; then
        check_pod_status "gatekeeper-system" "gatekeeper-controller-manager"
        check_pod_status "gatekeeper-system" "gatekeeper-audit"
        
        # Check for constraint templates and constraints
        local constraint_templates=$(kubectl get constrainttemplates 2>/dev/null | grep -v NAME | wc -l)
        if [ "$constraint_templates" -gt 0 ]; then
            log_success "Found $constraint_templates constraint templates"
        else
            log_warning "No constraint templates found"
        fi
        
        # Check for constraint violations
        local constraints=$(kubectl get constraints --all-namespaces 2>/dev/null | grep -v NAME | wc -l || echo "0")
        if [ "$constraints" -gt 0 ]; then
            log_success "Found $constraints policy constraints"
            
            # Check if there are any violations
            local violations=$(kubectl get constraints --all-namespaces -o json 2>/dev/null | 
                jq -r '.items[] | select((.status.totalViolations // 0) > 0) | .metadata.name' | wc -l)
            
            if [ "$violations" -gt 0 ]; then
                log_warning "Found $violations policy constraints with violations"
            else
                log_success "No policy violations detected"
            fi
        else
            log_warning "No policy constraints found"
        fi
    else
        log_warning "gatekeeper-system namespace not found"
    fi
    
    # Check kube-bench CIS benchmarks
    if kubectl get namespace security-tools >/dev/null 2>&1; then
        local kb_job=$(kubectl get cronjob -n security-tools -l app.kubernetes.io/name=kube-bench -o name 2>/dev/null)
        if [ -n "$kb_job" ]; then
            log_success "kube-bench cronjob configured"
            
            # Check if there are any recent jobs
            local kb_latest_job=$(kubectl get job -n security-tools -l app.kubernetes.io/name=kube-bench --sort-by=.metadata.creationTimestamp -o name 2>/dev/null | tail -1)
            if [ -n "$kb_latest_job" ]; then
                local kb_job_status=$(kubectl get $kb_latest_job -n security-tools -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null)
                if [ "$kb_job_status" = "True" ]; then
                    log_success "Latest kube-bench job completed successfully"
                else
                    log_warning "Latest kube-bench job did not complete successfully"
                fi
            else
                log_warning "No kube-bench jobs found"
            fi
        else
            log_warning "kube-bench cronjob not found"
        fi
    else
        log_warning "security-tools namespace not found"
    fi
    
    # Check network policies
    local network_policies=$(kubectl get networkpolicy --all-namespaces 2>/dev/null | grep -v NAME | wc -l)
    if [ "$network_policies" -gt 0 ]; then
        log_success "Found $network_policies network policies"
    else
        log_warning "No network policies found - network security may be compromised"
    fi
    
    # Dell hardware monitoring
    check_dell_hardware
    
    # Check security dashboard
    check_security_dashboard
    
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
