---
description: How to work on a remote project using Remote Dev containers
---

# Remote Dev Workflow

This workflow explains how to develop on a remote project using the Remote Dev system. **All project code runs inside a Docker container on the remote host, never locally.**

## Setup

1. Ensure `.env` is configured with the correct `RDEV_HOST` (e.g. `user@server` or `local`)
2. Build the base image if not already done:
```bash
./rdev build
```

## Creating a Project

### From a git repository
```bash
./rdev create <project-name> --git-url <repo-url>
# With GPU access:
./rdev create <project-name> --git-url <repo-url> --gpu
```

### From scratch
```bash
./rdev create <project-name>
# With GPU:
./rdev create <project-name> --gpu
```

## Working on a Project

### Running commands inside the container
**IMPORTANT:** Never run project code locally. Always use `./rdev exec`:

```bash
# Set up virtualenv
./rdev exec <project-name> python3 -m venv /workspace/.venv

# Install dependencies
./rdev exec <project-name> bash -c "source /workspace/.venv/bin/activate && pip install -r requirements.txt"

# Run a script
./rdev exec <project-name> bash -c "source /workspace/.venv/bin/activate && python3 main.py"

# Check files
./rdev exec <project-name> ls /workspace/
./rdev exec <project-name> cat /workspace/output.log
```

### Interactive shell
```bash
./rdev shell <project-name>
```

### Transferring files
```bash
# Push a local file into the container
./rdev push <project-name> ./local_file.py

# Pull a file from the container
./rdev pull <project-name> /workspace/results.csv ./
```

## Checking Status

```bash
# List all projects
./rdev list

# Project details (state, GPU, git status, disk usage)
./rdev status <project-name>

# View container logs
./rdev logs <project-name>
```

## Lifecycle Management

```bash
# Stop a project (data persists)
./rdev stop <project-name>

# Start it again
./rdev start <project-name>

# Destroy (removes container AND data)
./rdev destroy <project-name>
```

## Key Rules for LLM Agents

1. **Never run project code locally** — always use `./rdev exec`
2. **All project files live at `/workspace/`** inside the container
3. **Use virtualenvs** — create with `python3 -m venv /workspace/.venv`
4. **Read `/workspace/AGENT.md`** inside the container for project-specific instructions
5. **Use `bash -c "..."` for multi-step commands** to chain activate + run
6. **Check GPU** with `./rdev exec <name> nvidia-smi`
