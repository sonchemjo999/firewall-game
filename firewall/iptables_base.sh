#!/bin/bash
# ============================================================================
# NRO Shield — iptables Base Firewall Rules
# ============================================================================
# Mô tả: Thiết lập luật tường lửa cơ bản, ipset, và port forwarding NAT
# ============================================================================

set -euo pipefail

# === Load config ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../.env"

# Defaults (override bằng .env)
VPS_PUBLIC_IP=""
SSH_PORT="22"
GAME_PORTS="14445,20000,1875"
API_PORT="5000"
AI_ENGINE_PORT="8000"
PROXY_PORT_RANGE_START="30000"
PROXY_PORT_RANGE_END="60000"
MAX_CONN_PER_IP="500"

# Load .env nếu có
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} Cần quyền root"
    exit 1
fi

log_info "============================================"
log_info "  NRO Shield — Base Firewall Rules"
log_info "============================================"

# ============================================================================
# 1. TẠO IPSET SETS
# ============================================================================
log_info "Tạo ipset sets..."

# Whitelist IPs (luôn được cho phép)
ipset create -exist nroshield-whitelist hash:ip hashsize 4096 maxelem 65536
# Blacklist IPs (luôn bị chặn)
ipset create -exist nroshield-blacklist hash:ip hashsize 4096 maxelem 65536 timeout 86400
# Botnet IPs (từ blocklists)
ipset create -exist nroshield-botnet hash:net hashsize 65536 maxelem 1048576
# AI auto-blocked IPs (timeout 1 giờ mặc định)
ipset create -exist nroshield-ai-blocked hash:ip hashsize 4096 maxelem 65536 timeout 3600
# Rate-limited IPs (tạm chậm)
ipset create -exist nroshield-ratelimited hash:ip hashsize 4096 maxelem 65536 timeout 300

log_ok "ipset sets đã tạo"

# ============================================================================
# 2. FLUSH TẤT CẢ RULES CŨ
# ============================================================================
log_info "Flush iptables rules cũ..."

iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
iptables -t raw -F
iptables -t raw -X

log_ok "Đã flush tất cả rules"

# ============================================================================
# 3. CHÍNH SÁCH MẶC ĐỊNH: DROP INPUT, DROP FORWARD, ACCEPT OUTPUT
# ============================================================================
log_info "Thiết lập chính sách mặc định..."

iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

log_ok "Chính sách: INPUT=DROP, FORWARD=DROP, OUTPUT=ACCEPT"

# ============================================================================
# 4. LOOPBACK — Cho phép traffic nội bộ
# ============================================================================
log_info "Cho phép loopback..."

iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# ============================================================================
# 5. ESTABLISHED/RELATED — Cho phép connection đã thiết lập
# ============================================================================
log_info "Cho phép established/related..."

iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# ============================================================================
# 6. DROP INVALID PACKETS (raw/mangle)
# ============================================================================
log_info "Drop invalid packets..."

# Drop invalid ở mangle table (sớm nhất có thể)
iptables -t mangle -A PREROUTING -m conntrack --ctstate INVALID -j DROP

# Drop TCP packets không phải SYN mà lại NEW
iptables -t mangle -A PREROUTING -p tcp ! --syn -m conntrack --ctstate NEW -j DROP

# [REMOVED] Drop fragmented packets - This breaks RakNet/UDP gaming payloads (SA:MP)
# iptables -t mangle -A PREROUTING -f -j DROP

# Drop MSS bất thường
iptables -t mangle -A PREROUTING -p tcp -m conntrack --ctstate NEW -m tcpmss ! --mss 536:65535 -j DROP

log_ok "Invalid packet rules đã thiết lập"

# ============================================================================
# 7. CHỐNG PORT SCAN — Drop TCP flags bất thường
# ============================================================================
log_info "Chống port scan..."

# XMAS scan (tất cả flags bật)
iptables -t mangle -A PREROUTING -p tcp --tcp-flags ALL ALL -j DROP
# NULL scan (không có flag nào)
iptables -t mangle -A PREROUTING -p tcp --tcp-flags ALL NONE -j DROP
# FIN scan
iptables -t mangle -A PREROUTING -p tcp --tcp-flags ALL FIN -j DROP
# SYN-FIN (không hợp lệ)
iptables -t mangle -A PREROUTING -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP
# SYN-RST (không hợp lệ)
iptables -t mangle -A PREROUTING -p tcp --tcp-flags SYN,RST SYN,RST -j DROP
# FIN-RST (không hợp lệ)
iptables -t mangle -A PREROUTING -p tcp --tcp-flags FIN,RST FIN,RST -j DROP
# FIN without ACK
iptables -t mangle -A PREROUTING -p tcp --tcp-flags ACK,FIN FIN -j DROP
# URG without ACK
iptables -t mangle -A PREROUTING -p tcp --tcp-flags ACK,URG URG -j DROP
# PSH without ACK
iptables -t mangle -A PREROUTING -p tcp --tcp-flags ACK,PSH PSH -j DROP

log_ok "Port scan protection đã thiết lập"

# ============================================================================
# 8. IPSET RULES — Whitelist / Blacklist / Botnet
# ============================================================================
log_info "Áp dụng ipset rules..."

# Whitelist — luôn ACCEPT
iptables -A INPUT -m set --match-set nroshield-whitelist src -j ACCEPT
iptables -A FORWARD -m set --match-set nroshield-whitelist src -j ACCEPT

# Blacklist — luôn DROP
iptables -A INPUT -m set --match-set nroshield-blacklist src -j DROP
iptables -A FORWARD -m set --match-set nroshield-blacklist src -j DROP

