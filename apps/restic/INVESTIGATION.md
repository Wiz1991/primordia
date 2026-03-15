# Restic Backup Integration - Investigation

## Overview

This document captures the investigation into integrating [restic](https://restic.net/) for automated backups of the primordia media server stack.

## Current State

- **No backup solution** exists in the infrastructure
- All persistent data lives in `${APPDATA_DIR}` (default `/srv/homelab`) bind mounts and Docker named volumes
- The `.env` file and `apps/decypharr/config/config.json` are gitignored (contain secrets)

---

## Service Volume Inventory

### Bind Mounts (`${APPDATA_DIR}/...` → `/config`)

| Service | Host Path | Container Path | What's Inside |
|---------|-----------|---------------|---------------|
| **traefik** | `${APPDATA_DIR}/traefik/acme` | `/etc/traefik/acme` | Let's Encrypt certs (`acme.json`) |
| **traefik** | `${APPDATA_DIR}/traefik/logs` | `/var/log/traefik` | Access logs (skip) |
| **plex** | `${APPDATA_DIR}/plex` | `/config` | Library metadata, DB, preferences |
| **radarr** | `${APPDATA_DIR}/radarr` | `/config` | SQLite DB, config.xml, media covers |
| **sonarr** (tv) | `${APPDATA_DIR}/sonarr` | `/config` | SQLite DB, config.xml, media covers |
| **sonarr** (anime) | `${APPDATA_DIR}/sonarr_anime` | `/config` | SQLite DB, config.xml, media covers |
| **bazarr** | `${APPDATA_DIR}/bazarr` | `/config` | SQLite DB, config.ini, subtitle mappings |
| **prowlarr** | `${APPDATA_DIR}/prowlarr` | `/config` | SQLite DB, config.xml, indexer configs |
| **seerr** | `${APPDATA_DIR}/seerr` | `/app/config` | SQLite DB, settings.json |
| **decypharr** | `${APPDATA_DIR}/decypharr` | `/app` | RealDebrid keys, rclone config |
| **profilarr** | `${APPDATA_DIR}/profilarr` | `/config` | Profile sync config |
| **profilarr_anime** | `${APPDATA_DIR}/profilarr_anime` | `/config` | Profile sync config |
| **tautulli** | `${APPDATA_DIR}/tautulli` | `/config` | SQLite DB, config.ini, watch history |
| **newtarr** | `${APPDATA_DIR}/newtarr` | `/config` | Config data |

### Docker Named Volumes

| Volume | Service | Container Path | Notes |
|--------|---------|---------------|-------|
| `loki_data` | loki | `/loki` | Log storage - **rebuildable**, skip or low priority |
| `alloy_data` | alloy | `/var/lib/alloy/data` | Collector state - **rebuildable** |
| `grafana_data` | grafana | `/var/lib/grafana` | Dashboards, alerting rules - **back up if customized** |
| `zilean_data` | zilean | `/app/data` | IMDb cache - **rebuildable** |
| `zilean_tmp` | zilean | `/tmp` | Temp data - **skip** |
| `postgres_data_zilean` | zilean_postgres | `/var/lib/postgresql/data/pgdata` | PostgreSQL DB - **rebuildable** (IMDb cache) |

### Media Volumes (NOT backed up by restic)

| Host Path | Services | Notes |
|-----------|----------|-------|
| `/mnt/media` | plex, radarr, sonarr_*, bazarr, decypharr | Main media library (too large for restic) |
| `/mnt` | prowlarr | Full mount access |

### No Persistent Data

| Service | Notes |
|---------|-------|
| **byparr** | Stateless Cloudflare bypass container |

---

## Per-Service Exclude Patterns

### *arr Apps (radarr, sonarr, sonarr_anime, prowlarr)

```
logs/              # Text log files - regenerated
UpdateLogs/        # Update history logs
MediaCover/        # Cached poster/banner images (can be GBs) - re-downloaded on demand
asp/               # ASP.NET runtime cache
Backups/           # Internal app backups (we have restic now)
```

**Essential files:** `config.xml`, `*.db` (radarr.db, sonarr.db, prowlarr.db), `*.db-shm`, `*.db-wal`

### Plex

```
Cache/             # Regenerated automatically
Logs/              # Not needed for restore
Crash Reports/     # Not needed
Diagnostics/       # Not needed
Updates/           # Not needed
*.bif              # Video preview thumbnails - regenerated on demand
```

**Essential:** `Plug-in Support/Databases/`, `Preferences.xml`, metadata (optional but slow to rebuild)

### Bazarr

```
cache/             # Regenerated
log/               # Not needed for restore
backup/            # Internal backups (redundant with restic)
restore/           # Temp restore dir
```

**Essential:** `config/config.ini` (or `config.yaml`), `config/db/bazarr.db`

### Seerr

```
cache/             # Regenerated
logs/              # Not needed for restore
```

**Essential:** `db/db.sqlite3`, `settings.json`

### Tautulli

```
cache/             # Regenerated
logs/              # Not needed for restore
backups/           # Internal backups (redundant with restic)
```

**Essential:** `config.ini`, `tautulli.db`

### Traefik

```
logs/              # Access logs - skip entirely (${APPDATA_DIR}/traefik/logs)
```

**Essential:** `acme/acme.json` (Let's Encrypt certificates)

### Grafana (named volume)

```
png/               # Rendered panel images cache
```

**Essential:** `grafana.db` (dashboards, users, alerting)

---

## Recommended Restic Integration Approach

### Architecture: Sidecar Container

Use a dedicated restic container in the compose stack that:
1. Mounts `${APPDATA_DIR}` as read-only
2. Mounts named volumes that need backup (grafana_data)
3. Runs on a cron schedule (daily at 2 AM)
4. Supports pre-backup hooks (e.g., `pg_dump` for zilean if needed)

### Docker Image Options

| Image | Pros | Cons |
|-------|------|------|
| **[resticker](https://github.com/djmaze/resticker)** (`mazzolino/restic`) | Mature, supports pre/post commands, separate prune schedule | Less active maintenance |
| **[restic-compose-backup](https://github.com/ZettaIO/restic-compose-backup)** | Label-based config, DB dump support | Heavier, label coupling |
| **[lobaro/restic-backup-docker](https://github.com/lobaro/restic-backup-docker)** | Simple, lightweight | Fewer features |
| **[backrest](https://github.com/garethgeorge/backrest)** | Web UI, incremental, built on restic | Heavier, newer |
| **Plain `restic/restic` + cron script** | Full control, minimal deps | More manual setup |

**Recommendation:** Use `mazzolino/restic` (resticker) for its balance of simplicity and features, or a plain restic image with a custom backup script for full control over exclude patterns.

### Storage Backends

Restic supports: local disk, SFTP, S3 (AWS/Minio), Backblaze B2, Azure Blob, Google Cloud Storage, rclone-compatible backends.

### Suggested Retention Policy

```
RESTIC_FORGET_ARGS: >-
  --keep-daily 7
  --keep-weekly 4
  --keep-monthly 6
  --keep-yearly 2
```

### Exclude File (`restic-excludes.txt`)

```
# *arr apps (radarr, sonarr, sonarr_anime, prowlarr)
**/logs/
**/UpdateLogs/
**/MediaCover/
**/asp/
**/Backups/

# Plex
**/Cache/
**/Crash Reports/
**/Diagnostics/
**/Updates/
**/*.bif

# Bazarr
**/cache/
**/log/
**/backup/
**/restore/

# Seerr
**/cache/
**/logs/

# Tautulli
**/cache/
**/backups/

# Traefik
**/traefik/logs/

# General
**/*.log
**/*.log.*
**/logs.db
**/logs.db-shm
**/logs.db-wal
```

### Environment Variables Needed

```env
# Restic backup configuration
RESTIC_REPOSITORY=s3:https://s3.amazonaws.com/bucket-name
RESTIC_PASSWORD=your-restic-repo-password

# For S3 backends
AWS_ACCESS_KEY_ID=your-access-key
AWS_SECRET_ACCESS_KEY=your-secret-key

# For B2 backends (alternative)
# RESTIC_REPOSITORY=b2:bucket-name:path
# B2_ACCOUNT_ID=your-account-id
# B2_ACCOUNT_KEY=your-account-key

# Schedule
BACKUP_CRON=0 2 * * *
PRUNE_CRON=0 4 * * 0
```

### Database Considerations

- **SQLite databases** (*arr apps, seerr, tautulli, grafana): Safe to back up with restic if you include the `-shm` and `-wal` files. For maximum consistency, the apps ideally should be briefly paused, but in practice SQLite WAL mode handles concurrent reads well.
- **PostgreSQL** (zilean): Should use `pg_dump` pre-backup hook. However, since zilean's data is a rebuildable IMDb cache, it can be skipped entirely.

### Compose Integration

The restic service should be added as a new include file (`apps/restic/docker-compose.yml`) in the root `docker-compose.yml`. It needs:
- Read-only access to `${APPDATA_DIR}`
- Access to the exclude file
- Network access for remote storage backends
- No dependency on other services (runs independently)

---

## Sources

- [Servarr Wiki - Radarr Appdata](https://wiki.servarr.com/radarr/appdata-directory)
- [Servarr Wiki - Sonarr Appdata](https://wiki.servarr.com/sonarr/appdata-directory)
- [Servarr Wiki - Prowlarr Appdata](https://wiki.servarr.com/prowlarr/appdata-directory)
- [Plex - Data Directory Location](https://support.plex.tv/articles/202915258-where-is-the-plex-media-server-data-directory-located/)
- [Plex - Why is my data directory so large?](https://support.plex.tv/articles/202529153-why-is-my-plex-media-server-directory-so-large/)
- [Seerr - Backups Documentation](https://docs.seerr.dev/using-seerr/backups)
- [Tautulli FAQ](https://docs.tautulli.com/support/frequently-asked-questions)
- [Resticker (djmaze/resticker)](https://github.com/djmaze/resticker)
- [restic-compose-backup](https://github.com/ZettaIO/restic-compose-backup)
- [Backrest](https://github.com/garethgeorge/backrest)
