# Monitoring Configuration Examples

This directory contains configuration examples for the monitoring stack.

## Prometheus Configuration

### Custom Recording Rules

```yaml
# prometheus-rules.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-custom-rules
  namespace: monitoring
data:
  custom-rules.yml: |
    groups:
      - name: single-node-specific
        rules:
          - record: node:memory_utilization:ratio
            expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes
          - record: node:cpu_utilization:rate5m
            expr: 1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m]))
          - record: node:disk_utilization:ratio
            expr: (node_filesystem_size_bytes{mountpoint="/"} - node_filesystem_free_bytes{mountpoint="/"}) / node_filesystem_size_bytes{mountpoint="/"}
```

### Service Monitor Examples

```yaml
# Example ServiceMonitor for custom applications
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app-metrics
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: my-app
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
```

## Grafana Configuration

### Dashboard Provisioning

Create custom dashboards by placing JSON files in the grafana-dashboards ConfigMap.

### Data Source Configuration

```yaml
# Additional data sources can be configured via ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-additional-datasources
  namespace: monitoring
data:
  datasources.yaml: |
    apiVersion: 1
    datasources:
      - name: External-Prometheus
        type: prometheus
        access: proxy
        url: http://external-prometheus:9090
        isDefault: false
```

## Loki Configuration

### Log Parsing Rules

```yaml
# Custom log parsing for application logs
apiVersion: v1
kind: ConfigMap
metadata:
  name: loki-custom-config
  namespace: monitoring
data:
  config.yml: |
    # Add custom parsing rules here
    pipeline_stages:
      - json:
          expressions:
            level: level
            message: message
      - labels:
          level:
```

## Alert Rules

### Critical Alerts for Single Node

```yaml
# critical-alerts.yml
groups:
  - name: single-node-critical
    rules:
      - alert: NodeDown
        expr: up{job="node-exporter"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Node is down"
          description: "Single node {{ $labels.instance }} is down"

      - alert: HighMemoryUsage
        expr: node:memory_utilization:ratio > 0.9
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High memory usage"
          description: "Memory usage is {{ $value | humanizePercentage }}"

      - alert: HighDiskUsage
        expr: node:disk_utilization:ratio > 0.85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High disk usage"
          description: "Disk usage is {{ $value | humanizePercentage }}"
```
