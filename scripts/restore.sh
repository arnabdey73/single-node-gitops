#!/bin/bash

# Restore Script for Single Node GitOps Platform
# This script restores the cluster from a backup created by backup.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
RESTORE_DIR="${RESTORE_DIR:-/tmp/gitops-restore}"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to show usage
show_usage() {
    echo "Usage: $0 <backup-file> [options]"
    echo ""
    echo "Options:"
    echo "  --etcd-only          Restore only etcd snapshot"
    echo "  --resources-only     Restore only Kubernetes resources"
    echo "  --data-only          Restore only persistent data"
    echo "  --skip-etcd          Skip etcd restore"
    echo "  --skip-resources     Skip Kubernetes resources restore"
    echo "  --skip-data          Skip persistent data restore"
    echo "  --dry-run            Show what would be restored without doing it"
    echo "  --force              Force restore without confirmation"
    echo "  --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 /opt/backups/gitops/gitops-backup-20231210-143000.tar.gz"
    echo "  $0 backup.tar.gz --etcd-only"
    echo "  $0 backup.tar.gz --skip-etcd --dry-run"
}

# Function to extract backup
extract_backup() {
    local backup_file=$1
    local extract_dir=$2
    
    log_info "Extracting backup from $backup_file..."
    
    if [ ! -f "$backup_file" ]; then
        log_error "Backup file not found: $backup_file"
        exit 1
    fi
    
    # Create extraction directory
    mkdir -p "$extract_dir"
    
    # Extract backup
    if tar xzf "$backup_file" -C "$extract_dir" --strip-components=1; then
        log_success "Backup extracted to $extract_dir"
    else
        log_error "Failed to extract backup"
        exit 1
    fi
    
    # Verify backup contents
    if [ -f "$extract_dir/backup-manifest.txt" ]; then
        log_info "Backup manifest found:"
        cat "$extract_dir/backup-manifest.txt"
        echo ""
    else
        log_warning "Backup manifest not found"
    fi
}

# Function to confirm restore
confirm_restore() {
    local backup_file=$1
    
    if [ "$FORCE_RESTORE" = "true" ]; then
        return 0
    fi
    
    echo ""
    log_warning "This will restore the cluster from backup: $(basename "$backup_file")"
    log_warning "This operation may overwrite existing data and configurations!"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " confirmation
    
    case "$confirmation" in
        yes|YES|y|Y)
            log_info "Proceeding with restore..."
            return 0
            ;;
        *)
            log_info "Restore cancelled by user"
            exit 0
            ;;
    esac
}

# Function to restore etcd snapshot
restore_etcd() {
    local restore_dir=$1
    
    log_info "Restoring etcd snapshot..."
    
    # Find etcd snapshot
    local etcd_snapshot=$(find "$restore_dir" -name "etcd-snapshot-*" -type f | head -1)
    
    if [ -z "$etcd_snapshot" ]; then
        log_error "etcd snapshot not found in backup"
        return 1
    fi
    
    log_info "Found etcd snapshot: $(basename "$etcd_snapshot")"
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would restore etcd from: $etcd_snapshot"
        return 0
    fi
    
    # Stop K3s service
    log_info "Stopping K3s service..."
    if sudo systemctl is-active --quiet k3s; then
        sudo systemctl stop k3s
        log_success "K3s service stopped"
    fi
    
    # Restore etcd snapshot
    log_info "Restoring etcd snapshot..."
    if sudo k3s server --cluster-init --cluster-reset --cluster-reset-restore-path="$etcd_snapshot"; then
        log_success "etcd snapshot restored"
    else
        log_error "Failed to restore etcd snapshot"
        return 1
    fi
    
    # Start K3s service
    log_info "Starting K3s service..."
    sudo systemctl start k3s
    
    # Wait for cluster to be ready
    log_info "Waiting for cluster to be ready..."
    local timeout=300
    while ! kubectl cluster-info >/dev/null 2>&1; do
        sleep 5
        timeout=$((timeout - 5))
        if [ $timeout -le 0 ]; then
            log_error "Cluster failed to become ready within 5 minutes"
            return 1
        fi
    done
    
    log_success "Cluster is ready"
}

