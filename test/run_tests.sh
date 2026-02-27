#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# run_tests.sh — Integration tests for Remote Dev
# ═══════════════════════════════════════════════════════════════════════════════
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RDEV="$PROJECT_DIR/remote-dev.sh"

# ── Test framework ───────────────────────────────────────────────────────────

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

pass() {
    ((TESTS_PASSED++))
    ((TESTS_TOTAL++))
    echo -e "\033[0;32m  ✅ PASS: $1\033[0m"
}

fail() {
    ((TESTS_FAILED++))
    ((TESTS_TOTAL++))
    echo -e "\033[0;31m  ❌ FAIL: $1\033[0m"
    if [ -n "${2:-}" ]; then
        echo -e "\033[0;31m          $2\033[0m"
    fi
}

header() {
    echo ""
    echo -e "\033[1;36m━━━ $1 ━━━\033[0m"
}

# ── Cleanup function ────────────────────────────────────────────────────────

cleanup() {
    header "Cleanup"
    echo "Cleaning up test containers and data..."
    "$RDEV" destroy test-scratch --yes 2>/dev/null || true
    "$RDEV" destroy test-gitclone --yes 2>/dev/null || true
    echo "Done."
}

# Cleanup on exit
trap cleanup EXIT

# ── Pre-flight checks ───────────────────────────────────────────────────────

header "Pre-flight Checks"

# Check Docker is running
if ! docker info &>/dev/null; then
    echo -e "\033[0;31m❌ Docker is not running. Please start Docker Desktop and try again.\033[0m"
    exit 1
fi
pass "Docker is running"

# ── Test 1: Build the base image ────────────────────────────────────────────

header "Test 1: Build Base Image"

if "$RDEV" build; then
    pass "Base image built successfully"
else
    fail "Failed to build base image"
    exit 1  # Can't continue without the image
fi

# ── Test 2: Create a project from scratch ────────────────────────────────────

header "Test 2: Create Project from Scratch"

if "$RDEV" create test-scratch; then
    pass "Project 'test-scratch' created"
else
    fail "Failed to create project 'test-scratch'"
fi

# Verify container is running
if docker ps --format '{{.Names}}' | grep -q 'rdev-test-scratch'; then
    pass "Container 'rdev-test-scratch' is running"
else
    fail "Container 'rdev-test-scratch' is not running"
fi

# ── Test 3: Check template files ─────────────────────────────────────────────

header "Test 3: Template Files"

workspace_files=$("$RDEV" exec test-scratch ls /workspace/)

if echo "$workspace_files" | grep -q "AGENT.md"; then
    pass "AGENT.md exists in workspace"
else
    fail "AGENT.md missing from workspace"
fi

if echo "$workspace_files" | grep -q "README.md"; then
    pass "README.md exists in workspace"
else
    fail "README.md missing from workspace"
fi

# Verify README contains the project name
readme_content=$("$RDEV" exec test-scratch cat /workspace/README.md)
if echo "$readme_content" | grep -q "test-scratch"; then
    pass "README.md contains project name"
else
    fail "README.md does not contain project name"
fi

# ── Test 4: Execute commands inside container ────────────────────────────────

header "Test 4: Command Execution"

# Python check
python_version=$("$RDEV" exec test-scratch python3 --version 2>&1)
if echo "$python_version" | grep -q "Python 3"; then
    pass "Python 3 is available: $python_version"
else
    fail "Python 3 is not available" "$python_version"
fi

# Git check
git_version=$("$RDEV" exec test-scratch git --version 2>&1)
if echo "$git_version" | grep -q "git version"; then
    pass "Git is available: $git_version"
else
    fail "Git is not available" "$git_version"
fi

# ── Test 5: Persistent storage ──────────────────────────────────────────────

header "Test 5: Persistent Storage"

# Create a file
"$RDEV" exec test-scratch bash -c "echo 'persistence test data 12345' > /workspace/persist_test.txt"
pass "Created test file in workspace"

# Stop the container
"$RDEV" stop test-scratch
if ! docker ps --format '{{.Names}}' | grep -q 'rdev-test-scratch'; then
    pass "Container stopped"
else
    fail "Container did not stop"
fi

# Start the container
"$RDEV" start test-scratch

# Small delay to let container fully start
sleep 2

# Verify file still exists
persist_content=$("$RDEV" exec test-scratch cat /workspace/persist_test.txt 2>&1)
if echo "$persist_content" | grep -q "persistence test data 12345"; then
    pass "Data persisted across container restart"
else
    fail "Data did NOT persist across container restart" "$persist_content"
fi