# Botnet — luôn DROP
iptables -A INPUT -m set --match-set nroshield-botnet src -j DROP
iptables -A FORWARD -m set --match-set nroshield-botnet src -j DROP

# AI auto-blocked — DROP
iptables -A INPUT -m set --match-set nroshield-ai-blocked src -j DROP
iptables -A FORWARD -m set --match-set nroshield-ai-blocked src -j DROP

log_ok "ipset rules đã áp dụng"

# ============================================================================
# 9. SSH — Cho phép truy cập quản trị
# ============================================================================
log_info "Cho phép SSH port ${SSH_PORT}..."

iptables -A INPUT -p tcp --dport "$SSH_PORT" -m conntrack --ctstate NEW \
    -m recent --set --name ssh_limit
iptables -A INPUT -p tcp --dport "$SSH_PORT" -m conntrack --ctstate NEW \
    -m recent --update --seconds 60 --hitcount 50 --name ssh_limit -j DROP
iptables -A INPUT -p tcp --dport "$SSH_PORT" -m conntrack --ctstate NEW -j ACCEPT

# ============================================================================
# 10. INTERNAL SERVICES — API, Web, AI (chỉ từ localhost hoặc VPS IP)
# ============================================================================
log_info "Cho phép internal services..."

# Web Servers (HTTP/HTTPS)
iptables -A INPUT -p tcp -m multiport --dports 80,443 -j ACCEPT
# API
iptables -A INPUT -p tcp --dport "$API_PORT" -j ACCEPT
# AI Engine
iptables -A INPUT -p tcp --dport "$AI_ENGINE_PORT" -s 127.0.0.1 -j ACCEPT

# ============================================================================
# 11. ICMP — Giới hạn ping
# ============================================================================
log_info "Giới hạn ICMP..."

iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/s --limit-burst 4 -j ACCEPT
iptables -A INPUT -p icmp --icmp-type echo-request -j DROP

# ============================================================================
# 12. PROXY PORT RANGE — Cho phép traffic vào proxy ports
# ============================================================================
log_info "Cho phép proxy port range ${PROXY_PORT_RANGE_START}-${PROXY_PORT_RANGE_END}..."

# Giới hạn Connection limits per IP cho TCP Proxy (nếu vào thẳng VPS)
iptables -A INPUT -p tcp -m conntrack --ctorigdstport "$PROXY_PORT_RANGE_START":"$PROXY_PORT_RANGE_END" \
    -m connlimit --connlimit-above "$MAX_CONN_PER_IP" --connlimit-mask 32 -j DROP

# TCP + UDP: Cho phép connection mới
iptables -A INPUT -p tcp -m conntrack --ctorigdstport "$PROXY_PORT_RANGE_START":"$PROXY_PORT_RANGE_END" \
    -m conntrack --ctstate NEW -j ACCEPT
iptables -A INPUT -p udp -m conntrack --ctorigdstport "$PROXY_PORT_RANGE_START":"$PROXY_PORT_RANGE_END" \
    -m conntrack --ctstate NEW -j ACCEPT

# ============================================================================
# 13. FORWARD RULES — Cho phép NAT forwarded traffic
# ============================================================================
log_info "Thiết lập FORWARD rules..."

# Giới hạn Connection limits cho FORWARD (DNAT external server)
iptables -A FORWARD -p tcp -m conntrack --ctorigdstport "$PROXY_PORT_RANGE_START":"$PROXY_PORT_RANGE_END" \
    -m connlimit --connlimit-above "$MAX_CONN_PER_IP" --connlimit-mask 32 -j DROP

iptables -A FORWARD -m conntrack --ctstate NEW -j ACCEPT

# ============================================================================
# 14. NAT — MASQUERADE cho outbound traffic
# ============================================================================
log_info "Thiết lập NAT MASQUERADE..."

iptables -t nat -A POSTROUTING -j MASQUERADE

# ============================================================================
# 15. LOGGING — Ghi log packets bị drop
# ============================================================================
log_info "Thiết lập logging..."

# Log INPUT drops (giới hạn 5/min để tránh flood log)
iptables -A INPUT -m limit --limit 5/min --limit-burst 10 \
    -j LOG --log-prefix "[NROSHIELD-DROP-IN] " --log-level 4

# Log FORWARD drops
iptables -A FORWARD -m limit --limit 5/min --limit-burst 10 \
    -j LOG --log-prefix "[NROSHIELD-DROP-FWD] " --log-level 4

# ============================================================================
# 16. LƯU RULES — Persist qua reboot
# ============================================================================
log_info "Lưu iptables rules..."

# Lưu ipset
ipset save > /etc/ipset.rules 2>/dev/null || true

# Lưu iptables
iptables-save > /etc/iptables/rules.v4 2>/dev/null || \
    iptables-save > /etc/iptables.rules 2>/dev/null || true

log_ok "Rules đã lưu"

# ============================================================================
# TỔNG KẾT
# ============================================================================
echo ""
log_info "============================================"
log_ok "  BASE FIREWALL ĐÃ THIẾT LẬP!"
log_info "============================================"
echo ""

TOTAL_RULES=$(iptables -L -n | grep -c "^[A-Z]" || echo "0")
MANGLE_RULES=$(iptables -t mangle -L -n | grep -c "^[A-Z]" || echo "0")
NAT_RULES=$(iptables -t nat -L -n | grep -c "^[A-Z]" || echo "0")

echo "  📊 Input/Forward rules: ${TOTAL_RULES}"
echo "  🔧 Mangle rules:       ${MANGLE_RULES}"
echo "  🔀 NAT rules:          ${NAT_RULES}"
echo "  📋 ipset sets:         $(ipset list -n | wc -l)"
echo ""
log_info "Bước tiếp: chạy anti_ddos.sh"
