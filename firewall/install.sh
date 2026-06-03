#!/bin/bash
# ============================================================================
# NRO Shield — Script Cài Đặt Dependencies
# ============================================================================
# Mô tả: Cài đặt tất cả packages cần thiết cho hệ thống firewall
# Hệ điều hành: Ubuntu 22.04 LTS
# Quyền: Chạy với root (sudo)
# ============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# === Kiểm tra quyền root ===
if [[ $EUID -ne 0 ]]; then
    log_error "Script này cần chạy với quyền root (sudo)"
    exit 1
fi

# === Kiểm tra Ubuntu 22.04 ===
if ! grep -q "22.04" /etc/os-release 2>/dev/null; then
    log_warn "Hệ điều hành không phải Ubuntu 22.04. Tiếp tục nhưng có thể gặp lỗi."
fi

log_info "============================================"
log_info "  NRO Shield — Cài Đặt Dependencies"
log_info "============================================"

# === 1. Cập nhật hệ thống ===
log_info "Đang cập nhật hệ thống..."
apt-get update -y
apt-get upgrade -y
log_ok "Hệ thống đã cập nhật"

# === 2. Cài đặt packages cơ bản ===
log_info "Đang cài đặt packages cơ bản..."
apt-get install -y \
    iptables \
    iptables-persistent \
    ipset \
    netfilter-persistent \
    conntrack \
    curl \
    wget \
    net-tools \
    htop \
    iotop \
    iftop \
    vnstat \
    tcpdump \
    nmap \
    jq \
    bc \
    unzip \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release
log_ok "Packages cơ bản đã cài"

# === 3. Cài đặt Fail2Ban ===
log_info "Đang cài đặt Fail2Ban..."
apt-get install -y fail2ban
systemctl enable fail2ban
log_ok "Fail2Ban đã cài"

# === 4. Cài đặt CrowdSec ===
log_info "Đang cài đặt CrowdSec..."
if ! command -v cscli &>/dev/null; then
    curl -s https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.deb.sh | bash
    apt-get install -y crowdsec
    apt-get install -y crowdsec-firewall-bouncer-iptables
    systemctl enable crowdsec
    log_ok "CrowdSec đã cài"
else
    log_warn "CrowdSec đã tồn tại, bỏ qua"
fi

# === 5. Cài đặt Node.js 20 LTS ===
log_info "Đang cài đặt Node.js 20 LTS..."
if ! command -v node &>/dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
    log_ok "Node.js $(node --version) đã cài"
else
    log_warn "Node.js $(node --version) đã tồn tại"
fi

# === 6. Cài đặt Python 3 + pip ===
log_info "Đang cài đặt Python 3..."
apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev
log_ok "Python $(python3 --version) đã cài"

# === 7. Cài đặt MySQL/MariaDB ===
log_info "Đang cài đặt MariaDB..."
if ! command -v mysql &>/dev/null; then
    apt-get install -y mariadb-server mariadb-client
    systemctl enable mariadb
    systemctl start mariadb
    log_ok "MariaDB đã cài"
else
    log_warn "MySQL/MariaDB đã tồn tại"
fi

# === 8. Cài đặt GeoIP (tùy chọn) ===
log_info "Đang cài đặt GeoIP tools..."
apt-get install -y geoip-bin geoip-database || log_warn "Không cài được GeoIP"

# === 9. Cài đặt hping3 (testing) ===
log_info "Đang cài đặt hping3 (testing tool)..."
apt-get install -y hping3 || log_warn "Không cài được hping3"

# === 10. Bật IP forwarding ===
log_info "Bật IP forwarding..."
sysctl -w net.ipv4.ip_forward=1
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
log_ok "IP forwarding đã bật"

# === 11. Tạo thư mục log ===
log_info "Tạo thư mục log..."
mkdir -p /var/log/nroshield
mkdir -p /var/log/nroshield/attacks
mkdir -p /var/log/nroshield/traffic
mkdir -p /var/log/nroshield/ai
chmod 750 /var/log/nroshield
log_ok "Thư mục log đã tạo: /var/log/nroshield/"

# === 12. Tạo thư mục AI models ===
log_info "Tạo thư mục AI models..."
mkdir -p /opt/nroshield/ai_models
chmod 700 /opt/nroshield/ai_models
log_ok "Thư mục AI models: /opt/nroshield/ai_models/"

# === Tổng kết ===
echo ""
log_info "============================================"
log_ok "  CÀI ĐẶT HOÀN TẤT!"
log_info "============================================"
echo ""
log_info "Packages đã cài:"
echo "  ✅ iptables + ipset + iptables-persistent"
echo "  ✅ Fail2Ban"
echo "  ✅ CrowdSec + Firewall Bouncer"
echo "  ✅ Node.js $(node --version 2>/dev/null || echo 'N/A')"
echo "  ✅ Python $(python3 --version 2>/dev/null | awk '{print $2}' || echo 'N/A')"
echo "  ✅ MariaDB"
echo "  ✅ Network tools (tcpdump, nmap, hping3, vnstat...)"
echo ""
log_info "Bước tiếp: chạy sysctl_hardening.sh"
