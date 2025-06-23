# AppDeploy Platform Base Resource Consumption

Before deploying any applications, the AppDeploy platform itself consumes a baseline of resources. Here's a detailed breakdown of the resource consumption for the base platform components:

## 📊 Total Base Platform Resource Requirements

| Resource | Minimum Requirement | Recommended |
|----------|---------------------|------------|
| **CPU**  | 2 cores             | 4+ cores   |
| **Memory** | 4 GB              | 8+ GB      |
| **Storage** | 20 GB            | 40+ GB     |

## 🧩 Component-by-Component Resource Consumption

### Core Platform Components

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit | Storage |
|-----------|------------|-----------|---------------|------------|---------|
| K3s (base) | 0.5 cores | 1 core | 1 GB | 2 GB | 5 GB |
| ArgoCD | 0.3 cores | 0.5 cores | 512 MB | 1 GB | 1 GB |
| Dashboard | 0.1 cores | 0.2 cores | 128 MB | 256 MB | 100 MB |

### Monitoring & Logging Stack

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit | Storage |
|-----------|------------|-----------|---------------|------------|---------|
| Prometheus | 0.2 cores | 0.5 cores | 512 MB | 1 GB | 5 GB |
| Grafana | 0.1 cores | 0.2 cores | 256 MB | 512 MB | 500 MB |
| Loki | 0.2 cores | 0.4 cores | 256 MB | 512 MB | 2 GB |

### DevSecOps Components

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit | Storage |
|-----------|------------|-----------|---------------|------------|---------|
| Trivy Operator | 0.2 cores | 0.3 cores | 256 MB | 512 MB | 1 GB |
| OPA Gatekeeper | 0.2 cores | 0.3 cores | 256 MB | 512 MB | 256 MB |
| Kube-bench | 0.1 cores | 0.2 cores | 128 MB | 256 MB | 256 MB |
| Security Dashboard | 0.1 cores | 0.2 cores | 128 MB | 256 MB | 100 MB |

### Infrastructure Services

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit | Storage |
|-----------|------------|-----------|---------------|------------|---------|
| Docker Registry | 0.1 cores | 0.2 cores | 256 MB | 512 MB | 5 GB |
| Cert Manager | 0.1 cores | 0.2 cores | 128 MB | 256 MB | 100 MB |
| Traefik Ingress | 0.1 cores | 0.3 cores | 128 MB | 256 MB | 100 MB |

## 🔍 Resource Utilization Observations

1. **Initial Startup Peak**: During platform startup, CPU and memory usage may spike 30-50% higher than the steady-state numbers above.

2. **Resource Elasticity**: The platform is designed to scale its resource usage based on load - idle components will consume less than their requests.

3. **Storage Growth**: Log storage will grow over time - approximately 100-200 MB per day depending on cluster activity.

4. **Dell PowerEdge R540 Compatibility**: The platform is well optimized for Dell PowerEdge R540 hardware, which typically provides ample resources (24+ cores, 64GB+ RAM) for both the base platform and numerous applications.

## 💡 Resource Management Features

The platform includes these resource management features:

1. **Resource Quotas**: Automatically applied to prevent any component from consuming excessive resources.

2. **Health Monitoring**: The `health-check.sh` script monitors resource usage and alerts on potential issues.

3. **Resource Visualization**: Grafana dashboards provide real-time visibility into resource consumption.

4. **Garbage Collection**: Automatic cleanup of terminated pods and unused images to preserve storage.

## 🔧 Optimization Options

If you need to deploy on a resource-constrained environment:

```bash
# Install with minimal security components
./install.sh --disable-vulnerability-scanning --disable-cis-benchmarks

# Reduce Prometheus retention period (in applications/monitoring/values.yaml)
# Change from:
# retention: 15d
# To:
# retention: 5d
```

## 🚀 Initial Deployment Recommendations

For optimal performance:

- Allow 5-10 minutes after installation for resource usage to stabilize
- Monitor resource consumption with `kubectl top nodes` and `kubectl top pods -A`
- Check dashboard health indicators for any resource pressure warnings

The platform is designed to be efficient while providing comprehensive functionality. The numbers above represent the baseline consumption before deploying any applications of your own.
