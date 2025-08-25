# Docker 离线安装完整指南

适用于无互联网连接环境的 Docker 和 Docker Compose 完整离线安装解决方案。

## 📦 安装包内容

| 文件 | 版本 | 说明 |
|------|------|------|
| docker-28.2.2.tgz | 28.2.2 | Docker Engine 二进制文件包 |
| docker-compose | 最新版 | Docker Compose 二进制文件 |
| docker.service | - | Docker systemd 服务文件 |
| containerd.service | - | Containerd systemd 服务文件 |
| docker.socket | - | Docker socket 文件 |
| install.sh | 2.0 | 智能安装脚本（推荐） |
| migrate_docker.sh | 1.0 | Docker数据迁移工具 |
| uninstall.sh | 1.0 | 卸载脚本 |

---

# 方式一：自动脚本安装（推荐）

## 📋 前置准备

### 系统要求
- **架构**: Linux x86_64
- **内核**: ≥ 3.10
- **权限**: root 或 sudo
- **空间**: 建议 10GB+
- **Init**: systemd（推荐）

### 支持的发行版
- Ubuntu 18.04+
- Debian 9+
- CentOS 7+
- RHEL 7+
- Fedora 30+
- openSUSE Leap 15+

### 文件清单
确保以下文件都在同一目录下：
- `install.sh` - 主安装脚本
- `docker-28.2.2.tgz` - Docker二进制文件包
- `docker-compose` - Docker Compose二进制文件
- `docker.service` - Docker systemd服务文件
- `containerd.service` - Containerd systemd服务文件
- `docker.socket` - Docker socket文件

## 🚀 快速安装

### 1. 基础安装（交互式）

```bash
# 添加执行权限
chmod +x install.sh

# 运行安装脚本
sudo ./install.sh
```

脚本将会：
- 检测操作系统和环境
- 分析磁盘空间并推荐存储位置
- 询问是否自定义Docker数据目录
- 执行安装并启动服务

### 2. 自动安装（无交互）

```bash
# 使用默认配置自动安装
sudo ./install.sh --force-yes

# 指定自定义数据目录自动安装
sudo ./install.sh --force-yes --data-root /data/docker
```

### 3. 命令行参数

```bash
--force-yes, -y    # 自动确认所有提示
--data-root PATH   # 指定Docker数据目录
--debug           # 启用调试输出
--skip-checks     # 跳过系统检查（不推荐）
--help, -h        # 显示帮助信息

# 示例：组合使用多个选项
sudo ./install.sh --force-yes --data-root /mnt/docker --debug
```

## 💾 存储配置

### 交互式存储选择

运行脚本时，会显示磁盘分析：

```
==========================================
     Disk Space Analysis
==========================================

文件系统     容量  已用  可用  使用% 挂载点
/dev/sda2    100G  20G   80G   20%  /
/dev/sdb1    500G  10G  490G    2%  /data

推荐的Docker数据存储位置:
----------------------------------------
  ✓ /data/docker (推荐, 490GB 可用)
  • /var/lib/docker (默认, 80GB 可用)
```

### 命令行指定存储

```bash
# 直接指定数据目录
sudo ./install.sh --data-root /data/docker

# 使用环境变量
sudo DOCKER_CUSTOM_DATA_ROOT=/mnt/docker ./install.sh
```

### 迁移现有数据

如果检测到现有Docker数据，脚本会自动覆盖安装。用户只需：
1. 确认安装路径
2. 确认是否安装Docker Compose

## 🔧 环境变量配置

可通过环境变量自定义安装路径：

```bash
# 自定义二进制文件路径
sudo DOCKER_BIN_DIR=/opt/docker/bin ./install.sh

# 完整自定义示例
sudo DOCKER_BIN_DIR=/opt/docker/bin \
     DOCKER_LINK_DIR=/usr/local/bin \
     DOCKER_DATA_DIR=/data/docker \
     DOCKER_CONFIG_DIR=/etc/docker \
     ./install.sh
```

