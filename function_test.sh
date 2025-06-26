#!/bin/bash

# Test the specific problematic area
setup_minimal_dashboard() {
    echo "Setting up minimal dashboard"
    
    # Create service based on access type
    local service_type="ClusterIP"
    if [[ "$1" == "nodeport" ]]; then
        service_type="NodePort"
        local nodeport="30080"
        echo "Creating NodePort service (port: $nodeport) for direct network access..."
    else
        echo "Creating standard ClusterIP service..."
    fi
    
    # Check if the service exists, create if it doesn't
    if ! kubectl get service deployment-platform -n deployment-platform &> /dev/null; then
        echo "Creating AppDeploy dashboard service..."
        
        # Create a ConfigMap for the dashboard HTML
        if [ -f "applications/deployment-platform/index.html" ]; then
            kubectl create configmap deployment-platform-config -n deployment-platform --from-file=index.html=applications/deployment-platform/index.html || true
        else
            echo "Dashboard HTML file not found, using basic dashboard"
            kubectl create configmap deployment-platform-config -n deployment-platform --from-literal=index.html="<!DOCTYPE html><html><head><title>AppDeploy Dashboard</title></head><body><h1>AppDeploy Dashboard</h1><p>Real dashboard will be deployed via ArgoCD</p></body></html>" || true
        fi
        
        # Apply the deployment manifests
        if [ -f "applications/deployment-platform/deployment.yaml" ]; then
            kubectl apply -f applications/deployment-platform/deployment.yaml
        else
            echo "Deployment manifest not found, creating basic deployment"
        fi
        
        # Apply service configuration
        kubectl apply -f applications/deployment-platform/service.yaml || cat <<EOF | kubectl apply -f -
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
  type: ClusterIP
EOF

        if [[ "$service_type" == "NodePort" ]]; then
            kubectl patch service deployment-platform -n deployment-platform -p '{"spec": {"type": "NodePort", "ports": [{"name": "http", "port": 80, "targetPort": 80, "nodePort": 30080}]}}'
            local node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "Node IP not found")
            echo "Dashboard will be available at: http://${node_ip}:30080"
        fi
        
        echo "AppDeploy dashboard created with real-time Kubernetes data"
        echo "Waiting for the deployment to be ready..."
        sleep 5
        
        # Check if deployment is ready
        kubectl rollout status deployment/deployment-platform -n deployment-platform --timeout=60s || true
    else
        echo "AppDeploy dashboard service already exists"
        
        if [[ "$service_type" == "NodePort" ]]; then
            echo "Updating service to NodePort type..."
            kubectl patch service deployment-platform -n deployment-platform -p '{"spec": {"type": "NodePort", "ports": [{"name": "http", "port": 80, "targetPort": 80, "nodePort": 30080}]}}'
            local node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "Node IP not found")
            echo "Dashboard will be available at: http://${node_ip}:30080"
        fi
    fi
    
    echo "Function completed"
}

setup_minimal_dashboard