# Function to restore Kubernetes resources
restore_k8s_resources() {
    local restore_dir=$1
    local resources_dir="$restore_dir/k8s-resources"
    
    log_info "Restoring Kubernetes resources..."
    
    if [ ! -d "$resources_dir" ]; then
        log_error "Kubernetes resources directory not found in backup"
        return 1
    fi
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would restore Kubernetes resources from: $resources_dir"
        return 0
    fi
    
    # Restore namespaces first
    if [ -f "$resources_dir/namespaces.yaml" ]; then
        log_info "Restoring namespaces..."
        kubectl apply -f "$resources_dir/namespaces.yaml" || log_warning "Some namespaces may already exist"
    fi
    
    # Wait for namespaces to be created
    sleep 10
    
    # Restore storage classes
    if [ -f "$resources_dir/storageclasses.yaml" ]; then
        log_info "Restoring storage classes..."
        kubectl apply -f "$resources_dir/storageclasses.yaml" || log_warning "Some storage classes may already exist"
    fi
    
    # Restore persistent volumes
    if [ -f "$resources_dir/persistentvolumes.yaml" ]; then
        log_info "Restoring persistent volumes..."
        kubectl apply -f "$resources_dir/persistentvolumes.yaml" || log_warning "Some persistent volumes may already exist"
    fi
    
    # Restore secrets and configmaps
    if [ -f "$resources_dir/secrets.yaml" ]; then
        log_info "Restoring secrets..."
        kubectl apply -f "$resources_dir/secrets.yaml" || log_warning "Some secrets may already exist"
    fi
    
    if [ -f "$resources_dir/configmaps.yaml" ]; then
        log_info "Restoring configmaps..."
        kubectl apply -f "$resources_dir/configmaps.yaml" || log_warning "Some configmaps may already exist"
    fi
    
    # Restore persistent volume claims
    if [ -f "$resources_dir/persistentvolumeclaims.yaml" ]; then
        log_info "Restoring persistent volume claims..."
        kubectl apply -f "$resources_dir/persistentvolumeclaims.yaml" || log_warning "Some PVCs may already exist"
    fi
    
    # Restore ArgoCD applications
    if [ -f "$resources_dir/argocd-applications.yaml" ]; then
        log_info "Restoring ArgoCD applications..."
        kubectl apply -f "$resources_dir/argocd-applications.yaml" || log_warning "Some applications may already exist"
    fi
    
    # Restore cert-manager resources
    if [ -f "$resources_dir/certificates.cert-manager.io.yaml" ]; then
        log_info "Restoring cert-manager certificates..."
        kubectl apply -f "$resources_dir/certificates.cert-manager.io.yaml" || log_warning "Some certificates may already exist"
    fi
    
    if [ -f "$resources_dir/clusterissuers.cert-manager.io.yaml" ]; then
        log_info "Restoring cert-manager cluster issuers..."
        kubectl apply -f "$resources_dir/clusterissuers.cert-manager.io.yaml" || log_warning "Some cluster issuers may already exist"
    fi
    
    log_success "Kubernetes resources restored"
}

