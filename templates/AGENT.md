# Agent Instructions

You are working inside a **Remote Dev project container** on a shared Linux server.

## Environment

- **OS:** Ubuntu 22.04 (inside Docker container)
- **Workspace:** `/workspace` — all project files live here
- **Python:** Python 3.10+ with pip and venv available
- **Git:** Pre-configured, safe directory set for `/workspace`
- **GPU:** Check with `nvidia-smi` (if available)

## Rules

1. **Stay in /workspace.** All code, data, and configs go in `/workspace`.
2. **Use virtualenvs.** Create with `python3 -m venv .venv` and activate before installing packages.
3. **Commit often.** Use git to version your work inside the container.
4. **Don't modify system files** outside `/workspace` unless absolutely necessary.
5. **Long-running processes:** Use `tmux` for processes that should survive shell disconnects.

## Quick Reference

```bash
# Create and activate a virtualenv
python3 -m venv .venv && source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Check GPU availability
python3 -c "import torch; print(torch.cuda.is_available())"

# Run a script
python3 main.py
```
