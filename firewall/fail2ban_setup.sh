#!/bin/bash
# ============================================================================
# NRO Shield — Fail2Ban Setup
# ============================================================================
# Mô tả: Cấu hình Fail2Ban cho SSH và game NRO
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../.env"

SSH_PORT="2222"
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} Cần quyền root"; exit 1
fi

log_info "============================================"
log_info "  NRO Shield — Fail2Ban Setup"
log_info "============================================"

# === 1. Cài đặt ===
if ! command -v fail2ban-client &>/dev/null; then
    log_info "Cài đặt Fail2Ban..."
    apt-get install -y fail2ban
fi

# === 2. Cấu hình jail.local ===
log_info "Tạo cấu hình jail..."

cat > /etc/fail2ban/jail.local << JAILEOF
# ============================================================================
# NRO Shield — Fail2Ban Configuration
# ============================================================================

[DEFAULT]
# Ban time escalation: 10m → 1h → 1d → 1w
bantime.increment = true
bantime.factor = 24
bantime.formula = ban.Time * math.exp(float(ban.Count+1)*banFactor)/math.exp(1*banFactor)
bantime = 600
findtime = 600
maxretry = 5
# Sử dụng iptables multiport
banaction = iptables-multiport
banaction_allports = iptables-allports
# Bỏ qua localhost
ignoreip = 127.0.0.1/8 ::1

# ============================================================================
# SSH Protection
# ============================================================================
[sshd]
enabled = true
port = ${SSH_PORT}
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
findtime = 300
bantime = 3600

# ============================================================================
# NRO Shield — Drop Log Monitor
# ============================================================================
[nroshield-drops]
enabled = true
port = 0:65535
filter = nroshield-drops
logpath = /var/log/syslog
maxretry = 100
findtime = 60
bantime = 1800
action = iptables-allports[name=nroshield, protocol=all]

# ============================================================================
# NRO Shield — Repeated Connection Attempts
# ============================================================================
[nroshield-connflood]
enabled = true
port = 0:65535
filter = nroshield-connflood
logpath = /var/log/nroshield/traffic/*.log
maxretry = 200
findtime = 30
bantime = 3600
action = iptables-allports[name=nroshield-conn, protocol=all]

# ============================================================================
# Recidive — Ban lặp lại (meta-jail)
# ============================================================================
[recidive]
enabled = true
logpath = /var/log/fail2ban.log
banaction = iptables-allports
bantime = 604800
findtime = 86400
maxretry = 3
JAILEOF

log_ok "jail.local đã tạo"

# === 3. Tạo custom filters ===
log_info "Tạo custom filters..."

# Filter cho NRO Shield drop logs
cat > /etc/fail2ban/filter.d/nroshield-drops.conf << 'FILTEREOF'
[Definition]
failregex = \[NROSHIELD-DROP-(?:IN|FWD)\].*SRC=<HOST>
ignoreregex =
FILTEREOF

# Filter cho connection flood logs
cat > /etc/fail2ban/filter.d/nroshield-connflood.conf << 'FILTEREOF'
[Definition]
failregex = CONN_FLOOD src=<HOST>
            RATE_EXCEEDED src=<HOST>
ignoreregex =
FILTEREOF

log_ok "Custom filters đã tạo"

# === 4. Restart ===
log_info "Restart Fail2Ban..."
systemctl restart fail2ban
systemctl enable fail2ban

# === Tổng kết ===
echo ""
log_info "============================================"
log_ok "  FAIL2BAN ĐÃ THIẾT LẬP!"
log_info "============================================"
echo ""

fail2ban-client status 2>/dev/null || echo "  Đang khởi động..."
echo ""
echo "  Jails:"
echo "    ✅ sshd             — max 3 retries / 5 min"
echo "    ✅ nroshield-drops  — max 100 drops / 1 min"
echo "    ✅ nroshield-conn   — max 200 conns / 30 sec"
echo "    ✅ recidive         — ban 1 tuần nếu tái phạm"
echo ""
log_info "Lệnh hữu ích:"
echo "  fail2ban-client status            # Tổng quan"
echo "  fail2ban-client status sshd       # Chi tiết SSH"
echo "  fail2ban-client set sshd unbanip X # Mở ban IP"
echo ""
log_info "Bước tiếp: chạy traffic_monitor.sh"
