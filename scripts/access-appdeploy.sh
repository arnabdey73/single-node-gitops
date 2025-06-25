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

# Check if deployment-platform namespace exists
if ! kubectl get namespace deployment-platform &> /dev/null; then
    error "deployment-platform namespace does not exist. Has the platform been installed correctly?"
    exit 1
fi

# Check if deployment-platform service exists
if ! kubectl get service deployment-platform -n deployment-platform &> /dev/null; then
    error "deployment-platform service does not exist. Has the platform been installed correctly?"
    exit 1
fi

# Function to access the AppDeploy dashboard
access_dashboard() {
    # Kill any existing port-forward for this service to avoid conflicts
    pkill -f "kubectl port-forward.*deployment-platform" &> /dev/null || true
    
    local PORT=8082
    
    # Start port-forwarding in the background
    header "🔄 Setting up port forwarding for AppDeploy Dashboard..."
    kubectl port-forward svc/deployment-platform -n deployment-platform ${PORT}:80 &
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
    info "Then access the AppDeploy Dashboard at: http://localhost:8082"
    echo
    info "Remember to replace 'user' and 'your-remote-server-ip' with your actual SSH username and server IP"
}

# Main execution
header "🖥️  AppDeploy Dashboard Access"
echo

if [[ $# -eq 0 ]]; then
    # No arguments provided, show usage
    info "Usage:"
    echo -e "  ${YELLOW}./scripts/access-appdeploy.sh local${NC} - Access dashboard through local port-forwarding"
    echo -e "  ${YELLOW}./scripts/access-appdeploy.sh tunnel${NC} - Show instructions for SSH tunneling"
    exit 0
fi

case "$1" in
    local)
        access_dashboard
        ;;
    tunnel)
        show_ssh_tunnel_instructions
        ;;
    *)
        error "Unknown option: $1"
        info "Usage:"
        echo -e "  ${YELLOW}./scripts/access-appdeploy.sh local${NC} - Access dashboard through local port-forwarding"
        echo -e "  ${YELLOW}./scripts/access-appdeploy.sh tunnel${NC} - Show instructions for SSH tunneling"
        exit 1
        ;;
esac