# ── Test 6: Create project from git URL ──────────────────────────────────────

header "Test 6: Clone from Git URL"

if "$RDEV" create test-gitclone --git-url https://github.com/octocat/Hello-World.git; then
    pass "Project 'test-gitclone' created from git URL"
else
    fail "Failed to create project from git URL"
fi

# Verify repo was cloned
clone_files=$("$RDEV" exec test-gitclone ls /workspace/)
if echo "$clone_files" | grep -q "README"; then
    pass "Cloned repository contains README"
else
    fail "Cloned repository missing README"
fi

# Verify AGENT.md was added
if echo "$clone_files" | grep -q "AGENT.md"; then
    pass "AGENT.md was added to cloned project"
else
    fail "AGENT.md missing from cloned project"
fi

# Verify it's a git repo
git_status=$("$RDEV" exec test-gitclone bash -c "cd /workspace && git log --oneline -1" 2>&1)
if [ $? -eq 0 ] && [ -n "$git_status" ]; then
    pass "Git history present in cloned repo"
else
    fail "Git history not found in cloned repo" "$git_status"
fi

# ── Test 7: List projects ───────────────────────────────────────────────────

header "Test 7: List Projects"

list_output=$("$RDEV" list 2>&1)

if echo "$list_output" | grep -q "test-scratch"; then
    pass "'test-scratch' appears in project list"
else
    fail "'test-scratch' missing from project list"
fi

if echo "$list_output" | grep -q "test-gitclone"; then
    pass "'test-gitclone' appears in project list"
else
    fail "'test-gitclone' missing from project list"
fi

# ── Test 8: Project status ──────────────────────────────────────────────────

header "Test 8: Project Status"

status_output=$("$RDEV" status test-scratch 2>&1)

if echo "$status_output" | grep -q "running"; then
    pass "Status shows 'running' state"
else
    fail "Status does not show 'running' state"
fi

if echo "$status_output" | grep -q "rdev-test-scratch"; then
    pass "Status shows container name"
else
    fail "Status does not show container name"
fi

# ── Test 9: Push/pull files ──────────────────────────────────────────────────

header "Test 9: Push/Pull Files"

# Create a test file locally
echo "local test file content" > /tmp/rdev_test_push.txt

# Push it
if "$RDEV" push test-scratch /tmp/rdev_test_push.txt; then
    pass "File pushed to container"
else
    fail "Failed to push file to container"
fi

# Verify it arrived
push_content=$("$RDEV" exec test-scratch cat /workspace/rdev_test_push.txt 2>&1)
if echo "$push_content" | grep -q "local test file content"; then
    pass "Pushed file contains correct content"
else
    fail "Pushed file has wrong content" "$push_content"
fi

# Pull it back
rm -f /tmp/rdev_test_pull.txt
if "$RDEV" pull test-scratch /workspace/rdev_test_push.txt /tmp/rdev_test_pull.txt; then
    pass "File pulled from container"
else
    fail "Failed to pull file from container"
fi

if [ -f /tmp/rdev_test_pull.txt ] && grep -q "local test file content" /tmp/rdev_test_pull.txt; then
    pass "Pulled file contains correct content"
else
    fail "Pulled file has wrong content"
fi

# Cleanup temp files
rm -f /tmp/rdev_test_push.txt /tmp/rdev_test_pull.txt

# ── Test 10: Destroy project ────────────────────────────────────────────────

header "Test 10: Destroy Project"

if "$RDEV" destroy test-scratch --yes; then
    pass "Project 'test-scratch' destroyed"
else
    fail "Failed to destroy project 'test-scratch'"
fi

# Verify container is gone
if ! docker ps -a --format '{{.Names}}' | grep -q 'rdev-test-scratch'; then
    pass "Container removed"
else
    fail "Container still exists after destroy"
fi

# Verify data directory is gone
if [ ! -d "$PROJECT_DIR/data/projects/test-scratch" ]; then
    pass "Project data directory removed"
else
    fail "Project data directory still exists"
fi

# ── Results ──────────────────────────────────────────────────────────────────

echo ""
echo -e "\033[1m═══════════════════════════════════════════\033[0m"
echo -e "\033[1m  Test Results: $TESTS_PASSED/$TESTS_TOTAL passed\033[0m"

if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "\033[0;31m  $TESTS_FAILED test(s) FAILED\033[0m"
    echo -e "\033[1m═══════════════════════════════════════════\033[0m"
    exit 1
else
    echo -e "\033[0;32m  All tests passed! 🎉\033[0m"
    echo -e "\033[1m═══════════════════════════════════════════\033[0m"
    exit 0
fi
