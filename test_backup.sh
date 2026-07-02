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

# Run the tests
test_help_contains_options
test_arg_parsing

