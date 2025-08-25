#!/bin/bash

# ============================================================================
# Docker & Docker Compose Uninstallation Script
# ============================================================================
# Author: Docker Uninstall Script
# Description: Safely uninstall Docker and Docker Compose with cleanup
# ============================================================================

set -e
set -o pipefail

# --- Configuration Variables ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/uninstall_$(date +%Y%m%d_%H%M%S).log"
STATE_FILE="${SCRIPT_DIR}/.install_state"

# Default paths (can be overridden)
DOCKER_BIN_DIR="${DOCKER_BIN_DIR:-/usr/local/bin}"
DOCKER_LINK_DIR="${DOCKER_LINK_DIR:-/usr/bin}"
SYSTEMD_DIR="${SYSTEMD_DIR:-/etc/systemd/system}"
DOCKER_DATA_DIR="${DOCKER_DATA_DIR:-/var/lib/docker}"
DOCKER_CONFIG_DIR="${DOCKER_CONFIG_DIR:-/etc/docker}"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- Logging Functions ---

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE"
}

# --- Utility Functions ---

confirm_action() {
    local prompt="$1"
    local response
    
    if [[ "${FORCE_YES:-0}" == "1" ]]; then
        return 0
    fi
    
    read -p "$prompt (y/N)? " response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root or with sudo privileges"
        exit 1
    fi
}

load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        log_info "Loading installation state from: $STATE_FILE"
        source "$STATE_FILE"
        return 0
    else
        log_warning "No installation state file found. Will use default paths."
        return 1
    fi
}

# --- Service Management Functions ---

stop_services() {
    log_info "Stopping Docker services..."
    
    # Check if systemctl exists
    if command -v systemctl >/dev/null 2>&1; then
        # Stop docker service
        if systemctl is-active docker >/dev/null 2>&1; then
            systemctl stop docker || log_warning "Failed to stop docker service"
            log_info "Docker service stopped"
        else
            log_info "Docker service is not running"
        fi
        
        # Stop docker socket
        if systemctl is-active docker.socket >/dev/null 2>&1; then
            systemctl stop docker.socket || log_warning "Failed to stop docker socket"
            log_info "Docker socket stopped"
        else
            log_info "Docker socket is not running"
        fi
        
        # Stop containerd service
        if systemctl is-active containerd >/dev/null 2>&1; then
            systemctl stop containerd || log_warning "Failed to stop containerd service"
            log_info "Containerd service stopped"
        else
            log_info "Containerd service is not running"
        fi
    else
        log_warning "Systemctl not found. Please stop Docker services manually."
    fi
    
    # Kill any remaining docker processes
    if pgrep -x dockerd >/dev/null; then
        log_warning "Docker daemon still running, attempting to kill..."
        pkill -TERM dockerd || true
        sleep 2
        pkill -KILL dockerd 2>/dev/null || true
    fi
    
    if pgrep -x containerd >/dev/null; then
        log_warning "Containerd still running, attempting to kill..."
        pkill -TERM containerd || true
        sleep 2
        pkill -KILL containerd 2>/dev/null || true
    fi
}

disable_services() {
    log_info "Disabling Docker services..."
    
    if command -v systemctl >/dev/null 2>&1; then
        systemctl disable docker 2>/dev/null || true
        systemctl disable docker.socket 2>/dev/null || true
        systemctl disable containerd 2>/dev/null || true
        
        log_info "Services disabled"
    fi
}

remove_service_files() {
    log_info "Removing service files..."
    
    local services=(
        "docker.service"
        "docker.socket"
        "containerd.service"
    )
    
    for service in "${services[@]}"; do
        local service_file="${SYSTEMD_DIR}/${service}"
        if [[ -f "$service_file" ]]; then
            rm -f "$service_file"
            log_info "Removed: $service_file"
        fi
    done
    
    # Reload systemd if available
    if command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload
        log_info "Systemd configuration reloaded"
    fi
}

# --- Cleanup Functions ---

remove_binaries() {
    log_info "Removing Docker binaries..."
    
    local binaries=(
        "docker"
        "dockerd"
        "docker-proxy"
        "docker-init"
        "ctr"
        "runc"
        "containerd"
        "containerd-shim-runc-v2"
        "docker-compose"
    )
    
    # Remove from bin directory
    for binary in "${binaries[@]}"; do
        local bin_path="${DOCKER_BIN_DIR}/${binary}"
        if [[ -f "$bin_path" ]]; then
            rm -f "$bin_path"
            log_info "Removed binary: $bin_path"
        fi
    done
}

remove_symlinks() {
    log_info "Removing symlinks..."
    
    local binaries=(
        "docker"
        "dockerd"
        "docker-proxy"
        "docker-init"
        "ctr"
        "runc"
        "containerd"
        "containerd-shim-runc-v2"
        "docker-compose"
    )
    
    for binary in "${binaries[@]}"; do
        local link_path="${DOCKER_LINK_DIR}/${binary}"
        if [[ -L "$link_path" ]]; then
            rm -f "$link_path"
            log_info "Removed symlink: $link_path"
        fi
    done
}

remove_docker_group() {
    log_info "Checking Docker group..."
    
    if getent group docker >/dev/null 2>&1; then
        if confirm_action "Remove docker group"; then
            # Check if any users are in the group
            local users_in_group
            users_in_group=$(getent group docker | cut -d: -f4)
            
            if [[ -n "$users_in_group" ]]; then
                log_warning "The following users are in the docker group: $users_in_group"
                log_warning "They will lose docker access after group removal"
            fi
            
            groupdel docker || log_warning "Failed to remove docker group"
            log_info "Docker group removed"
        else
            log_info "Docker group kept"
        fi
    else
        log_info "Docker group does not exist"
    fi
}

