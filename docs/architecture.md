# Architecture Overview

This document describes the architecture of the single-node GitOps platform.

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Single Node                         │
├─────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │
│  │   ArgoCD    │  │  Monitoring │  │   Storage   │     │
│  │   GitOps    │  │   Stack     │  │  Longhorn   │     │
│  └─────────────┘  └─────────────┘  └─────────────┘     │
├─────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │
│  │   GitHub    │  │ cert-manager│  │   Security  │     │
│  │ Integration │  │    TLS      │  │   Tools     │     │
│  └─────────────┘  └─────────────┘  └─────────────┘     │
├─────────────────────────────────────────────────────────┤
│                 K3s Kubernetes                         │
├─────────────────────────────────────────────────────────┤
│              Ubuntu 20.04+ Linux                       │
└─────────────────────────────────────────────────────────┘
```

## Components

### Core Platform

#### K3s Kubernetes
- **Purpose**: Lightweight Kubernetes distribution
- **Features**: 
  - Single binary installation
  - Built-in containerd
  - Optimized for edge/IoT
  - Minimal resource footprint

#### ArgoCD (GitOps Controller)
- **Purpose**: Declarative GitOps CD for Kubernetes
- **Features**:
  - Git-based configuration management
  - Automated synchronization
  - Web UI for visualization
  - RBAC and security

### Application Stack

#### Monitoring
- **Prometheus**: Metrics collection and alerting
- **Grafana**: Visualization and dashboards
- **Loki**: Log aggregation and querying
- **AlertManager**: Alert handling and routing

#### External Git Integration

- **GitHub**: Primary Git repository hosting
- **Features**:
  - Git repository hosting
  - Web interface and collaboration
  - CI/CD integration capabilities
  - Issue tracking and project management
  - Webhook support for ArgoCD integration

#### Storage
- **Longhorn**: Distributed block storage
- **Features**:
  - Persistent volume management
  - Backup and restore
  - Volume snapshots
  - Cross-node replication

#### Security
- **cert-manager**: TLS certificate management
- **sealed-secrets**: Encrypted secret management
- **Network Policies**: Traffic segmentation

## Data Flow

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│  GitHub     │───▶│   ArgoCD    │───▶│ Kubernetes  │
│  Repository │    │             │    │  Cluster    │
└─────────────┘    └─────────────┘    └─────────────┘
       │                  │                  │
       │                  │                  ▼
       │                  │           ┌─────────────┐
       │                  │           │ Application │
       │                  │           │  Workloads  │
       │                  │           └─────────────┘
       │                  │
       ▼                  ▼
┌─────────────┐    ┌─────────────┐
│  External   │    │ Monitoring  │
│  Git SCM    │    │   Stack     │
└─────────────┘    └─────────────┘
```

## Network Architecture

### Internal Services
- **Pod Network**: 10.42.0.0/16 (default K3s)
- **Service Network**: 10.43.0.0/16 (default K3s)
- **DNS**: CoreDNS for service discovery

### External Access
- **NodePort**: Direct node access (30000-32767)
- **LoadBalancer**: K3s built-in ServiceLB
- **Ingress**: Traefik (built into K3s)

## Storage Architecture

### Storage Classes
- **local-path**: Local host path storage (default)
- **longhorn**: Distributed block storage
- **longhorn-static**: Static provisioning

### Persistent Volumes
- **Database Storage**: Longhorn volumes
- **Log Storage**: Local path volumes
- **Backup Storage**: External mounted volumes

## Security Model

### Authentication & Authorization
- **RBAC**: Kubernetes role-based access control
- **Service Accounts**: Application identity
- **Network Policies**: Traffic restriction

### Secret Management
- **Sealed Secrets**: Encrypted secrets in Git
- **cert-manager**: Automated TLS certificates
- **Key Rotation**: Automated certificate renewal

## Deployment Patterns

### GitOps Workflow
1. **Code Change**: Developer pushes to Git
2. **Detection**: ArgoCD detects changes
3. **Sync**: ArgoCD applies changes to cluster
4. **Monitoring**: Health and status reporting

### Application Structure
```
applications/
├── <component>/
│   ├── base/                # Base configuration
│   ├── overlays/           # Environment-specific
│   └── Application.yaml    # ArgoCD application
```

## Scalability Considerations

### Vertical Scaling
- Increase node resources (CPU, RAM, storage)
- Optimize resource requests/limits
- Use resource quotas

### Horizontal Scaling
- Add worker nodes (future expansion)
- Implement pod autoscaling
- Use external storage solutions

## Monitoring & Observability

### Metrics
- **Node Metrics**: CPU, memory, disk, network
- **Pod Metrics**: Resource usage, health
- **Application Metrics**: Custom business metrics

### Logs
- **System Logs**: K3s, containerd logs
- **Application Logs**: Centralized via Loki
- **Audit Logs**: Kubernetes API access

### Alerting
- **Infrastructure Alerts**: Node/pod failures
- **Application Alerts**: Service degradation
- **Security Alerts**: Unauthorized access

## Backup & Recovery

### Backup Strategy
- **etcd Snapshots**: Kubernetes state backup
- **Volume Snapshots**: Application data backup
- **Configuration Backup**: Git repository backup

### Recovery Procedures
- **Cluster Recovery**: Restore from etcd snapshot
- **Application Recovery**: Restore volumes
- **Data Recovery**: Restore from external backups
