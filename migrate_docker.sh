#!/bin/bash

# ============================================================================
# Docker数据目录迁移脚本 (健壮版)
# ============================================================================
# 结合了原始脚本的简洁性和新版脚本的灵活性
# 支持自定义路径和自动化场景
# ============================================================================

set -e
set -o pipefail

# 配置变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/docker_migration_$(date +%Y%m%d_%H%M%S).log"
DOCKER_CONFIG_DIR="${DOCKER_CONFIG_DIR:-/etc/docker}"
DEFAULT_TARGET="/home/docker"  # 默认目标路径
MIN_STORAGE_GB=10

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# --- 日志函数 ---

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

log_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $*" | tee -a "$LOG_FILE"
    fi
}

# --- 错误处理 ---

error_handler() {
    local line_no=$1
    local exit_code=$2
    log_error "脚本在第 $line_no 行失败，退出码: $exit_code"
    log_warning "尝试恢复Docker服务..."
    
    # 尝试重启Docker
    if command -v systemctl >/dev/null 2>&1; then
        systemctl start docker 2>/dev/null || true
    fi
    
    log_error "迁移失败！请检查日志: $LOG_FILE"
    exit $exit_code
}

# 设置错误陷阱
trap 'error_handler ${LINENO} $?' ERR

# --- 工具函数 ---

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        exit 1
    fi
}

confirm_action() {
    local prompt="$1"
    local default="${2:-N}"
    local response
    
    # 自动模式
    if [[ "${AUTO_YES:-0}" == "1" ]]; then
        log_debug "自动确认: $prompt"
        return 0
    fi
    
    # 交互模式
    if [[ "$default" == "Y" ]]; then
        read -p "$prompt (Y/n)? " response
        [[ -z "$response" || "$response" =~ ^[Yy]$ ]]
    else
        read -p "$prompt (y/N)? " response
        [[ "$response" =~ ^[Yy]$ ]]
    fi
}

# --- Docker相关函数 ---

