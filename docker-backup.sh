#!/bin/bash

# Docker Backup and Restore Script
# Usage: ./docker-backup.sh -backup|restore <docker_app_directory>

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
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name=$(basename "$app_dir")
    local backup_file="${app_dir}/${backup_name}_backup_${timestamp}.tar.gz"
    local temp_dir="${app_dir}/.backup_temp"
    
    log "Creating temporary directory: $temp_dir"
    mkdir -p "$temp_dir"
    
    # Copy docker-compose file
    log "Copying docker-compose file to temporary directory..."
    cp "$compose_file" "$temp_dir/"
    
    # Extract volume information from docker-compose file
    log "Extracting volume information..."
    
    # Parse volumes and bind mounts from docker-compose file
    local volumes=$(grep -A 5 "volumes:" "$compose_file" | grep -v "volumes:" | grep -v "^--$" | awk '{print $1}' | sed 's/://g' | grep -v "^$")
    local bind_mounts=$(grep -A 5 "volumes:" "$compose_file" | grep -v "volumes:" | grep -v "^--$" | grep -E "^\s*-\s*.*:.*" | awk '{print $2}' | awk -F':' '{print $1}' | sed 's/^-//g' | sed 's/^[[:space:]]*//g' | grep -v "^$")
    
    # Additional pattern to match bind mounts in another format
    local additional_bind_mounts=$(grep -E "volumes:" -A 100 "$compose_file" | grep -E "^\s+.*:\s*" | awk -F':' '{print $1}' | sed 's/^[[:space:]]*//g' | grep -v "^#" | grep -v "^$")
    
    # Backing up Docker volumes
    if [ ! -z "$volumes" ]; then
        log "Backing up Docker volumes..."
        mkdir -p "$temp_dir/volumes"
        
        while read -r volume; do
            if [ ! -z "$volume" ]; then
                log "Processing Docker volume: $volume"
                
                # Get volume data directory
                volume_path=$(docker volume inspect $volume --format '{{ .Mountpoint }}')
                
                if [ ! -z "$volume_path" ]; then
                    log "  - Found volume path: $volume_path"
                    volume_name=$(basename "$volume")
                    
                    # Create destination directory
                    mkdir -p "$temp_dir/volumes/$volume_name"
                    
                    # Stop containers using this volume for consistency
                    local containers=$(docker ps -a --filter "volume=$volume" --format "{{.Names}}")
                    for container in $containers; do
                        log "  - Stopping container $container temporarily..."
                        docker stop $container || true
                    done
                    
                    # Copy data
                    log "  - Copying volume data..."
                    sudo cp -rp $volume_path/* "$temp_dir/volumes/$volume_name/" || {
                        log "WARNING: Could not copy all files from $volume_path. Some files might be missing."
                    }
                    
                    # Create volume info file
                    echo "$volume" > "$temp_dir/volumes/$volume_name/.volume_info"
                    
                    # Restart containers
                    for container in $containers; do
                        log "  - Restarting container $container..."
                        docker start $container || true
                    done
                fi
            fi
        done <<< "$volumes"
    fi
    
    # Backing up bind mounts
    local combined_bind_mounts=$(echo -e "$bind_mounts\n$additional_bind_mounts" | sort -u | grep -v "^$")
    
    if [ ! -z "$combined_bind_mounts" ]; then
        log "Backing up bind mounts..."
        mkdir -p "$temp_dir/bind_mounts"
        
        while read -r mount; do
            if [ ! -z "$mount" ]; then
                log "Processing bind mount: $mount"
                
                # Process only local paths, not Docker volume references
                if [[ "$mount" == /* || "$mount" == ./* ]]; then
                    # Handle relative paths - if mount is relative, make it absolute
                    if [[ "$mount" == ./* ]]; then
                        mount="${app_dir}/${mount:2}"
                    fi
                    
                    # Check if the bind mount is a subdirectory of app_dir
                    if [[ "$mount" == $app_dir/* ]]; then
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
                        local mount_name=$(echo "$mount" | sed 's|/|_|g' | sed 's|^_||')
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
    
    # Create archive
    log "Creating backup archive: $backup_file"
    tar -czf "$backup_file" -C "$app_dir" $(basename "$temp_dir")
    
    # Clean up temporary directory
    log "Cleaning up temporary directory..."
    rm -rf "$temp_dir"
    
    log "Backup completed successfully: $backup_file"
}

# Restore backup function
function restore_backup {
    local app_dir=$1
    
    # Validate app directory
    if [ ! -d "$app_dir" ]; then
        log "ERROR: Directory $app_dir does not exist."
        exit 1
    fi
    
    # Find backup archive
    local backup_files=($(find "$app_dir" -maxdepth 1 -name "*_backup_*.tar.gz" | sort -r))
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
    
    # Create temporary directory for extraction
    local temp_dir="${app_dir}/.restore_temp"
    
    log "Creating temporary directory: $temp_dir"
    mkdir -p "$temp_dir"
    
    # Extract backup
    log "Extracting backup archive..."
    tar -xzf "$backup_file" -C "$temp_dir"
    
    # The extracted directory should be .backup_temp
    local extracted_dir="${temp_dir}/.backup_temp"
    if [ ! -d "$extracted_dir" ]; then
        extracted_dir="${temp_dir}/$(find "$temp_dir" -maxdepth 1 -type d | grep -v "^$temp_dir$" | head -n 1 | xargs basename)"
        if [ ! -d "$extracted_dir" ]; then
            log "ERROR: Could not find extracted directory."
            rm -rf "$temp_dir"
            exit 1
        fi
    fi
    
    # Copy docker-compose file
    log "Restoring docker-compose file..."
    if [ -f "$extracted_dir/docker-compose.yaml" ]; then
        cp "$extracted_dir/docker-compose.yaml" "$app_dir/"
    elif [ -f "$extracted_dir/docker-compose.yml" ]; then
        cp "$extracted_dir/docker-compose.yml" "$app_dir/"
    else
        log "WARNING: No docker-compose file found in backup."
    fi
    
    # Stop any running containers
    local compose_file=""
    if [ -f "$app_dir/docker-compose.yaml" ]; then
        compose_file="$app_dir/docker-compose.yaml"
    elif [ -f "$app_dir/docker-compose.yml" ]; then
        compose_file="$app_dir/docker-compose.yml"
    fi
    
    if [ ! -z "$compose_file" ]; then
        log "Stopping existing containers if running..."
        (cd "$app_dir" && docker-compose down 2>/dev/null) || \
        (cd "$app_dir" && docker compose down 2>/dev/null) || \
        log "No containers running or docker-compose failed."
    fi
    
    # Restore bind mounts
    if [ -d "$extracted_dir/bind_mounts" ]; then
        log "Restoring bind mounts..."
        
        # Restore internal bind mounts
        find "$extracted_dir/bind_mounts" -mindepth 1 -type d | grep -v "/external/" | while read -r dir; do
            local rel_path="${dir#$extracted_dir/bind_mounts/}"
            local dest_path="$app_dir/$rel_path"
            
            log "  - Restoring $rel_path to $dest_path"
            mkdir -p "$dest_path"
            
            # Copy files
            if [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
                cp -rp "$dir"/* "$dest_path/"
            fi
        done
        
        # Restore external bind mounts
        if [ -d "$extracted_dir/bind_mounts/external" ]; then
            log "Restoring external bind mounts..."
            find "$extracted_dir/bind_mounts/external" -mindepth 1 -type d | while read -r dir; do
                local mount_name=$(basename "$dir")
                
                if [ -f "$dir/.mount_info" ]; then
                    local original_path=$(cat "$dir/.mount_info")
                    log "  - Restoring external mount $mount_name to $original_path"
                    
                    # Create directory if needed
                    mkdir -p "$(dirname "$original_path")"
                    
                    # Copy files
                    if [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
                        cp -rp "$dir"/* "$original_path/"
                    fi
                else
                    log "  - WARNING: Could not determine original path for $mount_name"
                fi
            done
        fi
    fi
    
    # Restore Docker volumes
    if [ -d "$extracted_dir/volumes" ]; then
        log "Restoring Docker volumes..."
        find "$extracted_dir/volumes" -mindepth 1 -maxdepth 1 -type d | while read -r vol_dir; do
            local vol_name=$(basename "$vol_dir")
            
            if [ -f "$vol_dir/.volume_info" ]; then
                local original_volume=$(cat "$vol_dir/.volume_info")
                log "  - Restoring volume $original_volume"
                
                # Create the volume if it doesn't exist
                if ! docker volume inspect "$original_volume" &>/dev/null; then
                    log "  - Creating Docker volume: $original_volume"
                    docker volume create "$original_volume"
                fi
                
                # Get volume mountpoint
                local volume_path=$(docker volume inspect "$original_volume" --format '{{ .Mountpoint }}')
                
                if [ ! -z "$volume_path" ]; then
                    log "  - Copying data to $volume_path"
                    
                    # Create a temporary container to copy data to the volume
                    log "  - Using temporary container to restore volume data..."
                    docker run --rm -v "$original_volume":/volume_data -v "$vol_dir":/backup_data alpine sh -c "rm -rf /volume_data/* && cp -rp /backup_data/* /volume_data/"
                else
                    log "  - WARNING: Could not determine mountpoint for volume $original_volume"
                fi
            else
                log "  - WARNING: Could not determine original volume name for $vol_name"
            fi
        done
    fi
    
    # Start containers
    if [ ! -z "$compose_file" ]; then
        log "Starting containers..."
        (cd "$app_dir" && docker-compose up -d) || \
        (cd "$app_dir" && docker compose up -d) || \
        log "ERROR: Failed to start containers."
    fi
    
    # Clean up
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
