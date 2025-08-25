# Docker Offline Installation Complete Guide

[中文版本](README_CN.md)

A complete offline installation solution for Docker and Docker Compose in environments without internet connectivity.

## 📥 Downloading Required Files

Before using this offline installer, you need to download the following files:

### Docker Engine Binary
Download from: https://download.docker.com/linux/static/stable/
- Choose your architecture (typically `x86_64`)
- Download the latest stable version (e.g., `docker-28.2.2.tgz`)
- Rename it to `docker.tgz`
- Place the downloaded file in the same directory as the installation scripts

### Docker Compose Binary
Download from: https://github.com/docker/compose/releases
- Choose the latest release
- Download the Linux binary for your architecture (e.g., `docker-compose-linux-x86_64`)
- Rename it to `docker-compose`
- Place it in the same directory as the installation scripts

## 📦 Package Contents

| File | Version | Description |
|------|---------|-------------|
| docker-28.2.2.tgz | 28.2.2 | Docker Engine binary package |
| docker-compose | Latest | Docker Compose binary |
| docker.service | - | Docker systemd service file |
| containerd.service | - | Containerd systemd service file |
| docker.socket | - | Docker socket file |
| install.sh | 2.0 | Smart installation script (recommended) |
| migrate_docker.sh | 1.0 | Docker data migration tool |
| uninstall.sh | 1.0 | Uninstallation script |

---

# Method 1: Automated Script Installation (Recommended)

## 📋 Prerequisites

### System Requirements
- **Architecture**: Linux x86_64
- **Kernel**: ≥ 3.10
- **Privileges**: root or sudo
- **Storage**: 10GB+ recommended
- **Init**: systemd (recommended)

### Supported Distributions
- Ubuntu 18.04+
- Debian 9+
- CentOS 7+
- RHEL 7+
- Fedora 30+
- openSUSE Leap 15+

### File Checklist
Ensure all files are in the same directory:
- `install.sh` - Main installation script
- `docker-28.2.2.tgz` - Docker binary package
- `docker-compose` - Docker Compose binary
- `docker.service` - Docker systemd service file
- `containerd.service` - Containerd systemd service file
- `docker.socket` - Docker socket file

## 🚀 Quick Installation

### 1. Basic Installation (Interactive)

```bash
# Add execute permission
chmod +x install.sh

# Run installation script
sudo ./install.sh
```

The script will:
- Detect operating system and environment
- Analyze disk space and recommend storage locations
- Ask if you want to customize Docker data directory
- Perform installation and start services

### 2. Automatic Installation (Non-interactive)

```bash
# Automatic installation with default configuration
sudo ./install.sh --force-yes

# Automatic installation with custom data directory
sudo ./install.sh --force-yes --data-root /data/docker
```

### 3. Command Line Parameters

```bash
--force-yes, -y    # Automatically confirm all prompts
--data-root PATH   # Specify Docker data directory
--debug           # Enable debug output
--skip-checks     # Skip system checks (not recommended)
--help, -h        # Show help information

# Example: Combining multiple options
sudo ./install.sh --force-yes --data-root /mnt/docker --debug
```

## 💾 Storage Configuration

### Interactive Storage Selection

When running the script, disk analysis will be displayed:

```
==========================================
     Disk Space Analysis
==========================================

Filesystem     Size  Used  Avail Use% Mounted on
/dev/sda2      100G  20G   80G   20%  /
/dev/sdb1      500G  10G  490G    2%  /data

Recommended locations for Docker data:
----------------------------------------
  ✓ /data/docker (recommended, 490GB available)
  • /var/lib/docker (default, 80GB available)
```

### Command Line Storage Specification

```bash
# Directly specify data directory
sudo ./install.sh --data-root /data/docker

# Using environment variable
sudo DOCKER_CUSTOM_DATA_ROOT=/mnt/docker ./install.sh
```

### Migrating Existing Data

