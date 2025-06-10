# Hardware Monitoring Configuration for Dell PowerEdge R540

This directory contains hardware-specific monitoring configurations optimized for Dell PowerEdge R540 servers.

## Components

### Node Exporter Configuration
- **File**: `node-exporter-config.yaml`
- **Purpose**: Enables Dell-specific hardware monitoring including IPMI and thermal sensors
- **Features**: 
  - IPMI sensor monitoring
  - Hardware temperature monitoring
  - Dell-specific metrics collection

### Dell OpenManage Integration
- **Service**: Dell OpenManage Server Administrator (OMSA)
- **Web Interface**: https://your-server-ip:1311
- **Monitoring**: Hardware health, storage controller status, system events

### IPMI Monitoring
- **Tools**: ipmitool, ipmi_exporter
- **Sensors**: Temperature, voltage, fan speed, power consumption
- **Alerts**: Hardware threshold violations

## Deployment

1. **Apply Node Exporter Configuration**:
   ```bash
   kubectl apply -f node-exporter-config.yaml
   ```

2. **Install Dell OpenManage** (run dell-optimizations.sh):
   ```bash
   ./bootstrap/dell-optimizations.sh
   ```

3. **Verify Hardware Monitoring**:
   ```bash
   # Check IPMI sensors
   sudo ipmitool sensor list
   
   # Check Dell hardware status
   sudo omreport system summary
   ```

## Grafana Dashboards

Recommended dashboards for Dell hardware monitoring:
- **Node Exporter Full**: Dashboard ID 1860
- **IPMI for Prometheus**: Dashboard ID 15353
- **Dell Hardware Overview**: Custom dashboard (see templates/)

## Alerts

Hardware-specific alerts are configured for:
- CPU temperature thresholds
- Memory errors
- Storage controller issues
- Power supply status
- Fan failures

## Troubleshooting

### Common Issues

1. **IPMI Access Denied**:
   ```bash
   sudo modprobe ipmi_devintf ipmi_si
   sudo systemctl restart ipmievd
   ```

2. **Dell OpenManage Not Starting**:
   ```bash
   sudo systemctl enable --now dsm_om_connsvc
   sudo systemctl status srvadmin-services
   ```

3. **Missing Hardware Sensors**:
   ```bash
   # Check loaded modules
   lsmod | grep ipmi
   
   # Reload hardware monitoring
   sudo sensors-detect --auto
   ```