remove_docker_data() {
    log_info "Checking Docker data..."
    
    if [[ -d "$DOCKER_DATA_DIR" ]]; then
        local data_size
        data_size=$(du -sh "$DOCKER_DATA_DIR" 2>/dev/null | cut -f1)
        log_warning "Docker data directory exists at: $DOCKER_DATA_DIR (Size: ${data_size:-unknown})"
        
        if confirm_action "Remove Docker data directory (THIS WILL DELETE ALL CONTAINERS, IMAGES, AND VOLUMES!)"; then
            rm -rf "$DOCKER_DATA_DIR"
            log_info "Docker data directory removed"
        else
            log_info "Docker data directory kept"
        fi
    else
        log_info "Docker data directory does not exist"
    fi
}

remove_docker_config() {
    log_info "Checking Docker configuration..."
    
    if [[ -d "$DOCKER_CONFIG_DIR" ]]; then
        if confirm_action "Remove Docker configuration directory"; then
            # Backup daemon.json if it exists
            if [[ -f "${DOCKER_CONFIG_DIR}/daemon.json" ]]; then
                cp "${DOCKER_CONFIG_DIR}/daemon.json" "${SCRIPT_DIR}/daemon.json.backup.$(date +%Y%m%d_%H%M%S)"
                log_info "Backed up daemon.json"
            fi
            
            rm -rf "$DOCKER_CONFIG_DIR"
            log_info "Docker configuration directory removed"
        else
            log_info "Docker configuration directory kept"
        fi
    else
        log_info "Docker configuration directory does not exist"
    fi
}

remove_state_file() {
    if [[ -f "$STATE_FILE" ]]; then
        rm -f "$STATE_FILE"
        log_info "Installation state file removed"
    fi
}

cleanup_misc() {
    log_info "Performing miscellaneous cleanup..."
    
    # Remove docker network interfaces
    for interface in $(ip link show | grep -o 'docker[0-9]*' | sort -u); do
        ip link delete "$interface" 2>/dev/null || true
        log_info "Removed network interface: $interface"
    done
    
    # Remove docker iptables rules (if any)
    if command -v iptables >/dev/null 2>&1; then
        iptables -t nat -F DOCKER 2>/dev/null || true
        iptables -t filter -F DOCKER 2>/dev/null || true
        iptables -t filter -F DOCKER-ISOLATION-STAGE-1 2>/dev/null || true
        iptables -t filter -F DOCKER-ISOLATION-STAGE-2 2>/dev/null || true
        iptables -t filter -F DOCKER-USER 2>/dev/null || true
        log_info "Cleaned up iptables rules"
    fi
}

# --- Main Uninstallation Flow ---

main() {
    log_info "Docker Uninstallation Script"
    log_info "Log file: $LOG_FILE"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force-yes|-y)
                FORCE_YES=1
                shift
                ;;
            --purge)
                PURGE=1
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Check root privileges
    check_root
    
    # Load installation state if available
    load_state
    
    log_warning "This will uninstall Docker and Docker Compose from your system"
    
    if [[ "${PURGE:-0}" == "1" ]]; then
        log_warning "PURGE mode: Will also remove all Docker data, images, containers, and volumes!"
    fi
    
    if ! confirm_action "Proceed with uninstallation"; then
        log_info "Uninstallation cancelled by user"
        exit 0
    fi
    
    # Stop services
    stop_services
    
    # Disable services
    disable_services
    
    # Remove service files
    remove_service_files
    
    # Remove symlinks
    remove_symlinks
    
    # Remove binaries
    remove_binaries
    
    # Remove docker group
    remove_docker_group
    
    # Remove docker config
    remove_docker_config
    
    # Remove docker data (if purge mode)
    if [[ "${PURGE:-0}" == "1" ]]; then
        remove_docker_data
    else
        if [[ -d "$DOCKER_DATA_DIR" ]]; then
            log_info "Docker data directory preserved at: $DOCKER_DATA_DIR"
            log_info "Use --purge flag to remove it"
        fi
    fi
    
    # Cleanup miscellaneous
    cleanup_misc
    
    # Remove state file
    remove_state_file
    
    log_success "=== Docker uninstallation completed ==="
    log_info "Uninstallation log saved to: $LOG_FILE"
    
    # Check if reboot is recommended
    if [[ -d "/var/lib/docker" ]] || [[ -d "/run/docker" ]]; then
        log_warning "Some Docker directories still exist. A system reboot is recommended."
    fi
}

show_help() {
    cat << EOF
Docker Uninstallation Script

Usage: $0 [OPTIONS]

OPTIONS:
    --force-yes, -y     Automatically answer yes to all prompts
    --purge             Remove all Docker data, images, containers, and volumes
    --help, -h          Show this help message

ENVIRONMENT VARIABLES:
    DOCKER_BIN_DIR      Directory containing Docker binaries (default: /usr/local/bin)
    DOCKER_LINK_DIR     Directory containing symlinks (default: /usr/bin)
    DOCKER_DATA_DIR     Docker data directory (default: /var/lib/docker)
    DOCKER_CONFIG_DIR   Docker config directory (default: /etc/docker)

EXAMPLES:
    # Standard uninstallation (keeps data)
    sudo ./uninstall.sh
    
    # Complete removal including all data
    sudo ./uninstall.sh --purge
    
    # Automatic yes to all prompts
    sudo ./uninstall.sh --force-yes --purge

WARNING:
    Using --purge will permanently delete all Docker containers, images, and volumes!

EOF
}

# Run main function
main "$@"