#!/bin/bash
set -e

# ── Remote Dev Container Entrypoint ──

# Configure git defaults if not already set
if [ -z "$(git config --global user.name 2>/dev/null)" ]; then
    git config --global user.name "dev"
    git config --global user.email "dev@remote-dev"
fi

# Allow git operations on /workspace even if owned by different user
git config --global --add safe.directory /workspace

# Activate virtualenv if it exists
if [ -f /workspace/.venv/bin/activate ]; then
    echo "🐍 Activating virtualenv at /workspace/.venv"
    source /workspace/.venv/bin/activate
fi

echo "🚀 Remote Dev container ready — project: ${RDEV_PROJECT_NAME:-unknown}"
echo "   Workspace: /workspace"
echo "   Python:    $(python3 --version 2>&1)"
echo "   Git:       $(git --version 2>&1)"

# Keep container alive — allows docker exec to attach
exec tail -f /dev/null
