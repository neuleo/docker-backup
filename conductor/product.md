# Initial Concept

A simple yet powerful Bash script for backing up and restoring Docker applications with their volumes, bind mounts, and configuration files.

# Product Vision

This utility aims to provide self-hosters with a reliable, zero-dependency, single-file Bash script to easily back up and restore Docker-compose based applications. It targets home servers and VPS environments where simplicity, reliability, and ease of restoration are critical.

# Target Audience
- **Self-hosters**: Individuals hosting services on home servers / VPS who need a simple, self-contained backup mechanism.

# Core Features & Scope
1. **Container Life-cycle Management**: Stop containers during backup to ensure data consistency, and restart them after.
2. **Volume & Bind Mount Backup**: Automatically detect and archive both named Docker volumes and local directory bind mounts relative to the compose file.
3. **Backup Retention Rules**: Implement rules to automatically prune older backups, preventing disk exhaustion on host machines.
4. **Command Line Interface**: Maintain a simple, dependency-free CLI interface using flag-based arguments (e.g., `-backup`, `-restore`).
