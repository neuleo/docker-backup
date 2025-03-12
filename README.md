# Docker Backup Script

A simple yet powerful Bash script for backing up and restoring Docker applications with their volumes, bind mounts, and configuration files.

## Features

- Backs up Docker volumes with consistent data (stops containers temporarily)
- Captures bind mounts inside or outside the application directory
- Preserves the docker-compose.yml file
- Automatically handles volume and bind mount restoration
- Detailed logging of operations
- Easy to use with simple commands

## Requirements

- Docker
- Docker Compose (v1 or v2)
- Bash shell
- Root/sudo access (for accessing Docker volume data)

## Usage

### Installation

```bash
git clone https://github.com/username/docker-backup-script.git
cd docker-backup-script
chmod +x docker-backup.sh
```

### Backup a Docker application

```bash
./docker-backup.sh -backup /path/to/docker/app
```

This will:
1. Find the docker-compose.yml file in the specified directory
2. Extract volume and bind mount information
3. Create a backup archive containing all data and configuration
4. Save the archive in the application directory

### Restore a Docker application

```bash
./docker-backup.sh -restore /path/to/docker/app
```

This will:
1. Find the most recent backup archive in the directory (or let you select one)
2. Extract the archive to a temporary location
3. Restore the docker-compose.yml file
4. Restore all volumes and bind mounts
5. Start the containers

## Directory Structure

The script works best with Docker applications organized as follows:
```
/path/to/docker/app/
├── docker-compose.yml
├── data/  # (bind mounts in subdirectories)
└── config/
```

## Notes

- For backing up volumes, the script requires sudo access
- External bind mounts are preserved with their original paths
- The script will automatically stop and restart containers during backup
- Backups are named with timestamps for easy identification