If existing Docker data is detected, the script will automatically perform an overwrite installation. Users only need to:
1. Confirm installation path
2. Confirm whether to install Docker Compose

## 🔧 Environment Variable Configuration

You can customize installation paths via environment variables:

```bash
# Custom binary path
sudo DOCKER_BIN_DIR=/opt/docker/bin ./install.sh

# Complete customization example
sudo DOCKER_BIN_DIR=/opt/docker/bin \
     DOCKER_LINK_DIR=/usr/local/bin \
     DOCKER_DATA_DIR=/data/docker \
     DOCKER_CONFIG_DIR=/etc/docker \
     ./install.sh
```

### Supported Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| DOCKER_BIN_DIR | /usr/local/bin | Docker binary directory |
| DOCKER_LINK_DIR | /usr/bin | Symbolic link directory |
| DOCKER_DATA_DIR | /var/lib/docker | Docker data directory |
| DOCKER_CONFIG_DIR | /etc/docker | Docker configuration directory |
| DOCKER_STORAGE_DRIVER | overlay2 | Storage driver |

## 📝 Installation Process Details

### Phase 1: Environment Detection
1. Detect operating system type and version
2. Verify system architecture (x86_64)
3. Check init system (systemd/sysvinit/upstart)

### Phase 2: Prerequisite Checks
1. **Kernel Version** - Ensure ≥ 3.10
2. **Kernel Modules** - overlay, br_netfilter, etc.
3. **Cgroup Support** - v1 or v2
4. **Storage Driver** - overlay2, devicemapper, or vfs
5. **Network Tools** - iptables (optional but recommended)
6. **Disk Space** - At least 2GB available

### Phase 3: Storage Configuration
1. Analyze disk usage
2. Recommend suitable storage locations
3. Select or create data directory
4. Handle existing data migration

### Phase 4: Docker Installation
1. Extract Docker binaries
2. Copy to target directory
3. Create symbolic links
4. Configure systemd services

### Phase 5: Configuration and Startup
1. Create docker group
2. Generate daemon.json configuration
3. Start containerd service
4. Start Docker service

### Phase 6: Verification
1. Check Docker version
2. Verify service status
3. Test Docker functionality

---

# Method 2: Manual Installation (Alternative)

If the automated script fails, you can follow these manual installation steps.

## 📋 Prerequisites

- Linux x86_64 system
- root or sudo privileges
- Kernel version ≥ 3.10
- systemd or other init system

## 🔧 Installation Steps

### Step 1: Extract Docker Binaries

```bash
# Extract Docker archive
tar -xvf docker-28.2.2.tgz

# Check extracted content
ls -la docker/
```

### Step 2: Install Binaries

```bash
# Create target directory (if not exists)
sudo mkdir -p /usr/local/bin

# Move all binaries to target directory
sudo mv docker/* /usr/local/bin/

# Set execute permissions
sudo chmod +x /usr/local/bin/docker*
sudo chmod +x /usr/local/bin/containerd*
sudo chmod +x /usr/local/bin/ctr
sudo chmod +x /usr/local/bin/runc
```

### Step 3: Create Symbolic Links

For system-wide accessibility, create symbolic links to `/usr/bin`:

```bash
# Docker related commands
sudo ln -s /usr/local/bin/docker /usr/bin/docker
sudo ln -s /usr/local/bin/dockerd /usr/bin/dockerd
sudo ln -s /usr/local/bin/docker-proxy /usr/bin/docker-proxy
sudo ln -s /usr/local/bin/docker-init /usr/bin/docker-init

# Containerd related commands
sudo ln -s /usr/local/bin/containerd /usr/bin/containerd
sudo ln -s /usr/local/bin/containerd-shim-runc-v2 /usr/bin/containerd-shim-runc-v2
sudo ln -s /usr/local/bin/ctr /usr/bin/ctr
sudo ln -s /usr/local/bin/runc /usr/bin/runc
```

### Step 4: Create Docker Group