### 支持的环境变量

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| DOCKER_BIN_DIR | /usr/local/bin | Docker二进制文件目录 |
| DOCKER_LINK_DIR | /usr/bin | 符号链接目录 |
| DOCKER_DATA_DIR | /var/lib/docker | Docker数据目录 |
| DOCKER_CONFIG_DIR | /etc/docker | Docker配置目录 |
| DOCKER_STORAGE_DRIVER | overlay2 | 存储驱动 |

## 📝 安装流程详解

### 第一阶段：环境检测
1. 检测操作系统类型和版本
2. 验证系统架构（x86_64）
3. 检查init系统（systemd/sysvinit/upstart）

### 第二阶段：先决条件检查
1. **内核版本** - 确保 ≥ 3.10
2. **内核模块** - overlay、br_netfilter等
3. **Cgroup支持** - v1或v2
4. **存储驱动** - overlay2、devicemapper或vfs
5. **磁盘空间** - 至少2GB可用

### 第三阶段：存储配置
1. 分析磁盘使用情况
2. 推荐合适的存储位置
3. 选择或创建数据目录
4. 处理现有数据迁移

### 第四阶段：安装Docker
1. 解压Docker二进制文件
2. 复制到目标目录
3. 创建符号链接
4. 配置systemd服务

### 第五阶段：配置和启动
1. 创建docker组
2. 生成daemon.json配置
3. 启动containerd服务
4. 启动Docker服务

### 第六阶段：验证
1. 检查Docker版本
2. 验证服务状态
3. 测试Docker功能

---

# 方式二：手动安装（备选方案）

如果自动脚本安装失败，可以按照以下步骤手动安装。

## 📋 前置条件

- Linux x86_64 系统
- root 或 sudo 权限
- 内核版本 ≥ 3.10
- systemd 或其他 init 系统

## 🔧 安装步骤

### 步骤 1: 解压 Docker 二进制文件

```bash
# 解压 Docker 压缩包
tar -xvf docker-28.2.2.tgz

# 查看解压内容
ls -la docker/
```

### 步骤 2: 安装二进制文件

```bash
# 创建目标目录（如果不存在）
sudo mkdir -p /usr/local/bin

# 移动所有二进制文件到目标目录
sudo mv docker/* /usr/local/bin/

# 设置执行权限
sudo chmod +x /usr/local/bin/docker*
sudo chmod +x /usr/local/bin/containerd*
sudo chmod +x /usr/local/bin/ctr
sudo chmod +x /usr/local/bin/runc
```

### 步骤 3: 创建符号链接

为了系统全局可访问，创建符号链接到 `/usr/bin`：

```bash
# Docker 相关命令
sudo ln -s /usr/local/bin/docker /usr/bin/docker
sudo ln -s /usr/local/bin/dockerd /usr/bin/dockerd
sudo ln -s /usr/local/bin/docker-proxy /usr/bin/docker-proxy
sudo ln -s /usr/local/bin/docker-init /usr/bin/docker-init

# Containerd 相关命令
sudo ln -s /usr/local/bin/containerd /usr/bin/containerd
sudo ln -s /usr/local/bin/containerd-shim-runc-v2 /usr/bin/containerd-shim-runc-v2
sudo ln -s /usr/local/bin/ctr /usr/bin/ctr
sudo ln -s /usr/local/bin/runc /usr/bin/runc
```

### 步骤 4: 创建 Docker 组

```bash
# 创建 docker 组（如果不存在）
sudo groupadd docker 2>/dev/null || echo "Docker group already exists"

# 将当前用户添加到 docker 组（可选）
sudo usermod -aG docker $USER

# 注意：需要重新登录才能生效
```

### 步骤 5: 配置 Docker 数据目录

#### 选项 A: 使用默认位置 (/var/lib/docker)

```bash
# 创建默认数据目录
sudo mkdir -p /var/lib/docker
```

#### 选项 B: 使用自定义位置

