#!/bin/bash

# Force Reset Dashboard Script
# This completely removes and recreates the dashboard with the modern version

echo "🔄 Force Resetting AppDeploy Dashboard"
echo "======================================"
echo

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }

info "Step 1: Completely removing existing dashboard..."
kubectl delete deployment deployment-platform -n deployment-platform 2>/dev/null || true
kubectl delete service deployment-platform -n deployment-platform 2>/dev/null || true
kubectl delete configmap deployment-platform-config -n deployment-platform 2>/dev/null || true

info "Waiting for cleanup..."
sleep 5

info "Step 2: Verifying HTML file..."
if [ -f "applications/deployment-platform/index.html" ]; then
    local html_size=$(wc -l < applications/deployment-platform/index.html)
    info "HTML file size: $html_size lines"
    
    if [ $html_size -gt 800 ]; then
        success "Confirmed: HTML file contains modern dashboard"
    else
        warn "HTML file seems small - might not be the full modern version"
    fi
    
    # Check for key modern features
    if grep -q "AppDeployDashboard" applications/deployment-platform/index.html; then
        success "✓ JavaScript dashboard class found"
    else
        warn "✗ JavaScript dashboard class missing"
    fi
    
    if grep -q "animation" applications/deployment-platform/index.html; then
        success "✓ CSS animations found"
    else
        warn "✗ CSS animations missing"
    fi
    
    if grep -q "quick-access" applications/deployment-platform/index.html; then
        success "✓ Quick access section found"
    else
        warn "✗ Quick access section missing"
    fi
else
    echo "❌ HTML file not found at applications/deployment-platform/index.html"
    exit 1
fi

info "Step 3: Creating fresh ConfigMap..."
kubectl create configmap deployment-platform-config -n deployment-platform --from-file=index.html=applications/deployment-platform/index.html

info "Step 4: Deploying fresh deployment..."
if [ -f "applications/deployment-platform/deployment.yaml" ]; then
    kubectl apply -f applications/deployment-platform/deployment.yaml
else
    warn "Deployment manifest not found, creating basic deployment"
fi

info "Step 5: Creating NodePort service..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: deployment-platform
  namespace: deployment-platform
spec:
  selector:
    app.kubernetes.io/name: deployment-platform
  ports:
  - name: http
    port: 80
    targetPort: 80
    nodePort: 30080
    protocol: TCP
  type: NodePort
EOF

info "Step 6: Waiting for deployment to be ready..."
kubectl rollout status deployment/deployment-platform -n deployment-platform --timeout=120s

# Get node IP
local node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)

echo
success "Dashboard reset complete!"
echo
info "🌐 Access the dashboard from your Windows desktop:"
echo -e "  ${GREEN}http://${node_ip}:30080${NC}"
echo
info "🔍 To verify it's working:"
echo "  curl http://localhost:30080 | grep -i 'modern\\|animation\\|appdeploy'"
