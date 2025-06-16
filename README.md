# Single Node GitOps DevOps Platform

A complete GitOps-based DevOps platform designed for single-node deployments on Dell PowerEdge R540 hardware. This platform provides a solution for application deployment, monitoring, and management using K3s, ArgoCD, and other open source tools.

## � **Features**
- **Git Repository Integration** with ArgoCD
- **Kubernetes Dashboard** for cluster management  
- **Container Registry Support** with security scanning
- **CI/CD Pipeline Integration**
- **99.99% Uptime** target with Dell hardware optimizations
- **Real-time Analytics** with Prometheus and Grafana
- **Hardware Monitoring** for Dell PowerEdge R540
- **Security** with cert-manager and sealed-secrets

---

## 🚀 Quick Start - AppDeploy POC

### ⚡ **Get AppDeploy Running in 5 Minutes**

The fastest way to experience the power of AppDeploy POC:

1. **Install the platform**:
   ```bash
   cd single-node-gitops
   chmod +x install.sh
   ./install.sh 2>&1 | tee platform-installation.log
   ```

2. **Open the dashboard**:
   ```bash
   ./scripts/dashboard-access.sh open
   ```

3. **Start deploying applications** through the modern web interface!

### 🎯 **Platform Features**

The platform includes:
- ✅ Kubernetes deployment workflows
- ✅ Real-time monitoring and analytics  
- ✅ GitOps integration with ArgoCD
- ✅ Dashboard interfaces for management
- ✅ Dell PowerEdge R540 optimizations

---

## 🛠️ Complete Platform Installation

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

## 🎯 **Dashboard Interfaces**

### **Kubernetes Dashboard**

- **🚀 Quick Access**: `./scripts/dashboard-access.sh`
- **📱 URL**: `http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/`
- **🎯 Purpose**: Kubernetes cluster management and monitoring

**⭐ Key Features**:
- **Application deployment** and monitoring
- **Resource management** for pods, deployments, services
- **Real-time monitoring** and performance analytics  
- **Configuration management** for ConfigMaps and Secrets
- **Node and pod metrics**

**💼 Management Commands**:
```bash
# Start the platform
./scripts/deployment-platform.sh start

# Open dashboard in browser  
./scripts/deployment-platform.sh open

# View platform status
./scripts/deployment-platform.sh status

# Show logs
./scripts/deployment-platform.sh logs

# Run health checks
./scripts/health-check.sh
```

---

## 🔧 Supporting Dashboards

### Grafana (Monitoring & Metrics)

- **URL**: `http://your-server-ip:30300`
- **Default Login**: admin / admin (change on first login)
- **Features**:
  - Cluster metrics and performance monitoring
  - Dell PowerEdge R540 hardware monitoring
  - Custom application metrics
  - Pre-configured dashboards for K3s and Dell hardware

### AppDeploy POC (Deployment Platform)

- **URL**: `http://localhost:8080` (after running `./scripts/deployment-platform.sh open`)
- **Features**:
  - One-stop-shop application deployment
  - POC-grade deployment workflows
  - Real-time monitoring and analytics
  - GitOps integration with ArgoCD
  - Template-based deployments
  - Container registry support
  - CI/CD pipeline integration
- **Management**: Use `./scripts/deployment-platform.sh` for platform control

### ArgoCD (GitOps Management)

- **URL**: `http://your-server-ip:30080`
- **Login**: admin / `kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d`
- **Features**:
  - Application deployment status
  - Git synchronization monitoring
  - GitOps workflow management
  - Application health and sync status

### Kubernetes Dashboard (Cluster Management)

- **URL**: `http://your-server-ip:30443`
- **Access Token**: `kubectl -n kubernetes-dashboard create token admin-user`
- **Features**:
  - Complete cluster overview
  - Resource management and editing
  - Pod logs and debugging
  - YAML resource editing

### Storage

Storage on this platform uses Local Path Provisioner, which comes built-in with K3s.
Persistent volumes are stored on the local node at `/var/lib/rancher/k3s/storage`.

### Dell OpenManage (Hardware Monitoring)

- **URL**: `https://your-server-ip:1311`
- **Login**: root / (your system root password)
- **Features**:
  - Server hardware health monitoring
  - Temperature and fan monitoring
  - Power consumption tracking
  - RAID controller management

## 📊 Quick Dashboard Access

Use the dashboard access script for easy URL and credential retrieval:

```bash
# Get all dashboard URLs and credentials
./scripts/dashboard-access.sh

# Check overall system health
./scripts/health-check.sh
```

## ⚡ Pre-configured Features

### Dell PowerEdge R540 Dashboards

- Real-time CPU temperature monitoring
- Fan speed and failure detection
- Power consumption tracking
- Memory health indicators
- Storage controller status
- IPMI sensor integration

### Kubernetes Monitoring

- Cluster resource utilization
- Pod and container metrics
- Storage volume status
- Network performance
- Application deployment health

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

### **Architecture Documentation**
- [Platform Architecture](docs/platform-architecture.md) - Technical architecture and components
- [Platform README](applications/deployment-platform/README.md) - Detailed platform documentation

### **Platform Documentation**
- [Installation Guide](docs/installation.md)
- [Architecture Overview](docs/architecture.md)  
- [Application Lifecycle Management](docs/application-lifecycle.md)
- [Troubleshooting](docs/troubleshooting.md)

## 🔧 Management Scripts

### **Core Platform Scripts**
- `scripts/deployment-platform.sh` - Platform management

### **Platform Management Scripts**
- `scripts/health-check.sh` - System health verification
- `scripts/backup.sh` - Backup cluster state
- `scripts/restore.sh` - Restore from backup
- `scripts/dashboard-access.sh` - Get all dashboard URLs and credentials
- `scripts/validate-dell-optimizations.sh` - Validate Dell hardware optimizations

---

## 🌟 **Technical Features**

### **🔧 Core Technical Components**

This single-node GitOps platform includes:

1. **🚀 K3s**: Lightweight Kubernetes distribution
2. **� ArgoCD**: GitOps continuous delivery tool
3. **🔍 Monitoring**: Prometheus, Grafana, and Loki
4. **💾 Storage**: Local Path Provisioner for persistent storage
5. **🔒 Security**: Cert-manager and sealed-secrets

### **� Platform Management**

```bash
# Bootstrap the platform
./bootstrap/k3s-install.sh

# Access dashboards
./scripts/dashboard-access.sh

# Check system health
./scripts/health-check.sh
```

---
