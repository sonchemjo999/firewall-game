#!/bin/bash
# ============================================================================
# NRO Shield — Anti-DDoS Protection Rules
# ============================================================================
# Mô tả: Rules chuyên biệt chống các phương thức DDoS phổ biến
# Chạy sau: iptables_base.sh
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../.env"

# Defaults
SYN_RATE_LIMIT="200/sec"
SYN_BURST="50"
UDP_RATE_LIMIT="1000/sec"
UDP_BURST="500"
ICMP_RATE_LIMIT="1/sec"
ICMP_BURST="4"
NEW_CONN_RATE="200/sec"
NEW_CONN_BURST="100"
MAX_CONN_PER_IP="500"
PROXY_PORT_RANGE_START="30000"
PROXY_PORT_RANGE_END="60000"

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
log_info "  NRO Shield — Anti-DDoS Rules"
log_info "============================================"

# ============================================================================
# 1. CHỐNG SYN FLOOD — hashlimit per IP
# ============================================================================
log_info "Thiết lập chống SYN Flood..."

# Tạo chain riêng cho SYN
iptables -N NROSHIELD_SYN 2>/dev/null || iptables -F NROSHIELD_SYN

# Rate limit SYN packets per source IP
iptables -A NROSHIELD_SYN -p tcp --syn \
    -m hashlimit \
    --hashlimit-above "$SYN_RATE_LIMIT" \
    --hashlimit-burst "$SYN_BURST" \
    --hashlimit-mode srcip \
    --hashlimit-name syn_flood \
    --hashlimit-htable-expire 30000 \
    -j DROP

# SYN hợp lệ — cho phép
iptables -A NROSHIELD_SYN -j RETURN

# Áp dụng cho INPUT và FORWARD
iptables -I INPUT 1 -p tcp --syn -j NROSHIELD_SYN
iptables -I FORWARD 1 -p tcp --syn -j NROSHIELD_SYN

log_ok "SYN Flood protection: rate limit ${SYN_RATE_LIMIT} per IP"

# ============================================================================
# 2. CHỐNG UDP FLOOD
# ============================================================================
log_info "Thiết lập chống UDP Flood..."

iptables -N NROSHIELD_UDP 2>/dev/null || iptables -F NROSHIELD_UDP

# Rate limit UDP per source IP
iptables -A NROSHIELD_UDP -p udp \
    -m hashlimit \
    --hashlimit-above "$UDP_RATE_LIMIT" \
    --hashlimit-burst "$UDP_BURST" \
    --hashlimit-mode srcip \
    --hashlimit-name udp_flood \
    --hashlimit-htable-expire 30000 \
    -j DROP

iptables -A NROSHIELD_UDP -j RETURN

iptables -I INPUT 2 -p udp -m conntrack --ctstate NEW -j NROSHIELD_UDP
iptables -I FORWARD 2 -p udp -m conntrack --ctstate NEW -j NROSHIELD_UDP

log_ok "UDP Flood protection: rate limit ${UDP_RATE_LIMIT} per IP"

# ============================================================================
# 3. CHỐNG ACK FLOOD
# ============================================================================
log_info "Thiết lập chống ACK Flood..."

iptables -N NROSHIELD_ACK 2>/dev/null || iptables -F NROSHIELD_ACK

# Rate limit ACK packets (chỉ những ACK không thuộc ESTABLISHED)
iptables -A NROSHIELD_ACK -p tcp --tcp-flags ALL ACK \
    -m conntrack --ctstate NEW \
    -m hashlimit \
    --hashlimit-above "100/sec" \
    --hashlimit-burst 20 \
    --hashlimit-mode srcip \
    --hashlimit-name ack_flood \
    -j DROP

iptables -A NROSHIELD_ACK -j RETURN

iptables -I INPUT 3 -p tcp --tcp-flags ALL ACK -j NROSHIELD_ACK

log_ok "ACK Flood protection đã thiết lập"

# ============================================================================
# 4. CHỐNG RST FLOOD
# ============================================================================
log_info "Thiết lập chống RST Flood..."

iptables -N NROSHIELD_RST 2>/dev/null || iptables -F NROSHIELD_RST

iptables -A NROSHIELD_RST -p tcp --tcp-flags RST RST \
    -m hashlimit \
    --hashlimit-above "50/sec" \
    --hashlimit-burst 10 \
    --hashlimit-mode srcip \
    --hashlimit-name rst_flood \
    -j DROP

iptables -A NROSHIELD_RST -j RETURN

iptables -I INPUT 4 -p tcp --tcp-flags RST RST -j NROSHIELD_RST

log_ok "RST Flood protection đã thiết lập"

# ============================================================================
# 5. CHỐNG CONNECTION EXHAUSTION (Slowloris)
# ============================================================================
log_info "Thiết lập chống Connection Exhaustion..."

# Giới hạn connection đồng thời per IP trên proxy ports (TCP & UDP)
iptables -I FORWARD 3 -p tcp \
    -m conntrack --ctorigdstport "$PROXY_PORT_RANGE_START":"$PROXY_PORT_RANGE_END" \
    -m connlimit --connlimit-above "$MAX_CONN_PER_IP" --connlimit-mask 32 \
    -j DROP
