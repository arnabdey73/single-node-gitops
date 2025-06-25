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

### Step 2: Dell PowerEdge R540 Hardware Optimizations (Optional but Recommended)

If you're running on Dell PowerEdge R540 hardware, apply these optimizations for enhanced performance:

```bash
# Run Dell-specific optimizations
./bootstrap/dell-optimizations.sh

# Apply network and system optimizations
sudo cp configs/network/sysctl-optimizations.conf /etc/sysctl.d/99-k8s-dell-optimization.conf
sudo sysctl --system

# Verify Dell OpenManage installation
sudo systemctl status dsm_om_connsvc
sudo omreport system summary

# Check IPMI functionality
sudo ipmitool sensor list | head -10
```

**Dell PowerEdge R540 Features Enabled:**

- Hardware monitoring via Dell OpenManage Server Administrator
- IPMI sensor monitoring for temperature, fans, and power
- Optimized disk I/O scheduler for high-performance storage
- CPU governor set to performance mode
- Enhanced network tuning for high-throughput workloads
- Increased system limits for containerized workloads

### Step 3: Install K3s

```bash
# Run the K3s installation script
./bootstrap/k3s-install.sh

# Verify installation
kubectl get nodes
kubectl get pods -A
```

### Step 4: Configure kubectl

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

### Step 5: Deploy Base Infrastructure

```bash
# Apply base infrastructure
kubectl apply -k infrastructure/base/

# Wait for components to be ready
kubectl wait --for=condition=ready pod -l app=local-path-provisioner -n kube-system --timeout=300s
```

### Step 6: Bootstrap ArgoCD

```bash
# Deploy ArgoCD
kubectl apply -f bootstrap/argocd-bootstrap.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### Step 7: Access ArgoCD UI

```bash
# Access the AppDeploy Dashboard
./scripts/access-appdeploy.sh local

# Access at: http://localhost:8082

# Port forward to access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8081:8081

# Access at: https://localhost:8081
# Username: admin
# Password: (from previous step)
```

### Step 8: Deploy Applications

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

- **ArgoCD**: `https://localhost:8081` (port-forward required)
- **Grafana**: `http://localhost:3000` (port-forward to grafana service)
- **Prometheus**: `http://localhost:9090` (port-forward to prometheus service)

## Troubleshooting

### Common Issues

1. **Pods stuck in Pending**: Check node resources and storage
2. **Network issues**: Verify firewall and DNS settings
3. **Storage problems**: Check local-path provisioner is working

### Getting Help

- Check the [troubleshooting guide](troubleshooting.md)
- Review pod logs: `kubectl logs <pod-name> -n <namespace>`
- Check events: `kubectl get events --sort-by='.lastTimestamp'`

## Next Steps

- Configure ingress for external access
- Set up monitoring dashboards
- Configure backup schedules
- Review security settings

## Dell PowerEdge R540 Specific Setup

If you're running this on a Dell PowerEdge R540 server, you can take advantage of enhanced optimizations:

### Hardware Optimization

```bash
# Run Dell-specific optimizations
./bootstrap/dell-optimizations.sh

# Apply network optimizations
sudo cp configs/network/sysctl-optimizations.conf /etc/sysctl.d/99-k8s-optimization.conf
sudo sysctl --system
```

### Resource Allocation

Your PowerEdge R540 can handle increased resource allocations:

- **Simple storage** with local-path provisioner
- **Increased CPU/memory limits** for monitoring components
- **Enhanced monitoring** with hardware sensors and IPMI
- **Dell OpenManage integration** for hardware health monitoring

### Hardware Monitoring

After installation, you can access:

- **Dell OpenManage**: <https://your-server-ip:1311>
- **IPMI monitoring**: Integrated into Prometheus/Grafana
- **Hardware health checks**: Included in health-check script

### Performance Benefits

The Dell optimizations provide:

- **CPU governor set to performance** for maximum throughput
- **Optimized disk schedulers** for high-performance storage
- **Enhanced network buffers** for high-throughput workloads
- **Increased system limits** for container workloads

### Step 6: Validate Dell Optimizations (Optional)

After completing the installation, validate that all Dell PowerEdge R540 optimizations are properly applied:

```bash
# Run the validation script
./scripts/validate-dell-optimizations.sh

# Check hardware monitoring integration
kubectl get pods -n monitoring
kubectl logs -n monitoring -l app.kubernetes.io/name=node-exporter

# Verify Dell OpenManage web interface
curl -k https://localhost:1311 || echo "OpenManage web interface check"

# Test IPMI sensors
sudo ipmitool sensor list | grep -E "(Temp|Fan|Power)"
```

**Expected Results:**

- All validation checks should pass with minimal warnings
- Hardware sensors should be accessible via IPMI
- Dell OpenManage web interface should be accessible
- Monitoring stack should collect hardware metrics

### Step 7: Access Services

- **AppDeploy Dashboard**: `http://localhost:8082` (use `./scripts/access-appdeploy.sh local`)
- **ArgoCD**: `https://localhost:8081` (port-forward required)
- **Grafana**: `http://localhost:3000` (port-forward to grafana service)
- **Prometheus**: `http://localhost:9090` (port-forward to prometheus service)
- **Jenkins**: `http://your-server-ip:8080` (running on the server directly)
