# Resource Management for AppDeploy Platform

This document provides guidance on applying resource quotas and limits to ensure stable platform operation and prevent resource contention issues.

## Resource Quotas

Resource quotas help prevent any single application from consuming excessive resources that might impact the stability of the entire platform. The platform includes a template resource quota that can be applied to each namespace.

### Applying Resource Quotas to New Namespaces

When creating a new namespace for an application, apply the resource quota template:

```bash
# Create namespace
kubectl create namespace my-application

# Apply resource quota
kubectl apply -f configs/resource-quota-template.yaml -n my-application
```

### Customizing Resource Quotas

For namespaces with different resource needs, you can create a custom resource quota:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: custom-resource-quota
  namespace: high-demand-app
spec:
  hard:
    requests.cpu: "4"
    limits.cpu: "8"
    requests.memory: 8Gi
    limits.memory: 16Gi
    requests.storage: 50Gi
    pods: "30"
    services: "15"
    configmaps: "30"
    secrets: "30"
    persistentvolumeclaims: "20"
```

## Resource Limits for Pods

Always define resource requests and limits for each container in your deployments:

```yaml
resources:
  requests:
    memory: "256Mi"
    cpu: "100m"
  limits:
    memory: "512Mi"
    cpu: "500m"
```

## LimitRanges

LimitRanges can enforce default limits on pods in a namespace:

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limit-range
  namespace: my-application
spec:
  limits:
  - default:
      cpu: 500m
      memory: 512Mi
    defaultRequest:
      cpu: 100m
      memory: 256Mi
    type: Container
```

## Platform Monitoring

The platform's monitoring stack will alert you if:

1. Namespaces are approaching their resource quota limits
2. Nodes are experiencing resource pressure
3. Pods are being evicted due to resource constraints

## Recommended Workload Resource Guidelines

For optimal performance, follow these guidelines:

| Workload Type       | CPU Request | CPU Limit | Memory Request | Memory Limit |
|---------------------|-------------|-----------|----------------|-------------|
| Web Frontends       | 100-250m    | 500m      | 128-256Mi      | 512Mi       |
| API Services        | 250-500m    | 1000m     | 256-512Mi      | 1Gi         |
| Databases (small)   | 500m        | 1000m     | 512Mi          | 1Gi         |
| Batch Processing    | 250m        | 2000m     | 256Mi          | 2Gi         |
| Monitoring Services | 100m        | 500m      | 256Mi          | 1Gi         |

## Troubleshooting Resource Issues

If you encounter resource-related issues:

1. Check resource usage:

   ```bash
   kubectl top pods -n <namespace>
   kubectl top nodes
   ```

2. Check for pods hitting resource limits:

   ```bash
   kubectl describe pods -n <namespace> | grep -A 5 "Last State"
   ```

3. Check resource quota status:

   ```bash
   kubectl get resourcequota -n <namespace> -o yaml
   ```

4. Adjust resource quotas or limits as needed.

## Best Practices

1. **Start Small**: Begin with conservative limits and scale up as needed
2. **Monitor Usage**: Regularly check resource consumption patterns
3. **Set Appropriate Limits**: Avoid setting CPU limits too low, as this can cause throttling
4. **Memory Handling**: Set memory limits carefully, as containers exceeding memory limits will be terminated
5. **Storage Planning**: Consider the storage capacity of your node when setting storage quotas
