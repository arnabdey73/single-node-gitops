# Zero-Downtime Upgrade Best Practices

The AppDeploy Platform is designed to perform upgrades with minimal impact on running applications. Follow these best practices to ensure smooth upgrades:

## Before Upgrading

1. **Create Application Labels**:

   ```bash
   kubectl label application -n argocd my-critical-app criticality=high app-type=user
   ```

2. **Set Resource Requests/Limits**:
   Ensure your applications have appropriate resource requests and limits defined to prevent resource contention during upgrades.

3. **Create PodDisruptionBudgets**:
   For critical applications, define PDBs to prevent eviction during platform upgrades.

4. **Schedule During Low-Traffic Periods**:
   When possible, schedule upgrades during periods of low application traffic.

## During the Upgrade Process

1. **Monitor Application Health**:

   ```bash
   # Create a second terminal to monitor applications
   kubectl get pods -A -w
   ```

2. **Watch for Error Logs**:

   ```bash
   # Monitor for application errors during upgrade
   kubectl logs -n <namespace> <pod-name> --follow
   ```

3. **Be Ready to Roll Back**:
   If application issues are detected, use the backup created at the beginning of the upgrade:

   ```bash
   ./scripts/restore.sh <backup-name>
   ```

## After Upgrading

1. **Verify Application Functionality**:
   Perform tests on critical applications to verify they're working correctly.

2. **Check for Performance Changes**:
   Monitor application performance metrics in Grafana to ensure no degradation.

3. **Review Logs**:
   Look for any unusual errors or warnings in application logs.

## Emergency Procedures

If applications are affected during an upgrade:

1. **Pause the Upgrade**:
   Press Ctrl+C to interrupt the upgrade script.

2. **Roll Back if Necessary**:

   ```bash
   ./scripts/restore.sh <backup-name>
   ```

3. **Re-enable Application Auto-Sync**:

   ```bash
   kubectl -n argocd patch application <app-name> --type merge \
     -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
   ```

> **Note**: Always run the upgrade script from the scripts directory: `./scripts/upgrade-platform.sh`

## How AppDeploy Platform Protects Applications During Upgrades

The `upgrade-platform.sh` script implements several safeguards to protect running applications:

1. **Application Freeze**:  
   Before upgrading critical components, user applications are temporarily "frozen" by disabling their auto-sync mechanisms.

2. **Eviction Control**:
   Pod eviction is disabled during the upgrade to prevent disruptions.

3. **Resource Protection**:
   Special annotations are applied to application namespaces to prevent accidental pruning.

4. **PodDisruptionBudgets**:
   Critical deployments are protected with PDBs to ensure availability.

5. **Sequenced Updates**:
   The upgrade follows a careful sequence:
   - Infrastructure components first (ArgoCD)
   - Platform applications second
   - Security components last

6. **Health Verification**:
   At key points during the upgrade, health checks verify that components are functioning properly.

7. **Progressive Updates**:
   Updates are applied progressively with verification at each step.

8. **Maintenance Mode Option**:
   For potentially disruptive upgrades, a maintenance mode can be enabled.

By following these practices, your platform upgrades should not affect running applications.