```bash
# Create docker group (if not exists)
sudo groupadd docker 2>/dev/null || echo "Docker group already exists"

# Add current user to docker group (optional)
sudo usermod -aG docker $USER

# Note: Need to re-login for changes to take effect
```

### Step 5: Configure Docker Data Directory

#### Option A: Use Default Location (/var/lib/docker)

```bash
# Create default data directory
sudo mkdir -p /var/lib/docker
```

#### Option B: Use Custom Location

```bash
# Create custom data directory (example: /data/docker)
sudo mkdir -p /data/docker

# Create configuration directory
sudo mkdir -p /etc/docker

# Create daemon.json configuration file
sudo tee /etc/docker/daemon.json > /dev/null << 'EOF'
{
  "data-root": "/data/docker",
  "storage-driver": "overlay2",
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

### Step 6: Install systemd Service Files

#### 6.1 Understanding Docker Socket Activation

Docker Socket activation is an on-demand startup mechanism with two modes:

**Traditional Mode** (suitable for production):
- Docker starts automatically at boot and runs continuously
- Always uses memory (about 50-100MB)
- Fast response, no startup wait

**Socket Activation Mode** (suitable for development):
- Docker doesn't start automatically
- Starts on first docker command execution
- Saves memory resources
- Automatically wakes up when used after stopping

#### 6.2 Copy Service Files

```bash
# Copy containerd service file
sudo cp containerd.service /etc/systemd/system/

# Copy docker service file
sudo cp docker.service /etc/systemd/system/

# Copy docker socket file (optional)
sudo cp docker.socket /etc/systemd/system/
```

#### 6.3 Update Service File Paths (if needed)

If your binaries are not in `/usr/local/bin`, edit the service files:

```bash
# Edit docker.service
sudo sed -i 's|/usr/local/bin/dockerd|/your/path/dockerd|g' /etc/systemd/system/docker.service

# Edit containerd.service
sudo sed -i 's|/usr/local/bin/containerd|/your/path/containerd|g' /etc/systemd/system/containerd.service
```

### Step 7: Load Kernel Modules

```bash
# Load required kernel modules
sudo modprobe overlay
sudo modprobe br_netfilter

# Set kernel parameters
sudo tee /etc/sysctl.d/99-docker.conf > /dev/null << 'EOF'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

# Apply settings
sudo sysctl --system
```

### Step 8: Start Services

#### 8.1 Choose Startup Mode

**Option A: Traditional Mode (Docker always running)**

```bash
# Reload systemd configuration
sudo systemctl daemon-reload

# Enable and start containerd
sudo systemctl enable containerd
sudo systemctl start containerd

# Enable and start Docker (auto-start at boot)
sudo systemctl enable docker
sudo systemctl start docker

# Check service status
sudo systemctl status docker
```

**Option B: Socket Activation Mode (on-demand startup)**

```bash
# Reload systemd configuration
sudo systemctl daemon-reload

# Enable and start containerd
sudo systemctl enable containerd
sudo systemctl start containerd

# Only enable socket (not docker.service)
sudo systemctl enable docker.socket
sudo systemctl start docker.socket

# Test socket activation
docker version  # This will trigger Docker to start automatically

# Check status
sudo systemctl status docker.socket
sudo systemctl status docker
```

#### 8.2 Verify Startup Mode

```bash
# Check which services are enabled
systemctl list-unit-files | grep docker

# Traditional mode will show:
# docker.service    enabled
# docker.socket     disabled

# Socket mode will show:
# docker.service    disabled
# docker.socket     enabled
```

### Step 9: Install Docker Compose

```bash
# Copy docker-compose to binary directory
sudo cp docker-compose /usr/local/bin/docker-compose

# Set execute permission
sudo chmod +x /usr/local/bin/docker-compose

# Create symbolic link
sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
```

### Step 10: Verify Installation

```bash
# Check Docker version
docker version

# Check Docker info
docker info

# Run test container
docker run hello-world

