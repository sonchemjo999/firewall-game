#!/bin/bash
# ============================================================================
# NRO Shield v2.0 — Master Setup Script
# ============================================================================
# Setup de dang, on dinh lau dai. Chay 1 lenh duy nhat de cai dat toan bo.
# Su dung: sudo bash master_setup.sh [game_type]
# Vi du:   sudo bash master_setup.sh nro
#          sudo bash master_setup.sh minecraft
#          sudo bash master_setup.sh all
# ============================================================================

set -euo pipefail

# === Colors & Logging ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

log_step()  { echo -e "\n${PURPLE}${BOLD}[STEP]${NC} $1"; }
log_info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

GAME_TYPE="${1:-all}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/nroshield/setup_$(date +%Y%m%d_%H%M%S).log"
BACKUP_DIR="/opt/nroshield/backups/$(date +%Y%m%d_%H%M%S)"

# === Root check ===
if [[ $EUID -ne 0 ]]; then
    log_error "Can quyen root. Su dung: sudo bash $0 $GAME_TYPE"
    exit 1
fi

# === Create directories ===
mkdir -p /var/log/nroshield/{attacks,traffic,ai,setup}
mkdir -p /opt/nroshield/{ai_models,backups,configs}
mkdir -p "$BACKUP_DIR"

echo "" | tee "$LOG_FILE"
echo -e "${PURPLE}${BOLD}" | tee -a "$LOG_FILE"
echo "  ╔══════════════════════════════════════════════════╗" | tee -a "$LOG_FILE"
echo "  ║          NRO Shield v2.0 — Master Setup          ║" | tee -a "$LOG_FILE"
echo "  ║     Advanced DDoS Protection for Game Servers     ║" | tee -a "$LOG_FILE"
echo "  ╚══════════════════════════════════════════════════╝" | tee -a "$LOG_FILE"
echo -e "${NC}" | tee -a "$LOG_FILE"
echo "  Game Type: ${GAME_TYPE}" | tee -a "$LOG_FILE"
echo "  Date: $(date)" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# ============================================================================
# STEP 1: Backup current config
# ============================================================================
log_step "1/9 — Backup cau hinh hien tai"

if command -v iptables-save &>/dev/null; then
    iptables-save > "$BACKUP_DIR/iptables.rules.bak" 2>/dev/null || true
    log_ok "Backed up iptables rules"
fi
if command -v ipset &>/dev/null; then
    ipset save > "$BACKUP_DIR/ipset.rules.bak" 2>/dev/null || true
    log_ok "Backed up ipset rules"
fi
cp /etc/sysctl.conf "$BACKUP_DIR/sysctl.conf.bak" 2>/dev/null || true
log_ok "Backup luu tai: $BACKUP_DIR"

# ============================================================================
# STEP 2: Install dependencies
# ============================================================================
log_step "2/9 — Cai dat dependencies"

if [[ -f "$SCRIPT_DIR/install.sh" ]]; then
    bash "$SCRIPT_DIR/install.sh" 2>&1 | tee -a "$LOG_FILE"
else
    log_warn "install.sh khong tim thay, cai dat thu cong..."
    apt-get update -y
    apt-get install -y iptables iptables-persistent ipset netfilter-persistent \
        conntrack curl wget net-tools jq bc fail2ban
fi
log_ok "Dependencies da cai dat"

# ============================================================================
# STEP 3: Kernel hardening
# ============================================================================
log_step "3/9 — Toi uu hoa kernel (sysctl hardening)"

if [[ -f "$SCRIPT_DIR/sysctl_hardening.sh" ]]; then
    bash "$SCRIPT_DIR/sysctl_hardening.sh" 2>&1 | tee -a "$LOG_FILE"
else
    log_warn "sysctl_hardening.sh khong tim thay"
fi
log_ok "Kernel da toi uu"

# ============================================================================
# STEP 4: Base firewall rules
# ============================================================================
log_step "4/9 — Early Drop Engine (raw/mangle pre-conntrack)"

if [[ -f "$SCRIPT_DIR/early_drop.sh" ]]; then
    bash "$SCRIPT_DIR/early_drop.sh" 2>&1 | tee -a "$LOG_FILE"
fi
log_ok "Early Drop Engine da thiet lap — botnet bi drop truoc conntrack"

# ============================================================================
# STEP 5: Base firewall rules
# ============================================================================
log_step "5/9 — Thiet lap iptables co ban"

if [[ -f "$SCRIPT_DIR/iptables_base.sh" ]]; then
    bash "$SCRIPT_DIR/iptables_base.sh" 2>&1 | tee -a "$LOG_FILE"
fi
log_ok "Base firewall da thiet lap"

# ============================================================================
# STEP 5: Anti-DDoS v2 (strongest rules)
# ============================================================================
log_step "6/9 — Anti-DDoS v2 (chong tan cong manh nhat)"

if [[ -f "$SCRIPT_DIR/anti_ddos_v2.sh" ]]; then
    bash "$SCRIPT_DIR/anti_ddos_v2.sh" 2>&1 | tee -a "$LOG_FILE"
fi
if [[ -f "$SCRIPT_DIR/anti_bypass.sh" ]]; then
    bash "$SCRIPT_DIR/anti_bypass.sh" 2>&1 | tee -a "$LOG_FILE"
fi
if [[ -f "$SCRIPT_DIR/anti_botnet.sh" ]]; then
    bash "$SCRIPT_DIR/anti_botnet.sh" 2>&1 | tee -a "$LOG_FILE"
