# Specification: Backup Level Options and Automated Restore Setup

## Overview
This specification details the additions and modifications to `docker-backup.sh` to support flexible backup locations, automated restore folder setup, and backup cleanup after restore.

## Functional Requirements
1. **Option `-l` during backup**:
   - Usage: `./docker-backup.sh -backup -l <docker_app_directory>`
   - When `-l` is specified, the script shall create the final backup `.tar.gz` archive in the parent directory of `<docker_app_directory>` (i.e. one level up).
   - If multiple directories are passed, each backup is saved in its respective parent directory.
2. **Automated Subfolder Creation during restore**:
   - When restoring directly inside a parent directory (e.g. running `./docker-backup.sh -restore /mnt/docker` where backup archives like `app1_backup_*.tar.gz` reside):
     - The script must parse the filename to determine the app name (matching pattern `<app_name>_backup_<timestamp>.tar.gz`).
     - It must automatically create the folder `/mnt/docker/<app_name>/` if it does not exist.
     - It must extract and build the restore inside this new directory, including recreating docker-compose files and starting the containers inside that directory.
3. **Option `-d` during restore**:
   - Usage: `./docker-backup.sh -restore -d <docker_app_directory>`
   - When `-d` is specified, the exact `.tar.gz` archive that was successfully restored must be deleted automatically.
   - Deletion must only occur *after* a fully successful restore.

## Non-Functional Requirements
- Backward compatibility: Command syntax without `-l` and `-d` must remain unchanged and work as before.
- Portability: Rely strictly on core Bash features, standard GNU/POSIX utilities (sed, grep, tar, etc.), and Docker/Docker Compose.

## Acceptance Criteria
- Running `./docker-backup.sh -backup -l /mnt/docker/my-app` places the backup `.tar.gz` in `/mnt/docker/`.
- Running `./docker-backup.sh -restore /mnt/docker` with `app1_backup_*.tar.gz` in `/mnt/docker/` automatically creates `/mnt/docker/app1/` and restores the application there.
- Running `./docker-backup.sh -restore -d /mnt/docker/my-app` (or on a parent directory) restores the application and then deletes the restored `.tar.gz` archive file.