# Check Docker Compose version
docker-compose version
```

---

# Data Storage Management

## 🔄 Post-Installation Data Migration

If you need to migrate Docker data to a new location after installation:

### Using Migration Script

```bash
# Add execute permission
chmod +x migrate_docker.sh

# Interactive migration
sudo ./migrate_docker.sh

# Automatic migration to specified location
sudo ./migrate_docker.sh --target /new/path --yes
```

### Manual Migration Steps

```bash
# 1. Stop Docker services
sudo systemctl stop docker
sudo systemctl stop docker.socket

# 2. Create new directory
sudo mkdir -p /new/docker/path

# 3. Migrate data
sudo rsync -avP /var/lib/docker/ /new/docker/path/

# 4. Backup old directory
sudo mv /var/lib/docker /var/lib/docker.backup

# 5. Update configuration
sudo tee /etc/docker/daemon.json > /dev/null << 'EOF'
{
  "data-root": "/new/docker/path"
}
EOF

# 6. Restart services
sudo systemctl start docker
```

## 📊 Storage Monitoring

```bash
# View Docker disk usage
docker system df

# View detailed information
docker system df -v

# Clean unused resources
docker system prune -a

# View container disk usage
docker ps -s
```

---

# Troubleshooting & Maintenance

## ❓ Common Issues

### 1. Permission Error
```bash
# Error: This script must be run as root or with sudo privileges
# Solution: Run script with sudo
```

### 2. Kernel Version Too Old
```bash
# Error: Kernel version x.x.x is too old. Minimum required: 3.10
# Solution: Upgrade kernel or use newer operating system
```

### 3. Insufficient Disk Space
```bash
# Error: Insufficient disk space. Required: 2048MB
# Solution: Clean disk space or choose another partition
```

### 4. Docker Service Cannot Start
```bash
# View detailed errors
sudo systemctl status docker
sudo journalctl -xe -u docker

# Try manual debug startup
sudo dockerd --debug
```

### 5. Socket Permission Issues
```bash
# Ensure socket file permissions are correct
ls -la /run/docker.sock
# Should show: srw-rw---- ... root docker

# Fix permissions
sudo chmod 660 /run/docker.sock
sudo chown root:docker /run/docker.sock

# Add user to docker group
sudo usermod -aG docker $USER
newgrp docker
```

### 6. Storage Driver Issues
```bash
# Check supported storage drivers
docker info | grep "Storage Driver"

# If overlay2 is not available, use devicemapper
sudo tee /etc/docker/daemon.json > /dev/null << 'EOF'
{
  "storage-driver": "devicemapper"
}
EOF

sudo systemctl restart docker
```

### 7. Network Issues (iptables not found)
```bash
# Install iptables (if needed)
# For RHEL/CentOS:
sudo yum install -y iptables iptables-services

# For Ubuntu/Debian:
sudo apt-get install -y iptables

# Or configure Docker without iptables (limited networking)
sudo tee /etc/docker/daemon.json > /dev/null << 'EOF'
{
  "iptables": false,
  "bridge": "none"
}
EOF

