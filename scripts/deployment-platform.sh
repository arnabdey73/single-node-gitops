#!/bin/bash

# AppDeploy Deployment Platform Management Script
# Usage: ./deployment-platform.sh [start|stop|status|logs|open]

set -e

NAMESPACE="deployment-platform"
APP_NAME="deployment-platform"
LOCAL_PORT="8080"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed or not in PATH"
        exit 1
    fi
}

# Check if the deployment platform is running
check_status() {
    log "Checking deployment platform status..."
    
    # Check if namespace exists
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        warning "Namespace '$NAMESPACE' does not exist"
        return 1
    fi
    
    # Check if deployment is ready
    local ready_replicas=$(kubectl get deployment "$APP_NAME" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local desired_replicas=$(kubectl get deployment "$APP_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    
    if [[ "$ready_replicas" -eq "$desired_replicas" ]] && [[ "$ready_replicas" -gt 0 ]]; then
        success "Deployment platform is running ($ready_replicas/$desired_replicas replicas ready)"
        return 0
    else
        warning "Deployment platform is not ready ($ready_replicas/$desired_replicas replicas ready)"
        return 1    fi
}

# Start the deployment platform
start_platform() {
    log "Starting AppDeploy Deployment Platform..."
    
    # Apply the ArgoCD application if it doesn't exist
    if ! kubectl get application "$APP_NAME" -n argocd &> /dev/null; then
        log "Creating ArgoCD application for deployment platform..."
        kubectl apply -f applications/deployment-platform/application.yaml
    else
        log "ArgoCD application already exists, syncing..."
        kubectl patch application "$APP_NAME" -n argocd --type merge -p '{"operation":{"sync":{}}}'
    fi
    
    # Wait for deployment to be ready
    log "Waiting for deployment to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/"$APP_NAME" -n "$NAMESPACE" || {
        error "Deployment failed to become ready within 5 minutes"
        show_logs
        exit 1
    }
    
    success "Deployment platform is now running!"
    show_access_info
}

# Stop the deployment platform
stop_platform() {
    log "Stopping deployment platform..."
    
    if kubectl get application "$APP_NAME" -n argocd &> /dev/null; then
        kubectl delete application "$APP_NAME" -n argocd
        success "ArgoCD application deleted"
    else
        warning "ArgoCD application not found"
    fi
    
    # Wait for namespace to be cleaned up
    if kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log "Waiting for namespace cleanup..."
        kubectl wait --for=delete namespace/"$NAMESPACE" --timeout=120s || {
            warning "Namespace deletion timed out, forcing cleanup..."
            kubectl delete namespace "$NAMESPACE" --force --grace-period=0
        }
    fi
    
    success "Deployment platform stopped"
}

# Show logs
show_logs() {
    log "Showing deployment platform logs..."
    
    if check_status &> /dev/null; then
        kubectl logs -n "$NAMESPACE" -l app.kubernetes.io/name="$APP_NAME" --tail=50 -f
    else
        error "Deployment platform is not running"
        exit 1
    fi
}

# Open the deployment platform in browser
open_platform() {
    log "Opening deployment platform..."
    
    if ! check_status &> /dev/null; then
        error "Deployment platform is not running. Start it first with: $0 start"
        exit 1
    fi
    
    # Start port forwarding in background
    log "Setting up port forwarding to localhost:$LOCAL_PORT..."
    kubectl port-forward -n "$NAMESPACE" service/"$APP_NAME" "$LOCAL_PORT":80 &
    local port_forward_pid=$!
    
    # Wait a moment for port forwarding to establish
    sleep 2
    
    # Open in browser
    local url="http://localhost:$LOCAL_PORT"
    log "Opening $url in browser..."
    
    if command -v open &> /dev/null; then
        # macOS
        open "$url"
    elif command -v xdg-open &> /dev/null; then
        # Linux
        xdg-open "$url"
    else
        warning "Could not automatically open browser. Please visit: $url"
    fi
      echo ""
    success "Port forwarding active on $url"
    log "Press Ctrl+C to stop port forwarding"
    
    # Wait for port forwarding to be killed
    wait $port_forward_pid
}

# Show access information
show_access_info() {
    echo ""
    echo -e "${BLUE}=== AppDeploy Deployment Platform Access Info ===${NC}"
    echo ""
    echo "🌐 Web Interface:"
    echo "   Local Access: kubectl port-forward -n $NAMESPACE service/$APP_NAME 8080:80"
    echo "   Then visit: http://localhost:8080"
    echo ""
    echo "🔧 Management Commands:"
    echo "   Status: $0 status"
    echo "   Logs: $0 logs"
    echo "   Open: $0 open"
    echo "   Stop: $0 stop"
    echo ""
    echo "📊 Kubernetes Resources:"
    echo "   Namespace: $NAMESPACE"
    echo "   Deployment: $APP_NAME"
    echo "   Service: $APP_NAME"
    echo ""
}

# Main function
main() {
    check_kubectl
    
    case "${1:-status}" in
        start)
            start_platform
            ;;
        stop)
            stop_platform
            ;;
        status)
            if check_status; then
                show_access_info
            else
                echo ""
                log "To start the deployment platform, run: $0 start"
            fi
            ;;
        logs)
            show_logs
            ;;
        open)
            open_platform
            ;;
        *)            echo "AppDeploy Deployment Platform Management"
            echo ""
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  start   - Deploy and start the platform"
            echo "  stop    - Stop and remove the platform"
            echo "  status  - Check platform status (default)"
            echo "  logs    - Show platform logs"
            echo "  open    - Open platform in browser with port forwarding"
            echo ""
            exit 1
            ;;
    esac
}

main "$@"
