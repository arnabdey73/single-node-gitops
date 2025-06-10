#!/bin/bash

# Dell PowerEdge R540 Performance Validation Script
# This script validates that all Dell-specific optimizations are properly applied

set -euo pipefail

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

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check Dell hardware detection
check_dell_hardware_detection() {
    log_info "Validating Dell hardware detection..."
    
    if dmidecode -s system-manufacturer 2>/dev/null | grep -qi "dell"; then
        log_success "Dell hardware detected via DMI"
    else
        log_warning "Dell hardware not detected in DMI - may be running in VM or non-Dell hardware"
    fi
    
    if [ -f "/sys/class/dmi/id/product_name" ]; then
        local product_name=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "Unknown")
        if echo "$product_name" | grep -qi "poweredge.*r540"; then
            log_success "Dell PowerEdge R540 detected: $product_name"
        else
            log_warning "Product name: $product_name (expected PowerEdge R540)"
        fi
    fi
}

# Check Dell OpenManage installation
check_openmanage_installation() {
    log_info "Validating Dell OpenManage installation..."
    
    if command_exists omreport; then
        log_success "Dell OpenManage CLI tools installed"
        
        # Check service status
        if systemctl is-active --quiet dsm_om_connsvc 2>/dev/null; then
            log_success "Dell OpenManage service is running"
        else
            log_error "Dell OpenManage service is not running"
        fi
        
        # Test basic functionality
        if timeout 10 omreport system summary >/dev/null 2>&1; then
            log_success "Dell OpenManage communication working"
        else
            log_warning "Dell OpenManage communication test failed"
        fi
    else
        log_error "Dell OpenManage CLI tools not installed"
    fi
}

# Check IPMI functionality
check_ipmi_functionality() {
    log_info "Validating IPMI functionality..."
    
    if command_exists ipmitool; then
        log_success "IPMI tools installed"
        
        # Check IPMI modules
        if lsmod | grep -q ipmi; then
            log_success "IPMI kernel modules loaded"
        else
            log_error "IPMI kernel modules not loaded"
        fi
        
        # Test IPMI communication
        if timeout 10 sudo ipmitool sensor list >/dev/null 2>&1; then
            local sensor_count=$(sudo ipmitool sensor list 2>/dev/null | wc -l)
            log_success "IPMI sensors accessible: $sensor_count sensors found"
        else
            log_warning "IPMI sensor access failed - may need configuration"
        fi
    else
        log_error "IPMI tools not installed"
    fi
}

# Check CPU optimizations
check_cpu_optimizations() {
    log_info "Validating CPU optimizations..."
    
    # Check CPU governor
    if [ -f "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor" ]; then
        local governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "unknown")
        if [ "$governor" = "performance" ]; then
            log_success "CPU governor set to performance"
        else
            log_warning "CPU governor is '$governor', expected 'performance'"
        fi
    else
        log_warning "CPU frequency scaling not available"
    fi
    
    # Check CPU count
    local cpu_count=$(nproc)
    if [ "$cpu_count" -ge 16 ]; then
        log_success "CPU count: $cpu_count cores (optimized for high core count)"
    else
        log_warning "CPU count: $cpu_count cores (expected 16+ for PowerEdge R540)"
    fi
}

# Check memory optimizations
check_memory_optimizations() {
    log_info "Validating memory optimizations..."
    
    # Check total memory
    local total_mem_gb=$(free -g | awk 'NR==2{print $2}')
    if [ "$total_mem_gb" -ge 30 ]; then
        log_success "Total memory: ${total_mem_gb}GB (optimized for high memory)"
    else
        log_warning "Total memory: ${total_mem_gb}GB (expected 32GB+ for PowerEdge R540)"
    fi
    
    # Check swap status
    if ! swapon --show | grep -q "/"; then
        log_success "Swap is disabled (recommended for Kubernetes)"
    else
        log_error "Swap is enabled (should be disabled for Kubernetes)"
    fi
    
    # Check memory tuning parameters
    local swappiness=$(cat /proc/sys/vm/swappiness 2>/dev/null || echo "60")
    if [ "$swappiness" -le 10 ]; then
        log_success "vm.swappiness set to $swappiness (optimized)"
    else
        log_warning "vm.swappiness is $swappiness (recommend ≤10)"
    fi
}

