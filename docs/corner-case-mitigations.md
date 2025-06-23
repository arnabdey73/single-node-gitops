# Corner Case Mitigations for AppDeploy Platform

This document describes the corner case mitigations and resilience enhancements implemented in the AppDeploy POC platform. These mitigations ensure the platform operates reliably across a wide range of environments and scenarios.

## Overview of Mitigations

The following corner cases have been addressed with specific mitigations:

| Corner Case | Mitigation | Location |
|-------------|------------|----------|
| Network connectivity issues | Retry logic & network checks | `install.sh` |
| Proxy environments | Proxy detection and configuration | `install.sh` |
| Hardware-specific optimizations | Enhanced hardware detection | `install.sh` |
| Installation failures | Comprehensive error handling | `install.sh` |
| Resource limitations | Resource quotas & management | `configs/resource-quota-template.yaml` |
| Certificate expiration | Certificate monitoring | `install.sh` |
| Node reboots & recovery | Node recovery script | `scripts/node-recovery.sh` |
| DNS resolution issues | DNS validation & troubleshooting | `scripts/health-check.sh` |
| Log rotation & garbage collection | Log management system | `install.sh` |
| Version compatibility | Component version pinning | `install.sh` |
| System service management | Systemd service configuration | `install.sh` |

## How to Use These Mitigations

### 1. Network Connectivity & Proxy Environment

The installation script automatically detects network connectivity issues and proxy settings. If your environment uses HTTP proxies:

```bash
# Set proxy environment variables before running install.sh
export http_proxy=http://proxy.example.com:8080
export https_proxy=http://proxy.example.com:8080
export no_proxy=localhost,127.0.0.1,10.0.0.0/8,192.168.0.0/16

# Then run the installation script
./install.sh
```

### 2. Hardware Detection & Optimization

The installation script automatically detects your hardware type and applies appropriate optimizations. For Dell PowerEdge systems, specific Dell optimizations are applied. For other hardware, generic optimizations are used.

### 3. Resource Management

To prevent any namespace from consuming excessive resources:

```bash
# Apply resource quota to a namespace
kubectl apply -f configs/resource-quota-template.yaml -n my-application
```

See `docs/resource-management.md` for detailed guidance.

### 4. Node Recovery

If your system experiences issues after a reboot or failure:

```bash
# Run the node recovery script
./scripts/node-recovery.sh
```

This script will:

- Check and restart system services
- Fix DNS resolution issues
- Fix storage issues
- Restart critical components
- Fix stuck resources
- Sync applications

### 5. Enhanced Health Checks

Run enhanced health checks to verify system health:

```bash
# Verify health check enhancements are in place
./scripts/check-corner-case-mitigations.sh

# Run comprehensive health check
./scripts/health-check.sh
```

### 6. Upgrade Management

Use the automatically created upgrade script:

```bash
# Upgrade all platform components
./upgrade-platform.sh
```

This script handles:

- Creating a backup before upgrading
- Updating the repository
- Upgrading K3s (optional)
- Upgrading ArgoCD
- Upgrading applications

### 7. Log Management

The platform includes:

- Automatic log rotation for containerd
- Daily cleanup job for terminated pods and completed jobs
- Monitoring of log volume usage

## Testing the Mitigations

To verify these mitigations are working correctly:

```bash
# Verify installation script logs are being captured
cat appdeploy_install_*.log

# Check for proxy configuration (if applicable)
cat /etc/systemd/system/containerd.service.d/proxy.conf

# Verify K3s service configuration
systemctl status k3s

# Check system cleanup job
kubectl get cronjob -n kube-system system-cleanup

# Test DNS resolution
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: dns-test
  namespace: default
spec:
  template:
    spec:
      containers:
      - name: dns-test
        image: busybox:1.34.1
        command: ["/bin/sh", "-c", "nslookup kubernetes.default.svc.cluster.local && nslookup github.com"]
      restartPolicy: Never
  backoffLimit: 2
EOF
kubectl logs job/dns-test -n default
```

## Maintenance Recommendations

1. **Regular Health Checks**: Run `./scripts/health-check.sh` weekly
2. **System Updates**: Use `./upgrade-platform.sh` for platform updates
3. **Certificate Management**: Monitor certificate expiration with `kubectl get secrets --field-selector type=kubernetes.io/tls -A`
4. **Resource Monitoring**: Check namespace resource quotas regularly
5. **Backup Data**: Create regular backups with `./scripts/backup.sh`

## Troubleshooting

If issues arise:

1. Check installation logs: `cat appdeploy_install_*.log`
2. Run enhanced health checks: `./scripts/health-check.sh`
3. Attempt automatic recovery: `./scripts/node-recovery.sh`
4. Check system events: `kubectl get events --sort-by='.lastTimestamp'`
5. Monitor pod logs: `kubectl logs -n <namespace> <pod-name>`
