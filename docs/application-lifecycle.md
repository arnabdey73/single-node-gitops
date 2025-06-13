# Application Lifecycle Management

This document outlines the processes for onboarding (adding) and offloading (removing) applications on the AppDeploy POC platform.

## Application Onboarding Process

### Prerequisites

Before adding a new application to the platform, ensure you have:

- Application source code in a Git repository (GitHub, GitLab, etc.)
- Kubernetes manifests or Helm charts for your application
- Resource requirements defined (CPU, memory, storage)
- Necessary configuration parameters identified

### Step 1: Create Application Directory Structure

1. Create a new directory for your application in the `applications` directory:

   ```bash
   mkdir -p applications/your-application-name
   ```

2. Create the following files:
   - `application.yaml`: ArgoCD Application definition
   - `kustomization.yaml`: Kustomize configuration (if using Kustomize)
   - Other Kubernetes manifests (deployments, services, config maps, etc.)

### Step 2: Define the ArgoCD Application

Create an `application.yaml` file with the following structure:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: your-application-name
  namespace: argocd
  labels:
    app.kubernetes.io/name: your-application-name
    app.kubernetes.io/part-of: single-node-gitops
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/repository.git
    targetRevision: HEAD
    path: path/to/your/manifests
    # Or use Helm:
    # chart: your-chart
    # repoURL: https://charts.example.com
  destination:
    server: https://kubernetes.default.svc
    namespace: your-application-namespace
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### Step 3: Add Application Resources

Create the necessary Kubernetes manifests for your application:

1. **Deployment or StatefulSet**:
   - Define containers, images, and resource requests/limits
   - Configure environment variables and volume mounts

2. **Services**:
   - Define how the application is exposed internally

3. **Ingress** (if applicable):
   - Configure external access

4. **ConfigMaps and Secrets**:
   - Store configuration and sensitive data

5. **Persistent Volume Claims** (if applicable):
   - Define storage requirements

### Step 4: Deploy the Application

Register your application with ArgoCD:

```bash
# Apply the ArgoCD Application definition
kubectl apply -f applications/your-application-name/application.yaml

# Monitor the sync status
kubectl get applications -n argocd your-application-name
```

### Step 5: Verify Deployment

1. Check that ArgoCD has successfully synced the application:

   ```bash
   kubectl get applications -n argocd
   ```

2. Verify that the application pods are running:

   ```bash
   kubectl get pods -n your-application-namespace
   ```

3. Access the application:

   ```bash
   # Via port-forward (for testing)
   kubectl port-forward svc/your-service -n your-application-namespace local-port:service-port

   # Or via Ingress (if configured)
   curl https://your-application-hostname
   ```

## Application Offloading Process

### Step 1: Prepare for Removal

Before removing an application:

1. **Notify stakeholders** of the planned removal
2. **Backup any important data** stored in persistent volumes
3. **Document any configurations** that might be needed later

### Step 2: Remove the Application

There are two approaches to remove an application:

#### Option 1: Using kubectl (immediate removal)

```bash
# Delete the ArgoCD Application (this will cascade to all resources)
kubectl delete application -n argocd your-application-name
```

#### Option 2: Git-based removal (recommended for GitOps)

1. Remove the application directory or files from your Git repository
2. Commit and push the changes
3. ArgoCD will automatically remove the resources (if `automated` and `prune` are enabled)

### Step 3: Verify Removal

1. Check that the ArgoCD Application is gone:

   ```bash
   kubectl get applications -n argocd
   ```

2. Verify that the application namespace is cleaned up:

   ```bash
   kubectl get all -n your-application-namespace
   ```

3. Check for any persistent volumes that might need manual cleanup:
   ```bash
   kubectl get pv | grep your-application-namespace
   ```

### Step 4: Clean Up Additional Resources

Some resources might require manual cleanup:

1. **Persistent Volumes** (if `Retain` policy is used)
   ```bash
   kubectl delete pv <persistent-volume-name>
   ```

2. **Secrets in external systems** (like container registries, external databases)

3. **DNS records** or load balancer configurations (if managed externally)

## Best Practices

### Application Design

1. **Containerize applications** properly with minimal, secure images
2. **Define resource limits** to prevent noisy neighbor issues
3. **Use health checks** (readiness and liveness probes)
4. **Implement graceful shutdown** to handle termination signals

### Configuration Management

1. **Externalize configurations** in ConfigMaps or Secrets
2. **Use environment-specific values** (dev, staging, prod)
3. **Seal sensitive secrets** using sealed-secrets

### Observability

1. **Expose Prometheus metrics** for monitoring
2. **Configure logging** to work with the platform's log aggregation
3. **Add tracing** if your application is part of a microservices architecture

### GitOps Workflow

1. **Maintain a separate repository** for application configurations
2. **Use branches** for different environments
3. **Implement pull requests** for changes
4. **Enable ArgoCD automated sync** for continuous deployment

## Troubleshooting

### Common Onboarding Issues

1. **Application not syncing**:
   - Check ArgoCD logs: `kubectl logs -n argocd deployment/argocd-application-controller`
   - Verify Git repository access

2. **Pods failing to start**:
   - Check pod events: `kubectl describe pod -n your-namespace pod-name`
   - Look at pod logs: `kubectl logs -n your-namespace pod-name`

3. **Persistent volume issues**:
   - Verify storage class exists: `kubectl get storageclass`
   - Check PVC status: `kubectl get pvc -n your-namespace`

### Common Offloading Issues

1. **Resources not being pruned**:
   - Ensure `prune: true` is set in the Application's syncPolicy
   - Manually delete orphaned resources: `kubectl delete <resource> -n <namespace>`

2. **Stuck finalizers**:
   - Edit the resource to remove finalizers: `kubectl edit <resource> -n <namespace>`

3. **Persistent volumes not cleaning up**:
   - Check reclaim policy: `kubectl get pv <pv-name> -o jsonpath='{.spec.persistentVolumeReclaimPolicy}'`
   - Manually delete if needed: `kubectl delete pv <pv-name>`