iptables -I FORWARD 3 -p udp \
    -m conntrack --ctorigdstport "$PROXY_PORT_RANGE_START":"$PROXY_PORT_RANGE_END" \
    -m connlimit --connlimit-above "$MAX_CONN_PER_IP" --connlimit-mask 32 \
    -j DROP

# Giới hạn new connection rate per IP (TCP)
iptables -I FORWARD 3 -p tcp \
    -m conntrack --ctorigdstport "$PROXY_PORT_RANGE_START":"$PROXY_PORT_RANGE_END" \
    -m conntrack --ctstate NEW \
    -m hashlimit \
    --hashlimit-above "$NEW_CONN_RATE" \
    --hashlimit-burst "$NEW_CONN_BURST" \
    --hashlimit-mode srcip \
    --hashlimit-name new_conn_tcp \
    --hashlimit-htable-expire 30000 \
    -j DROP

# Giới hạn new connection rate per IP (UDP)
iptables -I FORWARD 3 -p udp \
    -m conntrack --ctorigdstport "$PROXY_PORT_RANGE_START":"$PROXY_PORT_RANGE_END" \
    -m conntrack --ctstate NEW \
    -m hashlimit \
    --hashlimit-above "$NEW_CONN_RATE" \
    --hashlimit-burst "$NEW_CONN_BURST" \
    --hashlimit-mode srcip \
    --hashlimit-name new_conn_udp \
    --hashlimit-htable-expire 30000 \
    -j DROP

log_ok "Connection exhaustion protection: max ${MAX_CONN_PER_IP} conn/IP"

# ============================================================================
# 6. CHỐNG ICMP FLOOD (Ping of Death)
# ============================================================================
log_info "Thiết lập chống ICMP Flood..."

# Đã có rule cơ bản ở iptables_base.sh, thêm hashlimit per IP
iptables -N NROSHIELD_ICMP 2>/dev/null || iptables -F NROSHIELD_ICMP

iptables -A NROSHIELD_ICMP -p icmp \
    -m hashlimit \
    --hashlimit-above "$ICMP_RATE_LIMIT" \
    --hashlimit-burst "$ICMP_BURST" \
    --hashlimit-mode srcip \
    --hashlimit-name icmp_flood \
    -j DROP

iptables -A NROSHIELD_ICMP -j RETURN

# Chèn trước rule ICMP accept ở base
iptables -I INPUT 5 -p icmp -j NROSHIELD_ICMP

log_ok "ICMP Flood protection: ${ICMP_RATE_LIMIT} per IP"

# ============================================================================
# 7. CHỐNG DNS/NTP/SSDP AMPLIFICATION
# ============================================================================
log_info "Thiết lập chống Amplification attacks..."

# Block incoming DNS responses mà mình không request
iptables -A INPUT -p udp --sport 53 -m conntrack --ctstate NEW -j DROP
# Block incoming NTP responses
iptables -A INPUT -p udp --sport 123 -m conntrack --ctstate NEW -j DROP
# Block incoming SSDP
iptables -A INPUT -p udp --sport 1900 -m conntrack --ctstate NEW -j DROP
# Block incoming SNMP
iptables -A INPUT -p udp --sport 161 -m conntrack --ctstate NEW -j DROP
# Block incoming Memcached
iptables -A INPUT -p udp --sport 11211 -m conntrack --ctstate NEW -j DROP
# Block incoming CLDAP
iptables -A INPUT -p udp --sport 389 -m conntrack --ctstate NEW -j DROP

log_ok "Amplification attack protection đã thiết lập"

# ============================================================================
# 8. CHỐNG GRE/IPIP TUNNEL FLOOD
# ============================================================================
log_info "Chống GRE/IPIP Flood..."

# Drop GRE protocol (nếu không dùng VPN)
iptables -A INPUT -p gre -j DROP
# Drop IPIP tunnel
iptables -A INPUT -p ipencap -j DROP

log_ok "GRE/IPIP Flood protection đã thiết lập"

# ============================================================================
# LƯU RULES
# ============================================================================
log_info "Lưu rules..."
iptables-save > /etc/iptables/rules.v4 2>/dev/null || \
    iptables-save > /etc/iptables.rules 2>/dev/null || true

echo ""
log_info "============================================"
log_ok "  ANTI-DDoS RULES ĐÃ THIẾT LẬP!"
log_info "============================================"
echo ""
echo "  🛡️ SYN Flood:          hashlimit ${SYN_RATE_LIMIT}/IP"
echo "  🛡️ UDP Flood:          hashlimit ${UDP_RATE_LIMIT}/IP"
echo "  🛡️ ACK Flood:          hashlimit 100/sec/IP"
echo "  🛡️ RST Flood:          hashlimit 50/sec/IP"
echo "  🛡️ Connection Limit:   ${MAX_CONN_PER_IP}/IP"
echo "  🛡️ New Conn Rate:      ${NEW_CONN_RATE}/IP"
echo "  🛡️ ICMP:               ${ICMP_RATE_LIMIT}/IP"
echo "  🛡️ Amplification:      DNS/NTP/SSDP/SNMP/Memcached blocked"
echo "  🛡️ Tunnel:             GRE/IPIP blocked"
echo ""
log_info "Bước tiếp: chạy anti_botnet.sh"
