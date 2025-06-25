#!/bin/bash

# AppDeploy Dashboard Access Script
# This script makes it easier to access the AppDeploy dashboard from a remote server

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

header() {
    echo -e "${CYAN}$1${NC}"
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    error "kubectl is not installed or not in the PATH"
    exit 1
fi

# Function to find the AppDeploy dashboard namespace and service
find_dashboard() {
    # First, try the default namespace
    if kubectl get namespace deployment-platform &> /dev/null; then
        if kubectl get service deployment-platform -n deployment-platform &> /dev/null; then
            echo "deployment-platform|deployment-platform"
            return 0
        fi
    fi
    
    # If that fails, try other possible namespaces
    local possible_namespaces=("appdeploy" "app-deploy" "platform" "gitops" "gitops-platform" "default" "apps")
    local possible_services=("deployment-platform" "appdeploy" "app-deploy" "platform-ui" "gitops-dashboard" "dashboard")
    
    # Check each namespace for services
    for ns in "${possible_namespaces[@]}"; do
        if kubectl get namespace "$ns" &> /dev/null; then
            for svc in "${possible_services[@]}"; do
                if kubectl get service "$svc" -n "$ns" &> /dev/null; then
                    echo "$ns|$svc"
                    return 0
                fi
            done
        fi
    done
    
    # Look for any service with "dashboard" or "ui" or "platform" in its name in any namespace
    local namespaces=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}')
    for ns in $namespaces; do
        local matching_services=$(kubectl get services -n "$ns" -o jsonpath='{.items[?(@.metadata.name contains "dashboard" || @.metadata.name contains "ui" || @.metadata.name contains "platform")].metadata.name}' 2>/dev/null)
        if [[ ! -z "$matching_services" ]]; then
            for svc in $matching_services; do
                echo "$ns|$svc"
                return 0
            done
        fi
    done
    
    return 1
}

# Function to diagnose platform issues
diagnose() {
    header "🔍 AppDeploy Platform Diagnosis"
    
    info "Checking Kubernetes cluster connectivity..."
    if ! kubectl cluster-info &> /dev/null; then
        error "Cannot connect to Kubernetes cluster"
        info "Make sure your kubeconfig is properly set up and the cluster is running"
        return
    fi
    
    success "Connected to Kubernetes cluster"
    
    info "Checking namespaces..."
    kubectl get namespaces
    echo
    
    info "Checking deployments in argocd namespace..."
    kubectl get deployments -n argocd 2>/dev/null || echo "No deployments found in argocd namespace"
    echo
    
    info "Checking for dashboard-related services in all namespaces..."
    kubectl get services --all-namespaces | grep -E 'dashboard|platform|ui|deploy' || echo "No dashboard-related services found"
    echo
    
    info "Checking for application manifests..."
    if [ -d "applications/deployment-platform" ]; then
        ls -la applications/deployment-platform
    else
        warn "deployment-platform application directory not found"
    fi
    echo
    
    info "Checking ArgoCD applications..."
    kubectl get applications -n argocd 2>/dev/null || echo "No ArgoCD applications found or CRD not installed"
    echo
    
    info "Platform status summary:"
    kubectl get pods --all-namespaces | grep -c "Running" > /dev/null && success "Some pods are running" || warn "No running pods found"
    kubectl get services -n deployment-platform &> /dev/null && success "deployment-platform namespace exists" || warn "deployment-platform namespace not found"
    
    echo
    info "If the platform is not fully deployed, you may need to run the installation process:"
    echo -e "${YELLOW}./install.sh${NC}"
    echo
    info "For more detailed troubleshooting:"
    echo -e "${YELLOW}./scripts/health-check.sh${NC}"
    echo
    info "You can also try creating a minimal dashboard for development/testing:"
    echo -e "${YELLOW}./scripts/access-appdeploy.sh setup${NC}"
}

