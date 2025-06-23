#!/bin/bash

# AppDeploy Platform Upgrade Script
# This script safely upgrades all platform components

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Versioning
PLATFORM_VERSION="1.0.0"
K3S_TARGET_VERSION="v1.26.4+k3s1"
ARGOCD_TARGET_VERSION="v2.8.0"

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✓ $1${NC}"
}

header() {
    echo ""
    echo -e "${CYAN}==== $1 ====${NC}"
    echo ""
}

# Check if running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root"
        exit 1
    fi
}

# Create backup before upgrade
create_backup() {
    header "Creating Pre-upgrade Backup"
    
    local backup_name="pre_upgrade_backup_$(date +%Y%m%d_%H%M%S)"
    
    log "Backing up platform before upgrade..."
    if ./scripts/backup.sh "$backup_name"; then
        success "Created backup: backup/$backup_name.tar.gz"
    else
        error "Failed to create backup. Aborting upgrade."
        exit 1
    fi
}

# Update repository
update_repository() {
    header "Updating Local Repository"
    
    if [ -d ".git" ]; then
        log "Syncing with git repository..."
        
        # Stash any local changes
        git stash -m "Auto-stash before upgrade" || true
        
        # Pull latest changes
        if git pull; then
            success "Successfully updated local repository"
        else
            error "Failed to update local repository. Aborting upgrade."
            exit 1
        fi
    else
        warn "Not a git repository. Skipping repository update."
    fi
}

# Upgrade K3s (optional)
upgrade_k3s() {
    header "K3s Version Check"
    
    local current_version=$(k3s --version | awk '{print $3}')
    
    log "Current K3s version: $current_version"
    log "Target K3s version: $K3S_TARGET_VERSION"
    
    if [ "$current_version" == "$K3S_TARGET_VERSION" ]; then
        success "K3s is already at the target version"
        return 0
    fi
    
    echo ""
    read -p "Do you want to upgrade K3s to $K3S_TARGET_VERSION? (y/N): " choice
    
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        header "Upgrading K3s"
        
        log "Downloading K3s installer..."
        curl -sfL https://get.k3s.io > /tmp/k3s-install.sh
        
        log "Upgrading K3s to $K3S_TARGET_VERSION..."
        INSTALL_K3S_VERSION="$K3S_TARGET_VERSION" sh /tmp/k3s-install.sh
        
        log "Waiting for K3s to restart..."
        sleep 30
        
        # Verify upgrade
        local new_version=$(k3s --version | awk '{print $3}')
        
        if [ "$new_version" == "$K3S_TARGET_VERSION" ]; then
            success "K3s upgraded successfully to $new_version"
        else
            warn "K3s version after upgrade: $new_version (expected: $K3S_TARGET_VERSION)"
        fi
    else
        log "Skipping K3s upgrade"
    fi
}

# Upgrade ArgoCD
upgrade_argocd() {
    header "Upgrading ArgoCD"
    
    log "Current ArgoCD version:"
    kubectl -n argocd get deployment argocd-server -o jsonpath='{.spec.template.spec.containers[0].image}' | cut -d: -f2
    
    log "Upgrading ArgoCD to $ARGOCD_TARGET_VERSION..."
    
    # Apply the new ArgoCD manifests
    local argocd_url="https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_TARGET_VERSION/manifests/install.yaml"
    
    log "Downloading ArgoCD manifests from $argocd_url..."
    if curl -sSL "$argocd_url" | kubectl apply -n argocd -f -; then
        log "Manifests applied successfully"
    else
        error "Failed to apply ArgoCD manifests"
        exit 1
    fi
    
    # Wait for rollout to complete
    log "Waiting for ArgoCD deployments to roll out..."
    kubectl -n argocd rollout status deployment/argocd-server --timeout=300s
    kubectl -n argocd rollout status deployment/argocd-repo-server --timeout=300s
    kubectl -n argocd rollout status deployment/argocd-application-controller --timeout=300s
    
    # Verify the upgrade
    log "New ArgoCD version:"
    local new_version=$(kubectl -n argocd get deployment argocd-server -o jsonpath='{.spec.template.spec.containers[0].image}' | cut -d: -f2)
    success "ArgoCD upgraded to $new_version"
}

# Upgrade applications
upgrade_applications() {
    header "Upgrading Platform Applications"
    
    log "Syncing ArgoCD applications..."
    
    # Get all applications
    local apps=$(kubectl get applications -n argocd -o jsonpath='{.items[*].metadata.name}')
    
    if [ -z "$apps" ]; then
        warn "No ArgoCD applications found"
        return 0
    fi
    
    # Force sync each application
    for app in $apps; do
        log "Syncing application: $app"
        kubectl -n argocd patch application "$app" --type merge -p '{"operation":{"sync":{"prune":true}}}'
        sleep 5
    done
    
    log "Waiting for applications to sync..."
    sleep 30
    
    # Check sync status
    local synced_count=0
    local total_apps=0
    
    for app in $apps; do
        total_apps=$((total_apps + 1))
        
        status=$(kubectl -n argocd get application "$app" -o jsonpath='{.status.sync.status}')
        
        if [ "$status" == "Synced" ]; then
            synced_count=$((synced_count + 1))
        else
            warn "Application $app is in $status state"
        fi
    done
    
    log "$synced_count out of $total_apps applications synced successfully"
    
    if [ "$synced_count" -eq "$total_apps" ]; then
        success "All applications synced successfully"
    else
        warn "Some applications are not synced. Check ArgoCD UI for details."
    fi
}

# Platform health check
verify_health() {
    header "Verifying Platform Health"
    
    if ./scripts/health-check.sh; then
        success "Platform health check passed"
    else
        warn "Platform health check reported issues. Please review logs above."
    fi
}

# Main upgrade process
main() {
    header "AppDeploy Platform Upgrade"
    log "Platform Version: $PLATFORM_VERSION"
    
    # Check if running as root
    check_root
    
    # Perform pre-flight checks
    echo ""
    read -p "Are you ready to upgrade the AppDeploy platform? This will create a backup first. (y/N): " choice
    
    if [[ ! "$choice" =~ ^[Yy]$ ]]; then
        log "Upgrade cancelled by user"
        exit 0
    fi
    
    # Start upgrade process
    create_backup
    update_repository
    upgrade_k3s
    upgrade_argocd
    upgrade_applications
    verify_health
    
    header "Upgrade Complete"
    success "The AppDeploy platform has been upgraded successfully"
    log "Platform Version: $PLATFORM_VERSION"
    
    echo ""
    echo "Next Steps:"
    echo "1. Check system health: ./scripts/health-check.sh"
    echo "2. Access the dashboard: ./scripts/dashboard-access.sh open"
    echo "3. Verify all applications: kubectl get applications -n argocd"
}

main "$@"
