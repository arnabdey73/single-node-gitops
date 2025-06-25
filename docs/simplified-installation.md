# Simplified Installation Guide

This guide explains how to install the AppDeploy platform using the simplified installation process.

## System Requirements

### Hardware

- **CPU**: 2+ cores (4+ recommended)
- **RAM**: 4GB minimum (8GB+ recommended)
- **Storage**: 50GB+ available space
- **Network**: Internet connectivity required

### Software

- Ubuntu 20.04+ (or compatible Linux distribution)
- sudo privileges

## One-Command Installation

The entire installation process has been streamlined into a single script that handles all steps automatically:

```bash
# Make the script executable
chmod +x install.sh

# Run the installation script
./install.sh
```

## What the Installation Script Does

The `install.sh` script automates all of these steps:

1. **System Requirements Check**
   - Verifies CPU, RAM, disk space
   - Installs required dependencies

2. **System Optimizations**
   - Dell hardware optimizations (if on Dell PowerEdge)
   - CPU governor optimization
   - Disk I/O scheduler tuning
   - Network settings optimization

3. **K3s Installation**
   - Installs K3s with optimized settings
   - Sets up kubeconfig

4. **Base Infrastructure Deployment**
   - Deploys storage classes and other infrastructure

5. **ArgoCD Deployment**
   - Deploys ArgoCD
   - Retrieves admin credentials

6. **Application Deployment**
   - Triggers ArgoCD to deploy all applications

7. **Access Setup**
   - Sets up convenient aliases and shortcuts

## After Installation

After installation completes, you can:

1. Access the AppDeploy dashboard:

   ```bash
   ./scripts/dashboard-access.sh open
   ```

2. Access ArgoCD:

   ```bash
   kubectl port-forward svc/argocd-server -n argocd 8080:443
   ```

   Then open: `https://localhost:8080`

3. Monitor application status:

   ```bash
   kubectl get applications -n argocd
   ```

4. Check system health:

   ```bash
   ./scripts/health-check.sh
   ```

## Managing Your Applications

To add or remove applications from the platform:

1. Follow the detailed instructions in the [Application Lifecycle Management](application-lifecycle.md) guide.

2. The guide covers:
   - Step-by-step application onboarding process
   - Application removal procedures
   - Best practices for application management
   - Troubleshooting common issues

## Manual Installation

If you prefer to install components step-by-step manually, refer to the detailed [installation guide](installation.md).
