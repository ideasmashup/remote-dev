#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# remote-dev.sh — Server-side management script for Remote Dev project containers
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

# ── Configuration (overridable via env vars or .env file) ────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load .env if present
if [ -f "$SCRIPT_DIR/.env" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/.env"
fi

RDEV_DATA_DIR="${RDEV_DATA_DIR:-$SCRIPT_DIR/data/projects}"
RDEV_IMAGE="${RDEV_IMAGE:-rdev-base:latest}"
RDEV_DOCKER="${RDEV_DOCKER:-docker}"
RDEV_DOCKER_CONTEXT="${RDEV_DOCKER_CONTEXT:-}"
RDEV_CONTAINER_PREFIX="rdev"
RDEV_TEMPLATES_DIR="${RDEV_TEMPLATES_DIR:-$SCRIPT_DIR/templates}"

# ── Helpers ──────────────────────────────────────────────────────────────────

# Colors
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m' # No Color

info()    { echo -e "${BLUE}ℹ${NC}  $*"; }
success() { echo -e "${GREEN}✅${NC} $*"; }
warn()    { echo -e "${YELLOW}⚠️${NC}  $*"; }
error()   { echo -e "${RED}❌${NC} $*" >&2; }
header()  { echo -e "\n${BOLD}${CYAN}═══ $* ═══${NC}\n"; }

# Docker command wrapper — injects --context when RDEV_DOCKER_CONTEXT is set
docker_cmd() {
    if [ -n "$RDEV_DOCKER_CONTEXT" ]; then
        $RDEV_DOCKER --context "$RDEV_DOCKER_CONTEXT" "$@"
    else
        $RDEV_DOCKER "$@"
    fi
}

container_name() {
    echo "${RDEV_CONTAINER_PREFIX}-${1}"
}

project_dir() {
    echo "${RDEV_DATA_DIR}/${1}"
}

ensure_data_dir() {
    mkdir -p "$RDEV_DATA_DIR"
}

container_exists() {
    docker_cmd container inspect "$(container_name "$1")" &>/dev/null
}

container_running() {
    local state
    state=$(docker_cmd container inspect -f '{{.State.Running}}' "$(container_name "$1")" 2>/dev/null)
    [ "$state" = "true" ]
}

# ── Commands ─────────────────────────────────────────────────────────────────

cmd_create() {
    local name=""
    local gpu=false
    local git_url=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --gpu)     gpu=true; shift ;;
            --no-gpu)  gpu=false; shift ;;
            --git-url) git_url="$2"; shift 2 ;;
            -*)        error "Unknown option: $1"; usage; exit 1 ;;
            *)         name="$1"; shift ;;
        esac
    done

    if [ -z "$name" ]; then
        error "Project name is required"
        echo "Usage: $0 create <name> [--gpu] [--git-url <url>]"
        exit 1
    fi

    header "Creating project: $name"

    # Check if container already exists
    if container_exists "$name"; then
        error "Project '$name' already exists. Use 'destroy' first or choose a different name."
        exit 1
    fi

    # Create project data directory
    local proj_dir
    proj_dir="$(project_dir "$name")"
    ensure_data_dir
    mkdir -p "$proj_dir"
    info "Created project directory: $proj_dir"

    # Copy template files into the project directory (only if not cloning a repo)
    if [ -z "$git_url" ]; then
        if [ -d "$RDEV_TEMPLATES_DIR" ]; then
            # Copy AGENT.md
            if [ -f "$RDEV_TEMPLATES_DIR/AGENT.md" ]; then
                cp "$RDEV_TEMPLATES_DIR/AGENT.md" "$proj_dir/AGENT.md"
            fi
            # Copy and process README template
            if [ -f "$RDEV_TEMPLATES_DIR/README.md" ]; then
                sed -e "s/{{PROJECT_NAME}}/$name/g" \
                    -e "s/{{DATE}}/$(date +%Y-%m-%d)/g" \
                    "$RDEV_TEMPLATES_DIR/README.md" > "$proj_dir/README.md"
            fi
            info "Copied template files"
        fi
    fi

    # Build docker run arguments
    local cname
    cname="$(container_name "$name")"
    local -a docker_args=(
        "run" "-d"
        "--name" "$cname"
        "--hostname" "$name"
        "-e" "RDEV_PROJECT_NAME=$name"
        "-v" "$proj_dir:/workspace"
        "--restart" "unless-stopped"
    )

    # GPU support
    if [ "$gpu" = true ]; then
        docker_args+=("--gpus" "all")
        info "GPU access enabled"
    fi

    docker_args+=("$RDEV_IMAGE")

    # Create and start the container
    info "Creating container: $cname"
    docker_cmd "${docker_args[@]}"

    # If git URL provided, clone repo inside the container
    if [ -n "$git_url" ]; then
        info "Cloning repository: $git_url"
        # Clone into a temp dir inside workspace, then move contents
        docker_cmd exec "$cname" bash -c "
            cd /workspace
            git clone '$git_url' /tmp/_rdev_clone
            # Move everything (including hidden files) from clone to workspace
            shopt -s dotglob
            mv /tmp/_rdev_clone/* /workspace/ 2>/dev/null || true
            rm -rf /tmp/_rdev_clone
        "
        # Also copy AGENT.md into cloned projects
        if [ -f "$RDEV_TEMPLATES_DIR/AGENT.md" ]; then
            docker_cmd cp "$RDEV_TEMPLATES_DIR/AGENT.md" "$cname:/workspace/AGENT.md"
        fi
        success "Repository cloned into workspace"
    fi

    success "Project '$name' created and running!"
    echo ""
    echo "  Shell into it:   $0 shell $name"
    echo "  Run a command:   $0 exec $name <command>"
    echo "  Project status:  $0 status $name"
}

cmd_destroy() {
    local name=""
    local yes=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --yes|-y) yes=true; shift ;;
            -*)       error "Unknown option: $1"; exit 1 ;;
            *)        name="$1"; shift ;;
        esac
    done

    if [ -z "$name" ]; then
        error "Project name is required"
        echo "Usage: $0 destroy <name> [--yes]"
        exit 1
    fi

    if ! container_exists "$name"; then
        error "Project '$name' does not exist"
        exit 1
    fi

    if [ "$yes" != true ]; then
        echo -n "Are you sure you want to destroy project '$name'? This will remove the container AND all project data. [y/N] "
        read -r confirm
        if [[ "$confirm" != [yY] ]]; then
            info "Cancelled"
            return
        fi
    fi

    header "Destroying project: $name"

    local cname
    cname="$(container_name "$name")"

    # Stop and remove container
    docker_cmd rm -f "$cname" &>/dev/null || true
    success "Container removed"

    # Remove project data
    local proj_dir
    proj_dir="$(project_dir "$name")"
    if [ -d "$proj_dir" ]; then
        rm -rf "$proj_dir"
        success "Project data removed: $proj_dir"
    fi

    success "Project '$name' destroyed"
}

cmd_start() {
    local name="${1:?Project name is required}"

    if ! container_exists "$name"; then
        error "Project '$name' does not exist"
        exit 1
    fi

    if container_running "$name"; then
        warn "Project '$name' is already running"
        return
    fi

    info "Starting project '$name'..."
    docker_cmd start "$(container_name "$name")"
    success "Project '$name' started"
}

cmd_stop() {
    local name="${1:?Project name is required}"

    if ! container_exists "$name"; then
        error "Project '$name' does not exist"
        exit 1
    fi

    if ! container_running "$name"; then
        warn "Project '$name' is not running"
        return
    fi

    info "Stopping project '$name'..."
    docker_cmd stop "$(container_name "$name")"
    success "Project '$name' stopped"
}

cmd_shell() {
    local name="${1:?Project name is required}"

    if ! container_exists "$name"; then
        error "Project '$name' does not exist"
        exit 1
    fi

    if ! container_running "$name"; then
        error "Project '$name' is not running. Start it first with: $0 start $name"
        exit 1
    fi

    info "Opening shell for project '$name'..."
    docker_cmd exec -it "$(container_name "$name")" bash
}

cmd_exec() {
    local name="${1:?Project name is required}"
    shift

    if [ $# -eq 0 ]; then
        error "Command is required"
        echo "Usage: $0 exec <name> <command...>"
        exit 1
    fi

    if ! container_exists "$name"; then
        error "Project '$name' does not exist"
        exit 1
    fi

    if ! container_running "$name"; then
        error "Project '$name' is not running. Start it first with: $0 start $name"
        exit 1
    fi

    docker_cmd exec "$(container_name "$name")" "$@"
}

cmd_list() {
    header "Remote Dev Projects"

    # Get all rdev containers
    local containers
    containers=$(docker_cmd ps -a --filter "name=^${RDEV_CONTAINER_PREFIX}-" --format '{{.Names}}\t{{.Status}}\t{{.State}}' 2>/dev/null)

    if [ -z "$containers" ]; then
        info "No projects found. Create one with: $0 create <name>"
        return
    fi

    printf "${BOLD}%-20s %-10s %s${NC}\n" "PROJECT" "STATE" "STATUS"
    printf "%-20s %-10s %s\n" "───────" "─────" "──────"

    while IFS=$'\t' read -r cname status state; do
        # Strip prefix to get project name
        local pname="${cname#${RDEV_CONTAINER_PREFIX}-}"

        # Color the state
        local state_colored
        if [ "$state" = "running" ]; then
            state_colored="${GREEN}running${NC}"
        else
            state_colored="${YELLOW}stopped${NC}"
        fi

        printf "%-20s ${state_colored}  %s\n" "$pname" "$status"
    done <<< "$containers"
}

cmd_status() {
    local name="${1:?Project name is required}"

    if ! container_exists "$name"; then
        error "Project '$name' does not exist"
        exit 1
    fi

    header "Project Status: $name"

    local cname
    cname="$(container_name "$name")"

    # Container info
    local state
    state=$(docker_cmd container inspect -f '{{.State.Status}}' "$cname")
    local started
    started=$(docker_cmd container inspect -f '{{.State.StartedAt}}' "$cname" 2>/dev/null || echo "N/A")
    local image
    image=$(docker_cmd container inspect -f '{{.Config.Image}}' "$cname")

    echo -e "  ${BOLD}Container:${NC}  $cname"
    echo -e "  ${BOLD}State:${NC}      $state"
    echo -e "  ${BOLD}Started:${NC}    $started"
    echo -e "  ${BOLD}Image:${NC}      $image"

    # Check GPU
    local gpu_flag
    gpu_flag=$(docker_cmd container inspect -f '{{range .HostConfig.DeviceRequests}}{{.Driver}}{{end}}' "$cname" 2>/dev/null)
    if [ -n "$gpu_flag" ]; then
        echo -e "  ${BOLD}GPU:${NC}        ${GREEN}enabled${NC}"
    else
        echo -e "  ${BOLD}GPU:${NC}        ${YELLOW}disabled${NC}"
    fi

    # Project directory
    local proj_dir
    proj_dir="$(project_dir "$name")"
    echo -e "  ${BOLD}Data dir:${NC}   $proj_dir"

    # Disk usage
    if [ -d "$proj_dir" ]; then
        local size
        size=$(du -sh "$proj_dir" 2>/dev/null | cut -f1)
        echo -e "  ${BOLD}Disk:${NC}       $size"
    fi

    # Git status inside container (if running)
    if container_running "$name"; then
        echo ""
        local git_status
        git_status=$(docker_cmd exec "$cname" bash -c "cd /workspace && git status --short 2>/dev/null || echo '(not a git repo)'" 2>/dev/null)
        echo -e "  ${BOLD}Git:${NC}"
        if [ -z "$git_status" ]; then
            echo "    clean (no uncommitted changes)"
        else
            echo "$git_status" | sed 's/^/    /'
        fi
    fi
}

cmd_logs() {
    local name="${1:?Project name is required}"

    if ! container_exists "$name"; then
        error "Project '$name' does not exist"
        exit 1
    fi

    docker_cmd logs "$(container_name "$name")" "${@:2}"
}

cmd_push() {
    local name="${1:?Project name is required}"
    local local_path="${2:?Local path is required}"

    if ! container_exists "$name"; then
        error "Project '$name' does not exist"
        exit 1
    fi

    info "Copying $local_path → container $(container_name "$name"):/workspace/"
    docker_cmd cp "$local_path" "$(container_name "$name"):/workspace/"
    success "Files copied"
}

cmd_pull() {
    local name="${1:?Project name is required}"
    local remote_path="${2:?Remote path is required}"
    local dest="${3:-.}"

    if ! container_exists "$name"; then
        error "Project '$name' does not exist"
        exit 1
    fi

    info "Copying container $(container_name "$name"):$remote_path → $dest"
    docker_cmd cp "$(container_name "$name"):$remote_path" "$dest"
    success "Files copied"
}

cmd_build() {
    header "Building Remote Dev base image"

    local docker_dir="$SCRIPT_DIR/docker"

    if [ ! -f "$docker_dir/Dockerfile" ]; then
        error "Dockerfile not found at $docker_dir/Dockerfile"
        exit 1
    fi

    info "Building image: $RDEV_IMAGE"
    docker_cmd build -t "$RDEV_IMAGE" "$docker_dir"
    success "Image built: $RDEV_IMAGE"
}

# ── Usage ────────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
${BOLD}Remote Dev${NC} — Project container management

${BOLD}Usage:${NC}
  $0 <command> [options]

${BOLD}Commands:${NC}
  ${CYAN}create${NC}  <name> [--gpu] [--git-url <url>]   Create a new project
  ${CYAN}destroy${NC} <name> [--yes]                     Remove project and data
  ${CYAN}start${NC}   <name>                              Start a stopped project
  ${CYAN}stop${NC}    <name>                              Stop a running project
  ${CYAN}shell${NC}   <name>                              Open a shell in the project
  ${CYAN}exec${NC}    <name> <cmd...>                     Run a command in the project
  ${CYAN}list${NC}                                        List all projects
  ${CYAN}status${NC}  <name>                              Show project details
  ${CYAN}logs${NC}    <name>                              Show container logs
  ${CYAN}push${NC}    <name> <local-path>                 Copy files into project
  ${CYAN}pull${NC}    <name> <remote-path> [dest]         Copy files from project
  ${CYAN}build${NC}                                       Build the base Docker image

${BOLD}Configuration:${NC}
  Set these environment variables or use a .env file:
    RDEV_DATA_DIR       Project data directory (default: ./data/projects)
    RDEV_IMAGE          Docker image (default: rdev-base:latest)
    RDEV_DOCKER         Docker binary (default: docker)
    RDEV_DOCKER_CONTEXT Docker context (default: none, e.g. "rootless")

EOF
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
    if [ $# -eq 0 ]; then
        usage
        exit 0
    fi

    local cmd="$1"
    shift

    case "$cmd" in
        create)   cmd_create "$@" ;;
        destroy)  cmd_destroy "$@" ;;
        start)    cmd_start "$@" ;;
        stop)     cmd_stop "$@" ;;
        shell)    cmd_shell "$@" ;;
        exec)     cmd_exec "$@" ;;
        list)     cmd_list ;;
        status)   cmd_status "$@" ;;
        logs)     cmd_logs "$@" ;;
        push)     cmd_push "$@" ;;
        pull)     cmd_pull "$@" ;;
        build)    cmd_build ;;
        help|-h|--help) usage ;;
        *)
            error "Unknown command: $cmd"
            usage
            exit 1
            ;;
    esac
}

main "$@"
