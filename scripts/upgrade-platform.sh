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

# Upgrading security components
upgrade_security_components() {
    header "Upgrading Security Components"
    
    log "Checking security components..."
    
    # Upgrade Trivy Operator
    log "Upgrading vulnerability scanning components..."
    if kubectl get namespace trivy-system &>/dev/null; then
        kubectl apply -f applications/security/scanning/trivy-operator.yaml
        success "Trivy Operator upgraded"
    else
        warn "Trivy Operator not installed, skipping"
    fi
    
    # Upgrade OPA Gatekeeper
    log "Upgrading policy enforcement components..."
    if kubectl get namespace gatekeeper-system &>/dev/null; then
        kubectl apply -f applications/security/gatekeeper.yaml
        success "OPA Gatekeeper upgraded"
    else
        warn "OPA Gatekeeper not installed, skipping"
    fi
    
    # Refresh security policies
    log "Refreshing security policies..."
    if kubectl get constraints &>/dev/null; then
        kubectl apply -f applications/security/policies.yaml
        success "Security policies refreshed"
    else
        warn "No security policies found, skipping"
    fi
    
    # Update CIS benchmarks
    log "Updating CIS benchmark components..."
    if kubectl get namespace security-tools &>/dev/null; then
        kubectl apply -f applications/security/kube-bench.yaml
        success "CIS benchmark components updated"
    else
        warn "Security tools namespace not found, skipping CIS benchmark update"
    fi
    
    # Update security dashboard
    log "Updating security dashboard..."
    if kubectl get namespace security-monitoring &>/dev/null; then
        kubectl apply -f applications/security/security-dashboard.yaml
        success "Security dashboard updated"
    else
        warn "Security monitoring namespace not found, skipping dashboard update"
    fi
    
    log "Security components upgrade complete"
}

# Freeze application resources to prevent changes during critical upgrades
freeze_application_resources() {
    header "Protecting Application Resources"
    
    log "Temporarily freezing application changes during critical upgrade components..."
    
    # Get all applications except platform ones
    local user_apps=$(kubectl get applications -n argocd -o jsonpath='{.items[?(@.metadata.labels.app-type=="user")].metadata.name}')
    
    if [ -z "$user_apps" ]; then
        log "No user applications found to freeze"
        return 0
    fi
    
    # Disable auto-sync temporarily
    for app in $user_apps; do
        log "Freezing application changes for: $app"
        kubectl -n argocd patch application "$app" --type merge \
          -p '{"spec":{"syncPolicy":{"automated":null}}}'
    done
    
    success "Application resources protected during upgrade"
}

# Unfreeze applications after upgrade is complete
unfreeze_application_resources() {
    header "Restoring Application Auto-Sync"
    
    local user_apps=$(kubectl get applications -n argocd -o jsonpath='{.items[?(@.metadata.labels.app-type=="user")].metadata.name}')
    
    if [ -z "$user_apps" ]; then
        log "No user applications found to unfreeze"
        return 0
    fi
    
    for app in $user_apps; do
        log "Restoring auto-sync for: $app"
        kubectl -n argocd patch application "$app" --type merge \
          -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
    done
    
    success "Application normal operations restored"
}

# Add protection mechanisms to user resources
protect_resources() {
    header "Setting Resource Protection"
    
    log "Adding resource protection annotations..."
    
    # Add protection annotations to critical user namespaces
    local user_namespaces=$(kubectl get namespaces -l type=application -o jsonpath='{.items[*].metadata.name}')
    
    for ns in $user_namespaces; do
        log "Adding protection to namespace: $ns"
        kubectl annotate namespace "$ns" \
          "appdeploy.io/protected=true" \
          "argocd.argoproj.io/sync-options=Prune=false" \
          --overwrite
    done
    
    # Create PodDisruptionBudgets for critical workloads if they don't exist
    for ns in $user_namespaces; do
        local deployments=$(kubectl get deployments -n "$ns" -o jsonpath='{.items[*].metadata.name}')
        for deploy in $deployments; do
            # Check if deployment is marked as critical
            if kubectl get deployment -n "$ns" "$deploy" -o jsonpath='{.metadata.labels.criticality}' | grep -q "high"; then
                log "Creating PodDisruptionBudget for critical deployment: $ns/$deploy"
                kubectl apply -f - <<EOF
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: $deploy-pdb
  namespace: $ns
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: $deploy
EOF
            fi
        done
    done
    
    success "Resource protection applied"
}

# Control eviction during upgrades
manage_eviction_controls() {
    local action=$1  # "enable" or "disable"
    header "Eviction Control: $action"
    
    if [ "$action" == "disable" ]; then
        log "Temporarily disabling pod eviction during upgrade..."
        kubectl annotate node --all "cluster-autoscaler.kubernetes.io/safe-to-evict=false" --overwrite
    elif [ "$action" == "enable" ]; then
        log "Re-enabling normal pod eviction..."
        kubectl annotate node --all "cluster-autoscaler.kubernetes.io/safe-to-evict=true" --overwrite
    fi
    
    success "Eviction control updated: $action"
}

