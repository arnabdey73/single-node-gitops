# Troubleshooting Guide

This guide helps you diagnose and resolve common issues with the single-node GitOps platform.

## Quick Diagnostics

### System Health Check

```bash
# Run the comprehensive health check
./scripts/health-check.sh

# Check cluster status
kubectl cluster-info
kubectl get nodes -o wide
kubectl get pods -A

# Check system resources
free -h
df -h
top
```

## Common Issues

### 1. K3s Installation Issues

#### Problem: K3s fails to start

**Symptoms:**

- `systemctl status k3s` shows failed state
- Nodes not appearing in `kubectl get nodes`

**Solutions:**

```bash
# Check K3s logs
sudo journalctl -u k3s -f

# Restart K3s service
sudo systemctl restart k3s

# Reinstall K3s if needed
curl -sfL https://get.k3s.io | sh -

# Check firewall settings
sudo ufw status
sudo ufw allow 6443/tcp  # K3s API server
```

#### Problem: kubectl command not found

**Solutions:**

```bash
# Verify K3s installation
which kubectl
ls -la /usr/local/bin/kubectl

# Create symlink if missing
sudo ln -s /usr/local/bin/k3s /usr/local/bin/kubectl

# Update PATH
export PATH=$PATH:/usr/local/bin
echo 'export PATH=$PATH:/usr/local/bin' >> ~/.bashrc
```

### 2. ArgoCD Issues

#### Problem: ArgoCD pods stuck in Pending

**Symptoms:**

- ArgoCD pods show `Pending` status
- `kubectl describe pod` shows scheduling issues

**Solutions:**

```bash
# Check node resources
kubectl describe nodes
kubectl top nodes

# Check for taints
kubectl describe nodes | grep -i taint

# Check storage availability
kubectl get pv,pvc -A

# Force reschedule
kubectl delete pod -l app.kubernetes.io/name=argocd-server -n argocd
```

#### Problem: Cannot access ArgoCD UI

**Solutions:**

```bash
# Check pod status
kubectl get pods -n argocd

# Check service status
kubectl get svc -n argocd

# Port forward to access UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Check for certificate issues
kubectl logs -l app.kubernetes.io/name=argocd-server -n argocd
```

### 3. Storage Issues

#### Problem: Pods stuck due to volume mount failures

**Symptoms:**

- Pods in `ContainerCreating` state
- Volume mount errors in events

**Solutions:**

```bash
# Check storage class
kubectl get storageclass

# Check PV/PVC status
kubectl get pv,pvc -A

# Check local-path provisioner status
kubectl get sc local-path

# Describe problematic PVC
kubectl describe pvc <pvc-name> -n <namespace>

# Check node storage capacity and local-path storage
df -h /var/lib/rancher/k3s/storage
```

#### Problem: Local-path provisioner issues

**Solutions:**

```bash
# Check local-path storage class
kubectl describe sc local-path

# Check if directory exists
sudo ls -la /var/lib/rancher/k3s/storage

# Fix permissions if needed
sudo chmod 755 /var/lib/rancher/k3s/storage
```

### 4. Networking Issues

#### Problem: Pods cannot communicate

**Symptoms:**

- Services unreachable
- DNS resolution failures
- Network timeouts

**Solutions:**

```bash
# Check CNI plugin status
kubectl get pods -n kube-system | grep -E "(flannel|calico|cilium)"

# Test DNS resolution
kubectl run test-pod --image=busybox -it --rm -- nslookup kubernetes.default

# Check iptables rules
sudo iptables -L -n

# Restart networking components
kubectl delete pods -n kube-system -l k8s-app=flannel
```

#### Problem: External access not working

**Solutions:**

```bash
# Check Traefik status (K3s ingress)
kubectl get pods -n kube-system | grep traefik

# Check ingress resources
kubectl get ingress -A

# Check service types
kubectl get svc -A

# Test port forwarding
kubectl port-forward svc/<service-name> -n <namespace> <local-port>:<service-port>
```

### 5. Application Deployment Issues

#### Problem: ArgoCD applications stuck in sync

**Symptoms:**

- Applications show `OutOfSync` status
- Sync operations fail

**Solutions:**

```bash
# Check ArgoCD application status
kubectl get applications -n argocd

# Describe problematic application
kubectl describe application <app-name> -n argocd

# Force refresh and sync
argocd app sync <app-name> --force

# Check for resource conflicts
kubectl get events --sort-by='.lastTimestamp' -A
```

