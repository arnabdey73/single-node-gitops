# Single Node GitOps DevOps Platform

A complete GitOps-based DevOps platform designed for single-node deployments using K3s, ArgoCD, and a curated set of cloud-native tools.

## 🚀 Features

- **Lightweight Kubernetes**: K3s for single-node clusters
- **GitOps Workflow**: ArgoCD for declarative deployments
- **Monitoring Stack**: Prometheus, Grafana, and Loki
- **Git Integration**: Works with GitHub and other external Git providers
- **Storage**: Longhorn for distributed storage
- **Security**: cert-manager and sealed-secrets
- **Backup & Recovery**: Automated backup solutions

## 📋 Prerequisites

### Minimum Requirements
- Ubuntu 20.04+ or similar Linux distribution
- Minimum 4GB RAM, 2 CPU cores
- 50GB+ available disk space
- Internet connectivity
- sudo privileges

### Optimized for Dell PowerEdge R540
This platform is specifically optimized for Dell PowerEdge R540 servers with:
- **CPU**: Intel Xeon Silver 4110 (16 cores) @ 3.000GHz
- **Memory**: 32GB RAM
- **Features**: Hardware monitoring, IPMI sensors, Dell OpenManage integration
- **Performance**: Enhanced resource limits and enterprise-grade configurations

## 🛠️ Quick Start

### Standard Installation

1. **Clone this repository**:
   ```bash
   git clone <repository-url>
   cd single-node-gitops
   ```

2. **Bootstrap the cluster**:
   ```bash
   ./bootstrap/k3s-install.sh
   ```

3. **Install ArgoCD**:
   ```bash
   kubectl apply -f bootstrap/argocd-bootstrap.yaml
   ```

4. **Deploy applications**:

   ```bash
   kubectl apply -f applications/
   ```

### Dell PowerEdge R540 Optimized Installation

If you're running on Dell PowerEdge R540 hardware, use these additional steps for optimal performance:

1. **Apply hardware optimizations** (before K3s installation):

   ```bash
   ./bootstrap/dell-optimizations.sh
   ```

2. **Install K3s with Dell optimizations**:

   ```bash
   ./bootstrap/k3s-install.sh  # Already includes Dell-specific flags
   ```

3. **Apply network optimizations**:

   ```bash
   sudo cp configs/network/sysctl-optimizations.conf /etc/sysctl.d/99-k8s-dell-optimization.conf
   sudo sysctl --system
   ```

4. **Deploy monitoring with hardware sensors**:

   ```bash
   kubectl apply -f configs/monitoring/node-exporter-dell-config.yaml
   kubectl apply -f applications/
   ```

5. **Access Dell OpenManage** (after deployment):
   - Web interface: `https://your-server-ip:1311`
   - Default login: root / (your system root password)

**Enhanced Features for Dell PowerEdge R540:**

- Hardware temperature and fan monitoring
- IPMI sensor integration
- Power consumption tracking
- Storage controller health monitoring
- Performance-optimized resource limits

## 📁 Directory Structure

```text
├── bootstrap/          # Initial cluster setup scripts
├── infrastructure/     # Base infrastructure components
├── applications/       # Application deployments
├── configs/           # Configuration files
├── scripts/           # Utility scripts
└── docs/             # Documentation
```

## 📖 Documentation

- [Installation Guide](docs/installation.md)
- [Architecture Overview](docs/architecture.md)
- [Troubleshooting](docs/troubleshooting.md)

## 🔧 Management Scripts

- `scripts/health-check.sh` - System health verification
- `scripts/backup.sh` - Backup cluster state
- `scripts/restore.sh` - Restore from backup

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.