```bash
# 创建自定义数据目录（示例：/data/docker）
sudo mkdir -p /data/docker

# 创建配置目录
sudo mkdir -p /etc/docker

# 创建 daemon.json 配置文件
sudo tee /etc/docker/daemon.json > /dev/null << 'EOF'
{
  "data-root": "/data/docker",
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  },
  "live-restore": true,
  "userland-proxy": false
}
EOF
```

### 步骤 6: 安装 systemd 服务文件

#### 6.1 了解 Docker Socket 激活

Docker Socket 激活是一种按需启动机制，有两种模式可选：

**传统模式**（适合生产环境）：
- Docker 开机自动启动并持续运行
- 始终占用内存（约 50-100MB）
- 响应速度快，无需等待启动

**Socket 激活模式**（适合开发环境）：
- Docker 不会自动启动
- 首次运行 docker 命令时才启动
- 节省内存资源
- 停止后再次使用会自动唤醒

#### 6.2 复制服务文件

```bash
# 复制 containerd 服务文件
sudo cp containerd.service /etc/systemd/system/

# 复制 docker 服务文件
sudo cp docker.service /etc/systemd/system/

# 复制 docker socket 文件（可选）
sudo cp docker.socket /etc/systemd/system/
```

#### 6.3 更新服务文件路径（如需要）

如果您的二进制文件不在 `/usr/local/bin`，需要编辑服务文件：

```bash
# 编辑 docker.service
sudo sed -i 's|/usr/local/bin/dockerd|/your/path/dockerd|g' /etc/systemd/system/docker.service

# 编辑 containerd.service
sudo sed -i 's|/usr/local/bin/containerd|/your/path/containerd|g' /etc/systemd/system/containerd.service
```

### 步骤 7: 加载内核模块

```bash
# 加载必需的内核模块
sudo modprobe overlay
sudo modprobe br_netfilter

# 设置内核参数
sudo tee /etc/sysctl.d/99-docker.conf > /dev/null << 'EOF'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

# 应用设置
sudo sysctl --system
```

### 步骤 8: 启动服务

#### 8.1 选择启动模式

**选项 A: 传统模式（Docker 始终运行）**

```bash
# 重新加载 systemd 配置
sudo systemctl daemon-reload

# 启用并启动 containerd
sudo systemctl enable containerd
sudo systemctl start containerd

# 启用并启动 Docker（开机自动启动）
sudo systemctl enable docker
sudo systemctl start docker

# 检查服务状态
sudo systemctl status docker
```

**选项 B: Socket 激活模式（按需启动）**

```bash
# 重新加载 systemd 配置
sudo systemctl daemon-reload

# 启用并启动 containerd
sudo systemctl enable containerd
sudo systemctl start containerd

# 仅启用 socket（不启用 docker.service）
sudo systemctl enable docker.socket
sudo systemctl start docker.socket

# 测试 socket 激活
docker version  # 这会触发 Docker 自动启动

# 检查状态
sudo systemctl status docker.socket
sudo systemctl status docker
```

#### 8.2 验证启动模式

```bash
# 检查哪些服务被启用
systemctl list-unit-files | grep docker

# 传统模式会显示：
# docker.service    enabled
# docker.socket     disabled

# Socket 模式会显示：
# docker.service    disabled
# docker.socket     enabled
```

### 步骤 9: 安装 Docker Compose

```bash
# 复制 docker-compose 到二进制目录
sudo cp docker-compose /usr/local/bin/docker-compose

# 设置执行权限
sudo chmod +x /usr/local/bin/docker-compose

# 创建符号链接
sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
```

### 步骤 10: 验证安装

```bash
# 检查 Docker 版本
docker version

# 检查 Docker 信息
docker info

# 运行测试容器
docker run hello-world

# 检查 Docker Compose 版本
docker-compose version
```

---

# 数据存储管理

## 🔄 安装后数据迁移

如需在安装后迁移Docker数据到新位置：

### 使用迁移脚本

```bash
# 添加执行权限
chmod +x migrate_docker.sh

# 交互式迁移
sudo ./migrate_docker.sh

# 自动迁移到指定位置
sudo ./migrate_docker.sh --target /new/path --yes
```

### 手动迁移步骤