# Check storage optimizations
check_storage_optimizations() {
    log_info "Validating storage optimizations..."
    
    # Check disk schedulers
    local optimized_disks=0
    local total_disks=0
    
    for scheduler_file in /sys/block/sd*/queue/scheduler; do
        if [ -f "$scheduler_file" ]; then
            total_disks=$((total_disks + 1))
            local current_scheduler=$(grep -o '\[.*\]' "$scheduler_file" 2>/dev/null | tr -d '[]' || echo "unknown")
            if [ "$current_scheduler" = "mq-deadline" ] || [ "$current_scheduler" = "deadline" ]; then
                optimized_disks=$((optimized_disks + 1))
            fi
        fi
    done
    
    if [ "$total_disks" -gt 0 ]; then
        if [ "$optimized_disks" -eq "$total_disks" ]; then
            log_success "All $total_disks disks using optimized I/O scheduler"
        else
            log_warning "$optimized_disks/$total_disks disks using optimized I/O scheduler"
        fi
    else
        log_warning "No block devices found for scheduler check"
    fi
}

# Check network optimizations
check_network_optimizations() {
    log_info "Validating network optimizations..."
    
    # Check TCP congestion control
    local tcp_congestion=$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || echo "unknown")
    if [ "$tcp_congestion" = "bbr" ]; then
        log_success "TCP congestion control set to BBR"
    else
        log_warning "TCP congestion control is '$tcp_congestion' (recommend BBR)"
    fi
    
    # Check network buffer sizes
    local rmem_max=$(cat /proc/sys/net/core/rmem_max 2>/dev/null || echo "0")
    if [ "$rmem_max" -ge 67108864 ]; then
        log_success "Network receive buffer optimized: $rmem_max bytes"
    else
        log_warning "Network receive buffer: $rmem_max bytes (recommend 67108864+)"
    fi
}

# Check system limits
check_system_limits() {
    log_info "Validating system limits..."
    
    # Check open file limits
    local nofile_limit=$(ulimit -n)
    if [ "$nofile_limit" -ge 65536 ]; then
        log_success "Open file limit: $nofile_limit (optimized)"
    else
        log_warning "Open file limit: $nofile_limit (recommend 65536+)"
    fi
    
    # Check process limits
    local nproc_limit=$(ulimit -u)
    if [ "$nproc_limit" -ge 32768 ]; then
        log_success "Process limit: $nproc_limit (optimized)"
    else
        log_warning "Process limit: $nproc_limit (recommend 32768+)"
    fi
}

# Check Kubernetes optimizations
check_kubernetes_optimizations() {
    log_info "Validating Kubernetes optimizations..."
    
    if command_exists kubectl; then
        # Check node labels
        if kubectl get nodes -o jsonpath='{.items[0].metadata.labels}' 2>/dev/null | grep -q "node-role.kubernetes.io/worker"; then
            log_success "Node properly labeled as worker"
        else
            log_warning "Node worker label not found"
        fi
        
        # Check resource allocations
        local node_info=$(kubectl describe node 2>/dev/null | grep -A 10 "Allocated resources" || echo "")
        if echo "$node_info" | grep -q "cpu.*requests"; then
            log_success "Kubernetes resource tracking enabled"
        else
            log_warning "Kubernetes resource information not available"
        fi
        
        # Check for Dell-specific monitoring
        if kubectl get pods -n monitoring 2>/dev/null | grep -q "node-exporter"; then
            log_success "Node exporter deployed for hardware monitoring"
        else
            log_warning "Node exporter not found - hardware monitoring may be limited"
        fi
    else
        log_error "kubectl not available - cannot validate Kubernetes optimizations"
    fi
}

# Main execution
main() {
    echo "======================================================="
    echo "Dell PowerEdge R540 Performance Validation"
    echo "======================================================="
    echo ""
    
    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        log_warning "Running as root - some checks may behave differently"
    fi
    
    # Run all validation checks
    check_dell_hardware_detection
    check_openmanage_installation
    check_ipmi_functionality
    check_cpu_optimizations
    check_memory_optimizations
    check_storage_optimizations
    check_network_optimizations
    check_system_limits
    check_kubernetes_optimizations
    
    # Summary
    echo ""
    echo "======================================================="
    echo "Validation Summary"
    echo "======================================================="
    echo -e "${GREEN}Passed: $CHECKS_PASSED${NC}"
    echo -e "${YELLOW}Warnings: $CHECKS_WARNING${NC}"
    echo -e "${RED}Failed: $CHECKS_FAILED${NC}"
    echo ""
    
    if [ "$CHECKS_FAILED" -eq 0 ]; then
        if [ "$CHECKS_WARNING" -eq 0 ]; then
            echo -e "${GREEN}✓ All Dell PowerEdge R540 optimizations are properly applied!${NC}"
            exit 0
        else
            echo -e "${YELLOW}⚠ Most optimizations applied, but some warnings need attention.${NC}"
            exit 0
        fi
    else
        echo -e "${RED}✗ Some optimizations are missing or not properly configured.${NC}"
        echo "Run ./bootstrap/dell-optimizations.sh to apply missing optimizations."
        exit 1
    fi
}

# Run main function
main "$@"