# Function to restore persistent data
restore_persistent_data() {
    local restore_dir=$1
    local data_dir="$restore_dir/persistent-data"
    
    log_info "Restoring persistent data..."
    
    if [ ! -d "$data_dir" ]; then
        log_warning "Persistent data directory not found in backup"
        return 0
    fi
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would restore persistent data from: $data_dir"
        return 0
    fi
    
    # Restore ArgoCD data
    if [ -f "$data_dir/argocd-data.tar.gz" ]; then
        log_info "Restoring ArgoCD data..."
        local argocd_pod=$(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [ -n "$argocd_pod" ]; then
            cat "$data_dir/argocd-data.tar.gz" | kubectl exec -n argocd "$argocd_pod" -i -- tar xzf - -C / || log_warning "Failed to restore ArgoCD data"
        fi
    fi
    
    # Restore Grafana data
    if [ -f "$data_dir/grafana-data.tar.gz" ]; then
        log_info "Restoring Grafana data..."
        local grafana_pod=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [ -n "$grafana_pod" ]; then
            cat "$data_dir/grafana-data.tar.gz" | kubectl exec -n monitoring "$grafana_pod" -i -- tar xzf - -C / || log_warning "Failed to restore Grafana data"
        fi
    fi
    
    # Restore Prometheus data
    if [ -f "$data_dir/prometheus-data.tar.gz" ]; then
        log_info "Restoring Prometheus data..."
        local prometheus_pod=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [ -n "$prometheus_pod" ]; then
            cat "$data_dir/prometheus-data.tar.gz" | kubectl exec -n monitoring "$prometheus_pod" -i -- tar xzf - -C / || log_warning "Failed to restore Prometheus data"
        fi
    fi
    
    # Note: External Git repositories (GitHub/GitLab) don't need data restoration
    log_info "Note: External Git repositories are managed by your Git provider"
    
    log_success "Persistent data restored"
}

# Function to verify restore
verify_restore() {
    log_info "Verifying restore..."
    
    # Wait for pods to be ready
    log_info "Waiting for pods to be ready..."
    sleep 30
    
    # Check if health check script exists and run it
    if [ -f "$(dirname "$0")/health-check.sh" ]; then
        log_info "Running health check..."
        if bash "$(dirname "$0")/health-check.sh"; then
            log_success "Health check passed"
        else
            log_warning "Health check reported issues"
        fi
    else
        log_warning "Health check script not found"
    fi
}

# Function to cleanup restore directory
cleanup_restore() {
    local restore_dir=$1
    
    if [ -d "$restore_dir" ]; then
        log_info "Cleaning up restore directory..."
        rm -rf "$restore_dir"
        log_success "Restore directory cleaned up"
    fi
}

# Main restore function
main() {
    local backup_file=$1
    
    # Parse command line arguments
    ETCD_ONLY=false
    RESOURCES_ONLY=false
    DATA_ONLY=false
    SKIP_ETCD=false
    SKIP_RESOURCES=false
    SKIP_DATA=false
    DRY_RUN=false
    FORCE_RESTORE=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --etcd-only)
                ETCD_ONLY=true
                shift
                ;;
            --resources-only)
                RESOURCES_ONLY=true
                shift
                ;;
            --data-only)
                DATA_ONLY=true
                shift
                ;;
            --skip-etcd)
                SKIP_ETCD=true
                shift
                ;;
            --skip-resources)
                SKIP_RESOURCES=true
                shift
                ;;
            --skip-data)
                SKIP_DATA=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE_RESTORE=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                if [ -z "$backup_file" ]; then
                    backup_file=$1
                fi
                shift
                ;;
        esac
    done
    
    if [ -z "$backup_file" ]; then
        log_error "Backup file not specified"
        show_usage
        exit 1
    fi
    
    echo "========================================"
    echo "Single Node GitOps Platform Restore"
    echo "========================================"
    echo ""
    
    # Check prerequisites
    log_info "Checking prerequisites..."
    
    if ! command_exists kubectl; then
        log_error "kubectl not found"
        exit 1
    fi
    
    if ! command_exists k3s && [ "$SKIP_ETCD" != "true" ] && [ "$ETCD_ONLY" != "false" ]; then
        log_error "k3s command not found (required for etcd restore)"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
    
    # Confirm restore
    confirm_restore "$backup_file"
    
    # Extract backup
    local restore_dir="$RESTORE_DIR/$(basename "$backup_file" .tar.gz)"
    extract_backup "$backup_file" "$restore_dir"
    
    # Perform restore based on options
    if [ "$ETCD_ONLY" = "true" ]; then
        restore_etcd "$restore_dir"
    elif [ "$RESOURCES_ONLY" = "true" ]; then
        restore_k8s_resources "$restore_dir"
    elif [ "$DATA_ONLY" = "true" ]; then
        restore_persistent_data "$restore_dir"
    else
        # Full restore
        if [ "$SKIP_ETCD" != "true" ]; then
            restore_etcd "$restore_dir"
        fi
        
        if [ "$SKIP_RESOURCES" != "true" ]; then
            restore_k8s_resources "$restore_dir"
        fi
        
        if [ "$SKIP_DATA" != "true" ]; then
            restore_persistent_data "$restore_dir"
        fi
    fi
    
    # Verify restore
    if [ "$DRY_RUN" != "true" ]; then
        verify_restore
    fi
    
    # Cleanup
    cleanup_restore "$restore_dir"
    
    # Summary
    echo ""
    echo "========================================"
    echo "Restore Summary"
    echo "========================================"
    if [ "$DRY_RUN" = "true" ]; then
        log_info "Dry run completed - no actual restore performed"
    else
        log_success "Restore completed successfully"
        log_info "Please verify all services are working correctly"
    fi
    echo ""
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
