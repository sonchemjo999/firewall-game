#!/bin/bash
# ============================================================================
# NRO Shield — CrowdSec Setup
# ============================================================================
# Mô tả: Cấu hình CrowdSec cho threat intelligence cộng đồng
# ============================================================================

set -euo pipefail

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
log_info "  NRO Shield — CrowdSec Setup"
log_info "============================================"

# === 1. Kiểm tra CrowdSec đã cài ===
if ! command -v cscli &>/dev/null; then
    log_info "Đang cài đặt CrowdSec..."
    curl -s https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.deb.sh | bash
    apt-get install -y crowdsec crowdsec-firewall-bouncer-iptables
fi

# === 2. Cấu hình collections ===
log_info "Cài đặt CrowdSec collections..."

# Linux collection (SSH, syslog, iptables)
cscli collections install crowdsecurity/linux 2>/dev/null || true
# Iptables collection
cscli collections install crowdsecurity/iptables 2>/dev/null || true
# SSH brute force
cscli collections install crowdsecurity/sshd 2>/dev/null || true

log_ok "Collections đã cài"

# === 3. Đăng ký blocklists ===
log_info "Đăng ký blocklists cộng đồng..."

# CrowdSec community blocklist (mặc định đã có)
cscli hub update 2>/dev/null || true

log_ok "Blocklists đã đăng ký"

# === 4. Cấu hình firewall bouncer ===
log_info "Cấu hình firewall bouncer..."

BOUNCER_CONFIG="/etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml"
if [[ -f "$BOUNCER_CONFIG" ]]; then
    log_ok "Bouncer config tồn tại: ${BOUNCER_CONFIG}"
fi

# === 5. Tạo custom scenario cho NRO game ===
log_info "Tạo custom scenario cho game traffic..."

SCENARIO_DIR="/etc/crowdsec/scenarios"
mkdir -p "$SCENARIO_DIR"

cat > "${SCENARIO_DIR}/nroshield-conn-flood.yaml" << 'EOF'
type: leaky
name: nroshield/conn-flood
description: "Detect connection flood on game proxy ports"
filter: "evt.Meta.log_type == 'nroshield-drop'"
groupby: "evt.Meta.source_ip"
capacity: 50
leakspeed: "10s"
blackhole: 5m
labels:
  type: conn_flood
  remediation: true
EOF

cat > "${SCENARIO_DIR}/nroshield-port-scan.yaml" << 'EOF'
type: leaky
name: nroshield/port-scan
description: "Detect port scanning on NRO Shield"
filter: "evt.Meta.log_type == 'nroshield-drop'"
groupby: "evt.Meta.source_ip"
distinct: "evt.Meta.dest_port"
capacity: 10
leakspeed: "5s"
blackhole: 10m
labels:
  type: port_scan
  remediation: true
EOF

log_ok "Custom scenarios đã tạo"

# === 6. Cấu hình rsyslog parser cho NRO Shield logs ===
log_info "Cấu hình log parser..."

PARSER_DIR="/etc/crowdsec/parsers/s01-parse"
mkdir -p "$PARSER_DIR"

cat > "${PARSER_DIR}/nroshield-logs.yaml" << 'EOF'
onsuccess: next_stage
filter: "evt.Parsed.program == 'kernel' && evt.Parsed.message contains 'NROSHIELD-DROP'"
name: nroshield/nroshield-logs
description: "Parse NRO Shield firewall drop logs"
nodes:
  - grok:
      pattern: '\[NROSHIELD-DROP-%{WORD:action}\] IN=%{WORD:iface}.*SRC=%{IP:source_ip}.*DST=%{IP:dest_ip}.*DPT=%{NUMBER:dest_port}'
      apply_on: message
    statics:
      - meta: log_type
        value: nroshield-drop
      - meta: source_ip
        expression: evt.Parsed.source_ip
      - meta: dest_port
        expression: evt.Parsed.dest_port
EOF

log_ok "Log parser đã cấu hình"

# === 7. Restart services ===
log_info "Restart CrowdSec services..."
systemctl restart crowdsec
systemctl restart crowdsec-firewall-bouncer 2>/dev/null || true
systemctl enable crowdsec
systemctl enable crowdsec-firewall-bouncer 2>/dev/null || true

log_ok "Services đã restart"

# === Tổng kết ===
echo ""
log_info "============================================"
log_ok "  CROWDSEC ĐÃ THIẾT LẬP!"
log_info "============================================"
echo ""

echo "  Trạng thái:"
cscli metrics 2>/dev/null | head -5 || echo "  (Chưa có metrics)"
echo ""
echo "  Collections: $(cscli collections list -o json 2>/dev/null | jq length 2>/dev/null || echo 'N/A')"
echo "  Scenarios:   $(cscli scenarios list -o json 2>/dev/null | jq length 2>/dev/null || echo 'N/A')"
echo ""
log_info "Lệnh hữu ích:"
echo "  cscli decisions list          # Xem IP đang bị chặn"
echo "  cscli alerts list             # Xem cảnh báo"
echo "  cscli metrics                 # Xem thống kê"
echo "  cscli decisions add --ip X    # Chặn IP thủ công"
echo ""
log_info "Bước tiếp: chạy fail2ban_setup.sh"
