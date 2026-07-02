#!/bin/bash
# Test script for docker-backup.sh

set -euo pipefail

# Helper to run script and check output
function test_help_contains_options {
    echo "Running test: test_help_contains_options"
    local help_output
    # Run the script with no arguments to get the help output.
    # It exits with 1, so we allow it.
    help_output=$(./docker-backup.sh || true)
    
    echo "$help_output" | grep -q -- "-l" || {
        echo "FAIL: Help does not contain '-l' option documentation"
        exit 1
    }
    
    echo "$help_output" | grep -q -- "-d" || {
        echo "FAIL: Help does not contain '-d' option documentation"
        exit 1
    }
    
    echo "PASS: Help contains documentation for -l and -d options"
}

function test_arg_parsing {
    echo "Running test: test_arg_parsing"
    local output
    # Run the script with -backup -l /nonexistent_dir.
    # It should not complain about directory '-l'.
    output=$(./docker-backup.sh -backup -l /nonexistent_dir 2>&1 || true)
    
    if echo "$output" | grep -q "Directory -l does not exist"; then
        echo "FAIL: Option -l was treated as directory name instead of a flag"
        exit 1
    fi
    
    echo "PASS: Option -l was successfully parsed as a flag"
}

function test_backup_parent_flag {
    echo "Running test: test_backup_parent_flag"
    
    # Set up dummy app directory
    local app_dir="temp_test_app"
    mkdir -p "$app_dir"
    echo -e "version: '3'\nservices:\n  web:\n    image: nginx:alpine" > "$app_dir/docker-compose.yml"
    
    # Run backup with -l flag
    ./docker-backup.sh -backup -l "$app_dir"
    
    # Check if backup exists in the parent directory (which is current directory)
    local parent_backups
    parent_backups=$(find . -maxdepth 1 -name "temp_test_app_backup_*.tar.gz" 2>/dev/null)
    
    # Check if backup exists inside the app directory
    local app_backups
    app_backups=$(find "$app_dir" -maxdepth 1 -name "temp_test_app_backup_*.tar.gz" 2>/dev/null)
    
    # Clean up
    rm -rf "$app_dir"
    if [ -n "$parent_backups" ]; then
        rm -f $parent_backups
    fi
    if [ -n "$app_backups" ]; then
        rm -f $app_backups
    fi
    
    if [ -z "$parent_backups" ]; then
        echo "FAIL: Backup file was not created in the parent directory of $app_dir"
        exit 1
    fi
    
    if [ -n "$app_backups" ]; then
        echo "FAIL: Backup file was mistakenly created inside the application directory"
        exit 1
    fi
    
    echo "PASS: Backup file was successfully created in the parent directory"
}

function test_restore_subfolder_and_cleanup {
    echo "Running test: test_restore_subfolder_and_cleanup"
    
    # Clean up from potential previous runs
    rm -rf app1 temp_restore_parent
    
    # Set up dummy app directory
    local app_dir="app1"
    mkdir -p "$app_dir"
    echo -e "version: '3'\nservices:\n  web:\n    image: nginx:alpine" > "$app_dir/docker-compose.yml"
    
    # Create the backup inside app1
    ./docker-backup.sh -backup "$app_dir"
    
    # Create a parent directory and move the backup file there
    local parent_dir="temp_restore_parent"
    mkdir -p "$parent_dir"
    
    local backup_file
    backup_file=$(find "$app_dir" -name "app1_backup_*.tar.gz" | head -n 1)
    
    local backup_name
    backup_name=$(basename "$backup_file")
    
    mv "$backup_file" "$parent_dir/"
    
    # Remove the original app directory
    rm -rf "$app_dir"
    
    # Run restore on the parent directory with -d flag
    ./docker-backup.sh -restore -d "$parent_dir"
    
    # Verify app1 directory was automatically created inside parent_dir
    if [ ! -d "$parent_dir/app1" ]; then
        echo "FAIL: Directory $parent_dir/app1 was not automatically created during restore"
        rm -rf "$parent_dir"
        exit 1
    fi
    
    # Verify compose file was restored inside the new directory
    if [ ! -f "$parent_dir/app1/docker-compose.yml" ] && [ ! -f "$parent_dir/app1/docker-compose.yaml" ]; then
        echo "FAIL: docker-compose file was not restored in $parent_dir/app1/"
        rm -rf "$parent_dir"
        exit 1
    fi
    
    # Verify the backup archive was deleted from the parent directory due to -d flag
    if [ -f "$parent_dir/$backup_name" ]; then
        echo "FAIL: Backup file $parent_dir/$backup_name was not deleted after successful restore with -d flag"
        rm -rf "$parent_dir"
        exit 1
    fi
    
    # Clean up
    rm -rf "$parent_dir"
    echo "PASS: Restore subfolder was automatically created, and backup file was deleted successfully"
}

# Run the tests
test_help_contains_options
test_arg_parsing
test_backup_parent_flag
test_restore_subfolder_and_cleanup



