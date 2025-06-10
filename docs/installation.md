# Installation Guide

This guide walks you through setting up the single-node GitOps platform from scratch.

## System Requirements

### Hardware
- **CPU**: 2+ cores (4+ recommended)
- **RAM**: 4GB minimum (8GB+ recommended)
- **Storage**: 50GB+ available space
- **Network**: Internet connectivity required

### Software
- Ubuntu 20.04+ (or compatible Linux distribution)
- sudo privileges
- curl, wget, git

## Installation Steps

### Step 1: Prepare the System

```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y curl wget git unzip

# Disable swap (required for Kubernetes)
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
```

### Step 2: Install K3s

```bash
# Run the K3s installation script
./bootstrap/k3s-install.sh

# Verify installation
kubectl get nodes
kubectl get pods -A
```

### Step 3: Configure kubectl

```bash
# Set up kubeconfig for regular user
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
export KUBECONFIG=~/.kube/config

# Add to shell profile for persistence
echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
source ~/.bashrc
```

### Step 4: Deploy Base Infrastructure

```bash
# Apply base infrastructure
kubectl apply -k infrastructure/base/

# Wait for components to be ready
kubectl wait --for=condition=ready pod -l app=local-path-provisioner -n kube-system --timeout=300s
```

### Step 5: Bootstrap ArgoCD

```bash
# Deploy ArgoCD
kubectl apply -f bootstrap/argocd-bootstrap.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### Step 6: Access ArgoCD UI

```bash
# Port forward to access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Access at: https://localhost:8080
# Username: admin
# Password: (from previous step)
```

### Step 7: Deploy Applications

```bash
# Deploy all applications via ArgoCD
kubectl apply -f applications/

# Monitor deployment status
kubectl get applications -n argocd
```

## Post-Installation Verification

### Check Cluster Health

```bash
# Run health check script
./scripts/health-check.sh

# Check all pods are running
kubectl get pods -A

# Check storage class
kubectl get storageclass
```

### Access Services

- **ArgoCD**: `https://localhost:8080` (port-forward required)
- **Grafana**: `http://localhost:3000` (port-forward to grafana service)
- **Prometheus**: `http://localhost:9090` (port-forward to prometheus service)

## Troubleshooting

### Common Issues

1. **Pods stuck in Pending**: Check node resources and storage
2. **Network issues**: Verify firewall and DNS settings
3. **Storage problems**: Check Longhorn installation

### Getting Help

- Check the [troubleshooting guide](troubleshooting.md)
- Review pod logs: `kubectl logs <pod-name> -n <namespace>`
- Check events: `kubectl get events --sort-by='.lastTimestamp'`

## Next Steps

- Configure ingress for external access
- Set up monitoring dashboards
- Configure backup schedules
- Review security settings
