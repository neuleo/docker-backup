# Product Guidelines

These guidelines define the user experience, coding standards, and operational principles for the Docker Backup utility.

## 1. CLI Design Principles
- **Predictability & POSIX Standards**: Use clear, standard command-line flags. Long flags (e.g., `--backup`, `--restore`) should be supported alongside or instead of non-standard single dash flags.
- **Safety First**: Prioritize data safety. Before stopping any containers or starting a backup, perform basic pre-flight checks (disk space check, permissions verify).
- **Idempotency**: Retrying a failed backup or restore operation should not corrupt existing states or duplicate archives.

## 2. User Experience & Logging
- **Visual Clarity**: Use consistent log levels (INFO, WARNING, ERROR). Timestamps should be clear, and stderr should be used for actual errors.
- **Interactivity**: The tool should be non-interactive by default (suitable for cron jobs) but support interactive selection (like choosing a backup file to restore) when run in a TUI/interactive terminal.
- **No Dependencies**: Do not introduce third-party binaries or libraries. Stick to standard POSIX utilities (`tar`, `gzip`, `find`, `grep`, `docker`, `docker-compose`).

## 3. Shell Scripting Standards
- **Strict Error Handling**: Use `set -euo pipefail` where applicable to catch failures early.
- **Portability**: Ensure the script is compatible with standard Bash 4.x+ environments without requiring rare bash extensions.
- **Cleanup**: Ensure temporary files (like `.backup_temp` or `.restore_temp`) are cleaned up under all exit conditions, including interrupts (`SIGINT`, `SIGTERM`).
