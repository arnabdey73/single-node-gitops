#!/bin/bash

# Container Security Updater for AppDeploy
# This script scans for vulnerabilities and generates reports

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

# Print header
print_header() {
    echo -e "\n${CYAN}====================================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}====================================================================${NC}\n"
}

# Check dependencies
check_dependencies() {
    local missing_deps=false
    
    for cmd in kubectl curl jq trivy; do
        if ! command -v $cmd &> /dev/null; then
            warn "$cmd is not installed. Some functionality may be limited."
            missing_deps=true
        fi
    done
    
    if [ "$missing_deps" = true ]; then
        warn "Some dependencies are missing. Install them for full functionality."
        read -p "Continue anyway? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            error "Operation aborted."
        fi
    fi
}

# Get vulnerabilities from Trivy
get_vulnerabilities() {
    log "Checking if Trivy operator is deployed..."
    
    if ! kubectl get namespace trivy-system &> /dev/null; then
        warn "Trivy operator is not deployed."
        return 1
    fi
    
    log "Getting vulnerability reports..."
    kubectl get vulnerabilityreports --all-namespaces -o wide
    
    log "Getting most critical vulnerabilities..."
    kubectl get vulnerabilityreports --all-namespaces -o json | jq '.items | sort_by(.report.summary.criticalCount) | reverse | .[0:5]'
}

# Check policy violations
check_policy_violations() {
    log "Checking if OPA Gatekeeper is deployed..."
    
    if ! kubectl get namespace gatekeeper-system &> /dev/null; then
        warn "OPA Gatekeeper is not deployed."
        return 1
    fi
    
    log "Getting policy violation reports..."
    kubectl get constraints -A
    
    # Show violations
    log "Checking for policy violations..."
    kubectl get constraints -o json | jq '.items[] | select(.status.totalViolations > 0) | {name: .metadata.name, violations: .status.totalViolations, violatingResources: .status.violations}'
}

# Run CIS benchmark
run_cis_benchmark() {
    log "Running CIS benchmark checks..."
    
    if ! kubectl get namespace security-tools &> /dev/null; then
        warn "Security tools namespace not found. CIS benchmarks may not be available."
        return 1
    fi
    
    log "Creating one-time CIS benchmark job..."
    kubectl create job --namespace security-tools cis-benchmark-$(date +%s) --from=cronjob/kube-bench
    
    # Wait for job to complete
    log "Waiting for benchmark job to complete (this may take a minute)..."
    sleep 30
    
    # Get latest job logs
    log "Getting benchmark results..."
    kubectl logs -n security-tools job/$(kubectl get job -n security-tools -o=jsonpath='{.items[-1:].metadata.name}')
}

# Generate security report
generate_report() {
    print_header "SECURITY REPORT SUMMARY"
    
    log "Generating security report..."
    
    # Output to both console and file
    local report_file="security-report-$(date +%Y%m%d).txt"
    
    {
        echo "==============================================="
        echo "  APPDEPLOY PLATFORM SECURITY REPORT"
        echo "  Generated: $(date)"
        echo "==============================================="
        echo
        
        echo "VULNERABILITY SCAN SUMMARY"
        echo "------------------------"
        get_vulnerabilities || echo "Vulnerability scanning not available"
        echo
        
        echo "POLICY COMPLIANCE"
        echo "----------------"
        check_policy_violations || echo "Policy compliance checking not available"
        echo
        
        echo "CIS BENCHMARK SUMMARY"
        echo "--------------------"
        run_cis_benchmark || echo "CIS benchmark not available"
        echo
        
        echo "RECOMMENDATIONS"
        echo "--------------"
        echo "1. Address all Critical and High vulnerabilities"
        echo "2. Review policy violations and ensure compliance"
        echo "3. Fix any failed CIS benchmark checks"
        echo
        
        echo "==============================================="
        echo "  End of Report"
        echo "==============================================="
    } | tee "$report_file"
    
    log "Security report saved to $report_file"
}

# Main function
main() {
    print_header "APPDEPLOY CONTAINER SECURITY CHECK"
    
    check_dependencies
    generate_report
    
    log "Security check completed"
}

# Run main function
main "$@"
