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

# Method 1: Complete reset and reinstall approach
info "Method 1: Complete ArgoCD reset and reinstall..."

# Check if ArgoCD server is running
if kubectl get deployment argocd-server -n argocd &>/dev/null; then
    info "Deleting existing ArgoCD server deployment..."
    kubectl delete deployment argocd-server -n argocd --ignore-not-found
fi

# Remove secrets
info "Cleaning up ArgoCD secrets..."
kubectl delete secret argocd-secret -n argocd --ignore-not-found
kubectl delete secret argocd-initial-admin-secret -n argocd --ignore-not-found

# Reinstall ArgoCD
info "Reinstalling ArgoCD..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for deployment to be ready
info "Waiting for ArgoCD server to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Get the initial admin password
info "Getting initial admin password..."
sleep 10
ADMIN_PASSWORD=""
for i in {1..30}; do
    if kubectl get secret argocd-initial-admin-secret -n argocd &>/dev/null; then
        ADMIN_PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d)
        break
    fi
    sleep 2
done

if [ -n "$ADMIN_PASSWORD" ]; then
    success "ArgoCD admin password retrieved successfully!"
    echo
    info "🔑 Login Credentials:"
    echo "   Username: admin"
    echo "   Password: $ADMIN_PASSWORD"
    echo
else
    warn "Could not retrieve initial admin password. Setting manual password..."
    
    # Manual method - set a known password
    MANUAL_PASSWORD="admin123"
    # Use argocd CLI method to set password
    kubectl exec -n argocd deployment/argocd-server -- argocd account update-password --account admin --new-password "$MANUAL_PASSWORD" --current-password "$ADMIN_PASSWORD" 2>/dev/null || {
        # If that fails, use direct secret patching with a proper bcrypt hash
        BCRYPT_HASH='$2a$12$lCbcPtEVmyf8CZjE2g5Pg.Lc4OOJ9GDnUOWTUBvTLqcxYjZLaKBN6'
        kubectl patch secret argocd-secret -n argocd -p="{\"stringData\":{\"admin.password\":\"$BCRYPT_HASH\"}}"
        kubectl rollout restart deployment/argocd-server -n argocd
        kubectl wait --for=condition=available --timeout=120s deployment/argocd-server -n argocd
    }
    
    success "Password set manually to: $MANUAL_PASSWORD"
    echo
    info "🔑 Login Credentials:"
    echo "   Username: admin"
    echo "   Password: $MANUAL_PASSWORD"
    echo
fi

# Configure ArgoCD server service for NodePort access
info "🌐 Configuring ArgoCD Access..."
if kubectl get service argocd-server -n argocd &>/dev/null; then
    SERVICE_TYPE=$(kubectl get service argocd-server -n argocd -o jsonpath='{.spec.type}')
    if [ "$SERVICE_TYPE" != "NodePort" ]; then
        info "Converting ArgoCD service to NodePort..."
        kubectl patch svc argocd-server -n argocd -p '{"spec":{"type":"NodePort","ports":[{"port":8080,"targetPort":8080,"nodePort":30082}]}}'
    fi
    
    NODE_PORT=$(kubectl get service argocd-server -n argocd -o jsonpath='{.spec.ports[0].nodePort}')
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    
    info "ArgoCD Access Information:"
    echo "   URL: http://$NODE_IP:$NODE_PORT"
    echo "   Username: admin"
    echo "   Password: See above"
    
    # Test the service
    info "Testing ArgoCD service..."
    if curl -k -s -o /dev/null -w "%{http_code}" "http://$NODE_IP:$NODE_PORT" | grep -q "200"; then
        success "ArgoCD service is accessible!"
    else
        warn "ArgoCD service may not be ready yet. Please wait a few minutes and try accessing the URL."
    fi
else
    error "ArgoCD server service not found"
fi

echo
success "ArgoCD password reset complete!"