#### Problem: Pod image pull failures

**Solutions:**

```bash
# Check image pull secrets
kubectl get secrets -A | grep docker

# Check node connectivity
curl -I https://docker.io

# Check pod events
kubectl describe pod <pod-name> -n <namespace>

# Pull image manually (for debugging)
sudo crictl pull <image-name>
```

### 6. Monitoring Stack Issues

#### Problem: Prometheus not scraping targets

**Solutions:**

```bash
# Check Prometheus configuration
kubectl get configmap prometheus-config -n monitoring -o yaml

# Check service monitors
kubectl get servicemonitor -A

# Access Prometheus UI
kubectl port-forward svc/prometheus -n monitoring 9090:9090

# Check targets in UI: http://localhost:9090/targets
```

#### Problem: Grafana dashboards not loading

**Solutions:**

```bash
# Check Grafana pod logs
kubectl logs -l app=grafana -n monitoring

# Check persistent volume
kubectl get pvc -n monitoring

# Reset admin password
kubectl get secret grafana-admin-password -n monitoring -o yaml

# Access Grafana UI
kubectl port-forward svc/grafana -n monitoring 3000:3000
```

## Resource Management

### Memory Issues

```bash
# Check memory usage
kubectl top nodes
kubectl top pods -A

# Find memory-hungry pods
kubectl top pods -A --sort-by=memory

# Adjust resource limits
kubectl patch deployment <deployment-name> -p '{"spec":{"template":{"spec":{"containers":[{"name":"<container>","resources":{"limits":{"memory":"1Gi"}}}]}}}}'
```

### Disk Space Issues

```bash
# Check disk usage
df -h

# Clean up unused images
sudo crictl rmi --prune

# Clean up logs
sudo truncate -s 0 /var/log/*.log

# Check for large files
sudo find / -type f -size +100M 2>/dev/null
```

## Debugging Tools

### Essential Commands

```bash
# Get detailed pod information
kubectl describe pod <pod-name> -n <namespace>

# Check pod logs
kubectl logs <pod-name> -n <namespace> --previous

# Execute commands in pod
kubectl exec -it <pod-name> -n <namespace> -- /bin/bash

# Check events
kubectl get events --sort-by='.lastTimestamp' -A

# Check resource usage
kubectl top nodes
kubectl top pods -A
```

### Network Debugging

```bash
# Test connectivity between pods
kubectl run netshoot --image=nicolaka/netshoot -it --rm

# Check DNS resolution
kubectl run dnsutils --image=gcr.io/kubernetes-e2e-test-images/dnsutils:1.3 -it --rm

# Check service endpoints
kubectl get endpoints -A
```

## Log Analysis

### System Logs

```bash
# K3s service logs
sudo journalctl -u k3s -f

# Container runtime logs
sudo journalctl -u containerd -f

# System messages
sudo tail -f /var/log/syslog
```

### Application Logs

```bash
# All pods in namespace
kubectl logs -l app=<app-label> -n <namespace> --tail=100

# Follow logs
kubectl logs -f <pod-name> -n <namespace>

# Previous container logs
kubectl logs <pod-name> -n <namespace> --previous
```

## Recovery Procedures

### Cluster Recovery

```bash
# Backup etcd
sudo k3s etcd-snapshot save

# Restore from backup
sudo k3s server \
  --cluster-init \
  --cluster-reset \
  --cluster-reset-restore-path=<snapshot-file>
```

### Pod Recovery

```bash
# Restart deployment
kubectl rollout restart deployment <deployment-name> -n <namespace>

# Delete and recreate pod
kubectl delete pod <pod-name> -n <namespace>

# Scale down and up
kubectl scale deployment <deployment-name> --replicas=0 -n <namespace>
kubectl scale deployment <deployment-name> --replicas=1 -n <namespace>
```

## Getting Help

### Log Collection

```bash
# Collect cluster info
kubectl cluster-info dump > cluster-dump.yaml

# Get all resource descriptions
kubectl describe all -A > all-resources.yaml

# Export logs
kubectl logs --all-containers=true --selector app=<app> -n <namespace> > app-logs.txt
```

### Community Resources

- [K3s Documentation](https://docs.k3s.io/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Kubernetes Troubleshooting](https://kubernetes.io/docs/tasks/debug-application-cluster/)
- [Local Path Provisioner](https://github.com/rancher/local-path-provisioner)

### Emergency Contacts

- Check project README for maintainer contacts
- Open issues in the project repository
- Consult team documentation for escalation procedures
