# Agent Instructions

You are working on a **Remote Dev** project. This project runs inside a Docker container on a remote host — **not on your local machine**.

## ⚠️ Critical Rule

**Never run project code locally.** All commands must go through `./rdev exec` or `./rdev shell` to execute inside the container.

## Host-Side Commands (from your local machine)

Use these `rdev` commands to interact with the project:

```bash
# Run a command inside the container
./rdev exec PROJECT_NAME <command>

# Run multi-step commands (e.g. activate venv + run script)
./rdev exec PROJECT_NAME bash -c "source /workspace/.venv/bin/activate && python3 main.py"

# Open an interactive shell
./rdev shell PROJECT_NAME

# Push a local file into the container
./rdev push PROJECT_NAME ./local_file.py

# Pull a file from the container
./rdev pull PROJECT_NAME /workspace/output.csv ./

# Check project status
./rdev status PROJECT_NAME

# View logs
./rdev logs PROJECT_NAME
```

## Container Environment

- **OS:** Ubuntu 22.04 (Docker container)
- **Workspace:** `/workspace` — all project files live here
- **Python:** Python 3.10+ with pip and venv
- **Git:** Pre-configured, safe directory set for `/workspace`
- **GPU:** Check with `./rdev exec PROJECT_NAME nvidia-smi` (if enabled)

## Inside the Container

When working inside the container (via `rdev exec` or `rdev shell`):

1. **Stay in `/workspace`.** All code, data, and configs belong here.
2. **Use virtualenvs:**
   ```bash
   python3 -m venv /workspace/.venv
   source /workspace/.venv/bin/activate
   pip install -r requirements.txt
   ```
3. **Commit often.** Use git to version your work.
4. **Long-running processes:** Use `tmux` for processes that should survive shell disconnects.
5. **Don't modify system files** outside `/workspace`.

## Typical Workflow

```bash
# 1. Set up environment
./rdev exec PROJECT_NAME python3 -m venv /workspace/.venv
./rdev exec PROJECT_NAME bash -c "source /workspace/.venv/bin/activate && pip install -r requirements.txt"

# 2. Run your code
./rdev exec PROJECT_NAME bash -c "source /workspace/.venv/bin/activate && python3 main.py"

# 3. Check results
./rdev exec PROJECT_NAME cat /workspace/results.txt

# 4. Push edits from local
./rdev push PROJECT_NAME ./modified_script.py

# 5. Pull results to local
./rdev pull PROJECT_NAME /workspace/output/ ./local_output/
```