```bash
# 1. 停止 Docker 服务
sudo systemctl stop docker
sudo systemctl stop docker.socket

# 2. 创建新目录
sudo mkdir -p /new/docker/path

# 3. 迁移数据
sudo rsync -avP /var/lib/docker/ /new/docker/path/

# 4. 备份旧目录
sudo mv /var/lib/docker /var/lib/docker.backup

# 5. 更新配置
sudo tee /etc/docker/daemon.json > /dev/null << 'EOF'
{
  "data-root": "/new/docker/path"
}
EOF

# 6. 重启服务
sudo systemctl start docker
```

## 📊 存储监控

```bash
# 查看 Docker 磁盘使用
docker system df

# 查看详细信息
docker system df -v

# 清理未使用资源
docker system prune -a

# 查看容器磁盘使用
docker ps -s
```

---

# 故障排除与维护

## ❓ 常见问题

### 1. 权限错误
```bash
# 错误：This script must be run as root or with sudo privileges
# 解决：使用 sudo 运行脚本
```

### 2. 内核版本过低
```bash
# 错误：Kernel version x.x.x is too old. Minimum required: 3.10
# 解决：升级系统内核或使用更新的操作系统
```

### 3. 磁盘空间不足
```bash
# 错误：Insufficient disk space. Required: 2048MB
# 解决：清理磁盘空间或选择其他分区
```

### 4. Docker服务无法启动
```bash
# 查看详细错误
sudo systemctl status docker
sudo journalctl -xe -u docker

# 尝试手动启动调试
sudo dockerd --debug
```

### 5. Socket权限问题
```bash
# 确保 socket 文件权限正确
ls -la /run/docker.sock
# 应该显示: srw-rw---- ... root docker

# 修复权限
sudo chmod 660 /run/docker.sock
sudo chown root:docker /run/docker.sock

# 添加用户到docker组
sudo usermod -aG docker $USER
newgrp docker
```

### 6. 存储驱动问题
```bash
# 检查支持的存储驱动
docker info | grep "Storage Driver"

# 如果 overlay2 不可用，使用 devicemapper
sudo tee /etc/docker/daemon.json > /dev/null << 'EOF'
{
  "storage-driver": "devicemapper"
}
EOF

sudo systemctl restart docker
```

### 7. 网络问题
```bash
# 检查 iptables 规则
sudo iptables -L -n

# 重置 iptables（谨慎使用）
sudo iptables -F
sudo iptables -X
sudo iptables -t nat -F
sudo iptables -t nat -X

# 重启 Docker
sudo systemctl restart docker
```

## 🔍 切换启动模式

### 从传统模式切换到 Socket 模式
```bash
sudo systemctl disable docker
sudo systemctl stop docker
sudo systemctl enable docker.socket
sudo systemctl start docker.socket
```

### 从 Socket 模式切换到传统模式
```bash
sudo systemctl disable docker.socket
sudo systemctl stop docker.socket
sudo systemctl enable docker
sudo systemctl start docker
```

## 📝 配置文件示例

### 完整的 daemon.json 示例

```json
{
  "data-root": "/var/lib/docker",
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3",
    "labels": "production"
  },
  "live-restore": true,
  "userland-proxy": false,
  "max-concurrent-downloads": 3,
  "max-concurrent-uploads": 5,
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 64000,
      "Soft": 64000
    }
  },
  "insecure-registries": [],
  "registry-mirrors": [],
  "exec-opts": ["native.cgroupdriver=systemd"],
  "default-runtime": "runc",
  "runtimes": {
    "runc": {
      "path": "/usr/bin/runc"
    }
  }
}
```

---

# 卸载与清理

## 🗑️ 卸载 Docker

### 使用卸载脚本

```bash
# 保留数据卸载
sudo ./uninstall.sh

# 完全删除（包括数据）
sudo ./uninstall.sh --purge
```

### 手动卸载步骤

