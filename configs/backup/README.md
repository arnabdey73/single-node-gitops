# Backup Configuration Examples

This directory contains backup policies and scheduling examples.

## Backup Policies

### Volume Snapshot Class

```yaml
# Note: local-path provisioner doesn't support VolumeSnapshots
# For reliable backups with local-path, you should use file-based backups
# Example using rsync to backup the local storage directory:
# sudo rsync -av /var/lib/rancher/k3s/storage/ /path/to/backup/
```

### Scheduled Volume Snapshots

```yaml
# scheduled-snapshots.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: daily-snapshots
  namespace: monitoring
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: snapshot-creator
            image: bitnami/kubectl:latest
            command:
            - /bin/sh
            - -c
            - |              # Back up volumes by copying data from persistent volumes
              # Note: This approach requires root access to the node
              # For a POC environment, consider using the backup.sh script instead
              echo "Running file-based backup of persistent volumes"
              date > /tmp/last-backup-date
          restartPolicy: OnFailure
          serviceAccountName: snapshot-creator
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: snapshot-creator
  namespace: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: snapshot-creator
rules:
- apiGroups: ["snapshot.storage.k8s.io"]
  resources: ["volumesnapshots"]
  verbs: ["create", "get", "list"]
- apiGroups: [""]
  resources: ["persistentvolumeclaims"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: snapshot-creator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: snapshot-creator
subjects:
- kind: ServiceAccount
  name: snapshot-creator
  namespace: monitoring
```

## Backup Retention Policies

### Automated Cleanup

```yaml
# backup-cleanup.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: backup-cleanup
  namespace: monitoring
spec:
  schedule: "0 3 * * 0"  # Weekly on Sunday at 3 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: cleanup
            image: bitnami/kubectl:latest
            command:
            - /bin/sh
            - -c
            - |
              # Delete snapshots older than 7 days
              kubectl get volumesnapshots -o json | \
              jq -r '.items[] | select(.metadata.creationTimestamp | fromdateiso8601 < (now - 604800)) | .metadata.name' | \
              xargs -r kubectl delete volumesnapshot
          restartPolicy: OnFailure
          serviceAccountName: snapshot-creator
```

## External Backup Configuration

### Rsync for Local Storage Backup

```bash
# Example rsync command for backing up local-path storage
# Add to crontab or systemd timer

# Daily backup
rsync -avz --delete /var/lib/rancher/k3s/storage/ /mnt/backup/k3s-storage-backup/

# Using the provided backup.sh script is recommended for comprehensive backups
/path/to/scripts/backup.sh
```

### NFS Backup Configuration

```yaml
# nfs-backup.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-backup-storage
spec:
  capacity:
    storage: 100Gi
  accessModes:
    - ReadWriteMany
  nfs:
    server: nfs-server.example.com
    path: /backups/kubernetes
  persistentVolumeReclaimPolicy: Retain
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-backup-storage
  namespace: monitoring
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 100Gi
  volumeName: nfs-backup-storage
```

## Backup Verification

### Backup Test Job

```yaml
# backup-verification.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: backup-verification
  namespace: monitoring
spec:
  schedule: "0 6 * * 1"  # Weekly on Monday at 6 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: verify-backups
            image: bitnami/kubectl:latest
            command:
            - /bin/sh
            - -c
            - |
              # Verify that recent snapshots exist
              RECENT_SNAPSHOTS=$(kubectl get volumesnapshots -o json | \
                jq '.items[] | select(.metadata.creationTimestamp | fromdateiso8601 > (now - 86400)) | .metadata.name' | wc -l)
              
              if [ "$RECENT_SNAPSHOTS" -lt 2 ]; then
                echo "ERROR: Less than 2 recent snapshots found"
                exit 1
              fi
              
              echo "SUCCESS: Found $RECENT_SNAPSHOTS recent snapshots"
          restartPolicy: OnFailure
          serviceAccountName: snapshot-creator
```
