# Single Node GitOps DevOps Platform

A complete GitOps-based DevOps platform designed for single-node deployments using K3s, ArgoCD, and a curated set of cloud-native tools.

## 🚀 Features

- **Lightweight Kubernetes**: K3s for single-node clusters
- **GitOps Workflow**: ArgoCD for declarative deployments
- **Monitoring Stack**: Prometheus, Grafana, and Loki
- **Code Repository**: Gitea for Git hosting
- **Storage**: Longhorn for distributed storage
- **Security**: cert-manager and sealed-secrets
- **Backup & Recovery**: Automated backup solutions

## 📋 Prerequisites

- Ubuntu 20.04+ or similar Linux distribution
- Minimum 4GB RAM, 2 CPU cores
- 50GB+ available disk space
- Internet connectivity
- sudo privileges

## 🛠️ Quick Start

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

## 📁 Directory Structure

```
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
