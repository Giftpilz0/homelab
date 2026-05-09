# Restore Guide

This guide covers restoring data from restic backups.
All commands are run **on the affected client host** as `root` (or via `sudo`).

---

## Architecture Overview

| Component | Detail                                            |
| --------- | ------------------------------------------------- |
| Tool      | `resticprofile` (wrapper around `restic`)         |
| Config    | `/etc/resticprofile/profiles.yaml`                |
| Passwords | `/etc/resticprofile/passwords/<repo>.txt`         |
| Backend   | REST server on `pve.nixpi.de:8000`                |
| Repo URL  | `rest:http://pve.nixpi.de:8000/<hostname>/<repo>` |

Each host has two profiles:

| Profile          | What it backs up                                          |
| ---------------- | --------------------------------------------------------- |
| `podman-volumes` | `/home/container/.local/share/containers/storage/volumes` |
| `podman-configs` | `/home/container/.config/containers/systemd`              |

---

## Quick Start

```bash
# 1. List snapshots (run on the affected host as root)
resticprofile --config /etc/resticprofile/profiles.yaml --name podman-volumes snapshots

# 2. Restore latest snapshot to a temporary location
resticprofile --config /etc/resticprofile/profiles.yaml --name podman-volumes \
  restore --target /tmp/restore latest

# 3. Stop affected containers, copy data back, restart
systemctl --user -M container@ stop <service>.service
cp -a /tmp/restore/home/container/.local/share/containers/storage/volumes/<volume>/ \
     /home/container/.local/share/containers/storage/volumes/<volume>/
systemctl --user -M container@ start <service>.service
```

---

## Full Reference

### List Snapshots

```bash
# All snapshots for a profile
resticprofile --config /etc/resticprofile/profiles.yaml --name podman-volumes snapshots

# Show detailed snapshot info
resticprofile --config /etc/resticprofile/profiles.yaml --name podman-volumes snapshots --verbose

# Both profiles at once
for profile in podman-volumes podman-configs; do
  echo "=== $profile ==="
  resticprofile --config /etc/resticprofile/profiles.yaml --name "$profile" snapshots
done
```

### Browse Snapshot Contents

```bash
# List files in the latest snapshot
resticprofile --config /etc/resticprofile/profiles.yaml --name podman-volumes \
  ls latest

# List files in a specific snapshot (use ID from snapshots output)
resticprofile --config /etc/resticprofile/profiles.yaml --name podman-volumes \
  ls a1b2c3d4

# List a specific path inside the snapshot
resticprofile --config /etc/resticprofile/profiles.yaml --name podman-volumes \
  ls latest /home/container/.local/share/containers/storage/volumes

# Search for a file across snapshots
resticprofile --config /etc/resticprofile/profiles.yaml --name podman-volumes \
  find "filename.conf"
```

### Restore Data

#### Restore Latest Snapshot to Temporary Location

```bash
resticprofile --config /etc/resticprofile/profiles.yaml --name podman-volumes \
  restore --target /tmp/restore latest
```

#### Restore a Specific Snapshot

```bash
# Get snapshot ID first
resticprofile --config /etc/resticprofile/profiles.yaml --name podman-volumes snapshots

# Restore by snapshot ID
resticprofile --config /etc/resticprofile/profiles.yaml --name podman-volumes \
  restore --target /tmp/restore a1b2c3d4
```

#### Restore a Specific Volume Only

```bash
resticprofile --config /etc/resticprofile/profiles.yaml --name podman-volumes \
  restore --target /tmp/restore \
  --include /home/container/.local/share/containers/storage/volumes/<volume-name> \
  latest
```

#### Restore Configs Only

```bash
resticprofile --config /etc/resticprofile/profiles.yaml --name podman-configs \
  restore --target /tmp/restore-configs latest
```

#### Preview Without Restoring (Dry Run)

```bash
resticprofile --config /etc/resticprofile/profiles.yaml --name podman-volumes \
  restore --target /tmp/restore --dry-run --verbose=2 latest
```

### Mount Repository for Manual Browsing

