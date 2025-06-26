#!/bin/bash

# ArgoCD Password Reset Script
echo "🔐 Resetting ArgoCD Admin Password"
echo "=================================="

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; }

# Set new password
NEW_PASSWORD="admin123"

info "Setting new ArgoCD admin password to: $NEW_PASSWORD"

# Method 1: Try to delete and let ArgoCD recreate the admin user
info "Method 1: Clearing admin user to reset password..."

# Delete the admin user from the argocd-cm ConfigMap
kubectl patch configmap argocd-cm -n argocd --type merge -p '{"data":{"accounts.admin":"apiKey, login"}}'

# Clear any existing password
kubectl patch secret argocd-secret -n argocd --type merge -p '{"data":{"admin.password":"","admin.passwordMtime":""}}'

# Restart ArgoCD server to regenerate admin password
info "Restarting ArgoCD server..."
kubectl rollout restart deployment/argocd-server -n argocd

# Wait for rollout
kubectl rollout status deployment/argocd-server -n argocd --timeout=60s

# Wait a bit for the initial secret to be created
sleep 10

# Try to get the new admin password
info "Checking for new admin password..."
if kubectl get secret argocd-initial-admin-secret -n argocd &>/dev/null; then
    ADMIN_PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d)
    success "ArgoCD admin password reset successfully!"
    echo
    info "🔑 Login Credentials:"
    echo "   Username: admin"
    echo "   Password: $ADMIN_PASSWORD"
    echo
else
    warn "Initial admin secret not found. Using manual password method..."
    
    # Manual method - create a known password hash
    # Use a pre-computed bcrypt hash for "admin123"
    BCRYPT_HASH='$2a$10$rRyBsGSHK6.uc8fntPwVIuLVHgsAhAX7TcdrqW/XFuKK8N6xpgaYW'
    
    kubectl patch secret argocd-secret -n argocd --type merge -p "{\"stringData\":{\"admin.password\":\"$BCRYPT_HASH\"}}"
    
    success "Password set manually to: $NEW_PASSWORD"
    echo
    info "🔑 Login Credentials:"
    echo "   Username: admin"
    echo "   Password: $NEW_PASSWORD"
    echo
fi

# Get ArgoCD server service info
info "🌐 ArgoCD Access Information:"
if kubectl get service argocd-server -n argocd &>/dev/null; then
    SERVICE_TYPE=$(kubectl get service argocd-server -n argocd -o jsonpath='{.spec.type}')
    if [ "$SERVICE_TYPE" = "NodePort" ]; then
        NODE_PORT=$(kubectl get service argocd-server -n argocd -o jsonpath='{.spec.ports[0].nodePort}')
        NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
        echo "   URL: http://$NODE_IP:$NODE_PORT"
    else
        echo "   Service Type: $SERVICE_TYPE"
        echo "   Use port-forwarding: kubectl port-forward svc/argocd-server -n argocd 8080:443"
        echo "   Then access: https://localhost:8080"
    fi
else
    error "ArgoCD server service not found"
fi

echo
success "ArgoCD password reset complete!"
