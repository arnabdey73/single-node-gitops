# Backup Configuration Examples

This directory contains backup policies and scheduling examples.

## Backup Policies

### Volume Snapshot Class

```yaml
# volume-snapshot-class.yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: longhorn-snapshot-class
  annotations:
    snapshot.storage.kubernetes.io/is-default-class: "true"
driver: driver.longhorn.io
deletionPolicy: Delete
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
            - |
              kubectl create volumesnapshot prometheus-snapshot-$(date +%Y%m%d) \
                --from-pvc=prometheus-storage \
                --volume-snapshot-class=longhorn-snapshot-class
              kubectl create volumesnapshot grafana-snapshot-$(date +%Y%m%d) \
                --from-pvc=grafana-pv-claim \
                --volume-snapshot-class=longhorn-snapshot-class
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

### S3 Backup for Longhorn

```yaml
# longhorn-s3-backup.yaml
apiVersion: v1
kind: Secret
metadata:
  name: s3-backup-secret
  namespace: longhorn-system
type: Opaque
stringData:
  AWS_ACCESS_KEY_ID: "your-access-key"
  AWS_SECRET_ACCESS_KEY: "your-secret-key"
  AWS_ENDPOINTS: "https://s3.amazonaws.com"
---
apiVersion: longhorn.io/v1beta1
kind: BackupTarget
metadata:
  name: s3-backup-target
  namespace: longhorn-system
spec:
  backupTargetURL: "s3://your-bucket@region/backups"
  credentialSecret: "s3-backup-secret"
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