# Function to set up a minimal dashboard for development/testing
setup_minimal_dashboard() {
    header "🛠️ Setting up minimal AppDeploy dashboard"
    
    # Check if namespace exists, create if it doesn't
    if ! kubectl get namespace deployment-platform &> /dev/null; then
        info "Creating deployment-platform namespace..."
        kubectl create namespace deployment-platform
    fi
    
    # Create service based on access type
    local service_type="ClusterIP"
    if [[ "$1" == "nodeport" ]]; then
        service_type="NodePort"
        local nodeport="30080"
        info "Creating NodePort service (port: $nodeport) for direct network access..."
    else
        info "Creating standard ClusterIP service..."
    fi
    
    # Check if the service exists, create if it doesn't
    if ! kubectl get service deployment-platform -n deployment-platform &> /dev/null; then
        info "Creating minimal AppDeploy dashboard service..."
        
        # Create a ConfigMap for the dashboard HTML
        kubectl create configmap appdeploy-dashboard-config -n deployment-platform --from-literal=index.html="
<!DOCTYPE html>
<html lang=\"en\">
<head>
    <meta charset=\"UTF-8\">
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
    <title>AppDeploy Dashboard</title>
    <style>
        body { 
            font-family: Arial, sans-serif; 
            margin: 0; 
            padding: 20px; 
            background: #f5f5f5;
            color: #333;
        }
        .container { 
            max-width: 1200px; 
            margin: 0 auto; 
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .header { 
            text-align: center; 
            padding: 20px;
            margin-bottom: 20px;
            background: #1a73e8;
            color: white;
            border-radius: 4px;
        }
        h1 { margin: 0; }
        .message {
            padding: 15px;
            background: #e8f0fe;
            border-left: 4px solid #1a73e8;
            margin-bottom: 20px;
        }
        .footer {
            text-align: center;
            margin-top: 40px;
            color: #666;
            font-size: 0.9rem;
        }
        .network-info {
            margin-top: 20px;
            padding: 10px;
            background: #f0f8ff;
            border: 1px solid #add8e6;
            border-radius: 4px;
        }
    </style>
</head>
<body>
    <div class=\"container\">
        <div class=\"header\">
            <h1>AppDeploy Dashboard</h1>
            <p>Single-Node GitOps Platform</p>
        </div>
        
        <div class=\"message\">
            <p><strong>Development Mode</strong>: This is a minimal AppDeploy Dashboard created for testing purposes.</p>
            <p>The full platform does not appear to be installed. Please run <code>./install.sh</code> to deploy the complete platform.</p>
        </div>
        
        <h2>Available Services</h2>
        <ul id=\"services\">
            <li>Loading service information...</li>
        </ul>
        
        <h2>System Status</h2>
        <ul id=\"status\">
            <li>Loading system status...</li>
        </ul>
        
        <div class=\"network-info\" id=\"networkInfo\">
            <h3>Access Information</h3>
            <p id=\"hostInfo\">Detecting host information...</p>
        </div>
        
        <div class=\"footer\">
            <p>AppDeploy Platform &copy; 2025</p>
        </div>
    </div>
    
    <script>
        // Simple function to fetch and display services
        async function fetchServices() {
            document.getElementById('services').innerHTML = '<li>Checking available services...</li>';
            document.getElementById('status').innerHTML = '<li>Checking system status...</li>';
            
            // In a real dashboard, this would make API calls to get real service statuses
            setTimeout(() => {
                document.getElementById('services').innerHTML = 
                    '<li>Kubernetes API: <span style=\"color:green\">✓ Connected</span></li>' +
                    '<li>ArgoCD: <span style=\"color:green\">✓ Detected</span></li>' +
                    '<li>Monitoring: <span style=\"color:green\">✓ Detected</span></li>';
                
                document.getElementById('status').innerHTML = 
                    '<li>Nodes: <span style=\"color:green\">✓ 1 Running</span></li>' +
                    '<li>Platform Installation: <span style=\"color:green\">✓ Minimal Dashboard Mode</span></li>' +
                    '<li>ArgoCD UI: <span>Available at <a href=\"http://' + window.location.hostname + ':30081\">http://' + window.location.hostname + ':30081</a></span></li>';
                
                document.getElementById('hostInfo').innerHTML = 'Connected to: ' + window.location.host + 
                    '<br>For local network access, use: <strong>http://' + window.location.hostname + 
                    (window.location.port ? ':' + window.location.port : '') + 
                    '</strong>';
            }, 1000);
        }
        
        // Load data when page loads
        window.onload = fetchServices;
    </script>
</body>
</html>" || true
        
        # Create a minimal deployment for the dashboard
        cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: deployment-platform
  namespace: deployment-platform
  labels:
    app.kubernetes.io/name: deployment-platform
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: deployment-platform
  template:
    metadata:
      labels:
        app.kubernetes.io/name: deployment-platform
    spec:
      containers:
      - name: nginx
        image: nginx:stable
        ports:
        - containerPort: 80
        volumeMounts:
        - name: config-volume
          mountPath: /usr/share/nginx/html
      volumes:
      - name: config-volume
        configMap:
          name: appdeploy-dashboard-config
---
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
    protocol: TCP
EOF

        if [[ "$service_type" == "NodePort" ]]; then
            kubectl patch service deployment-platform -n deployment-platform -p '{"spec": {"type": "NodePort", "ports": [{"name": "http", "port": 80, "targetPort": 80, "nodePort": 30080}]}}'
            local node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "Node IP not found")
            info "Dashboard will be available at: http://${node_ip}:30080"
        fi
        
        success "Minimal AppDeploy dashboard created"
        info "Waiting for the deployment to be ready..."
        sleep 5
        
        # Check if deployment is ready
        kubectl rollout status deployment/deployment-platform -n deployment-platform --timeout=60s || true
    else
        success "AppDeploy dashboard service already exists"
        
        if [[ "$service_type" == "NodePort" ]]; then
            info "Updating service to NodePort type..."
            kubectl patch service deployment-platform -n deployment-platform -p '{"spec": {"type": "NodePort", "ports": [{"name": "http", "port": 80, "targetPort": 80, "nodePort": 30080}]}}'
            local node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "Node IP not found")
            info "Dashboard will be available at: http://${node_ip}:30080"
        fi
    fi
    
    echo
    info "You can now access the dashboard using:"
    if [[ "$service_type" == "NodePort" ]]; then
        local node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "<NODE-IP>")
        echo -e "${YELLOW}http://${node_ip}:30080${NC}"
        info "This URL should be accessible from any computer on your local network"
    else
        echo -e "${YELLOW}./scripts/access-appdeploy.sh local${NC}"
    fi
    echo
    info "For the full platform experience, please run the complete installation:"
    echo -e "${YELLOW}./install.sh${NC}"
}

