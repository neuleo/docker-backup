#!/bin/bash

# Docker Backup and Restore Script
# Usage: ./docker-backup.sh -backup|-restore <docker_app_directory>

set -e

# Display help function
function show_help {
    echo "Docker Backup and Restore Script"
    echo "Usage: $0 -backup|-restore <docker_app_directory>"
    echo ""
    echo "Options:"
    echo "  -backup    Create a backup of the specified Docker application directory"
    echo "  -restore   Restore a backup to the specified Docker application directory"
    echo ""
    exit 1
}

# Log function to display current actions
function log {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Check if docker and docker-compose are installed
function check_requirements {
    log "Checking requirements..."
    
    if ! command -v docker &> /dev/null; then
        log "ERROR: Docker is not installed."
        exit 1
    fi
    
    if ! { command -v docker-compose &> /dev/null || docker compose version &> /dev/null; }; then
        log "ERROR: Docker Compose is not installed."
        exit 1
    fi
    
    log "Requirements satisfied."
}

# Create backup function
function create_backup {
    local app_dir=$1
    
    # Validate app directory
    if [ ! -d "$app_dir" ]; then
        log "ERROR: Directory $app_dir does not exist."
        exit 1
    fi
    
    # Find docker-compose file
    local compose_file=""
    if [ -f "$app_dir/docker-compose.yaml" ]; then
        compose_file="$app_dir/docker-compose.yaml"
    elif [ -f "$app_dir/docker-compose.yml" ]; then
        compose_file="$app_dir/docker-compose.yml"
    else
        log "ERROR: No docker-compose.yaml or docker-compose.yml found in $app_dir."
        exit 1
    fi
    
    log "Found compose file: $compose_file"
    
    # Create backup directory
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name
    backup_name=$(basename "$app_dir")
    local backup_file="${app_dir}/${backup_name}_backup_${timestamp}.tar.gz"
    local temp_dir="${app_dir}/.backup_temp"
    
    log "Creating temporary directory: $temp_dir"
    mkdir -p "$temp_dir"
    
    # Copy docker-compose file
    log "Copying docker-compose file to temporary directory..."
    cp "$compose_file" "$temp_dir/"
    
    # Extract volume information from docker-compose file (nur benannte Volumes)
    log "Extracting volume information..."
    local volumes
    volumes=$(grep -E '^\s*-\s*[^./][^:]*:' "$compose_file" | sed -E 's/^\s*-\s*([^:]+):.*$/\1/' | sort -u)
    
    # Backing up Docker volumes using container-based tar method
    if [ -n "$volumes" ]; then
        log "Backing up Docker volumes..."
        mkdir -p "$temp_dir/volumes"
        
        while read -r volume; do
            if [ -n "$volume" ]; then
                log "Processing Docker volume: $volume"
                
                # Get volume mountpoint
                local volume_path
                volume_path=$(docker volume inspect "$volume" --format '{{ .Mountpoint }}')
                if [ -n "$volume_path" ]; then
                    log "  - Found volume path: $volume_path"
                    local volume_name
                    volume_name=$(basename "$volume")
                    
                    mkdir -p "$temp_dir/volumes/$volume_name"
                    
                    # Stop Container(s) using dieses Volume für konsistente Backups
                    local containers
                    containers=$(docker ps -a --filter "volume=$volume" --format "{{.Names}}")
                    for container in $containers; do
                        log "  - Stopping container $container temporarily..."
                        docker stop "$container" || true
                    done
                    
                    # Backup Volume per containerbasiertem tar-Befehl
                    log "  - Backing up volume data using docker container..."
                    docker run --rm -v "$volume":/data -v "$temp_dir/volumes/$volume_name":/backup alpine sh -c "tar czf /backup/backup.tar.gz -C /data ."
                    
                    echo "$volume" > "$temp_dir/volumes/$volume_name/.volume_info"
                    
                    for container in $containers; do
                        log "  - Restarting container $container..."
                        docker start "$container" || true
                    done
                fi
            fi
        done <<< "$volumes"
    fi
    
    # Backing up bind mounts
    local bind_mounts
    bind_mounts=$(grep -A 5 "volumes:" "$compose_file" | grep -v "volumes:" | grep -v "^--$" | grep -E "^\s*-\s*.*:.*" | awk '{print $2}' | awk -F':' '{print $1}' | sed 's/^-//g' | sed 's/^[[:space:]]*//g' | grep -v "^$")
    local additional_bind_mounts
    additional_bind_mounts=$(grep -E "volumes:" -A 100 "$compose_file" | grep -E "^\s+.*:\s*" | awk -F':' '{print $1}' | sed 's/^[[:space:]]*//g' | grep -v "^#" | grep -v "^$")
    local combined_bind_mounts
    combined_bind_mounts=$(echo -e "$bind_mounts\n$additional_bind_mounts" | sort -u | grep -v "^$")
    
    if [ -n "$combined_bind_mounts" ]; then
        log "Backing up bind mounts..."
        mkdir -p "$temp_dir/bind_mounts"
        
        while read -r mount; do
            if [ -n "$mount" ]; then
                log "Processing bind mount: $mount"
                if [[ "$mount" == /* || "$mount" == ./* ]]; then
                    if [[ "$mount" == ./* ]]; then
                        mount="${app_dir}/${mount:2}"
                    fi
                    
                    if [[ "$mount" == "$app_dir/"* ]]; then
                        local rel_path="${mount#$app_dir/}"
                        log "  - Backing up local bind mount: $rel_path"
                        if [ -d "$mount" ]; then
                            mkdir -p "$temp_dir/bind_mounts/$rel_path"
                            cp -rp "$mount"/* "$temp_dir/bind_mounts/$rel_path/" || {
                                log "WARNING: Could not copy all files from $mount. Some files might be missing."
                            }
                        elif [ -f "$mount" ]; then
                            mkdir -p "$temp_dir/bind_mounts/$(dirname "$rel_path")"
                            cp -p "$mount" "$temp_dir/bind_mounts/$rel_path"
                        fi
                    else
                        log "  - External bind mount detected: $mount"
                        local mount_name
                        mount_name=$(echo "$mount" | sed 's|/|_|g' | sed 's|^_||')
                        mkdir -p "$temp_dir/bind_mounts/external/$mount_name"
                        if [ -d "$mount" ]; then
                            cp -rp "$mount"/* "$temp_dir/bind_mounts/external/$mount_name/" || {
                                log "WARNING: Could not copy all files from $mount. Some files might be missing."
                            }
                        elif [ -f "$mount" ]; then
                            cp -p "$mount" "$temp_dir/bind_mounts/external/$mount_name/"
                        fi
                        echo "$mount" > "$temp_dir/bind_mounts/external/$mount_name/.mount_info"
                    fi
                fi
            fi
        done <<< "$combined_bind_mounts"
    fi
    
    log "Creating backup archive: $backup_file"
    tar -czf "$backup_file" -C "$app_dir" "$(basename "$temp_dir")"
    
    log "Cleaning up temporary directory..."
    rm -rf "$temp_dir"
    
    log "Backup completed successfully: $backup_file"
}

# Restore backup function
function restore_backup {
    local app_dir=$1
    
    if [ ! -d "$app_dir" ]; then
        log "ERROR: Directory $app_dir does not exist."
        exit 1
    fi
    
    local backup_files
    IFS=$'\n' read -d '' -r -a backup_files < <(find "$app_dir" -maxdepth 1 -name "*_backup_*.tar.gz" | sort -r && printf '\0')
    local backup_file=""
    
    if [ ${#backup_files[@]} -eq 0 ]; then
        log "ERROR: No backup files found in $app_dir."
        exit 1
    elif [ ${#backup_files[@]} -eq 1 ]; then
        backup_file="${backup_files[0]}"
    else
        log "Multiple backup files found:"
        for i in "${!backup_files[@]}"; do
            echo "[$i] $(basename "${backup_files[$i]}")"
        done
        read -p "Select a backup file by number: " selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -lt "${#backup_files[@]}" ]; then
            backup_file="${backup_files[$selection]}"
        else
            log "ERROR: Invalid selection."
            exit 1
        fi
    fi
    
    log "Using backup file: $backup_file"
    
    local temp_dir="${app_dir}/.restore_temp"
    log "Creating temporary directory: $temp_dir"
    mkdir -p "$temp_dir"
    
    log "Extracting backup archive..."
    tar -xzf "$backup_file" -C "$temp_dir"
    
    local extracted_dir="${temp_dir}/.backup_temp"
    if [ ! -d "$extracted_dir" ]; then
        extracted_dir="${temp_dir}/$(find "$temp_dir" -maxdepth 1 -type d | grep -v "^$temp_dir\$" | head -n 1 | xargs basename)"
        if [ ! -d "$temp_dir/$extracted_dir" ]; then
            log "ERROR: Could not find extracted directory."
            rm -rf "$temp_dir"
            exit 1
        else
            extracted_dir="$temp_dir/$extracted_dir"
        fi
    fi
    
    log "Restoring docker-compose file..."
    if [ -f "$extracted_dir/docker-compose.yaml" ]; then
        cp "$extracted_dir/docker-compose.yaml" "$app_dir/"
    elif [ -f "$extracted_dir/docker-compose.yml" ]; then
        cp "$extracted_dir/docker-compose.yml" "$app_dir/"
    else
        log "WARNING: No docker-compose file found in backup."
    fi
    
    local compose_file=""
    if [ -f "$app_dir/docker-compose.yaml" ]; then
        compose_file="$app_dir/docker-compose.yaml"
    elif [ -f "$app_dir/docker-compose.yml" ]; then
        compose_file="$app_dir/docker-compose.yml"
    fi
    
    if [ -n "$compose_file" ]; then
        log "Stopping existing containers if running..."
        (cd "$app_dir" && docker-compose down 2>/dev/null) || \
        (cd "$app_dir" && docker compose down 2>/dev/null) || \
        log "No containers running or docker-compose failed."
    fi
    
    if [ -d "$extracted_dir/bind_mounts" ]; then
        log "Restoring bind mounts..."
        find "$extracted_dir/bind_mounts" -mindepth 1 -type d | grep -v "/external/" | while read -r dir; do
            local rel_path="${dir#$extracted_dir/bind_mounts/}"
            local dest_path="$app_dir/$rel_path"
            log "  - Restoring $rel_path to $dest_path"
            mkdir -p "$dest_path"
            if [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
                cp -rp "$dir"/* "$dest_path/"
            fi
        done
        if [ -d "$extracted_dir/bind_mounts/external" ]; then
            log "Restoring external bind mounts..."
            find "$extracted_dir/bind_mounts/external" -mindepth 1 -type d | while read -r dir; do
                local mount_name
                mount_name=$(basename "$dir")
                if [ -f "$dir/.mount_info" ]; then
                    local original_path
                    original_path=$(cat "$dir/.mount_info")
                    log "  - Restoring external mount $mount_name to $original_path"
                    mkdir -p "$(dirname "$original_path")"
                    if [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
                        cp -rp "$dir"/* "$original_path/"
                    fi
                else
                    log "  - WARNING: Could not determine original path for $mount_name"
                fi
            done
        fi
    fi
    
    if [ -d "$extracted_dir/volumes" ]; then
        log "Restoring Docker volumes..."
        find "$extracted_dir/volumes" -mindepth 1 -maxdepth 1 -type d | while read -r vol_dir; do
            local vol_name
            vol_name=$(basename "$vol_dir")
            if [ -f "$vol_dir/.volume_info" ]; then
                local original_volume
                original_volume=$(cat "$vol_dir/.volume_info")
                log "  - Restoring volume $original_volume"
                if ! docker volume inspect "$original_volume" &>/dev/null; then
                    log "  - Creating Docker volume: $original_volume"
                    docker volume create "$original_volume"
                fi
                log "  - Restoring data into volume $original_volume..."
                docker run --rm -v "$original_volume":/data -v "$vol_dir":/backup alpine sh -c "tar xzf /backup/backup.tar.gz -C /data"
            else
                log "  - WARNING: Could not determine original volume name for $vol_name"
            fi
        done
    fi
    
    if [ -n "$compose_file" ]; then
        log "Starting containers..."
        (cd "$app_dir" && docker-compose up -d) || \
        (cd "$app_dir" && docker compose up -d) || \
        log "ERROR: Failed to start containers."
    fi
    
    log "Cleaning up..."
    rm -rf "$temp_dir"
    
    log "Restore completed successfully!"
}

# Main script execution
check_requirements

if [ $# -lt 2 ]; then
    show_help
fi

action=$1
app_dir=$2

case "$action" in
    -backup)
        create_backup "$app_dir"
        ;;
    -restore)
        restore_backup "$app_dir"
        ;;
    *)
        show_help
        ;;
esac

exit 0
