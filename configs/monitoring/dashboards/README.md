# Dell Hardware Monitoring Dashboard Templates

This directory contains Grafana dashboard templates optimized for Dell PowerEdge R540 hardware monitoring.

## Available Dashboards

### 1. Dell Hardware Overview
- **File**: `dell-hardware-overview.json`
- **Features**: 
  - IPMI sensor data (temperature, power, fans)
  - Dell OpenManage system health
  - Storage controller status
  - Power consumption monitoring

### 2. PowerEdge Performance
- **File**: `poweredge-performance.json`
- **Features**:
  - CPU utilization with thermal monitoring
  - Memory usage and health
  - Network throughput optimization
  - Disk I/O performance with enterprise features

### 3. Enterprise Resource Monitoring
- **File**: `enterprise-resources.json`
- **Features**:
  - Kubernetes resource utilization optimized for 32GB RAM
  - Container performance with high-density workloads
  - Storage performance metrics for Longhorn with 3 replicas
  - Network optimization monitoring

## Import Instructions

1. **Access Grafana**: <http://your-server-ip:3000>
2. **Login**: admin/admin (change on first login)
3. **Import Dashboard**:
   - Go to **+** → **Import**
   - Upload JSON file or paste content
   - Configure data source (Prometheus)

## Custom Metrics

Dell-specific metrics available:

```promql
# IPMI Temperature Sensors
ipmi_temperature_celsius{sensor=~".*CPU.*|.*Ambient.*|.*Inlet.*"}

# Power Consumption
ipmi_power_watts{sensor="Pwr Consumption"}

# Fan Speed
ipmi_fan_speed_rpm

# Dell System Health
dell_system_health_status

# Storage Controller Status
dell_storage_controller_status
```

## Alerting Rules

Recommended alerts for Dell hardware:

- **High CPU Temperature**: > 80°C
- **Critical Fan Speed**: < 1000 RPM
- **Power Supply Issues**: Status != "Ok"
- **Storage Controller Problems**: Status != "Ok"
- **Memory Errors**: ECC error rate > threshold

## Troubleshooting

### Dashboard Not Loading
1. Check Prometheus is scraping IPMI metrics
2. Verify Dell OpenManage is running
3. Ensure IPMI tools are properly configured

### Missing Metrics
```bash
# Check IPMI connectivity
sudo ipmitool sensor list

# Verify node-exporter is collecting IPMI data
curl http://node-exporter:9100/metrics | grep ipmi

# Check Dell OpenManage status
sudo systemctl status dsm_om_connsvc
```