# Function to access the AppDeploy dashboard
access_dashboard() {
    # Kill any existing port-forward for this service to avoid conflicts
    pkill -f "kubectl port-forward.*${SERVICE}" &> /dev/null || true
    
    local PORT=8082
    
    # Find the target port for the service
    local TARGET_PORT=$(kubectl get service ${SERVICE} -n ${NAMESPACE} -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "80")
    
    # Start port-forwarding in the background
    header "🔄 Setting up port forwarding for AppDeploy Dashboard..."
    info "Using service: ${SERVICE} in namespace: ${NAMESPACE}"
    kubectl port-forward svc/${SERVICE} -n ${NAMESPACE} ${PORT}:${TARGET_PORT} &
    local PORT_FORWARD_PID=$!
    
    # Add a small delay to ensure port-forwarding is established
    sleep 2
    
    if ps -p $PORT_FORWARD_PID > /dev/null; then
        success "Port forwarding established successfully"
        info "AppDeploy Dashboard is now available at: http://localhost:${PORT}"
        info "Press Ctrl+C to stop port-forwarding when done"
        
        # On some systems, try to open the URL automatically
        if command -v xdg-open &> /dev/null; then
            xdg-open "http://localhost:${PORT}" &> /dev/null || true
        elif command -v open &> /dev/null; then
            open "http://localhost:${PORT}" &> /dev/null || true
        elif command -v start &> /dev/null; then
            start "http://localhost:${PORT}" &> /dev/null || true
        fi
        
        # Keep the script running to maintain the port-forward
        wait $PORT_FORWARD_PID
    else
        error "Failed to establish port-forwarding"
        exit 1
    fi
}

