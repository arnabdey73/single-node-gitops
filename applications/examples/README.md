# Example Applications

This directory contains example applications that demonstrate how to deploy workloads using the GitOps pattern.

## Sample Web Application

### Application Structure

```
applications/examples/webapp/
├── application.yaml          # ArgoCD Application definition
├── kustomization.yaml       # Kustomize configuration
├── deployment.yaml          # Kubernetes Deployment
├── service.yaml            # Kubernetes Service
├── ingress.yaml            # Ingress configuration
└── configmap.yaml          # Application configuration
```

### Deploying the Example

1. **Enable the example application**:
   ```bash
   kubectl apply -f applications/examples/webapp/application.yaml
   ```

2. **Monitor deployment**:
   ```bash
   kubectl get applications -n argocd
   kubectl get pods -n examples
   ```

3. **Access the application**:
   ```bash
   # Port forward to access locally
   kubectl port-forward svc/webapp -n examples 8080:80
   
   # Or access via ingress (if configured)
   curl -H "Host: webapp.example.com" http://localhost
   ```

## Database Application Example

Demonstrates how to deploy a stateful application with persistent storage:

- PostgreSQL database
- Persistent volume claims
- Secrets management
- Backup configuration

## Microservices Example

Shows how to deploy multiple interconnected services:

- Frontend service
- Backend API
- Database
- Service mesh configuration
- Network policies

## Monitoring Integration

Examples show how to:

- Add Prometheus metrics endpoints
- Configure ServiceMonitor resources
- Create custom Grafana dashboards
- Set up log aggregation with Loki

## Best Practices Demonstrated

1. **Resource Management**:
   - CPU and memory limits
   - Quality of Service classes
   - Horizontal Pod Autoscaling

2. **Security**:
   - Non-root containers
   - Read-only root filesystems
   - Network policies
   - Pod security standards

3. **Observability**:
   - Health checks
   - Metrics exposition
   - Structured logging
   - Distributed tracing

4. **GitOps Workflow**:
   - Declarative configuration
   - Automated synchronization
   - Rollback procedures
   - Environment promotion
