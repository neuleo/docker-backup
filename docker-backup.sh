#!/bin/bash

# Docker Backup and Restore Script
# Usage: ./docker-backup.sh -backup|-restore <docker_app_directory>

set -e

# Display help function
function show_help {
    echo "Docker Backup and Restore Script"
    echo "Usage: $0 -backup [-l] <docker_app_directory1> [docker_app_directory2 ...]"
    echo "       $0 -restore [-d] <docker_app_directory1> [docker_app_directory2 ...]"
    echo ""
    echo "Options:"
    echo "  -backup    Create a backup of the specified Docker application directory/directories."
    echo "             If a directory does not contain a compose file but has subdirectories with one,"
    echo "             all those subdirectories will be backed up."
    echo "  -restore   Restore a backup to the specified Docker application directory/directories."
    echo "             If a directory does not contain a backup archive but has subdirectories with one,"
    echo "             those subdirectories will be restored."
    echo "  -l         Create backup archive one level up (in the parent directory) of the docker app directory."
    echo "  -d         Delete the backup archive after a successful restore."
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

    if [ ! -d "$app_dir" ]; then
        log "ERROR: Directory $app_dir does not exist."
        exit 1
    fi

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

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name=$(basename "$app_dir")
    local backup_file="${app_dir}/${backup_name}_backup_${timestamp}.tar.gz"
    local temp_dir="${app_dir}/.backup_temp"

    log "Creating temporary directory: $temp_dir"
    mkdir -p "$temp_dir"

    log "Copying docker-compose file to temporary directory..."
    cp "$compose_file" "$temp_dir/"

    log "Extracting volume information..."
    local project_name=$(basename "$app_dir")
    
    local config_volumes=""
    if docker compose version &>/dev/null; then
        config_volumes=$(cd "$app_dir" && docker compose config --volumes 2>/dev/null || true)
    else
        config_volumes=$(cd "$app_dir" && docker-compose config --volumes 2>/dev/null || true)
    fi

    local volumes=""
    if [ -n "$config_volumes" ]; then
        while read -r volume; do
            [ -z "$volume" ] && continue
            local full_volume_name="${project_name}_${volume}"
            if docker volume inspect "$full_volume_name" &>/dev/null; then
                if [ -z "$volumes" ]; then
                    volumes="$full_volume_name"
                else
                    volumes="$volumes"$'\n'"$full_volume_name"
                fi
            else
                if docker volume inspect "$volume" &>/dev/null; then
                    if [ -z "$volumes" ]; then
                        volumes="$volume"
                    else
                        volumes="$volumes"$'\n'"$volume"
                    fi
                else
                    log "WARNING: Volume $volume (tried as $full_volume_name) not found"
                fi
            fi
        done <<< "$config_volumes"
    fi

    if [ -n "$volumes" ]; then
        log "Backing up Docker volumes..."
        mkdir -p "$temp_dir/volumes"

        while read -r volume; do
            [ -z "$volume" ] && continue
            log "Processing Docker volume: $volume"
            local volume_path=$(docker volume inspect "$volume" --format '{{ .Mountpoint }}' 2>/dev/null)
            if [ -n "$volume_path" ]; then
                log "  - Found volume path: $volume_path"
                local volume_name=$(basename "$volume")
                mkdir -p "$temp_dir/volumes/$volume_name"

                local containers=$(docker ps -a --filter "volume=$volume" --format "{{.Names}}" 2>/dev/null || true)
                for container in $containers; do
                    [ -z "$container" ] && continue
                    log "  - Stopping container $container temporarily..."
                    docker stop "$container" || true
                done

                log "  - Backing up volume data using docker container..."
                docker run --rm -v "$volume":/data -v "$temp_dir/volumes/$volume_name":/backup alpine sh -c "tar czf /backup/backup.tar.gz -C /data ."
                echo "$volume" > "$temp_dir/volumes/$volume_name/.volume_info"

                for container in $containers; do
                    [ -z "$container" ] && continue
                    log "  - Restarting container $container..."
                    docker start "$container" || true
                done
            else
                log "WARNING: Could not find volume path for $volume"
            fi
        done <<< "$volumes"
    fi

    local bind_mounts=$(grep -A 5 "volumes:" "$compose_file" | grep -v "volumes:" | grep -v "^--$" | grep -E "^\s*-\s*.*:.*" | awk '{print $2}' | awk -F':' '{print $1}' | sed 's/^-//g' | sed 's/^[[:space:]]*//g' | grep -v "^$")
    local additional_bind_mounts=$(grep -E "volumes:" -A 100 "$compose_file" | grep -E "^\s+.*:\s*" | awk -F':' '{print $1}' | sed 's/^[[:space:]]*//g' | grep -v "^#" | grep -v "^$")
    local combined_bind_mounts=$(echo -e "$bind_mounts\n$additional_bind_mounts" | sort -u | grep -v "^$")

    if [ -n "$combined_bind_mounts" ]; then
        log "Backing up bind mounts..."
        mkdir -p "$temp_dir/bind_mounts"

        while read -r mount; do
            [ -z "$mount" ] && continue
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
                        cp -rp "$mount"/* "$temp_dir/bind_mounts/$rel_path/" || log "WARNING: Could not copy all files from $mount."
                    elif [ -f "$mount" ]; then
                        mkdir -p "$temp_dir/bind_mounts/$(dirname "$rel_path")"
                        cp -p "$mount" "$temp_dir/bind_mounts/$rel_path"
                    fi
                else
                    log "  - WARNING: External bind mount '$mount' is outside of the application directory and will not be backed up."
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
                local mount_name=$(basename "$dir")
                if [ -f "$dir/.mount_info" ]; then
                    local original_path=$(cat "$dir/.mount_info")
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
            local vol_name=$(basename "$vol_dir")
            if [ -f "$vol_dir/.volume_info" ]; then
                local original_volume=$(cat "$vol_dir/.volume_info")
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

check_requirements

if [ $# -lt 2 ]; then
    show_help
fi

action=$1
shift

backup_parent=false
delete_backup=false
dirs=()

while [ $# -gt 0 ]; do
    case "$1" in
        -l)
            backup_parent=true
            shift
            ;;
        -d)
            delete_backup=true
            shift
            ;;
        -*)
            log "ERROR: Unknown option $1"
            show_help
            ;;
        *)
            dirs+=("$1")
            shift
            ;;
    esac
done

if [ ${#dirs[@]} -eq 0 ]; then
    log "ERROR: No directories specified."
    show_help
fi

case "$action" in
    -backup)
        for dir in "${dirs[@]}"; do
            # Remove trailing slash for consistency
            dir="${dir%/}"
            if [ ! -d "$dir" ]; then
                log "ERROR: Directory $dir does not exist."
                continue
            fi

            if [ -f "$dir/docker-compose.yaml" ] || [ -f "$dir/docker-compose.yml" ]; then
                create_backup "$dir"
            else
                log "No docker-compose file found directly in $dir. Checking direct subdirectories..."
                local found_subdirs=false
                # Using find to handle hidden directories or spaces carefully, or a simple loop if files are standard
                for subdir in "$dir"/*; do
                    if [ -d "$subdir" ] && { [ -f "$subdir/docker-compose.yaml" ] || [ -f "$subdir/docker-compose.yml" ]; }; then
                        log "Found Docker application in subdirectory: $subdir"
                        create_backup "$subdir"
                        found_subdirs=true
                    fi
                done
                if [ "$found_subdirs" = false ]; then
                    log "WARNING: No docker-compose.yaml or docker-compose.yml found in $dir or its direct subdirectories."
                fi
            fi
        done
        ;;
    -restore)
        for dir in "${dirs[@]}"; do
            dir="${dir%/}"
            if [ ! -d "$dir" ]; then
                log "ERROR: Directory $dir does not exist."
                continue
            fi

            # Check if this directory contains a backup file or has subdirectories with backup files
            local has_backups=false
            if [ -n "$(find "$dir" -maxdepth 1 -name "*_backup_*.tar.gz" 2>/dev/null)" ]; then
                has_backups=true
            fi

            if [ "$has_backups" = true ]; then
                restore_backup "$dir"
            else
                log "No backup files found directly in $dir. Checking direct subdirectories..."
                local found_subdirs=false
                for subdir in "$dir"/*; do
                    if [ -d "$subdir" ] && [ -n "$(find "$subdir" -maxdepth 1 -name "*_backup_*.tar.gz" 2>/dev/null)" ]; then
                        log "Found backups in subdirectory: $subdir"
                        restore_backup "$subdir"
                        found_subdirs=true
                    fi
                done
                if [ "$found_subdirs" = false ]; then
                    log "WARNING: No backups found in $dir or its direct subdirectories."
                fi
            fi
        done
        ;;
    *)
        show_help
        ;;
esac

exit 0