#!/bin/bash

# Backup Script for Single Node GitOps Platform
# This script creates backups of the cluster state and persistent data

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration optimized for PowerEdge R540
BACKUP_DIR="${BACKUP_DIR:-/opt/backups/gitops}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"  # Increased from 7 days
BACKUP_COMPRESSION="${BACKUP_COMPRESSION:-gzip}"      # Use compression for large storage
PARALLEL_JOBS="${PARALLEL_JOBS:-4}"                  # Utilize multiple CPU cores for backup
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
BACKUP_NAME="gitops-backup-${TIMESTAMP}"

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

# Function to create backup directory
create_backup_dir() {
    local backup_path="$BACKUP_DIR/$BACKUP_NAME"
    
    log_info "Creating backup directory: $backup_path"
    
    if ! mkdir -p "$backup_path"; then
        log_error "Failed to create backup directory"
        exit 1
    fi
    
    echo "$backup_path"
}

# Function to backup etcd snapshot (K3s)
backup_etcd() {
    local backup_path=$1
    
    log_info "Creating etcd snapshot..."
    
    if command_exists k3s; then
        if sudo k3s etcd-snapshot save --etcd-snapshot-dir "$backup_path" --etcd-snapshot-name "etcd-snapshot-${TIMESTAMP}"; then
            log_success "etcd snapshot created successfully"
        else
            log_error "Failed to create etcd snapshot"
            return 1
        fi
    else
        log_warning "k3s command not found, skipping etcd backup"
        return 1
    fi
}

# Function to backup Kubernetes resources
backup_k8s_resources() {
    local backup_path=$1
    local resources_dir="$backup_path/k8s-resources"
    
    log_info "Backing up Kubernetes resources..."
    
    mkdir -p "$resources_dir"
    
    # Backup all resources
    kubectl get all --all-namespaces -o yaml > "$resources_dir/all-resources.yaml" 2>/dev/null || log_warning "Failed to backup all resources"
    
    # Backup specific resource types
    local resource_types=(
        "namespaces"
        "configmaps"
        "secrets"
        "persistentvolumes"
        "persistentvolumeclaims"
        "storageclasses"
        "applications.argoproj.io"
        "certificates.cert-manager.io"
        "clusterissuers.cert-manager.io"
    )
    
    for resource in "${resource_types[@]}"; do
        log_info "Backing up $resource..."
        if kubectl get "$resource" --all-namespaces -o yaml > "$resources_dir/${resource}.yaml" 2>/dev/null; then
            log_success "Backed up $resource"
        else
            log_warning "Failed to backup $resource (might not exist)"
        fi
    done
    
    # Backup ArgoCD applications separately
    if kubectl get namespace argocd >/dev/null 2>&1; then
        log_info "Backing up ArgoCD applications..."
        kubectl get applications -n argocd -o yaml > "$resources_dir/argocd-applications.yaml" 2>/dev/null || log_warning "Failed to backup ArgoCD applications"
    fi
    
    log_success "Kubernetes resources backup completed"
}

# Function to backup persistent volume data
backup_persistent_data() {
    local backup_path=$1
    local data_dir="$backup_path/persistent-data"
    
    log_info "Backing up persistent volume data..."
    
    mkdir -p "$data_dir"
    
    # Backup ArgoCD data
    if kubectl get pvc -n argocd >/dev/null 2>&1; then
        log_info "Backing up ArgoCD data..."
        kubectl exec -n argocd deployment/argocd-server -- tar czf - /home/argocd 2>/dev/null | cat > "$data_dir/argocd-data.tar.gz" || log_warning "Failed to backup ArgoCD data"
    fi
    
    # Backup Grafana data
    if kubectl get pvc grafana-pv-claim -n monitoring >/dev/null 2>&1; then
        log_info "Backing up Grafana data..."
        local grafana_pod=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [ -n "$grafana_pod" ]; then
            kubectl exec -n monitoring "$grafana_pod" -- tar czf - /var/lib/grafana 2>/dev/null | cat > "$data_dir/grafana-data.tar.gz" || log_warning "Failed to backup Grafana data"
        fi
    fi
    
    # Backup Prometheus data
    if kubectl get pvc prometheus-storage -n monitoring >/dev/null 2>&1; then
        log_info "Backing up Prometheus data..."
        local prometheus_pod=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [ -n "$prometheus_pod" ]; then
            kubectl exec -n monitoring "$prometheus_pod" -- tar czf - /prometheus 2>/dev/null | cat > "$data_dir/prometheus-data.tar.gz" || log_warning "Failed to backup Prometheus data"
        fi
    fi
    
    # Note: External Git repositories (GitHub/GitLab) are backed up by the provider
    log_info "Note: External Git repositories are managed by your Git provider"
    
    log_success "Persistent data backup completed"
}

