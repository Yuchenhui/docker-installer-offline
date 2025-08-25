#!/bin/bash

# ============================================================================
# Docker & Docker Compose Offline Installation Script (Robust Version)
# ============================================================================
# Author: Enhanced Installation Script
# Description: Robust offline installation of Docker and Docker Compose
#              with OS detection, error handling, and rollback support
# ============================================================================

set -e  # Exit on error
set -o pipefail  # Exit on pipe failure

# --- Configuration Variables ---
SCRIPT_VERSION="2.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/install_$(date +%Y%m%d_%H%M%S).log"
DOCKER_TGZ="${SCRIPT_DIR}/docker.tgz"
DOCKER_COMPOSE_BIN="${SCRIPT_DIR}/docker-compose"

# Default paths (can be overridden)
DOCKER_BIN_DIR="${DOCKER_BIN_DIR:-/usr/local/bin}"
DOCKER_LINK_DIR="${DOCKER_LINK_DIR:-/usr/bin}"
SYSTEMD_DIR="${SYSTEMD_DIR:-/etc/systemd/system}"
DOCKER_DATA_DIR="${DOCKER_DATA_DIR:-/var/lib/docker}"
DOCKER_CONFIG_DIR="${DOCKER_CONFIG_DIR:-/etc/docker}"

# Storage configuration
DOCKER_CUSTOM_DATA_ROOT=""
DOCKER_STORAGE_DRIVER="${DOCKER_STORAGE_DRIVER:-overlay2}"
MIN_STORAGE_GB=10  # Minimum required storage in GB

# Installation flags
DOCKER_COMPOSE_INSTALLED=false

# Service files
DOCKER_SERVICE_FILE="${SCRIPT_DIR}/docker.service"
CONTAINERD_SERVICE_FILE="${SCRIPT_DIR}/containerd.service"
DOCKER_SOCKET_FILE="${SCRIPT_DIR}/docker.socket"

# Removed STATE_FILE - not needed for simple installation

# OS Detection Variables
OS_TYPE=""
OS_VERSION=""
INIT_SYSTEM=""
KERNEL_VERSION=""
ARCH=""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# --- Logging Functions ---

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE" >&2
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*" | tee -a "$LOG_FILE" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$LOG_FILE" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE" >&2
}

log_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $*" | tee -a "$LOG_FILE" >&2
    fi
}

# --- Utility Functions ---

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