# Manage ingress traffic during upgrades
manage_ingress_traffic() {
    local action=$1  # "maintenance" or "normal"
    header "Traffic Management: $action"
    
    # Check if maintenance ingress config exists
    if [ ! -f "configs/maintenance-ingress.yaml" ]; then
        log "Creating maintenance ingress configuration..."
        mkdir -p configs
        cat > configs/maintenance-ingress.yaml <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: maintenance-ingress
  namespace: default
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: maintenance-service
            port:
              number: 80
---
apiVersion: v1
kind: Service
metadata:
  name: maintenance-service
  namespace: default
spec:
  selector:
    app: maintenance
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: maintenance
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: maintenance
  template:
    metadata:
      labels:
        app: maintenance
    spec:
      containers:
      - name: maintenance
        image: nginx:latest
        ports:
        - containerPort: 80
        volumeMounts:
        - name: html-volume
          mountPath: /usr/share/nginx/html
      volumes:
      - name: html-volume
        configMap:
          name: maintenance-html
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: maintenance-html
  namespace: default
data:
  index.html: |
    <!DOCTYPE html>
    <html>
    <head>
      <title>AppDeploy Maintenance</title>
      <style>
        body {
          font-family: Arial, sans-serif;
          text-align: center;
          padding-top: 100px;
          background-color: #f8f9fa;
        }
        .container {
          max-width: 600px;
          margin: 0 auto;
          padding: 20px;
          background-color: white;
          border-radius: 8px;
          box-shadow: 0 2px 10px rgba(0, 0, 0, 0.1);
        }
        h1 {
          color: #2c3e50;
        }
        .spinner {
          margin: 30px auto;
          width: 50px;
          height: 50px;
          border: 3px solid rgba(0, 123, 255, 0.3);
          border-radius: 50%;
          border-top-color: #007bff;
          animation: spin 1s linear infinite;
        }
        @keyframes spin {
          to { transform: rotate(360deg); }
        }
      </style>
    </head>
    <body>
      <div class="container">
        <h1>System Maintenance</h1>
        <p>The AppDeploy platform is currently being updated. This process should take just a few minutes.</p>
        <div class="spinner"></div>
        <p>Thank you for your patience.</p>
      </div>
    </body>
    </html>
EOF
    fi
    
    if [ "$action" == "maintenance" ]; then
        log "Setting up maintenance mode for ingress traffic..."
        kubectl apply -f configs/maintenance-ingress.yaml
    elif [ "$action" == "normal" ]; then
        log "Restoring normal ingress traffic..."
        kubectl delete -f configs/maintenance-ingress.yaml --ignore-not-found=true
    fi
    
    success "Ingress traffic mode: $action"
}

# Verify update progress and health
verify_progressive_update() {
    local component=$1
    local namespace=$2
    local deployment=$3
    local timeout=${4:-300}
    
    log "Verifying progressive update of $component..."
    
    # Wait for rollout to complete
    if kubectl -n "$namespace" rollout status deployment/"$deployment" --timeout="${timeout}s"; then
        # Check for any new errors in the logs
        local pod=$(kubectl -n "$namespace" logs pod -l app="$deployment" --since=5m 2>/dev/null | grep -c -i "error" || echo "0")
        local error_count=$pod
        
        if [ "$error_count" -gt 0 ]; then
            warn "Detected $error_count errors in $component logs post-update"
        else
            success "$component updated successfully with no errors"
        fi
    else
        error "Failed to update $component within timeout period"
        return 1
    fi
    
    return 0
}

# Sequenced upgrade with application protection
upgrade_with_sequence() {
    header "Sequenced Platform Upgrade"
    
    # Prepare platform - disable disruptions
    manage_eviction_controls "disable"
    freeze_application_resources
    protect_resources
    
    # Upgrade infrastructure components first
    log "Upgrading infrastructure components..."
    upgrade_argocd
    
    # Pause to allow stabilization
    log "Allowing system to stabilize..."
    sleep 30
    
    # Check infrastructure health before proceeding
    log "Checking infrastructure health..."
    if ! ./scripts/health-check.sh || kubectl get pods -n argocd | grep -q -v "Running"; then
        error "Infrastructure components health check failed. Aborting further upgrades."
        unfreeze_application_resources
        manage_eviction_controls "enable"
        exit 1
    fi
    
    # Now upgrade higher-level platform components
    log "Upgrading platform applications..."
    upgrade_applications
    
    # Then upgrade security components
    log "Upgrading security components..."
    upgrade_security_components
    
    # Re-enable normal operations
    unfreeze_application_resources
    manage_eviction_controls "enable"
    
    success "Sequenced upgrade completed successfully"
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
    
    # Start upgrade process with enhanced application protection
    create_backup
    update_repository
    
    # Ask about maintenance mode
    echo ""
    read -p "Do you want to enable maintenance mode during upgrade? (y/N): " maint_choice
    if [[ "$maint_choice" =~ ^[Yy]$ ]]; then
        manage_ingress_traffic "maintenance"
    fi
    
    # First handle K3s separately as it's the most disruptive
    upgrade_k3s
    
    # Perform sequenced upgrade with protection for other components
    upgrade_with_sequence
    
    # Verify overall health
    verify_health
    
    # Restore traffic if needed
    if [[ "$maint_choice" =~ ^[Yy]$ ]]; then
        manage_ingress_traffic "normal"
    fi
    
    header "Upgrade Complete"
    success "The AppDeploy platform has been upgraded successfully"
    log "Platform Version: $PLATFORM_VERSION"
    
    echo ""
    echo "Next Steps:"
    echo "1. Check system health: ./scripts/health-check.sh"
    echo "2. Access the dashboard: ./scripts/dashboard-access.sh open"
    echo "3. Verify all applications: kubectl get applications -n argocd"
    echo "4. Check application logs for any anomalies: kubectl logs -n <namespace> <pod-name>"
}

main "$@"
