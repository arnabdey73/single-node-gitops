#!/bin/bash

echo "🎯 AppDeploy Modern Dashboard Verification"
echo "=========================================="
echo

# Check if HTML file exists and has modern features
if [ -f "applications/deployment-platform/index.html" ]; then
    echo "✅ Dashboard HTML file found"
    
    # Check file size (modern dashboard should be substantial)
    size=$(wc -l < applications/deployment-platform/index.html)
    echo "📊 Dashboard file size: $size lines"
    
    if [ $size -gt 800 ]; then
        echo "✅ Dashboard appears to be the full modern version"
    else
        echo "⚠️  Dashboard seems too small - might be minimal version"
    fi
    
    # Check for modern features
    echo
    echo "🔍 Checking for modern dashboard features:"
    
    if grep -q "animation" applications/deployment-platform/index.html; then
        echo "✅ Animations found"
    else
        echo "❌ No animations found"
    fi
    
    if grep -q "openArgoCD\|openGrafana" applications/deployment-platform/index.html; then
        echo "✅ CTA buttons (ArgoCD/Grafana) found"
    else
        echo "❌ CTA buttons not found"
    fi
    
    if grep -q "quick-access" applications/deployment-platform/index.html; then
        echo "✅ Quick access section found"
    else
        echo "❌ Quick access section not found"
    fi
    
    if grep -q "real-time" applications/deployment-platform/index.html; then
        echo "✅ Real-time features found"
    else
        echo "❌ Real-time features not found"
    fi
    
    if grep -q "AppDeployDashboard" applications/deployment-platform/index.html; then
        echo "✅ JavaScript dashboard class found"
    else
        echo "❌ JavaScript dashboard class not found"
    fi
    
else
    echo "❌ Dashboard HTML file not found!"
fi

echo
echo "🚀 Next Steps:"
echo "1. Run: ./scripts/access-appdeploy.sh setup nodeport"
echo "2. Access dashboard at: http://<node-ip>:30080"
echo "3. The dashboard should show:"
echo "   - Real-time application status"
echo "   - Animated loading indicators"
echo "   - Quick access buttons for ArgoCD and Grafana"
echo "   - Modern responsive design"
echo "   - Live system metrics"
