#!/bin/bash
# ============================================================================
# NRO Shield — Master Deploy Script
# ============================================================================
# Mô tả: Triển khai toàn bộ hệ thống NRO Shield
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FW_DIR="${SCRIPT_DIR}/firewall"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
log_ok()      { echo -e "${GREEN}[ OK ]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[FAIL]${NC} $1"; }
log_section() { echo -e "\n${BOLD}${CYAN}═══════════════════════════════════════${NC}"; echo -e "${BOLD}  $1${NC}"; echo -e "${BOLD}${CYAN}═══════════════════════════════════════${NC}\n"; }

# === Kiểm tra root ===
if [[ $EUID -ne 0 ]]; then
    log_error "Cần chạy với quyền root: sudo bash deploy.sh"
    exit 1
fi

# === Kiểm tra .env ===
ENV_FILE="${SCRIPT_DIR}/.env"
if [[ ! -f "$ENV_FILE" ]]; then
    log_error "Chưa có file .env! Hãy copy từ .env.example:"
    echo "  cp .env.example .env"
    echo "  nano .env  # Sửa cấu hình"
    exit 1
fi

source "$ENV_FILE"

# === Kiểm tra bắt buộc ===
if [[ -z "${VPS_PUBLIC_IP:-}" ]]; then
    log_error "VPS_PUBLIC_IP chưa được cấu hình trong .env"
    exit 1
fi

echo -e "${BOLD}${GREEN}"
echo "  ███╗   ██╗██████╗  ██████╗     ███████╗██╗  ██╗██╗███████╗██╗     ██████╗ "
echo "  ████╗  ██║██╔══██╗██╔═══██╗    ██╔════╝██║  ██║██║██╔════╝██║     ██╔══██╗"
echo "  ██╔██╗ ██║██████╔╝██║   ██║    ███████╗███████║██║█████╗  ██║     ██║  ██║"
echo "  ██║╚██╗██║██╔══██╗██║   ██║    ╚════██║██╔══██║██║██╔══╝  ██║     ██║  ██║"
echo "  ██║ ╚████║██║  ██║╚██████╔╝    ███████║██║  ██║██║███████╗███████╗██████╔╝"
echo "  ╚═╝  ╚═══╝╚═╝  ╚═╝ ╚═════╝     ╚══════╝╚═╝  ╚═╝╚═╝╚══════╝╚══════╝╚═════╝ "
echo -e "${NC}"
echo "  DDoS Protection as a Service — Game NRO"
echo "  VPS IP: ${VPS_PUBLIC_IP}"
echo ""

DEPLOY_LOG="${SCRIPT_DIR}/deploy.log"
echo "[$(date)] Deploy started" > "$DEPLOY_LOG"

run_step() {
    local step_name="$1"
    local script_path="$2"

    log_section "$step_name"

    if [[ -f "$script_path" ]]; then
        if bash "$script_path" 2>&1 | tee -a "$DEPLOY_LOG"; then
            log_ok "$step_name — Hoàn tất ✅"
            echo "[$(date)] $step_name: OK" >> "$DEPLOY_LOG"
        else
            log_error "$step_name — Lỗi! Xem deploy.log"
            echo "[$(date)] $step_name: FAILED" >> "$DEPLOY_LOG"
            read -rp "Tiếp tục? (y/n): " cont
            [[ "$cont" != "y" ]] && exit 1
        fi
    else
        log_warn "Không tìm thấy: $script_path — Bỏ qua"
    fi
}

# ============================================================================
# TRIỂN KHAI TỪNG BƯỚC
# ============================================================================

# Giai đoạn 1: Firewall Engine
run_step "Bước 1/6: Cài đặt Dependencies" "${FW_DIR}/install.sh"
run_step "Bước 2/6: Kernel Hardening" "${FW_DIR}/sysctl_hardening.sh"
run_step "Bước 3/6: Base Firewall Rules" "${FW_DIR}/iptables_base.sh"
run_step "Bước 4/6: Anti-DDoS Protection" "${FW_DIR}/anti_ddos.sh"
run_step "Bước 5/6: Anti-Botnet Protection" "${FW_DIR}/anti_botnet.sh"
run_step "Bước 6/6: CrowdSec + Fail2Ban" "${FW_DIR}/crowdsec_setup.sh"

# Fail2Ban
bash "${FW_DIR}/fail2ban_setup.sh" 2>&1 | tee -a "$DEPLOY_LOG" || true

# ============================================================================
# THIẾT LẬP SYSTEMD SERVICES
# ============================================================================
log_section "Thiết lập Systemd Services"

# Traffic monitor service (chạy mỗi phút)
cat > /etc/systemd/system/nroshield-monitor.service << EOF
[Unit]
Description=NRO Shield Traffic Monitor
After=network.target

[Service]
Type=oneshot
ExecStart=${FW_DIR}/traffic_monitor.sh
StandardOutput=append:/var/log/nroshield/monitor.log
EOF

cat > /etc/systemd/system/nroshield-monitor.timer << EOF
[Unit]
Description=NRO Shield Monitor Timer

[Timer]
OnCalendar=*:*:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable nroshield-monitor.timer
systemctl start nroshield-monitor.timer

log_ok "Monitor timer đã thiết lập (mỗi phút)"

# ============================================================================
# THIẾT LẬP LOGROTATE
# ============================================================================
log_section "Thiết lập Logrotate"

cat > /etc/logrotate.d/nroshield << 'EOF'
/var/log/nroshield/*.log
/var/log/nroshield/**/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 640 root root
    sharedscripts
}
EOF

log_ok "Logrotate đã cấu hình (giữ 7 ngày)"

# ============================================================================
# TỔNG KẾT
# ============================================================================
log_section "TRIỂN KHAI HOÀN TẤT!"

echo "  📊 Thống kê:"
echo "    iptables rules:  $(iptables -L -n 2>/dev/null | grep -c '^[A-Z]') chains"
echo "    ipset sets:      $(ipset list -n 2>/dev/null | wc -l) sets"
echo "    Conntrack max:   $(sysctl -n net.netfilter.nf_conntrack_max 2>/dev/null)"
echo ""
echo "  🔧 Quản lý dịch vụ (Systemd):"
echo "    systemctl status nroshield-api    # Backend API"
echo "    systemctl status nroshield-ai     # AI Engine"
echo "    systemctl status nroshield-bot    # Telegram Bot"
echo ""
echo "  📝 Logs: tail -f /var/log/nroshield/api.log"
echo "  🛠️ Cleanup: bash cleanup_logs.sh"
echo ""
echo "  📝 Deploy log: ${DEPLOY_LOG}"
echo ""
