#!/bin/bash

set -e

echo "Deploying ArgoCD with required permissions..."

echo "Step 1: Installing ArgoCD Custom Resource Definitions..."
kubectl apply -f bootstrap/argocd-crd.yaml

echo "Step 2: Installing ArgoCD components..."
kubectl apply -f bootstrap/argocd-bootstrap.yaml

echo "Step 3: Waiting for ArgoCD server to start..."
kubectl -n argocd wait --for=condition=available --timeout=300s deployment/argocd-server

echo "ArgoCD deployment completed."
echo "To access the UI, use NodePort 30081 (http://your-node-ip:30081)"
echo "Default login credentials: username=admin, password=admin"
