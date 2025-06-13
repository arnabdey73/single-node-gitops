# Initial Setup Guide

This guide covers the initial setup steps after running the bootstrap scripts.

## Prerequisites Completed

After running the bootstrap scripts, you should have:

- ✅ K3s cluster installed and running
- ✅ ArgoCD deployed in the `argocd` namespace
- ✅ Basic cluster configuration applied

## Step 1: Verify Installation

```bash
# Check cluster status
kubectl cluster-info
kubectl get nodes

# Check all pods are running
kubectl get pods -A

# Verify ArgoCD is running
kubectl get pods -n argocd
```

## Step 2: Access ArgoCD

### Get Admin Password

```bash
# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
```

### Access the UI

```bash
# Port forward to access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Alternative: Use NodePort (if configured)
# Access at: http://<node-ip>:30080
```

- **URL**: https://localhost:8080
- **Username**: admin
- **Password**: (from the command above)

## Step 3: Configure ArgoCD

### Add Repository (if using private repos)

```bash
# Add your Git repository
argocd repo add https://github.com/your-org/your-repo.git \
  --username your-username \
  --password your-token

# For SSH access
argocd repo add git@github.com:your-org/your-repo.git \
  --ssh-private-key-path ~/.ssh/id_rsa
```

### Create ArgoCD Project

```bash
# Create a project for your applications
argocd proj create single-node-gitops \
  --description "Single Node GitOps Platform" \
  --src https://github.com/your-org/single-node-gitops.git \
  --dest https://kubernetes.default.svc,argocd \
  --allow-cluster-resource '*/*' \
  --allow-namespaced-resource '*/*'
```

## Step 4: Deploy Base Infrastructure

```bash
# Apply base infrastructure components
kubectl apply -k infrastructure/base/

# Monitor deployment
watch kubectl get pods -A
```

## Step 5: Deploy Applications

### Deploy All Applications

```bash
# Deploy all applications via ArgoCD
kubectl apply -f applications/

# Check application status in ArgoCD
kubectl get applications -n argocd
```

### Monitor Deployments

```bash
# Watch application sync status
watch 'kubectl get applications -n argocd'

# Check specific application
kubectl describe application monitoring -n argocd
```

## Step 6: Configure Storage (Local-path Provisioner)

The local-path provisioner is configured automatically with K3s:

```bash
# Check the default storage class
kubectl get sc

# Verify local-path StorageClass exists
kubectl describe sc local-path

# Check storage directory
sudo ls -la /var/lib/rancher/k3s/storage

# If needed, create a test PVC
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-claim
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 100Mi
  fromBackup: ""
EOF
```

## Step 7: Configure Monitoring

### Access Monitoring Services

```bash
# Grafana
kubectl port-forward svc/grafana -n monitoring 3000:3000

# Prometheus
kubectl port-forward svc/prometheus -n monitoring 9090:9090

# AlertManager
kubectl port-forward svc/alertmanager -n monitoring 9093:9093
```

### Default Credentials

- **Grafana**: admin/admin (change on first login)
- **Prometheus**: No authentication required
- **AlertManager**: No authentication required

## Step 8: Configure Git Repository (Gitea)

If deploying Gitea:

```bash
# Access Gitea
kubectl port-forward svc/gitea -n gitea 3001:3000

# Initial setup at: http://localhost:3001
```

## Step 9: Security Configuration

### Deploy cert-manager

```bash
# Check cert-manager pods
kubectl get pods -n cert-manager

# Create a test certificate issuer
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
EOF
```

### Deploy sealed-secrets

```bash
# Check sealed-secrets controller
kubectl get pods -n kube-system | grep sealed-secrets

# Install kubeseal CLI (for creating sealed secrets)
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.18.0/kubeseal-0.18.0-linux-amd64.tar.gz
tar -xvzf kubeseal-0.18.0-linux-amd64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

## Step 10: Configure Backup

```bash
# Set up backup schedule
./scripts/backup.sh

# Test backup
kubectl create secret generic test-secret --from-literal=key=value
./scripts/backup.sh
./scripts/restore.sh
```

## Step 11: Health Check

```bash
# Run comprehensive health check
./scripts/health-check.sh

# Check resource usage
kubectl top nodes
kubectl top pods -A
```

## Troubleshooting

### Common Issues

1. **Pods stuck in Pending**: Check node resources and storage
2. **ArgoCD sync failures**: Check Git repository access and credentials
3. **Storage issues**: Verify local-path provisioner and node storage

### Log Inspection

```bash
# Check system logs
sudo journalctl -u k3s -f

# Check pod logs
kubectl logs -f <pod-name> -n <namespace>

# Check events
kubectl get events --sort-by='.lastTimestamp' -A
```

## Next Steps

1. **Configure Ingress**: Set up external access to services
2. **Set up Monitoring Alerts**: Configure alert rules and notifications  
3. **Backup Strategy**: Implement regular backup schedules
4. **Security Hardening**: Review and apply security best practices
5. **Documentation**: Document any custom configurations

## Useful Commands

```bash
# Quick cluster overview
kubectl get all -A

# Resource usage
kubectl top nodes && kubectl top pods -A

# ArgoCD applications status
kubectl get applications -n argocd -o wide

# Storage status
kubectl get pv,pvc -A

# Service endpoints
kubectl get svc -A
```

## Access Summary

After setup, you can access services at:

- **ArgoCD**: `https://localhost:8080` (port-forward)
- **Grafana**: `http://localhost:3000` (port-forward)  
- **Prometheus**: `http://localhost:9090` (port-forward)
- **Kubernetes Dashboard**: `http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/` (kubectl proxy)
- **Gitea**: `http://localhost:3001` (port-forward)

Remember to save your ArgoCD admin password and update default credentials for all services!