sudo systemctl restart docker
```

## 🔍 Switching Startup Modes

### Switch from Traditional to Socket Mode
```bash
sudo systemctl disable docker
sudo systemctl stop docker
sudo systemctl enable docker.socket
sudo systemctl start docker.socket
```

### Switch from Socket to Traditional Mode
```bash
sudo systemctl disable docker.socket
sudo systemctl stop docker.socket
sudo systemctl enable docker
sudo systemctl start docker
```

## 📝 Configuration File Examples

### Complete daemon.json Example

```json
{
  "data-root": "/var/lib/docker",
  "storage-driver": "overlay2",
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

# Uninstallation & Cleanup

## 🗑️ Uninstall Docker

### Using Uninstall Script

```bash
# Uninstall keeping data
sudo ./uninstall.sh

# Complete removal (including data)
sudo ./uninstall.sh --purge
```

### Manual Uninstall Steps

```bash
# Stop services
sudo systemctl stop docker
sudo systemctl stop containerd

# Disable services
sudo systemctl disable docker
sudo systemctl disable containerd

# Remove service files
sudo rm -f /etc/systemd/system/docker.service
sudo rm -f /etc/systemd/system/containerd.service
sudo rm -f /etc/systemd/system/docker.socket

# Remove binaries
sudo rm -f /usr/local/bin/docker*
sudo rm -f /usr/local/bin/containerd*
sudo rm -f /usr/local/bin/ctr
sudo rm -f /usr/local/bin/runc

# Remove symbolic links
sudo rm -f /usr/bin/docker*
sudo rm -f /usr/bin/containerd*
sudo rm -f /usr/bin/ctr
sudo rm -f /usr/bin/runc

# Remove configuration files
sudo rm -rf /etc/docker

# Remove data (CAUTION! This will delete all containers and images)
# sudo rm -rf /var/lib/docker
# sudo rm -rf /var/lib/containerd

# Remove docker group
sudo groupdel docker
```

---

# Verification & Testing

## 📊 Verify Installation

```bash
# Check versions
docker version
docker-compose version

# View Docker info
docker info

# Run test container
docker run hello-world

# Test Docker Compose
echo "version: '3'" > test-compose.yml
echo "services:" >> test-compose.yml
echo "  hello:" >> test-compose.yml
echo "    image: hello-world" >> test-compose.yml

docker-compose -f test-compose.yml up
rm test-compose.yml
```

## 📚 Logs and Status

### Log File Locations
- Installation log: `install_YYYYMMDD_HHMMSS.log`
- Migration log: `migrate_YYYYMMDD_HHMMSS.log`
- Uninstall log: `uninstall_YYYYMMDD_HHMMSS.log`

### Viewing Logs
```bash
# View latest installation log
ls -lt install_*.log | head -1

# Real-time log viewing
tail -f install_*.log

# View Docker service logs
sudo journalctl -xe -u docker
sudo journalctl -xe -u containerd
```

---

# Optimization Suggestions & Best Practices

## 🚀 Optimization Suggestions

### 1. Log Management

Limit container log size:

```bash
# Configure in daemon.json
"log-opts": {
  "max-size": "50m",
  "max-file": "3"
}
```

### 2. Storage Cleanup

Regularly clean unused resources:

```bash
# Clean unused containers, networks, images
docker system prune -a

# View disk usage
docker system df
```

### 3. Resource Limits

Set resource limits for containers:

```bash
# Limit memory and CPU
docker run -m 512m --cpus="1.0" your-image
```

### 4. Monitoring

Set up monitoring and alerts:

```bash
# View real-time resource usage
docker stats

# Export metrics
docker system events
```

## 💡 Best Practices

1. **Choose appropriate storage location** - Avoid system disk, choose data disk with sufficient space
2. **Backup important data** - Regularly backup important containers and data volumes
3. **Regular cleanup** - Use `docker system prune` to clean unused resources
4. **Monitor disk usage** - Use `docker system df` to check space usage
5. **Keep logs** - Save installation logs for troubleshooting
6. **Test verification** - Thoroughly test Docker functionality after installation
7. **Regular updates** - Regularly update Docker to the latest version

## 🆘 Getting Help

```bash
# Show script help information
./install.sh --help
./migrate_docker.sh --help
./uninstall.sh --help

# Enable debug mode for detailed information
sudo ./install.sh --debug
```

---

# Reference Resources

## 📚 Related Documentation

- [Docker Official Documentation](https://docs.docker.com)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Containerd Documentation](https://containerd.io)

## ⚠️ Important Notes

- This installation package is suitable for offline environments
- Ensure system requirements are met before installation
- Thoroughly test before production use
- Regular updates to the latest version are recommended
- Running the script repeatedly will perform an overwrite installation

## 📄 License

This installation script is under MIT License. Docker and Docker Compose follow their respective licenses.

---

**Version**: 2.0.0 | **Updated**: 2024