confirm_action() {
    local prompt="$1"
    local response
    
    if [[ "${FORCE_YES:-0}" == "1" ]]; then
        log_debug "Auto-confirming: $prompt"
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

check_existing_installation() {
    local docker_installed=false
    
    # Check if Docker is already installed
    if command_exists docker; then
        local docker_version
        docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
        log_info "Existing Docker installation detected (version: $docker_version) - performing overwrite installation"
        docker_installed=true
    fi
    
    # Check if Docker Compose is installed
    if command_exists docker-compose; then
        local compose_version
        compose_version=$(docker-compose version --short 2>/dev/null || echo "unknown")
        log_info "Existing Docker Compose installation detected (version: $compose_version) - will be overwritten"
    fi
    
    # If Docker is installed, stop existing services for clean overwrite
    if [[ "$docker_installed" == "true" ]]; then
        log_info "Stopping existing Docker services for overwrite installation..."
        if command_exists systemctl; then
            systemctl stop docker 2>/dev/null || true
            systemctl stop docker.socket 2>/dev/null || true
            systemctl stop containerd 2>/dev/null || true
        elif command_exists service; then
            service docker stop 2>/dev/null || true
        fi
    fi
}

# Removed save_state and load_state functions - not needed

cleanup_on_error() {
    log_error "Installation failed. Starting cleanup..."
    
    # Stop services if they were started
    if command_exists systemctl; then
        systemctl stop docker 2>/dev/null || true
        systemctl stop docker.socket 2>/dev/null || true
        systemctl stop containerd 2>/dev/null || true
        systemctl disable docker 2>/dev/null || true
        systemctl disable docker.socket 2>/dev/null || true
        systemctl disable containerd 2>/dev/null || true
        systemctl daemon-reload 2>/dev/null || true
    elif command_exists service; then
        service docker stop 2>/dev/null || true
    fi
    
    # Remove partially installed service files
    local service_files=("/etc/systemd/system/docker.service" "/etc/systemd/system/containerd.service" "/etc/systemd/system/docker.socket")
    for service_file in "${service_files[@]}"; do
        if [[ -f "$service_file" ]] && [[ ! -f "${service_file}.orig" ]]; then
            log_debug "Removing partially installed $(basename "$service_file")"
            rm -f "$service_file"
        fi
    done
    
    # Clean up extracted files
    if [[ -d "docker" ]]; then
        log_debug "Cleaning up extracted files..."
        rm -rf "docker"
    fi
    
    # Clean up temporary files
    if [[ -n "${TEMP_SERVICE_DIR:-}" ]] && [[ -d "$TEMP_SERVICE_DIR" ]]; then
        log_debug "Cleaning up temporary service files..."
        rm -rf "$TEMP_SERVICE_DIR"
    fi
    
    log_info "Cleanup completed. Check log file: $LOG_FILE"
    log_warning "You may need to manually verify system state after cleanup"
    exit 1
}

trap cleanup_on_error ERR

# --- OS Detection Functions ---

detect_os() {
    log_info "Detecting operating system..."
    
    # Detect OS type
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_TYPE="${ID}"
        OS_VERSION="${VERSION_ID}"
        log_info "Detected OS: ${NAME} ${VERSION}"
    elif [[ -f /etc/redhat-release ]]; then
        OS_TYPE="rhel"
        OS_VERSION=$(rpm -q --qf "%{VERSION}" redhat-release 2>/dev/null || echo "unknown")
    elif [[ -f /etc/debian_version ]]; then
        OS_TYPE="debian"
        OS_VERSION=$(cat /etc/debian_version)
    else
        log_warning "Could not detect OS type, assuming generic Linux"
        OS_TYPE="linux"
        OS_VERSION="unknown"
    fi
    
    # Detect architecture
    ARCH=$(uname -m)
    if [[ "$ARCH" != "x86_64" ]]; then
        log_error "This script is designed for x86_64 architecture. Detected: $ARCH"
        exit 1
    fi
    
    # Detect kernel version
    KERNEL_VERSION=$(uname -r)
    log_info "Kernel version: $KERNEL_VERSION"
    
    # Detect init system
    if command_exists systemctl; then
        INIT_SYSTEM="systemd"
        log_info "Init system: systemd"
    elif command_exists service; then
        if [[ -d /etc/init.d ]]; then
            INIT_SYSTEM="sysvinit"
            log_info "Init system: SysV init"
        else
            INIT_SYSTEM="upstart"
            log_info "Init system: Upstart"
        fi
    else
        log_warning "Could not detect init system"
        INIT_SYSTEM="unknown"
    fi
    
    # OS detection completed
}

# --- Prerequisite Check Functions ---

check_kernel_version() {
    local min_kernel="3.10"
    local current_kernel
    
    current_kernel=$(uname -r | cut -d'-' -f1)
    
    if [[ "$(printf '%s\n' "$min_kernel" "$current_kernel" | sort -V | head -n1)" != "$min_kernel" ]]; then
        log_error "Kernel version $current_kernel is too old. Minimum required: $min_kernel"
        return 1
    fi
    
    log_info "Kernel version check passed: $current_kernel"
    return 0
}

check_kernel_modules() {
    log_info "Checking required kernel modules..."
    
    local required_modules=(
        "overlay"
        "br_netfilter"
    )
    
    local optional_modules=(
        "nf_nat"
        "xt_conntrack"
        "ip_vs"
        "ip_vs_rr"
        "ip_vs_wrr"
        "ip_vs_sh"
    )
    
    for module in "${required_modules[@]}"; do
        if ! lsmod | grep -q "^$module" && ! modprobe -n "$module" 2>/dev/null; then
            log_error "Required kernel module '$module' is not available"
            return 1
        fi
        log_debug "Kernel module '$module' is available"
    done
    
    for module in "${optional_modules[@]}"; do
        if ! lsmod | grep -q "^$module" && ! modprobe -n "$module" 2>/dev/null; then
            log_warning "Optional kernel module '$module' is not available"
        else
            log_debug "Optional kernel module '$module' is available"
        fi
    done
    
    # Try to load required modules
    for module in "${required_modules[@]}"; do
        modprobe "$module" 2>/dev/null || true
    done
    
    log_success "Kernel modules check completed"
    return 0
}

check_cgroups() {
    log_info "Checking cgroup support..."
    
    if [[ ! -d /sys/fs/cgroup ]]; then
        log_error "Cgroups are not mounted at /sys/fs/cgroup"
        return 1
    fi
    
    # Check for cgroup v1 or v2
    if [[ -f /sys/fs/cgroup/cgroup.controllers ]]; then
        log_info "Cgroup v2 detected"
    elif [[ -d /sys/fs/cgroup/memory ]] && [[ -d /sys/fs/cgroup/cpu ]]; then
        log_info "Cgroup v1 detected"
    else
        log_warning "Unusual cgroup configuration detected"
    fi
    
    log_success "Cgroup support check passed"
    return 0
}

check_storage_driver() {
    log_info "Checking storage driver support..."
    
    # Check for overlay2 support (preferred)
    if grep -q overlay /proc/filesystems; then
        log_info "Overlay filesystem is supported (recommended)"
        return 0
    fi
    
    # Check for devicemapper as fallback
    if [[ -e /dev/mapper/control ]]; then
        log_warning "Overlay not available, devicemapper will be used"
        return 0
    fi
    
    # Check for vfs as last resort (slower but works everywhere)
    log_warning "Neither overlay nor devicemapper available"
    log_warning "VFS storage driver will be used (slower performance)"
    log_info "Docker will work but with reduced performance"
    return 0
}

check_network_tools() {
    log_info "Checking network tools..."
    
    # Check for iptables
    if ! command_exists iptables; then
        log_warning "iptables is not installed. Docker networking will be limited."
        log_warning "Without iptables:"
        log_warning "  - Port mapping (-p) won't work"
        log_warning "  - Bridge networking won't work"
        log_warning "  - Containers must use --network host"
        log_info "To install iptables later:"
        log_info "  RHEL/CentOS: sudo yum install iptables"
        log_info "  Ubuntu/Debian: sudo apt-get install iptables"
        log_info "  SUSE: sudo zypper install iptables"
        
        # Ask user if they want to continue without iptables
        if confirm_action "Continue installation without iptables (limited networking)"; then
            log_info "Continuing without iptables - Docker will be configured for limited networking"
            # Set flag to configure Docker without iptables
            DOCKER_NO_IPTABLES=true
        else
            log_error "Installation cancelled. Please install iptables first."
            return 1
        fi
    else
        log_success "iptables found"
        DOCKER_NO_IPTABLES=false
    fi
    
    # Check for ip command
    if ! command_exists ip; then
        log_warning "ip command not found. Installing iproute2 is recommended."
    fi
    
    log_success "Network tools check completed"
    return 0
}

check_disk_space() {
    log_info "Checking disk space..."
    
    local required_space=2048  # MB
    local docker_dir_parent
    
    # Use custom data root if set, otherwise use default
    local check_dir="${DOCKER_CUSTOM_DATA_ROOT:-$DOCKER_DATA_DIR}"
    docker_dir_parent=$(dirname "$check_dir")
    
    local available_space
    available_space=$(df -m "$docker_dir_parent" | awk 'NR==2 {print $4}')
    
    if [[ $available_space -lt $required_space ]]; then
        log_error "Insufficient disk space. Required: ${required_space}MB, Available: ${available_space}MB"
        return 1
    fi
    
    log_info "Disk space check passed. Available: ${available_space}MB"
    return 0
}

analyze_disk_usage() {
    log_info "Analyzing disk usage..."
    
    echo ""
    echo "=========================================="
    echo "     Disk Space Analysis"
    echo "=========================================="
    echo ""
    
    # Show filesystem usage
    df -h | head -1
    df -h | grep -v "tmpfs\|udev\|loop" | tail -n +2 | sort -k4 -hr
    
    echo ""
    echo "Recommended locations for Docker data:"
    echo "----------------------------------------"
    
    # Find suitable mount points with enough space
    local suitable_found=false
    while IFS= read -r line; do
        local mount_point=$(echo "$line" | awk '{print $6}')
        local available_gb=$(echo "$line" | awk '{print $4}' | sed 's/G//')
        
        # Skip system critical mount points
        if [[ "$mount_point" == "/" ]] || [[ "$mount_point" == "/boot" ]] || \
           [[ "$mount_point" == "/proc" ]] || [[ "$mount_point" == "/sys" ]] || \
           [[ "$mount_point" == "/dev" ]]; then
            continue
        fi
        
        # Check if it's a number (ends with G)
        if [[ "$available_gb" =~ ^[0-9]+$ ]] || [[ "$available_gb" =~ ^[0-9]+\.[0-9]+$ ]]; then
            if (( $(echo "$available_gb > $MIN_STORAGE_GB" | bc -l 2>/dev/null || echo "0") )); then
                echo "  ✓ $mount_point/docker (${available_gb}GB available)"
                suitable_found=true
            fi
        fi
    done < <(df -h | grep -v "tmpfs\|udev\|loop" | tail -n +2)
    
    # Always show default location
    local default_available=$(df -h /var | tail -1 | awk '{print $4}')
    echo "  • /var/lib/docker (default, ${default_available} available)"
    
    if [[ "$suitable_found" == "false" ]]; then
        log_warning "No additional suitable mount points found with >${MIN_STORAGE_GB}GB free space"
    fi
    
    echo ""
}

select_docker_data_directory() {
    log_info "Configuring Docker data directory..."
    
    # Analyze current disk usage
    analyze_disk_usage
    
    echo "Docker images, containers, and volumes can consume significant disk space."
    echo "The default location is /var/lib/docker"
    echo ""
    
    read -p "自定义 Docker 数据目录 (直接回车使用默认 /var/lib/docker): " custom_path
    
    if [[ -z "$custom_path" ]]; then
        log_info "Using default Docker data directory: /var/lib/docker"
        return 0
    fi
    
    # Validate the custom path
    local path_valid=false
    while [[ "$path_valid" == "false" ]]; do
        # Check if parent directory exists
        local parent_dir=$(dirname "$custom_path")
        if [[ ! -d "$parent_dir" ]]; then
            log_warning "Parent directory does not exist: $parent_dir"
            mkdir -p "$parent_dir" || {
                log_error "Failed to create parent directory"
                read -p "请重新输入路径: " custom_path
                continue
            }
        fi
            
        # Check available space
        local available_space_gb=$(df -BG "$parent_dir" | awk 'NR==2 {print $4}' | sed 's/G//')
        if [[ "$available_space_gb" -lt "$MIN_STORAGE_GB" ]]; then
            log_warning "Available space: ${available_space_gb}GB, Recommended: >${MIN_STORAGE_GB}GB"
        fi
        
        # Check if directory exists and has content
        if [[ -d "$custom_path" ]] && [[ -n "$(ls -A "$custom_path" 2>/dev/null)" ]]; then
            log_warning "Directory exists and is not empty: $custom_path"
        fi
        
        DOCKER_CUSTOM_DATA_ROOT="$custom_path"
        path_valid=true
        log_success "Docker data directory set to: $custom_path"
    done
}

check_existing_docker_data() {
    log_info "Checking for existing Docker data..."
    
    if [[ -d "/var/lib/docker" ]] && [[ -n "$(ls -A /var/lib/docker 2>/dev/null)" ]]; then
        local size=$(du -sh /var/lib/docker 2>/dev/null | cut -f1)
        log_warning "Existing Docker data found at /var/lib/docker (Size: ${size:-unknown})"
        
        if [[ -n "$DOCKER_CUSTOM_DATA_ROOT" ]] && [[ "$DOCKER_CUSTOM_DATA_ROOT" != "/var/lib/docker" ]]; then
            echo ""
            echo "Options for existing Docker data:"
            echo "1. Migrate existing data to new location (recommended)"
            echo "2. Start fresh (existing data will remain at /var/lib/docker)"
            echo "3. Cancel and use default location"
            echo ""
            
            local choice
            read -p "Choose an option (1-3): " choice
            
            case "$choice" in
                1)
                    migrate_docker_data
                    ;;
                2)
                    log_info "Starting fresh at new location. Old data remains at /var/lib/docker"
                    ;;
                3)
                    log_info "Cancelled. Using default location /var/lib/docker"
                    DOCKER_CUSTOM_DATA_ROOT=""
                    ;;
                *)
                    log_warning "Invalid choice. Starting fresh at new location"
                    ;;
            esac
        fi
    fi
}