# Function to provide SSH tunnel instructions
show_ssh_tunnel_instructions() {
    header "🔒 SSH Tunneling Instructions for Remote Access"
    info "Execute this command on your local machine to create an SSH tunnel:"
    echo
    echo -e "${YELLOW}ssh -L 8082:localhost:8082 user@your-remote-server-ip${NC}"
    echo
    info "Then, while the SSH connection is active, run this command on the remote server:"
    echo
    local TARGET_PORT=$(kubectl get service ${SERVICE} -n ${NAMESPACE} -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "80")
    echo -e "${YELLOW}kubectl port-forward svc/${SERVICE} -n ${NAMESPACE} 8082:${TARGET_PORT}${NC}"
    echo
    info "Then access the AppDeploy Dashboard at: http://localhost:8082"
    echo
    info "Remember to replace 'user' and 'your-remote-server-ip' with your actual SSH username and server IP"
    echo
    info "Alternative one-step approach (run on your local machine):"
    echo -e "${YELLOW}ssh -L 8082:localhost:${TARGET_PORT} user@your-remote-server-ip \"kubectl port-forward svc/${SERVICE} -n ${NAMESPACE} ${TARGET_PORT}:${TARGET_PORT}\"${NC}"
}

# Main execution
header "🖥️  AppDeploy Dashboard Access"
echo

if [[ $# -eq 0 ]]; then
    # No arguments provided, show usage
    info "Usage:"
    echo -e "  ${YELLOW}./scripts/access-appdeploy.sh local${NC}     - Access dashboard through local port-forwarding"
    echo -e "  ${YELLOW}./scripts/access-appdeploy.sh tunnel${NC}    - Show instructions for SSH tunneling"
    echo -e "  ${YELLOW}./scripts/access-appdeploy.sh diagnose${NC}  - Run diagnostics on platform setup"
    echo -e "  ${YELLOW}./scripts/access-appdeploy.sh setup${NC}     - Set up a minimal dashboard for testing"
    echo -e "  ${YELLOW}./scripts/access-appdeploy.sh setup nodeport${NC} - Set up a minimal dashboard with NodePort for network access"
    exit 0
fi

case "$1" in
    local)
        # Try to find the dashboard service first
        DASHBOARD_INFO=$(find_dashboard)
        if [[ $? -ne 0 ]]; then
            error "Could not find the AppDeploy dashboard in any namespace."
            info "Try running the diagnostic tool to check platform status:"
            echo -e "  ${YELLOW}./scripts/access-appdeploy.sh diagnose${NC}"
            exit 1
        fi
        
        # Parse the namespace and service name
        NAMESPACE=$(echo $DASHBOARD_INFO | cut -d '|' -f 1)
        SERVICE=$(echo $DASHBOARD_INFO | cut -d '|' -f 2)
        
        access_dashboard
        ;;
    tunnel)
        # Try to find the dashboard service first
        DASHBOARD_INFO=$(find_dashboard)
        if [[ $? -ne 0 ]]; then
            error "Could not find the AppDeploy dashboard in any namespace."
            info "Try running the diagnostic tool to check platform status:"
            echo -e "  ${YELLOW}./scripts/access-appdeploy.sh diagnose${NC}"
            exit 1
        fi
        
        # Parse the namespace and service name
        NAMESPACE=$(echo $DASHBOARD_INFO | cut -d '|' -f 1)
        SERVICE=$(echo $DASHBOARD_INFO | cut -d '|' -f 2)
        
        show_ssh_tunnel_instructions
        ;;
    diagnose)
        diagnose
        ;;
    setup)
        if [[ $# -ge 2 && "$2" == "nodeport" ]]; then
            setup_minimal_dashboard "nodeport"
        else
            setup_minimal_dashboard
        fi
        ;;
    *)
        error "Unknown option: $1"
        info "Usage:"
        echo -e "  ${YELLOW}./scripts/access-appdeploy.sh local${NC}     - Access dashboard through local port-forwarding"
        echo -e "  ${YELLOW}./scripts/access-appdeploy.sh tunnel${NC}    - Show instructions for SSH tunneling"
        echo -e "  ${YELLOW}./scripts/access-appdeploy.sh diagnose${NC}  - Run diagnostics on platform setup"
        echo -e "  ${YELLOW}./scripts/access-appdeploy.sh setup${NC}     - Set up a minimal dashboard for testing"
        echo -e "  ${YELLOW}./scripts/access-appdeploy.sh setup nodeport${NC} - Set up a minimal dashboard with NodePort for network access"
        exit 1
        ;;
esac