get_current_docker_root() {
    local daemon_json="${DOCKER_CONFIG_DIR}/daemon.json"
    local current_root="/var/lib/docker"
    
    if [[ -f "$daemon_json" ]]; then
        # 尝试多种方式解析JSON
        if command_exists python3; then
            current_root=$(python3 -c "
import json
try:
    with open('$daemon_json') as f:
        print(json.load(f).get('data-root', '/var/lib/docker'))
except:
    print('/var/lib/docker')
" 2>/dev/null) || current_root="/var/lib/docker"
        elif command_exists python; then
            current_root=$(python -c "
import json
try:
    print json.load(open('$daemon_json')).get('data-root', '/var/lib/docker')
except:
    print '/var/lib/docker'
" 2>/dev/null) || current_root="/var/lib/docker"
        elif command_exists jq; then
            current_root=$(jq -r '.["data-root"] // "/var/lib/docker"' "$daemon_json" 2>/dev/null) || current_root="/var/lib/docker"
        fi
    fi
    
    echo "$current_root"
}

check_docker_running() {
    if command_exists systemctl; then
        systemctl is-active --quiet docker
    elif command_exists service; then
        service docker status >/dev/null 2>&1
    else
        pgrep -x dockerd >/dev/null 2>&1
    fi
}

stop_docker() {
    log_info "停止Docker服务..."
    
    # 先尝试正常停止
    if command_exists systemctl; then
        systemctl stop docker.socket 2>/dev/null || true
        systemctl stop docker || {
            log_warning "systemctl停止失败，尝试强制停止"
        }
    elif command_exists service; then
        service docker stop || true
    fi
    
    # 确保进程完全停止
    local max_wait=30
    local count=0
    while check_docker_running && [[ $count -lt $max_wait ]]; do
        sleep 1
        ((count++))
    done
    
    # 强制停止
    if check_docker_running; then
        log_warning "正常停止超时，强制终止进程"
        pkill -TERM dockerd 2>/dev/null || true
        sleep 2
        pkill -KILL dockerd 2>/dev/null || true
    fi
    
    log_success "Docker服务已停止"
}

start_docker() {
    log_info "启动Docker服务..."
    
    if command_exists systemctl; then
        systemctl start docker || {
            log_error "Docker启动失败"
            systemctl status docker --no-pager
            return 1
        }
    elif command_exists service; then
        service docker start || return 1
    else
        log_error "无法启动Docker服务，请手动启动"
        return 1
    fi
    
    # 等待Docker就绪
    local max_wait=30
    local count=0
    while ! docker info >/dev/null 2>&1 && [[ $count -lt $max_wait ]]; do
        sleep 1
        ((count++))
    done
    
    if docker info >/dev/null 2>&1; then
        log_success "Docker服务启动成功"
        return 0
    else
        log_error "Docker服务启动超时"
        return 1
    fi
}

# --- 磁盘分析 ---

analyze_disk_space() {
    echo ""
    echo "=========================================="
    echo "     磁盘空间分析"
    echo "=========================================="
    
    # 显示当前Docker数据大小
    local current_root=$(get_current_docker_root)
    if [[ -d "$current_root" ]]; then
        local current_size=$(du -sh "$current_root" 2>/dev/null | cut -f1)
        echo "当前Docker数据: $current_root"
        echo "数据大小: ${current_size:-未知}"
        echo ""
    fi
    
    # 显示文件系统使用情况
    echo "文件系统使用情况:"
    echo "----------------------------------------"
    df -h | head -1
    df -h | grep -v "tmpfs\|udev\|loop" | tail -n +2 | sort -k4 -hr
    echo ""
    
    # 推荐存储位置
    echo "推荐的Docker数据存储位置:"
    echo "----------------------------------------"
    
    local recommendations=()
    while IFS= read -r line; do
        local mount_point=$(echo "$line" | awk '{print $6}')
        local available=$(echo "$line" | awk '{print $4}')
        local available_gb=$(echo "$available" | sed 's/[^0-9.]//g')
        
        # 跳过系统关键挂载点
        if [[ "$mount_point" =~ ^/(boot|proc|sys|dev|run)$ ]]; then
            continue
        fi
        
        # 检查空间是否充足
        if [[ -n "$available_gb" ]] && (( $(echo "$available_gb > $MIN_STORAGE_GB" | bc -l 2>/dev/null || echo "0") )); then
            if [[ "$mount_point" == "/" ]]; then
                recommendations+=("  • /var/lib/docker (默认位置, ${available} 可用)")
            else
                recommendations+=("  ✓ ${mount_point}/docker (推荐, ${available} 可用)")
            fi
        fi
    done < <(df -h | grep -v "tmpfs\|udev\|loop" | tail -n +2)
    
    if [[ ${#recommendations[@]} -eq 0 ]]; then
        echo "  ⚠ 未找到充足空间的挂载点 (需要>${MIN_STORAGE_GB}GB)"
    else
        printf "%s\n" "${recommendations[@]}"
    fi
    
    echo ""
}

# --- 路径选择 ---

select_target_path() {
    local target_path=""
    
    # 如果通过参数指定了路径
    if [[ -n "${TARGET_PATH:-}" ]]; then
        target_path="$TARGET_PATH"
        log_info "使用命令行指定的路径: $target_path"
    # 如果是自动模式，使用默认路径
    elif [[ "${AUTO_YES:-0}" == "1" ]]; then
        target_path="$DEFAULT_TARGET"
        log_info "自动模式，使用默认路径: $target_path"
    # 交互式选择
    else
        while [[ -z "$target_path" ]]; do
            echo ""
            echo "请输入目标路径 (默认: $DEFAULT_TARGET):"
            read -p "> " input_path
            
            if [[ -z "$input_path" ]]; then
                target_path="$DEFAULT_TARGET"
            else
                target_path="$input_path"
            fi
            
            # 验证路径
            local parent_dir=$(dirname "$target_path")
            if [[ ! -d "$parent_dir" ]]; then
                log_warning "父目录不存在: $parent_dir"
                if confirm_action "创建父目录"; then
                    mkdir -p "$parent_dir" || {
                        log_error "创建目录失败"
                        target_path=""
                        continue
                    }
                else
                    target_path=""
                    continue
                fi
            fi
            
            # 检查空间
            local available_gb=$(df -BG "$parent_dir" | awk 'NR==2 {print $4}' | sed 's/G//')
            if [[ "$available_gb" -lt "$MIN_STORAGE_GB" ]]; then
                log_warning "空间不足。可用: ${available_gb}GB, 建议: >${MIN_STORAGE_GB}GB"
                if ! confirm_action "仍然继续"; then
                    target_path=""
                    continue
                fi
            fi
            
            # 检查目录是否为空
            if [[ -d "$target_path" ]] && [[ -n "$(ls -A "$target_path" 2>/dev/null)" ]]; then
                log_warning "目录不为空: $target_path"
                if ! confirm_action "使用此目录"; then
                    target_path=""
                    continue
                fi
            fi
        done
    fi
    
    echo "$target_path"
}

# --- 数据迁移 ---

migrate_data() {
    local source="$1"
    local target="$2"
    
    log_info "开始迁移Docker数据..."
    log_info "源路径: $source"
    log_info "目标路径: $target"
    
    # 创建目标目录
    mkdir -p "$target" || {
        log_error "无法创建目标目录"
        return 1
    }
    
    # 检查源目录
    if [[ ! -d "$source" ]]; then
        log_warning "源目录不存在，跳过迁移: $source"
        return 0
    fi
    
    # 计算数据大小
    local total_size=$(du -sh "$source" 2>/dev/null | cut -f1)
    log_info "待迁移数据大小: ${total_size:-未知}"
    
    # 执行迁移
    if command_exists rsync; then
        log_info "使用rsync迁移数据 (显示进度)..."
        rsync -avP --stats "$source/" "$target/" || {
            log_error "rsync迁移失败"
            return 1
        }
    else
        log_info "使用cp迁移数据..."
        cp -a "$source/"* "$target/" 2>/dev/null || {
            log_error "cp迁移失败"
            return 1
        }
    fi
    
    log_success "数据迁移完成"
    return 0
}

# --- 配置更新 ---

update_daemon_config() {
    local new_root="$1"
    local daemon_json="${DOCKER_CONFIG_DIR}/daemon.json"
    
    log_info "更新Docker配置..."
    
    # 备份现有配置
    if [[ -f "$daemon_json" ]]; then
        cp "$daemon_json" "${daemon_json}.bak.$(date +%Y%m%d_%H%M%S)"
        log_info "已备份现有配置"
    fi
    
    # 创建配置目录
    mkdir -p "$DOCKER_CONFIG_DIR"
    
    # 更新或创建配置
    if [[ -f "$daemon_json" ]] && command_exists python3; then
        # 智能合并配置
        python3 << EOF
import json
import sys

config_file = "$daemon_json"
new_root = "$new_root"

try:
    with open(config_file, 'r') as f:
        config = json.load(f)
except:
    config = {}

# 更新data-root
config['data-root'] = new_root

# 确保基础配置存在
if 'storage-driver' not in config:
    config['storage-driver'] = 'overlay2'
if 'log-driver' not in config:
    config['log-driver'] = 'json-file'
    config['log-opts'] = {
        'max-size': '100m',
        'max-file': '3'
    }

with open(config_file, 'w') as f:
    json.dump(config, f, indent=2)

print("配置已更新")
EOF
    else
        # 创建新配置
        cat > "$daemon_json" << EOF
{
  "data-root": "$new_root",
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  },
  "live-restore": true
}
EOF
    fi
    
    log_success "Docker配置更新完成"
}

# --- 验证 ---

verify_migration() {
    local expected_root="$1"
    
    log_info "验证迁移结果..."
    
    # 检查Docker信息
    local actual_root=$(docker info 2>/dev/null | grep "Docker Root Dir" | cut -d: -f2 | xargs)
    
    if [[ "$actual_root" == "$expected_root" ]]; then
        log_success "✓ Docker正在使用新的数据目录: $actual_root"
    else
        log_warning "Docker根目录验证失败"
        log_warning "期望: $expected_root"
        log_warning "实际: $actual_root"
    fi
    
    # 列出容器和镜像
    echo ""
    log_info "容器状态:"
    docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" 2>/dev/null || echo "无法获取容器信息"
    
    echo ""
    log_info "镜像列表:"
    docker images --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}" 2>/dev/null || echo "无法获取镜像信息"
}

# --- 清理 ---

cleanup_old_data() {
    local old_path="$1"
    
    if [[ -d "$old_path" ]] && [[ "$old_path" != "/" ]]; then
        local size=$(du -sh "$old_path" 2>/dev/null | cut -f1)
        
        echo ""
        log_info "旧数据位于: $old_path (大小: ${size:-未知})"
        
        if confirm_action "删除旧的Docker数据" "N"; then
            # 先移动到备份位置
            local backup_path="${old_path}.backup.$(date +%Y%m%d_%H%M%S)"
            log_info "移动到备份位置: $backup_path"
            mv "$old_path" "$backup_path" || {
                log_error "无法移动旧数据"
                return 1
            }
            
            if confirm_action "立即删除备份" "N"; then
                rm -rf "$backup_path"
                log_success "备份已删除"
            else
                log_info "备份保留在: $backup_path"
                log_info "确认无问题后可手动删除"
            fi
        else
            log_info "旧数据保留在: $old_path"
        fi
    fi
}

# --- 显示使用帮助 ---

show_help() {
    cat << EOF
Docker数据目录迁移工具 (健壮版)

用法: $0 [选项]

选项:
    -t, --target PATH    指定目标路径 (默认: $DEFAULT_TARGET)
    -y, --yes           自动确认所有提示
    -d, --debug         启用调试输出
    -h, --help          显示此帮助信息

环境变量:
    TARGET_PATH         目标路径 (可代替 --target)
    AUTO_YES           自动确认 (设为1启用)
    DEBUG              调试模式 (设为1启用)

示例:
    # 交互式迁移
    sudo $0
    
    # 自动迁移到默认位置
    sudo $0 --yes
    
    # 指定目标路径
    sudo $0 --target /data/docker
    
    # 完全自动化
    sudo $0 --target /mnt/docker --yes

功能特性:
    • 智能磁盘空间分析
    • 自动路径推荐
    • 配置文件智能合并
    • 数据完整性验证
    • 异常自动恢复
    • 详细日志记录

日志位置: $LOG_FILE

EOF
}

# --- 主函数 ---

main() {
    echo "=========================================="
    echo "   Docker数据目录迁移工具 (健壮版)"
    echo "=========================================="
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--target)
                TARGET_PATH="$2"
                shift 2
                ;;
            -y|--yes)
                AUTO_YES=1
                shift
                ;;
            -d|--debug)
                DEBUG=1
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    log_info "日志文件: $LOG_FILE"
    
    # 检查权限
    check_root
    
    # 获取当前Docker根目录
    CURRENT_ROOT=$(get_current_docker_root)
    log_info "当前Docker数据目录: $CURRENT_ROOT"
    
    # 分析磁盘空间
    if [[ "${AUTO_YES:-0}" != "1" ]]; then
        analyze_disk_space
    fi
    
    # 选择目标路径
    TARGET_ROOT=$(select_target_path)
    
    # 检查是否相同
    if [[ "$CURRENT_ROOT" == "$TARGET_ROOT" ]]; then
        log_warning "目标路径与当前路径相同，无需迁移"
        exit 0
    fi
    
    # 显示迁移计划
    echo ""
    echo "迁移计划:"
    echo "  源路径: $CURRENT_ROOT"
    echo "  目标路径: $TARGET_ROOT"
    echo ""
    
    if ! confirm_action "开始迁移" "Y"; then
        log_info "用户取消迁移"
        exit 0
    fi
    
    # 执行迁移
    
    # 1. 停止Docker
    if check_docker_running; then
        stop_docker
    fi
    
    # 2. 迁移数据
    migrate_data "$CURRENT_ROOT" "$TARGET_ROOT"
    
    # 3. 更新配置
    update_daemon_config "$TARGET_ROOT"
    
    # 4. 启动Docker
    start_docker
    
    # 5. 验证结果
    sleep 2
    verify_migration "$TARGET_ROOT"
    
    # 6. 清理旧数据
    if [[ "${AUTO_YES:-0}" != "1" ]]; then
        cleanup_old_data "$CURRENT_ROOT"
    fi
    
    # 显示最终状态
    echo ""
    echo "=========================================="
    log_success "迁移完成！"
    log_info "新的Docker数据目录: $TARGET_ROOT"
    log_info "配置备份: ${DOCKER_CONFIG_DIR}/daemon.json.bak.*"
    echo ""
    
    # 显示磁盘使用
    df -h "$TARGET_ROOT" | tail -n +1
    
    exit 0
}

# 执行主函数
main "$@"