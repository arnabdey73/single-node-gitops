# Ingress Configuration Examples

This directory contains configuration examples for ingress and external access.

## Traefik Configuration (K3s Built-in)

### Basic Ingress Route

```yaml
# basic-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: monitoring-ingress
  namespace: monitoring
  annotations:
    kubernetes.io/ingress.class: traefik
    traefik.ingress.kubernetes.io/router.tls: "true"
spec:
  tls:
  - hosts:
    - grafana.local
    - prometheus.local
    secretName: monitoring-tls
  rules:
  - host: grafana.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: grafana
            port:
              number: 3000
  - host: prometheus.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: prometheus
            port:
              number: 9090
```

### Traefik Middleware Examples

```yaml
# auth-middleware.yaml
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: basic-auth
  namespace: monitoring
spec:
  basicAuth:
    secret: basic-auth-secret
---
# redirect-https.yaml
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: redirect-https
spec:
  redirectScheme:
    scheme: https
    permanent: true
```

### Advanced Ingress with Authentication

```yaml
# secure-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: secure-monitoring
  namespace: monitoring
  annotations:
    kubernetes.io/ingress.class: traefik
    traefik.ingress.kubernetes.io/router.middlewares: monitoring-basic-auth@kubernetescrd
spec:
  tls:
  - hosts:
    - monitoring.example.com
    secretName: monitoring-tls-cert
  rules:
  - host: monitoring.example.com
    http:
      paths:
      - path: /grafana
        pathType: Prefix
        backend:
          service:
            name: grafana
            port:
              number: 3000
      - path: /prometheus
        pathType: Prefix
        backend:
          service:
            name: prometheus
            port:
              number: 9090
```

## NodePort Services

For simple external access without ingress:

```yaml
# nodeport-services.yaml
apiVersion: v1
kind: Service
metadata:
  name: grafana-nodeport
  namespace: monitoring
spec:
  type: NodePort
  ports:
  - port: 3000
    targetPort: 3000
    nodePort: 30300
    name: grafana
  selector:
    app.kubernetes.io/name: grafana
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus-nodeport
  namespace: monitoring
spec:
  type: NodePort
  ports:
  - port: 9090
    targetPort: 9090
    nodePort: 30900
    name: prometheus
  selector:
    app.kubernetes.io/name: prometheus
```

## LoadBalancer Configuration

For cloud environments or with MetalLB:

```yaml
# loadbalancer-services.yaml
apiVersion: v1
kind: Service
metadata:
  name: monitoring-lb
  namespace: monitoring
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 3000
    name: grafana
  - port: 9090
    targetPort: 9090
    name: prometheus
  selector:
    app.kubernetes.io/name: grafana
```
