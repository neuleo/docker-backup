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

# Run the test
test_help_contains_options
