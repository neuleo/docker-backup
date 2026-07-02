# Technology Stack

This document records the technology stack used in the Docker Backup project.

## Core Technologies
- **Bash (Bourne Again SHell)**: The primary scripting language used to orchestrate backup and restore processes.
- **Docker**: The containerization platform. Used to inspect volumes, locate mount points, spin up utility containers, and manage application container states.
- **Docker Compose**: Used to retrieve application configurations (volumes, bind mounts) and manage multi-container applications (`up`, `down`, `config`).

## System Utilities
- **tar & gzip**: Used for archiving and compressing files and directories.
- **find & grep**: Used for searching files, backup archives, and parsing configuration info.