# Function to backup local-path volumes
backup_local_path_volumes() {
    local backup_path="$1"
    
    log_info "Backing up local-path volumes..."
    
    local storage_dir="/var/lib/rancher/k3s/storage"
    if [ ! -d "$storage_dir" ]; then
        log_warning "Local storage directory not found at $storage_dir, skipping volume backups"
        return 0
    fi
    
    local volumes_dir="$backup_path/local-storage"
    mkdir -p "$volumes_dir"
    
    # Export PV and PVC information
    kubectl get pv -o yaml > "$volumes_dir/persistent-volumes.yaml" 2>/dev/null || log_warning "Failed to backup PVs metadata"
    kubectl get pvc --all-namespaces -o yaml > "$volumes_dir/persistent-volume-claims.yaml" 2>/dev/null || log_warning "Failed to backup PVCs metadata"
    
    # We could potentially backup the actual local-path storage data, but this is complex
    # and would require sudo access and consideration for running containers
    log_info "Note: Only metadata is backed up, consider backing up /var/lib/rancher/k3s/storage separately"
    
    log_success "Local-path volumes metadata backup completed"
}

# Function to create backup manifest
create_backup_manifest() {
    local backup_path=$1
    local manifest_file="$backup_path/backup-manifest.txt"
    
    log_info "Creating backup manifest..."
    
    cat > "$manifest_file" << EOF
Single Node GitOps Platform Backup
Timestamp: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Backup Name: $BACKUP_NAME
Kubernetes Version: $(kubectl version --short --client 2>/dev/null | grep Client || echo "Unknown")
Cluster Info: $(kubectl cluster-info | head -1)

Backup Contents:
- etcd snapshot
- Kubernetes resources (YAML)
- Persistent volume data
- Local-path PV/PVC metadata
- Configuration files

Backup Size: $(du -sh "$backup_path" | cut -f1)

To restore from this backup:
1. Restore etcd snapshot: sudo k3s server --cluster-reset --cluster-reset-restore-path=<etcd-snapshot>
2. Apply Kubernetes resources: kubectl apply -f k8s-resources/
3. Restore persistent data to appropriate volumes
4. Verify all services are running

EOF
    
    log_success "Backup manifest created"
}

# Function to compress backup
compress_backup() {
    local backup_path=$1
    local backup_parent=$(dirname "$backup_path")
    local backup_name=$(basename "$backup_path")
    
    log_info "Compressing backup..."
    
    cd "$backup_parent"
    if tar czf "${backup_name}.tar.gz" "$backup_name"; then
        rm -rf "$backup_name"
        log_success "Backup compressed to ${backup_name}.tar.gz"
        echo "$backup_parent/${backup_name}.tar.gz"
    else
        log_error "Failed to compress backup"
        echo "$backup_path"
    fi
}

# Function to cleanup old backups
cleanup_old_backups() {
    log_info "Cleaning up backups older than $BACKUP_RETENTION_DAYS days..."
    
    if [ -d "$BACKUP_DIR" ]; then
        find "$BACKUP_DIR" -name "gitops-backup-*" -type f -mtime +$BACKUP_RETENTION_DAYS -delete 2>/dev/null || log_warning "Failed to clean up some old backups"
        find "$BACKUP_DIR" -name "gitops-backup-*" -type d -mtime +$BACKUP_RETENTION_DAYS -exec rm -rf {} + 2>/dev/null || log_warning "Failed to clean up some old backup directories"
        log_success "Old backups cleaned up"
    fi
}

# Function to verify backup
verify_backup() {
    local backup_file=$1
    
    log_info "Verifying backup integrity..."
    
    if [ -f "$backup_file" ]; then
        if tar tzf "$backup_file" >/dev/null 2>&1; then
            log_success "Backup archive is valid"
            return 0
        else
            log_error "Backup archive is corrupted"
            return 1
        fi
    else
        log_warning "Backup file not found for verification"
        return 1
    fi
}

# Main backup function
main() {
    echo "========================================"
    echo "Single Node GitOps Platform Backup"
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
    
    log_success "Prerequisites check passed"
    
    # Create backup directory
    local backup_path
    backup_path=$(create_backup_dir)
    
    # Perform backups
    backup_etcd "$backup_path"
    backup_k8s_resources "$backup_path"
    backup_persistent_data "$backup_path"
    backup_local_path_volumes "$backup_path"
    
    # Create manifest
    create_backup_manifest "$backup_path"
    
    # Compress backup
    local final_backup
    final_backup=$(compress_backup "$backup_path")
    
    # Verify backup
    verify_backup "$final_backup"
    
    # Cleanup old backups
    cleanup_old_backups
    
    # Summary
    echo ""
    echo "========================================"
    echo "Backup Summary"
    echo "========================================"
    log_success "Backup completed successfully"
    log_info "Backup location: $final_backup"
    log_info "Backup size: $(du -sh "$final_backup" 2>/dev/null | cut -f1 || echo "Unknown")"
    echo ""
    log_info "To restore from this backup:"
    log_info "1. Run: ./scripts/restore.sh $final_backup"
    log_info "2. Or manually follow instructions in backup-manifest.txt"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
