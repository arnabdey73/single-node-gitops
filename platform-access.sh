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

echo "🔐 Login Credentials:"
echo "┌─────────────────────────────────────────────┐"
echo "│ ArgoCD:                                     │"
echo "│   Username: admin                           │"
echo "│   Password: admin123                        │"
echo "│                                             │"
echo "│ Grafana:                                    │"
echo "│   Username: admin                           │"
echo "│   Password: admin                           │"
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
echo "• ArgoCD uses HTTP (insecure mode) - no certificate needed"
echo "• Dashboard provides real-time Kubernetes cluster information"
echo "• Grafana shows system monitoring and metrics"
echo
echo "🔧 Troubleshooting:"
echo "• If ArgoCD login fails, the password was just reset to 'admin123'"
echo "• If services are not accessible, check your network connectivity"
echo "• Dashboard CTA buttons will open ArgoCD and Grafana in new tabs"
echo

echo "============================================"