migrate_docker_data() {
    log_info "Migrating Docker data to $DOCKER_CUSTOM_DATA_ROOT..."
    
    # Stop Docker if running
    if command_exists systemctl && systemctl is-active docker >/dev/null 2>&1; then
        log_info "Stopping Docker service for migration..."
        systemctl stop docker || {
            log_error "Failed to stop Docker service"
            return 1
        }
    elif command_exists service && service docker status >/dev/null 2>&1; then
        log_info "Stopping Docker service for migration..."
        service docker stop || {
            log_error "Failed to stop Docker service"
            return 1
        }
    fi
    
    # Create target directory
    mkdir -p "$DOCKER_CUSTOM_DATA_ROOT" || {
        log_error "Failed to create target directory"
        return 1
    }
    
    # Copy data with rsync if available, otherwise use cp
    if command_exists rsync; then
        log_info "Migrating data using rsync..."
        rsync -avP /var/lib/docker/ "$DOCKER_CUSTOM_DATA_ROOT/" || {
            log_error "Failed to migrate data"
            return 1
        }
    else
        log_info "Migrating data using cp..."
        cp -a /var/lib/docker/* "$DOCKER_CUSTOM_DATA_ROOT/" || {
            log_error "Failed to migrate data"
            return 1
        }
    fi
    
    # Backup old directory
    if confirm_action "Backup old Docker directory to /var/lib/docker.backup"; then
        mv /var/lib/docker /var/lib/docker.backup.$(date +%Y%m%d_%H%M%S) || {
            log_warning "Failed to backup old directory"
        }
    fi
    
    log_success "Docker data migration completed"
}

run_prerequisite_checks() {
    log_info "Running prerequisite checks..."
    
    local checks_passed=true
    
    check_kernel_version || checks_passed=false
    check_kernel_modules || checks_passed=false
    check_cgroups || checks_passed=false
    check_storage_driver || checks_passed=false
    check_network_tools || checks_passed=false
    check_disk_space || checks_passed=false
    
    if [[ "$checks_passed" == "false" ]]; then
        log_error "Prerequisite checks failed"
        
        if ! confirm_action "Some checks failed. Continue anyway"; then
            exit 1
        fi
        
        log_warning "Continuing despite failed checks (user override)"
    else
        log_success "All prerequisite checks passed"
    fi
}

# --- Installation Functions ---

extract_docker_binaries() {
    log_info "Extracting Docker binaries..."
    
    if [[ ! -f "$DOCKER_TGZ" ]]; then
        log_error "Docker archive not found: $DOCKER_TGZ"
        return 1
    fi
    
    # Extract directly to current directory
    log_debug "Extracting to current directory"
    tar -xzf "$DOCKER_TGZ" || {
        log_error "Failed to extract Docker archive"
        return 1
    }
    
    # Check if extraction created docker directory
    if [[ ! -d "docker" ]]; then
        log_error "Docker directory not found after extraction"
        return 1
    fi
    
    log_success "Docker binaries extracted successfully"
    return 0
}

install_docker_binaries() {
    log_info "Installing Docker binaries to $DOCKER_BIN_DIR..."
    
    # Create directory if it doesn't exist
    mkdir -p "$DOCKER_BIN_DIR"
    
    # List of expected binaries
    local binaries=(
        "docker"
        "dockerd"
        "docker-proxy"
        "docker-init"
        "ctr"
        "runc"
        "containerd"
        "containerd-shim-runc-v2"
    )
    
    # Copy binaries from docker directory
    local installed_count=0
    for binary in "${binaries[@]}"; do
        local src="docker/${binary}"
        local dst="${DOCKER_BIN_DIR}/${binary}"
        
        if [[ -f "$src" ]]; then
            if cp -f "$src" "$dst" && chmod +x "$dst"; then
                log_debug "Installed: $binary"
                ((installed_count++))
            else
                log_error "Failed to copy or set permissions for $binary"
                return 1
            fi
        else
            log_warning "Binary not found: $binary"
        fi
    done
    
    if [[ $installed_count -eq 0 ]]; then
        log_error "No Docker binaries were installed. Please check the archive file."
        return 1
    fi
    
    log_success "Docker binaries installed ($installed_count/${#binaries[@]})"
}

create_symlinks() {
    log_info "Creating symlinks..."
    
    # Create link directory if it doesn't exist
    mkdir -p "$DOCKER_LINK_DIR"
    
    local binaries=(
        "docker"
        "dockerd"
        "docker-proxy"
        "docker-init"
        "ctr"
        "runc"
        "containerd"
        "containerd-shim-runc-v2"
    )
    
    for binary in "${binaries[@]}"; do
        local src="${DOCKER_BIN_DIR}/${binary}"
        local dst="${DOCKER_LINK_DIR}/${binary}"
        
        if [[ -f "$src" ]]; then
            # Remove existing link or file if it exists
            if [[ -L "$dst" ]] || [[ -f "$dst" ]]; then
                log_debug "Removing existing file/link: $dst"
                rm -f "$dst"
            fi
            
            ln -s "$src" "$dst" || {
                log_warning "Failed to create symlink for $binary"
            }
# Symlink created
            log_debug "Created symlink: $dst -> $src"
        fi
    done
    
    log_success "Symlinks created"
}

create_docker_socket() {
    log_info "Creating docker.socket file..."
    
    cat > "${DOCKER_SOCKET_FILE}" << 'EOF'
[Unit]
Description=Docker Socket for the API

[Socket]
ListenStream=/run/docker.sock
SocketMode=0660
SocketUser=root
SocketGroup=docker

[Install]
WantedBy=sockets.target
EOF
    
    log_success "docker.socket file created"
}

configure_docker_socket() {
    log_info "Configuring Docker Socket activation..."
    
    # Output user interface to stderr so it doesn't interfere with return value
    {
        echo ""
        echo "=========================================="
        echo "     Docker Socket 激活配置"
        echo "=========================================="
        echo ""
        echo "Docker Socket 可以让 Docker 按需启动，而不是始终运行："
        echo ""
        echo "  传统模式 (systemctl enable docker):"
        echo "    • Docker 开机自动启动并持续运行"
        echo "    • 始终占用内存（约 50-100MB）"
        echo "    • 适合生产环境和频繁使用场景"
        echo ""
        echo "  Socket 激活模式 (systemctl enable docker.socket):"
        echo "    • Docker 不会自动启动，首次使用时才启动"
        echo "    • 节省内存资源，适合开发环境"
        echo "    • 执行 docker 命令时自动唤醒服务"
        echo ""
    } >&2
    
    local use_socket=false
    if confirm_action "是否启用 Docker Socket 激活（推荐用于开发环境）"; then
        use_socket=true
        log_info "将配置 Docker Socket 激活模式"
    else
        log_info "将使用传统启动模式（Docker 始终运行）"
    fi
    
    # Return only the socket configuration value
    echo "$use_socket"
}

install_systemd_services() {
    if [[ "$INIT_SYSTEM" != "systemd" ]]; then
        log_warning "Systemd not detected, skipping service installation"
        echo "false"  # Return socket configuration
        return 0
    fi
    
    log_info "Installing systemd service files..."
    
    # Ask about socket activation
    local use_socket=$(configure_docker_socket)
    
    # Create docker.socket if it doesn't exist
    if [[ ! -f "$DOCKER_SOCKET_FILE" ]]; then
        create_docker_socket
    fi
    
    # Update service files with correct paths
    update_service_files "$use_socket"
    
    # Prepare service files list
    local services=(
        "docker.service:$DOCKER_SERVICE_FILE"
        "containerd.service:$CONTAINERD_SERVICE_FILE"
    )
    
    # Add socket file if user wants it
    if [[ "$use_socket" == "true" ]]; then
        services+=("docker.socket:$DOCKER_SOCKET_FILE")
    fi
    
    # Copy service files
    for service_spec in "${services[@]}"; do
        IFS=':' read -r service_name service_file <<< "$service_spec"
        
        if [[ -f "$service_file" ]]; then
            cp -f "$service_file" "${SYSTEMD_DIR}/${service_name}" || {
                log_error "Failed to copy $service_name"
                echo "false"  # Return socket configuration on error
                return 1
            }
            chmod 644 "${SYSTEMD_DIR}/${service_name}"
            log_debug "Installed service: $service_name"
        else
            log_warning "Service file not found: $service_file"
        fi
    done
    
    # Reload systemd
    systemctl daemon-reload || {
        log_error "Failed to reload systemd"
        echo "false"  # Return socket configuration on error
        return 1
    }
    
    log_success "Systemd services installed"
    
    # Return socket configuration for start_services function
    echo "$use_socket"
}

update_service_files() {
    log_info "Updating service files with correct paths..."
    
    # Create temporary updated service files
    local temp_docker_service="${SCRIPT_DIR}/docker.service.tmp"
    local temp_containerd_service="${SCRIPT_DIR}/containerd.service.tmp"
    local use_socket="${1:-false}"
    
    # Escape the path for sed - replace / with \/
    local escaped_bin_dir="${DOCKER_BIN_DIR//\//\\/}"
    
    # Update docker.service
    if [[ -f "$DOCKER_SERVICE_FILE" ]]; then
        # First update the binary path (handle both /usr/bin and /usr/local/bin)
        sed -e "s|/usr/bin/dockerd|${escaped_bin_dir}/dockerd|g" \
            -e "s|/usr/local/bin/dockerd|${escaped_bin_dir}/dockerd|g" \
            "$DOCKER_SERVICE_FILE" > "$temp_docker_service" || {
            log_error "Failed to update docker.service"
            return 1
        }
        
        # If not using socket mode, remove socket dependency and change ExecStart
        if [[ "$use_socket" != "true" ]]; then
            sed -i '/^Requires=docker.socket/d' "$temp_docker_service" || {
                log_error "Failed to remove socket dependency"
                return 1
            }
            # Change ExecStart to not use socket activation
            sed -i 's|-H fd://|--host=unix:///var/run/docker.sock|g' "$temp_docker_service" || {
                log_error "Failed to update ExecStart"
                return 1
            }
        fi
        
        mv "$temp_docker_service" "$DOCKER_SERVICE_FILE" || {
            log_error "Failed to replace docker.service"
            return 1
        }
        log_debug "Updated docker.service with path: ${DOCKER_BIN_DIR}/dockerd, socket mode: $use_socket"
    fi
    
    # Update containerd.service
    if [[ -f "$CONTAINERD_SERVICE_FILE" ]]; then
        sed "s|/usr/local/bin/containerd|${escaped_bin_dir}/containerd|g" "$CONTAINERD_SERVICE_FILE" > "$temp_containerd_service" || {
            log_error "Failed to update containerd.service"
            return 1
        }
        mv "$temp_containerd_service" "$CONTAINERD_SERVICE_FILE" || {
            log_error "Failed to replace containerd.service"
            return 1
        }
        log_debug "Updated containerd.service with path: ${DOCKER_BIN_DIR}/containerd"
    fi
}

create_docker_group() {
    log_info "Creating docker group..."
    
    if getent group docker >/dev/null 2>&1; then
        log_info "Docker group already exists"
    else
        groupadd docker || {
            log_error "Failed to create docker group"
            return 1
        }
        log_success "Docker group created"
    fi
    
    # Add current user to docker group if not root
    if [[ -n "${SUDO_USER}" ]] && [[ "${SUDO_USER}" != "root" ]]; then
        if confirm_action "Add user '${SUDO_USER}' to docker group"; then
            usermod -aG docker "${SUDO_USER}" || {
                log_warning "Failed to add user to docker group"
            }
            log_info "User '${SUDO_USER}' added to docker group"
            log_warning "User needs to log out and back in for group changes to take effect"
        fi
    fi
}

configure_docker() {
    log_info "Configuring Docker..."
    
    # Create docker config directory
    mkdir -p "$DOCKER_CONFIG_DIR"
    
    # Create daemon.json with sensible defaults
    local daemon_json="${DOCKER_CONFIG_DIR}/daemon.json"
    
    if [[ -f "$daemon_json" ]]; then
        log_info "Docker daemon.json already exists, backing up..."
        cp "$daemon_json" "${daemon_json}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Build daemon.json content based on configuration
    local daemon_content="{
  \"storage-driver\": \"${DOCKER_STORAGE_DRIVER}\","
    
    # Add iptables configuration if needed
    if [[ "${DOCKER_NO_IPTABLES:-false}" == "true" ]]; then
        daemon_content="${daemon_content}
  \"iptables\": false,
  \"bridge\": \"none\","
        log_warning "Configuring Docker without iptables - networking will be limited"
    fi
    
    # Add custom data-root if specified
    if [[ -n "$DOCKER_CUSTOM_DATA_ROOT" ]]; then
        daemon_content="${daemon_content}
  \"data-root\": \"${DOCKER_CUSTOM_DATA_ROOT}\","
        log_info "Configuring Docker to use custom data directory: $DOCKER_CUSTOM_DATA_ROOT"
    fi
    
    # Add the rest of the configuration
    daemon_content="${daemon_content}
  \"log-driver\": \"json-file\",
  \"log-opts\": {
    \"max-size\": \"100m\",
    \"max-file\": \"3\"
  },
  \"live-restore\": true,
  \"userland-proxy\": false,
  \"max-concurrent-downloads\": 3,
  \"max-concurrent-uploads\": 5,
  \"default-ulimits\": {
    \"nofile\": {
      \"Name\": \"nofile\",
      \"Hard\": 64000,
      \"Soft\": 64000
    }
  }
}"
    
    echo "$daemon_content" > "$daemon_json"
    
    # Pretty print the configuration for confirmation
    log_info "Docker daemon.json configuration:"
    if command_exists python3; then
        python3 -m json.tool "$daemon_json" 2>/dev/null || cat "$daemon_json"
    elif command_exists python; then
        python -m json.tool "$daemon_json" 2>/dev/null || cat "$daemon_json"
    else
        cat "$daemon_json"
    fi
    
# Docker configured
    log_success "Docker configured"
}

start_services() {
    local use_socket="$1"
    
    if [[ "$INIT_SYSTEM" != "systemd" ]]; then
        log_warning "Non-systemd init system detected. Please start Docker manually."
        return 0
    fi
    
    log_info "Starting Docker services..."
    
    # Enable and start containerd
    systemctl enable containerd || {
        log_error "Failed to enable containerd"
        return 1
    }
    systemctl start containerd || {
        log_error "Failed to start containerd"
        systemctl status containerd --no-pager
        return 1
    }
    log_success "Containerd service started"
    
    if [[ "$use_socket" == "true" ]]; then
        # Socket activation mode
        log_info "Configuring Socket activation mode..."
        
        # Enable and start docker socket (but NOT docker service)
        systemctl enable docker.socket || {
            log_error "Failed to enable docker.socket"
            return 1
        }
        systemctl start docker.socket || {
            log_error "Failed to start docker.socket"
            systemctl status docker.socket --no-pager
            return 1
        }
        
        # Don't enable docker service for auto-start
        log_info "Docker will start on-demand via socket activation"
        log_info "First docker command will activate the service"
        
        # Test socket activation
        log_info "Testing socket activation..."
        docker version --format '{{.Server.Version}}' >/dev/null 2>&1 || {
            log_warning "Socket activation test failed, starting Docker manually"
            systemctl start docker
        }
    else
        # Traditional mode - Docker always running
        log_info "Configuring traditional startup mode..."
        
        # Enable and start docker service
        systemctl enable docker || {
            log_error "Failed to enable docker"
            return 1
        }
        systemctl start docker || {
            log_error "Failed to start docker"
            systemctl status docker --no-pager
            return 1
        }
        log_success "Docker service started and enabled for auto-start"
    fi
}

install_docker_compose() {
    echo ""
    echo "Docker Compose 是用于定义和运行多容器 Docker 应用程序的工具"
    read -p "是否安装 Docker Compose? (Y/n): " install_compose
    
    # Default to yes if empty
    if [[ -z "$install_compose" ]] || [[ "$install_compose" =~ ^[Yy]$ ]]; then
        log_info "Installing Docker Compose..."
        
        if [[ ! -f "$DOCKER_COMPOSE_BIN" ]]; then
            log_warning "Docker Compose binary not found at: $DOCKER_COMPOSE_BIN"
            log_info "Skipping Docker Compose installation"
            return 0
        fi
        
        # Copy docker-compose to bin directory
        cp -f "$DOCKER_COMPOSE_BIN" "${DOCKER_BIN_DIR}/docker-compose" || {
            log_error "Failed to copy docker-compose"
            return 1
        }
        
        chmod +x "${DOCKER_BIN_DIR}/docker-compose"
        
        # Create symlink
        ln -sf "${DOCKER_BIN_DIR}/docker-compose" "${DOCKER_LINK_DIR}/docker-compose" || {
            log_warning "Failed to create docker-compose symlink"
        }
        
        log_success "Docker Compose installed"
        # Set flag for verification
        DOCKER_COMPOSE_INSTALLED=true
    else
        log_info "Skipping Docker Compose installation"
        DOCKER_COMPOSE_INSTALLED=false
    fi
}

verify_installation() {
    log_info "Verifying installation..."
    echo ""
    echo "=========================================="
    echo "     Installation Verification"
    echo "=========================================="
    
    local all_good=true
    
    # Verify Docker installation
    echo ""
    log_info "Testing Docker..."
    if command_exists docker; then
        echo "Docker 版本信息:"
        docker version 2>/dev/null || {
            log_error "Docker daemon is not running or not accessible"
            all_good=false
        }
    else
        log_error "Docker command not found"
        all_good=false
    fi
    
    # Verify Docker Compose if it was installed
    if [[ "${DOCKER_COMPOSE_INSTALLED:-false}" == "true" ]]; then
        echo ""
        log_info "Testing Docker Compose..."
        if command_exists docker-compose; then
            echo "Docker Compose 版本信息:"
            docker-compose version 2>/dev/null || {
                log_warning "Docker Compose command failed"
            }
        else
            log_warning "Docker Compose command not found"
        fi
    fi
    
    echo ""
    echo "=========================================="
    
    if [[ "$all_good" == "true" ]]; then
        log_success "Installation verification passed"
        return 0
    else
        log_error "Installation verification failed"
        return 1
    fi
}

# --- Main Installation Flow ---

main() {
    log_info "Docker Offline Installation Script v${SCRIPT_VERSION}"
    log_info "Log file: $LOG_FILE"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force-yes|-y)
                FORCE_YES=1
                shift
                ;;
            --debug)
                DEBUG=1
                shift
                ;;
            --skip-checks)
                SKIP_CHECKS=1
                shift
                ;;
            --data-root)
                if [[ -n "$2" ]] && [[ "$2" != --* ]]; then
                    DOCKER_CUSTOM_DATA_ROOT="$2"
                    log_info "Docker data directory set via command line: $2"
                    shift 2
                else
                    log_error "--data-root requires a directory path"
                    exit 1
                fi
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
    
    # Check for existing installation
    check_existing_installation
    
    # Detect OS
    detect_os
    
    # Run prerequisite checks
    if [[ "${SKIP_CHECKS:-0}" != "1" ]]; then
        run_prerequisite_checks
    else
        log_warning "Skipping prerequisite checks (--skip-checks)"
    fi
    
    # Select Docker data directory
    select_docker_data_directory
    
    # Check for existing Docker data and handle migration if needed
    check_existing_docker_data
    
    log_info "开始安装 Docker..."
    
    # Extract Docker binaries
    extract_docker_binaries || {
        log_error "Failed to extract Docker binaries"
        exit 1
    }
    
    # Install Docker binaries
    install_docker_binaries || {
        log_error "Failed to install Docker binaries"
        exit 1
    }
    
    # Create symlinks
    create_symlinks || {
        log_error "Failed to create symlinks"
        exit 1
    }
    
    # Create docker group
    create_docker_group
    
    # Configure Docker
    configure_docker
    
    # Install systemd services and get socket configuration
    local use_socket
    use_socket=$(install_systemd_services)
    
    # Start services
    start_services "$use_socket"
    
    # Install Docker Compose
    install_docker_compose
    
    # Verify installation
    verify_installation
    
    # Cleanup extracted files
    if [[ -d "docker" ]]; then
        log_debug "Cleaning up extracted files..."
        rm -rf "docker"
    fi
    
    log_success "=== Docker installation completed successfully ==="
    log_info "Installation log saved to: $LOG_FILE"
    
    echo ""
    log_info "安装完成！以下是验证结果："
    
    if [[ -n "${SUDO_USER}" ]] && [[ "${SUDO_USER}" != "root" ]]; then
        log_warning "Remember to log out and back in for docker group membership to take effect"
    fi
}

show_help() {
    cat << EOF
Docker Offline Installation Script v${SCRIPT_VERSION}

Usage: $0 [OPTIONS]

OPTIONS:
    --force-yes, -y         Automatically answer yes to all prompts
    --debug                 Enable debug output
    --skip-checks           Skip prerequisite checks
    --data-root PATH        Specify custom Docker data directory
    --help, -h              Show this help message

ENVIRONMENT VARIABLES:
    DOCKER_BIN_DIR          Directory for Docker binaries (default: /usr/local/bin)
    DOCKER_LINK_DIR         Directory for symlinks (default: /usr/bin)
    DOCKER_DATA_DIR         Docker data directory (default: /var/lib/docker)
    DOCKER_CONFIG_DIR       Docker config directory (default: /etc/docker)
    DOCKER_STORAGE_DRIVER   Storage driver (default: overlay2)

STORAGE CONFIGURATION:
    The script will analyze available disk space and suggest suitable locations
    for Docker data storage. You can:
    
    1. Use interactive mode to select a directory during installation
    2. Specify a directory via --data-root command line option
    3. Set DOCKER_CUSTOM_DATA_ROOT environment variable

EXAMPLES:
    # Standard installation with interactive directory selection
    sudo ./install_robust.sh
    
    # Automatic installation with custom data directory
    sudo ./install_robust.sh --force-yes --data-root /data/docker
    
    # Debug mode with custom paths
    sudo DOCKER_BIN_DIR=/opt/docker/bin ./install_robust.sh --debug
    
    # Skip directory selection (use default /var/lib/docker)
    sudo ./install_robust.sh --force-yes

NOTES:
    - The script will detect existing Docker installations and offer migration
    - Minimum recommended storage: ${MIN_STORAGE_GB}GB
    - Use --debug for detailed output and troubleshooting

EOF
}

# Run main function
main "$@"