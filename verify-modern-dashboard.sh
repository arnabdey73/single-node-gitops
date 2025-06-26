#!/bin/bash

# AppDeploy Dashboard Verification Script
# Run this on the Ubuntu server to verify the modern dashboard is deployed

echo "🔍 AppDeploy Dashboard Verification"
echo "=================================="
echo

# Check ConfigMap content
echo "📄 Checking ConfigMap content..."
if kubectl get configmap deployment-platform-config -n deployment-platform &>/dev/null; then
    echo "✅ ConfigMap exists"
    
    # Check if it contains modern dashboard features
    if kubectl get configmap deployment-platform-config -n deployment-platform -o yaml | grep -q "AppDeployDashboard"; then
        echo "✅ Modern dashboard JavaScript class found in ConfigMap"
    else
        echo "❌ Modern dashboard JavaScript class NOT found in ConfigMap"
    fi
    
    if kubectl get configmap deployment-platform-config -n deployment-platform -o yaml | grep -q "animation"; then
        echo "✅ CSS animations found in ConfigMap"
    else
        echo "❌ CSS animations NOT found in ConfigMap"
    fi
    
    if kubectl get configmap deployment-platform-config -n deployment-platform -o yaml | grep -q "quick-access"; then
        echo "✅ Quick access section found in ConfigMap"
    else
        echo "❌ Quick access section NOT found in ConfigMap"
    fi
    
    # Check ConfigMap size
    local configmap_size=$(kubectl get configmap deployment-platform-config -n deployment-platform -o yaml | wc -l)
    echo "📊 ConfigMap size: $configmap_size lines"
    
    if [ $configmap_size -gt 1000 ]; then
        echo "✅ ConfigMap appears to contain full modern dashboard"
    else
        echo "⚠️  ConfigMap seems small - might contain minimal dashboard"
    fi
else
    echo "❌ ConfigMap not found"
fi

echo
echo "🚀 Checking deployment status..."
kubectl get deployment deployment-platform -n deployment-platform 2>/dev/null || echo "❌ Deployment not found"

echo
echo "📦 Checking pod status..."
kubectl get pods -n deployment-platform -l app.kubernetes.io/name=deployment-platform 2>/dev/null || echo "❌ No pods found"

echo
echo "🌐 Checking service..."
if kubectl get service deployment-platform -n deployment-platform &>/dev/null; then
    echo "✅ Service exists"
    kubectl get service deployment-platform -n deployment-platform
    
    # Get node IP for access
    local node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
    if [ ! -z "$node_ip" ]; then
        echo
        echo "🔗 Dashboard should be accessible at: http://${node_ip}:30080"
        echo
        echo "🧪 Testing local access..."
        if curl -s http://localhost:30080 | grep -q "AppDeploy Dashboard"; then
            echo "✅ Dashboard responds locally"
            if curl -s http://localhost:30080 | grep -q "AppDeployDashboard"; then
                echo "✅ Modern dashboard detected (JavaScript class found)"
            else
                echo "⚠️  Basic dashboard detected (JavaScript class not found)"
            fi
        else
            echo "❌ Dashboard not responding locally"
        fi
    fi
else
    echo "❌ Service not found"
fi

echo
echo "📋 Summary:"
echo "  - Access from Windows Chrome: http://${node_ip}:30080"
echo "  - If you see a basic dashboard, run: ./scripts/access-appdeploy.sh setup nodeport"
echo "  - The modern dashboard should have animations, quick access buttons, and real-time data"
