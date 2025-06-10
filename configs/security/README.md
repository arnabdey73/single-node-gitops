# Security Configuration Examples

This directory contains security configuration examples for the platform.

## Network Policies

### Monitoring Namespace Isolation

```yaml
# monitoring-network-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: monitoring-isolation
  namespace: monitoring
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  # Allow traffic from ingress controllers
  - from:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: TCP
      port: 3000  # Grafana
    - protocol: TCP
      port: 9090  # Prometheus
  # Allow internal monitoring traffic
  - from:
    - podSelector: {}
    ports:
    - protocol: TCP
      port: 3000
    - protocol: TCP
      port: 9090
    - protocol: TCP
      port: 3100  # Loki
  egress:
  # Allow DNS resolution
  - to: []
    ports:
    - protocol: UDP
      port: 53
  # Allow access to Kubernetes API
  - to:
    - namespaceSelector: {}
      podSelector:
        matchLabels:
          component: kube-apiserver
    ports:
    - protocol: TCP
      port: 6443
  # Allow scraping targets
  - to: []
    ports:
    - protocol: TCP
      port: 10250  # kubelet
    - protocol: TCP
      port: 9100   # node-exporter
```

### Default Deny Policy

```yaml
# default-deny.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: monitoring
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

### ArgoCD Network Policy

```yaml
# argocd-network-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: argocd-network-policy
  namespace: argocd
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  # Allow access to ArgoCD server
  - from: []
    ports:
    - protocol: TCP
      port: 8080
  # Allow internal ArgoCD communication
  - from:
    - podSelector: {}
  egress:
  # Allow DNS
  - to: []
    ports:
    - protocol: UDP
      port: 53
  # Allow HTTPS to external Git repositories
  - to: []
    ports:
    - protocol: TCP
      port: 443
  # Allow SSH to external Git repositories
  - to: []
    ports:
    - protocol: TCP
      port: 22
  # Allow access to Kubernetes API
  - to: []
    ports:
    - protocol: TCP
      port: 6443
```

## RBAC Configuration

### Read-Only User

```yaml
# readonly-user.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: readonly-user
  namespace: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: readonly-cluster
rules:
- apiGroups: [""]
  resources: ["*"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["*"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["extensions"]
  resources: ["*"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: readonly-user-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: readonly-cluster
subjects:
- kind: ServiceAccount
  name: readonly-user
  namespace: monitoring
```

### Namespace Admin

```yaml
# namespace-admin.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: monitoring-admin
  namespace: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: monitoring-admin
  namespace: monitoring
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: monitoring-admin-binding
  namespace: monitoring
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: monitoring-admin
subjects:
- kind: ServiceAccount
  name: monitoring-admin
  namespace: monitoring
```

## Pod Security Standards

### Restricted Pod Security

```yaml
# pod-security-policy.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: secure-workloads
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

### Security Context Examples

```yaml
# secure-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: secure-app
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: secure-app
  template:
    metadata:
      labels:
        app: secure-app
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: app
        image: nginx:alpine
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          runAsNonRoot: true
          runAsUser: 1000
          capabilities:
            drop:
            - ALL
        resources:
          limits:
            memory: "128Mi"
            cpu: "100m"
          requests:
            memory: "64Mi"
            cpu: "50m"
        volumeMounts:
        - name: tmp
          mountPath: /tmp
        - name: cache
          mountPath: /var/cache/nginx
        - name: run
          mountPath: /var/run
      volumes:
      - name: tmp
        emptyDir: {}
      - name: cache
        emptyDir: {}
      - name: run
        emptyDir: {}
```

## Sealed Secrets Examples

### Creating Sealed Secrets

```bash
# Example commands for creating sealed secrets

# Create a regular secret
kubectl create secret generic mysecret \
  --from-literal=username=admin \
  --from-literal=password=secretpassword \
  --dry-run=client -o yaml > mysecret.yaml

# Seal the secret
kubeseal -f mysecret.yaml -w mysealedsecret.yaml

# Apply the sealed secret
kubectl apply -f mysealedsecret.yaml

# Clean up the plain secret file
rm mysecret.yaml
```

### Sealed Secret Template

```yaml
# sealed-secret-template.yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: mysecret
  namespace: monitoring
spec:
  encryptedData:
    username: AgBy3i4OJSWK+PiTySYZZA9rO43cGDEQAx...
    password: AhBy3i4OJSWK+PiTySYZZA9rO43cGDEQAx...
  template:
    metadata:
      name: mysecret
      namespace: monitoring
    type: Opaque
```