```bash
mkdir -p /mnt/restic-mount

# Mount (runs in foreground – Ctrl+C to unmount)
resticprofile --config /etc/resticprofile/profiles.yaml --name podman-volumes \
  mount /mnt/restic-mount

# Browse snapshots
ls /mnt/restic-mount/snapshots/
ls /mnt/restic-mount/snapshots/latest/
```

> Mounted repositories are read-only. Use `restore` for actual recovery.

---

## Common Recovery Scenarios

### Scenario 1: Restore a Single Container Volume

```bash
# 1. Identify the snapshot and volume name
resticprofile --config /etc/resticprofile/profiles.yaml --name podman-volumes snapshots
resticprofile --config /etc/resticprofile/profiles.yaml --name podman-volumes \
  ls latest /home/container/.local/share/containers/storage/volumes

# 2. Stop the container
systemctl --user -M container@ stop <service>.service

# 3. Restore the volume to a temp location
resticprofile --config /etc/resticprofile/profiles.yaml --name podman-volumes \
  restore --target /tmp/restore \
  --include /home/container/.local/share/containers/storage/volumes/<volume-name> \
  latest

# 4. Overwrite live data
rm -rf /home/container/.local/share/containers/storage/volumes/<volume-name>
cp -a /tmp/restore/home/container/.local/share/containers/storage/volumes/<volume-name> \
     /home/container/.local/share/containers/storage/volumes/

# 5. Fix ownership and restart
chown -R container:container /home/container/.local/share/containers/storage/volumes/<volume-name>
systemctl --user -M container@ start <service>.service

# 6. Clean up
rm -rf /tmp/restore
```

### Scenario 2: Full Host Recovery (All Volumes + Configs)

```bash
# 1. Restore configs
resticprofile --config /etc/resticprofile/profiles.yaml --name podman-configs \
  restore --target /tmp/restore-configs latest

# 2. Restore volumes
resticprofile --config /etc/resticprofile/profiles.yaml --name podman-volumes \
  restore --target /tmp/restore-volumes latest

# 3. Stop all containers
loginctl enable-linger container  # ensure user session is active
machinectl shell container@  # or use -M container@ on systemctl

# 4. Copy data back to original locations
cp -a /tmp/restore-configs/home/container/.config/containers/systemd/. \
     /home/container/.config/containers/systemd/
cp -a /tmp/restore-volumes/home/container/.local/share/containers/storage/volumes/. \
     /home/container/.local/share/containers/storage/volumes/

# 5. Fix ownership
chown -R container:container /home/container

# 6. Reload and start services
systemctl --user -M container@ daemon-reload
systemctl --user -M container@ start <service1>.service <service2>.service

# 7. Clean up
rm -rf /tmp/restore-configs /tmp/restore-volumes
```

### Scenario 3: Restore to a Point in Time

```bash
# List all snapshots with dates
resticprofile --config /etc/resticprofile/profiles.yaml --name podman-volumes snapshots

# Restore the snapshot from before the incident (use the snapshot ID)
resticprofile --config /etc/resticprofile/profiles.yaml --name podman-volumes \
  restore --target /tmp/restore a1b2c3d4
```

---

## Backup Schedule Reference

| Profile          | Schedule       | Retention                                   |
| ---------------- | -------------- | ------------------------------------------- |
| `podman-volumes` | Daily at 02:00 | 14 daily / 8 weekly / 12 monthly / 3 yearly |
| `podman-configs` | Daily at 01:00 | 14 daily / 8 weekly / 12 monthly / 3 yearly |

Integrity checks run every **Sunday at 03:00** (10% data subset read).

---

## Troubleshooting

### Check Backup Logs

```bash
# View recent backup log
cat /etc/resticprofile/logs/podman-volumes-backup.log

# View check log
cat /etc/resticprofile/logs/podman-volumes-check.log
```

### Verify Repository Integrity

```bash
resticprofile --config /etc/resticprofile/profiles.yaml --name podman-volumes check
```

### View Scheduled Jobs

```bash
# List systemd timers managed by resticprofile
systemctl list-timers | grep restic
```
