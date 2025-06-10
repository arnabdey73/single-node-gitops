#!/bin/bash
# Dell PowerEdge R540 Hardware Optimizations
# This script applies Dell-specific optimizations for the GitOps platform

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✓ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠ $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ✗ $1${NC}"
}

error() {
    log_error "$1"
    exit 1
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if running on Dell hardware
check_dell_hardware() {
    if ! dmidecode -s system-manufacturer 2>/dev/null | grep -qi "dell"; then
        log_warning "This script is optimized for Dell hardware but doesn't detect Dell system"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    else
        log_success "Dell hardware detected"
    fi
}

# Install Dell OpenManage tools
install_dell_openmanage() {
    log "Installing Dell OpenManage tools..."
    
    # Add Dell repository
    if [ ! -f /etc/apt/sources.list.d/linux.dell.com.sources.list ]; then
        wget -q -O - https://linux.dell.com/repo/hardware/dsu/public.key | sudo apt-key add -
        echo 'deb http://linux.dell.com/repo/hardware/dsu/os_independent/ /' | sudo tee -a /etc/apt/sources.list.d/linux.dell.com.sources.list
        sudo apt-get update
    fi
    
    # Install OpenManage components
    sudo apt-get install -y srvadmin-base srvadmin-storageservices srvadmin-webserver
    
    # Enable and start services
    sudo systemctl enable dsm_om_connsvc
    sudo systemctl start dsm_om_connsvc
    
    log_success "Dell OpenManage tools installed"
}

# Optimize disk scheduler for enterprise storage
optimize_disk_scheduler() {
    log "Optimizing disk scheduler for enterprise storage..."
    
    # Create udev rule for disk scheduler
    cat << 'EOF' | sudo tee /etc/udev/rules.d/60-scheduler.rules
# Set I/O scheduler for SSDs and enterprise drives
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="mq-deadline"
ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/scheduler}="mq-deadline"
EOF
    
    # Apply immediately to existing devices
    for disk in /sys/block/sd*; do
        if [ -f "$disk/queue/scheduler" ]; then
            echo mq-deadline | sudo tee "$disk/queue/scheduler" >/dev/null 2>&1 || true
        fi
    done
    
    log_success "Disk scheduler optimized"
}

# Set CPU governor to performance
optimize_cpu_performance() {
    log "Setting CPU governor to performance..."
    
    # Install cpufrequtils
    sudo apt-get install -y cpufrequtils
    
    # Set governor to performance
    echo 'GOVERNOR="performance"' | sudo tee /etc/default/cpufrequtils
    
    # Apply immediately
    if command_exists cpufreq-set; then
        for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            if [ -f "$cpu" ]; then
                echo performance | sudo tee "$cpu" >/dev/null 2>&1 || true
            fi
        done
    fi
    
    log_success "CPU governor set to performance"
}

# Increase system limits for high-performance workloads
optimize_system_limits() {
    log "Optimizing system limits..."
    
    # Set open file limits
    cat << 'EOF' | sudo tee -a /etc/security/limits.conf
# Kubernetes/Container optimizations
* soft nofile 65536
* hard nofile 65536
* soft nproc 32768
* hard nproc 32768
root soft nofile 65536
root hard nofile 65536
EOF
    
    # Set system-wide limits
    cat << 'EOF' | sudo tee /etc/sysctl.d/99-k8s-dell-optimization.conf
# Network optimizations for Dell PowerEdge R540
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 65536 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_window_scaling = 1
net.core.netdev_budget = 600

# Memory management
vm.swappiness = 1
vm.dirty_ratio = 80
vm.dirty_background_ratio = 5
vm.dirty_expire_centisecs = 12000

# File system optimizations
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512

# Kernel optimizations
kernel.pid_max = 4194304
kernel.threads-max = 1048576
EOF
    
    # Apply sysctl settings
    sudo sysctl --system
    
    log_success "System limits optimized"
}

# Configure IPMI monitoring
setup_ipmi_monitoring() {
    log "Setting up IPMI monitoring..."
    
    # Install IPMI tools
    sudo apt-get install -y ipmitool
    
    # Load IPMI modules
    sudo modprobe ipmi_devintf
    sudo modprobe ipmi_si
    
    # Add to modules to load at boot
    echo 'ipmi_devintf' | sudo tee -a /etc/modules
    echo 'ipmi_si' | sudo tee -a /etc/modules
    
    # Test IPMI connectivity
    if sudo ipmitool sensor list >/dev/null 2>&1; then
        log_success "IPMI monitoring configured successfully"
    else
        log_warning "IPMI setup completed but sensor access may require additional configuration"
    fi
}

# Create hardware monitoring configuration
create_hardware_monitoring_config() {
    log "Creating hardware monitoring configuration..."
    
    # Create monitoring config directory
    mkdir -p /tmp/hardware-monitoring
    
    # Node exporter configuration for Dell hardware
    cat << 'EOF' > /tmp/hardware-monitoring/node-exporter-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: node-exporter-config
  namespace: monitoring
data:
  node-exporter.yaml: |
    collectors:
      enabled:
        - cpu
        - diskstats
        - filesystem
        - loadavg
        - meminfo
        - netdev
        - stat
        - time
        - hwmon  # Enable hardware monitoring for Dell servers
        - ipmi   # Enable IPMI monitoring
        - thermal_zone
      disabled:
        - arp
        - bcache
        - bonding
        - conntrack
        - edac
        - entropy
        - fibrechannel
        - infiniband
        - nfs
        - nfsd
        - pressure
        - rapl
        - schedstat
        - sockstat
        - textfile
        - timex
        - udp_queues
        - uname
        - vmstat
        - xfs
        - zfs
EOF
    
    log_success "Hardware monitoring configuration created at /tmp/hardware-monitoring/"
}

# Optimize for containerized workloads
optimize_for_containers() {
    log "Applying container-specific optimizations..."
    
    # Docker/containerd optimizations
    mkdir -p /etc/systemd/system/containerd.service.d
    cat << 'EOF' | sudo tee /etc/systemd/system/containerd.service.d/override.conf
[Service]
LimitNOFILE=1048576
LimitNPROC=1048576
LimitCORE=infinity
TasksMax=infinity
EOF
    
    # Create container storage optimization
    cat << 'EOF' | sudo tee /etc/sysctl.d/98-container-optimization.conf
# Container storage optimizations
vm.max_map_count = 262144
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
    
    sudo sysctl --system
    
    log_success "Container optimizations applied"
}

# Main function
main() {
    echo "========================================="
    echo "Dell PowerEdge R540 Optimization Script"
    echo "========================================="
    
    if [ "$EUID" -eq 0 ]; then
        error "This script should not be run as root. Use sudo when needed."
    fi
    
    check_dell_hardware
    
    log "Starting Dell PowerEdge R540 optimizations..."
    
    # Update package list
    sudo apt-get update
    
    # Apply optimizations
    install_dell_openmanage
    optimize_disk_scheduler
    optimize_cpu_performance
    optimize_system_limits
    setup_ipmi_monitoring
    create_hardware_monitoring_config
    optimize_for_containers
    
    log_success "All optimizations completed successfully!"
    echo ""
    echo "========================================="
    echo "Next Steps:"
    echo "1. Reboot the system to apply all changes"
    echo "2. Apply hardware monitoring config: kubectl apply -f /tmp/hardware-monitoring/"
    echo "3. Access Dell OpenManage at: https://$(hostname -I | awk '{print $1}'):1311"
    echo "4. Default login: root / (your system root password)"
    echo "========================================="
}

# Run main function
main "$@"
