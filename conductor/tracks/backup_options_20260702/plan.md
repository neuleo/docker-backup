# Plan: Backup Level Options and Automated Restore Setup

## Phase 1: Preparation & Argument Parsing
- [x] Task: Update help display to document the new `-l` option for backup and `-d` option for restore. (3699b00)
- [ ] Task: Refactor argument parsing in `docker-backup.sh` to extract `-l` (for backup) and `-d` (for restore) flags, supporting them in any argument order before directory paths.

## Phase 2: Implementation of `-l` Backup Flag
- [ ] Task: Modify `create_backup` function to accept an optional flag or destination path parameter indicating whether the target output folder is the parent directory.
- [ ] Task: Verify that when `-l` is provided, the backup archive is written to the parent folder of the specified application directory.

## Phase 3: Implementation of Automatic Subfolder Restore and `-d` Restore Flag
- [ ] Task: Modify restore logic to recognize if it is being run on a backup file directly or scanning a directory. If backups are found directly in the target directory (e.g. `/mnt/docker`), determine target app names from file prefixes (e.g. `<app_name>_backup_<timestamp>.tar.gz`).
- [ ] Task: For each backup file, create the corresponding subfolder (e.g., `/mnt/docker/<app_name>/`), move/reference the backup file, and run the restore process inside that subfolder.
- [ ] Task: Implement `-d` option to delete the successfully restored `.tar.gz` file at the end of `restore_backup`.

## Phase 4: Verification and Testing
- [ ] Task: Write automated test cases checking backup with `-l`, restore with automatic directory creation, and restore with `-d`.
- [ ] Task: Conductor - User Manual Verification 'Backup Level & Restore Improvements' (Protocol in workflow.md)
