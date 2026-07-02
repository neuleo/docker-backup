# Implementation Plan - Implement Backup Retention Rules

## Phase 1: Test Harness and CLI Flag Configuration
- [ ] Task: Write tests for retention parameter parsing and default limits
    - [ ] Create basic test script `test-retention.sh`
    - [ ] Write failing test asserting `--keep` parsing failure/handling
- [ ] Task: Implement CLI flag parsing for `--keep` / `-keep` argument
    - [ ] Update `docker-backup.sh` CLI option parser to support `--keep` or `-keep`
    - [ ] Ensure default limit of 5 is set if not provided
- [ ] Task: Conductor - User Manual Verification 'Phase 1: Test Harness and CLI Flag Configuration' (Protocol in workflow.md)

## Phase 2: Retention Pruning Logic Implementation
- [ ] Task: Write tests for backup pruning
    - [ ] Write test simulating generation of 7 backups
    - [ ] Assert that running pruning with `--keep 5` deletes the 2 oldest backups and keeps the 5 newest
- [ ] Task: Implement pruning logic in `docker-backup.sh`
    - [ ] Write retention loop to list, sort by date, and prune old backup archives
    - [ ] Ensure only archives matching the name pattern are pruned
- [ ] Task: Conductor - User Manual Verification 'Phase 2: Retention Pruning Logic Implementation' (Protocol in workflow.md)
