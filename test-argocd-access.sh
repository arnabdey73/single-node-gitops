#!/bin/bash

echo "=== ArgoCD Access Test ==="
echo

# Get node IP
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "Node IP: $NODE_IP"

# Get ArgoCD NodePort
ARGOCD_PORT=$(kubectl get svc argocd-server-nodeport -n argocd -o jsonpath='{.spec.ports[0].nodePort}')
echo "ArgoCD NodePort: $ARGOCD_PORT"

# Check ArgoCD service
echo
echo "=== ArgoCD Service Status ==="
kubectl get svc argocd-server-nodeport -n argocd

echo
echo "=== ArgoCD Pod Status ==="
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server

echo
echo "=== Connection Details ==="
echo "ArgoCD URL: https://$NODE_IP:$ARGOCD_PORT"
echo "Username: admin"
echo "Password: admin123"
echo
echo "You can access ArgoCD from your Windows desktop using Chrome at:"
echo "https://$NODE_IP:$ARGOCD_PORT"
echo
echo "Note: You may need to accept the self-signed certificate in Chrome."

# Test basic connectivity
echo
echo "=== Testing Connectivity ==="
echo "Testing HTTPS connection..."
if curl -k -s --connect-timeout 10 https://$NODE_IP:$ARGOCD_PORT/ > /dev/null 2>&1; then
    echo "✅ ArgoCD is accessible via HTTPS"
else
    echo "❌ ArgoCD is not responding via HTTPS"
    echo "Checking pod logs..."
    kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=5
fi
