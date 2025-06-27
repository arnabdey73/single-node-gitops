#!/bin/bash

echo "============================================"
echo "🚀 AppDeploy Platform - Quick Access Guide"
echo "============================================"
echo

# Get node IP
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

echo "📍 Platform Access URLs:"
echo "┌─────────────────────────────────────────────┐"
echo "│ Dashboard:  http://$NODE_IP:30080    │"
echo "│ ArgoCD:     http://$NODE_IP:30415    │" 
echo "│ Grafana:    http://$NODE_IP:30300    │"
echo "└─────────────────────────────────────────────┘"
echo

echo "🔐 Access Information:"
echo "┌─────────────────────────────────────────────┐"
echo "│ ArgoCD:                                     │"
echo "│   ✅ Anonymous access enabled               │"
echo "│   No login required                         │"
echo "│                                             │"
echo "│ Grafana:                                    │"
echo "│   ✅ Anonymous access enabled               │"
echo "│   No login required                         │"
echo "└─────────────────────────────────────────────┘"
echo

echo "📊 Platform Status:"
echo "┌─────────────────────────────────────────────┐"

# Check ArgoCD
if kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server --no-headers | grep -q "Running"; then
    echo "│ ✅ ArgoCD:     Running                      │"
else
    echo "│ ❌ ArgoCD:     Not Running                  │"
fi

# Check Grafana 
if kubectl get pods -n monitoring -l app=grafana --no-headers 2>/dev/null | grep -q "Running"; then
    echo "│ ✅ Grafana:    Running                      │"
else
    echo "│ ❌ Grafana:    Not Running                  │"
fi

# Check Dashboard
if kubectl get pods -n deployment-platform -l app=deployment-platform --no-headers 2>/dev/null | grep -q "Running"; then
    echo "│ ✅ Dashboard:  Running                      │"
else
    echo "│ ❌ Dashboard:  Not Running                  │"
fi

echo "└─────────────────────────────────────────────┘"
echo

echo "💡 Usage Notes:"
echo "• Access all services from your Windows desktop using Chrome"
echo "• ArgoCD and Grafana use anonymous access - no login required"
echo "• Dashboard provides real-time Kubernetes cluster information"
echo "• All services have admin-level anonymous access for easy use"
echo
echo "🔧 Troubleshooting:"
echo "• If services are not accessible, check your network connectivity"
echo "• Dashboard CTA buttons will open ArgoCD and Grafana in new tabs"
echo "• Anonymous access provides full admin privileges"
echo

echo "============================================"