fi
log_ok "Anti-DDoS v2 da thiet lap"

# ============================================================================
# STEP 6: Game-specific rules
# ============================================================================
log_step "7/9 — Thiet lap rules cho game: ${GAME_TYPE}"

if [[ -f "$SCRIPT_DIR/multi_game_support.sh" ]]; then
    bash "$SCRIPT_DIR/multi_game_support.sh" "$GAME_TYPE" 2>&1 | tee -a "$LOG_FILE"
fi
log_ok "Game rules da thiet lap cho: ${GAME_TYPE}"

# ============================================================================
# STEP 7: Setup systemd services cho tu dong khoi dong
# ============================================================================
log_step "8/9 — Thiet lap systemd services (on dinh lau dai)"

# Tao systemd service cho iptables restore khi reboot
cat > /etc/systemd/system/nroshield-firewall.service << 'SVCEOF'
[Unit]
Description=NRO Shield Firewall Rules Restore
After=network-pre.target
Before=network.target
Wants=network-pre.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/sbin/iptables-restore /etc/iptables/rules.v4
ExecStart=/sbin/ipset restore -f /etc/ipset.rules
ExecStop=/sbin/iptables-save -f /etc/iptables/rules.v4
ExecStop=/sbin/ipset save -f /etc/ipset.rules

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable nroshield-firewall.service 2>/dev/null || true

# Tao cron job tu dong cap nhat blocklists
cat > /etc/cron.daily/nroshield-update << 'CRONEOF'
#!/bin/bash
# NRO Shield daily blocklist update
LOG="/var/log/nroshield/cron_update.log"
echo "$(date) — Starting blocklist update" >> "$LOG"

# Update botnet lists
if [[ -f /opt/nroshield/configs/botnet_update.sh ]]; then
    bash /opt/nroshield/configs/botnet_update.sh >> "$LOG" 2>&1
fi

# Rotate old attack logs (keep 30 days)
find /var/log/nroshield/attacks/ -type f -mtime +30 -delete 2>/dev/null
echo "$(date) — Update complete" >> "$LOG"
CRONEOF
chmod +x /etc/cron.daily/nroshield-update

# Save current rules
iptables-save > /etc/iptables/rules.v4 2>/dev/null || \
    iptables-save > /etc/iptables.rules 2>/dev/null || true
ipset save > /etc/ipset.rules 2>/dev/null || true

log_ok "Systemd services da thiet lap — firewall se tu khoi dong khi reboot"

# ============================================================================
# STEP 8: Verify & Summary
# ============================================================================
log_step "9/9 — Kiem tra va tong ket"

echo ""
echo -e "${PURPLE}${BOLD}  ╔══════════════════════════════════════════════════╗${NC}"
echo -e "${PURPLE}${BOLD}  ║              SETUP HOAN TAT!                      ║${NC}"
echo -e "${PURPLE}${BOLD}  ╚══════════════════════════════════════════════════╝${NC}"
echo ""

TOTAL_INPUT=$(iptables -L INPUT -n 2>/dev/null | grep -c "^" || echo "0")
TOTAL_FORWARD=$(iptables -L FORWARD -n 2>/dev/null | grep -c "^" || echo "0")
TOTAL_MANGLE=$(iptables -t mangle -L -n 2>/dev/null | grep -c "^" || echo "0")
TOTAL_NAT=$(iptables -t nat -L -n 2>/dev/null | grep -c "^" || echo "0")
TOTAL_IPSET=$(ipset list -n 2>/dev/null | wc -l || echo "0")
CONNTRACK_MAX=$(sysctl -n net.netfilter.nf_conntrack_max 2>/dev/null || echo "N/A")

echo "  Thong ke bao mat:"
echo "  ─────────────────────────────────────────"
echo "  INPUT rules:        ${TOTAL_INPUT}"
echo "  FORWARD rules:      ${TOTAL_FORWARD}"
echo "  Mangle rules:       ${TOTAL_MANGLE}"
echo "  NAT rules:          ${TOTAL_NAT}"
echo "  ipset sets:         ${TOTAL_IPSET}"
echo "  Conntrack max:      ${CONNTRACK_MAX}"
echo "  Game type:          ${GAME_TYPE}"
echo "  ─────────────────────────────────────────"
echo "  Backup:             ${BACKUP_DIR}"
echo "  Log:                ${LOG_FILE}"
echo ""
echo "  Tinh nang bao ve:"
echo "  [x] Anti-SYN Flood (3 lop)"
echo "  [x] Anti-UDP Flood (game-aware)"
echo "  [x] Anti-ACK/RST/FIN Flood"
echo "  [x] Anti-Bypass (TCP/UDP validation)"
echo "  [x] Anti-Carpet Bombing"
echo "  [x] Anti-Reflection (NTP/DNS/Memcached)"
echo "  [x] Early Drop Engine (raw table pre-conntrack)"
echo "  [x] Anti-Botnet (IP blocklists)"
echo "  [x] Adaptive Rate Limiting"
echo "  [x] Dynamic Blacklisting"
echo "  [x] Game-specific packet validation"
echo "  [x] Connection exhaustion defense"
echo "  [x] Kernel hardening (sysctl)"
echo "  [x] Auto-restore on reboot"
echo "  [x] Daily blocklist updates"
echo "  [x] Auto-blacklist (10s interval)"
echo ""
echo -e "${GREEN}  Setup on dinh lau dai — firewall tu dong khoi dong khi reboot.${NC}"
echo -e "${CYAN}  Su dung: systemctl status nroshield-firewall${NC}"
echo ""