```bash
# 停止服务
sudo systemctl stop docker
sudo systemctl stop containerd

# 禁用服务
sudo systemctl disable docker
sudo systemctl disable containerd

# 删除服务文件
sudo rm -f /etc/systemd/system/docker.service
sudo rm -f /etc/systemd/system/containerd.service
sudo rm -f /etc/systemd/system/docker.socket

# 删除二进制文件
sudo rm -f /usr/local/bin/docker*
sudo rm -f /usr/local/bin/containerd*
sudo rm -f /usr/local/bin/ctr
sudo rm -f /usr/local/bin/runc

# 删除符号链接
sudo rm -f /usr/bin/docker*
sudo rm -f /usr/bin/containerd*
sudo rm -f /usr/bin/ctr
sudo rm -f /usr/bin/runc

# 删除配置文件
sudo rm -rf /etc/docker

# 删除数据（谨慎！这将删除所有容器和镜像）
# sudo rm -rf /var/lib/docker
# sudo rm -rf /var/lib/containerd

# 删除 docker 组
sudo groupdel docker
```

---

# 验证与测试

## 📊 验证安装

```bash
# 检查版本
docker version
docker-compose version

# 查看Docker信息
docker info

# 运行测试容器
docker run hello-world

# 测试 Docker Compose
echo "version: '3'" > test-compose.yml
echo "services:" >> test-compose.yml
echo "  hello:" >> test-compose.yml
echo "    image: hello-world" >> test-compose.yml

docker-compose -f test-compose.yml up
rm test-compose.yml
```

## 📚 日志和状态

### 日志文件位置
- 安装日志：`install_YYYYMMDD_HHMMSS.log`
- 迁移日志：`migrate_YYYYMMDD_HHMMSS.log`
- 卸载日志：`uninstall_YYYYMMDD_HHMMSS.log`

### 查看日志
```bash
# 查看最新安装日志
ls -lt install_*.log | head -1

# 实时查看日志
tail -f install_*.log

# 查看 Docker 服务日志
sudo journalctl -xe -u docker
sudo journalctl -xe -u containerd
```

---

# 优化建议与最佳实践

## 🚀 优化建议

### 1. 日志管理

限制容器日志大小：

```bash
# 在 daemon.json 中配置
"log-opts": {
  "max-size": "50m",
  "max-file": "3"
}
```

### 2. 存储清理

定期清理未使用的资源：

```bash
# 清理未使用的容器、网络、镜像
docker system prune -a

# 查看磁盘使用情况
docker system df
```

### 3. 资源限制

为容器设置资源限制：

```bash
# 限制内存和 CPU
docker run -m 512m --cpus="1.0" your-image
```

### 4. 监控

设置监控和告警：

```bash
# 查看实时资源使用
docker stats

# 导出指标
docker system events
```

## 💡 最佳实践

1. **选择合适的存储位置** - 避免使用系统盘，选择空间充足的数据盘
2. **备份重要数据** - 定期备份重要的容器和数据卷
3. **定期清理** - 使用 `docker system prune` 清理未使用资源
4. **监控磁盘使用** - 使用 `docker system df` 查看空间占用
5. **保留日志** - 保存安装日志以备故障排查
6. **测试验证** - 安装后充分测试Docker功能
7. **定期更新** - 定期更新Docker到最新版本

## 🆘 获取帮助

```bash
# 显示脚本帮助信息
./install.sh --help
./migrate_docker.sh --help
./uninstall.sh --help

# 启用调试模式获取详细信息
sudo ./install.sh --debug
```

---

# 参考资源

## 📚 相关文档

- [Docker 官方文档](https://docs.docker.com)
- [Docker Compose 文档](https://docs.docker.com/compose/)
- [Containerd 文档](https://containerd.io)

## ⚠️ 注意事项

- 本安装包适用于离线环境
- 安装前请确保满足系统要求
- 生产环境使用前请充分测试
- 建议定期更新到最新版本
- 重复执行脚本会进行覆盖安装

## 📄 许可证

本安装脚本采用 MIT 许可证。Docker 和 Docker Compose 遵循其各自的许可证。

---

**版本**: 2.0.0 | **更新日期**: 2024