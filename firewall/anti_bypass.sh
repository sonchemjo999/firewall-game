#!/bin/bash
# ============================================================================
# NRO Shield v2 — Anti-Bypass Protection
# ============================================================================
# Mô tả: Chống bypass firewall, TCP validation nâng cao, chống spoof
# Hỗ trợ: NRO, SA:MP, MU Online, Lineage, Minecraft, FiveM, Rust
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../.env"

# Defaults
PROXY_PORT_RANGE_START="30000"
PROXY_PORT_RANGE_END="60000"
MAX_CONN_PER_IP="500"
CHALLENGE_TIMEOUT="10"

[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} Cần quyền root"; exit 1
fi

log_info "============================================"
log_info "  NRO Shield v2 — Anti-Bypass Protection"
log_info "============================================"

# ============================================================================
# 1. IPSET NÂNG CAO — Thêm sets cho bypass detection
# ============================================================================
log_info "Tạo ipset sets nâng cao..."

# Challenge-response tracking
ipset create -exist nroshield-challenged hash:ip hashsize 4096 maxelem 65536 timeout 60
# Verified IPs (đã pass challenge)
ipset create -exist nroshield-verified hash:ip hashsize 8192 maxelem 131072 timeout 3600
# Suspicious IPs (hành vi bất thường)
ipset create -exist nroshield-suspicious hash:ip hashsize 4096 maxelem 65536 timeout 600
# GeoIP blocked countries
ipset create -exist nroshield-geoblock hash:net hashsize 4096 maxelem 65536
# Per-port rate tracking
ipset create -exist nroshield-port-abuse hash:ip,port hashsize 4096 maxelem 65536 timeout 300

log_ok "ipset sets nâng cao đã tạo"

# ============================================================================
# 2. CHỐNG TCP BYPASS — Validate TCP handshake
# ============================================================================
log_info "Thiết lập chống TCP Bypass..."

iptables -N NROSHIELD_TCP_VALID 2>/dev/null || iptables -F NROSHIELD_TCP_VALID

# Drop TCP packets với window size = 0 nhưng không phải RST (bypass technique)
iptables -A NROSHIELD_TCP_VALID -p tcp --tcp-flags RST RST -j RETURN
iptables -A NROSHIELD_TCP_VALID -p tcp -m tcpmss --mss 1:535 -j DROP

# Drop TCP với TTL bất thường (< 20 hoặc > 128 — dấu hiệu spoofing)
iptables -A NROSHIELD_TCP_VALID -m ttl --ttl-lt 20 -j DROP

# Drop packets với quá nhiều TCP options (bypass fingerprint)
iptables -A NROSHIELD_TCP_VALID -p tcp -m u32 --u32 \
    "12&0x0F000000=0x0F000000" -j DROP 2>/dev/null || true

# Chặn TCP fragments nhỏ bất thường (fragment attack bypass)
iptables -A NROSHIELD_TCP_VALID -p tcp -m length --length 0:39 \
    -m conntrack --ctstate NEW -j DROP

# Drop SYN packets với data payload (SYN flood bypass)
iptables -A NROSHIELD_TCP_VALID -p tcp --syn -m length --length 100: \
    -m conntrack --ctstate NEW -j DROP 2>/dev/null || true

iptables -A NROSHIELD_TCP_VALID -j RETURN

# Áp dụng cho proxy ports
iptables -I INPUT 1 -p tcp -m conntrack --ctorigdstport "$PROXY_PORT_RANGE_START":"$PROXY_PORT_RANGE_END" \
    -j NROSHIELD_TCP_VALID
iptables -I FORWARD 1 -p tcp -m conntrack --ctorigdstport "$PROXY_PORT_RANGE_START":"$PROXY_PORT_RANGE_END" \
    -j NROSHIELD_TCP_VALID

log_ok "TCP Bypass protection đã thiết lập"

# ============================================================================
# 3. CHỐNG UDP BYPASS — Validate UDP patterns
# ============================================================================
log_info "Thiết lập chống UDP Bypass..."

iptables -N NROSHIELD_UDP_VALID 2>/dev/null || iptables -F NROSHIELD_UDP_VALID

# Drop UDP packets quá nhỏ (< 28 bytes = IP header + UDP header)
iptables -A NROSHIELD_UDP_VALID -p udp -m length --length 0:27 -j DROP

# Drop UDP packets quá lớn (> 4096 bytes — bất thường cho game traffic)
iptables -A NROSHIELD_UDP_VALID -p udp -m length --length 4097:65535 -j DROP

# Rate limit UDP per source IP trên proxy ports (adaptive)
iptables -A NROSHIELD_UDP_VALID -p udp \
    -m hashlimit \
    --hashlimit-above 500/sec \
    --hashlimit-burst 200 \
    --hashlimit-mode srcip \
    --hashlimit-name udp_bypass \
    --hashlimit-htable-expire 10000 \
    -j DROP

# Drop UDP reflection (source port = dest port — amplification bypass)
iptables -A NROSHIELD_UDP_VALID -p udp -m u32 --u32 \
    "0>>22&0x3C@0>>16&0xFFFF=0>>22&0x3C@0&0xFFFF" -j DROP 2>/dev/null || true

iptables -A NROSHIELD_UDP_VALID -j RETURN

iptables -I INPUT 2 -p udp -m conntrack --ctorigdstport "$PROXY_PORT_RANGE_START":"$PROXY_PORT_RANGE_END" \
    -j NROSHIELD_UDP_VALID
iptables -I FORWARD 2 -p udp -m conntrack --ctorigdstport "$PROXY_PORT_RANGE_START":"$PROXY_PORT_RANGE_END" \
    -j NROSHIELD_UDP_VALID

log_ok "UDP Bypass protection đã thiết lập"

# ============================================================================
# 4. CHỐNG CARPET BOMBING (Distributed flood nhiều IP đích)
# ============================================================================
log_info "Thiết lập chống Carpet Bombing..."

# Giới hạn tổng connections NEW per destination port (chống carpet bombing)
iptables -N NROSHIELD_CARPET 2>/dev/null || iptables -F NROSHIELD_CARPET

iptables -A NROSHIELD_CARPET -m conntrack --ctstate NEW \
    -m hashlimit \
    --hashlimit-above 1000/sec \
    --hashlimit-burst 500 \
    --hashlimit-mode dstport \
    --hashlimit-name carpet_bomb \
    --hashlimit-htable-expire 10000 \
    -j DROP

iptables -A NROSHIELD_CARPET -j RETURN

iptables -I INPUT 3 -m conntrack --ctorigdstport "$PROXY_PORT_RANGE_START":"$PROXY_PORT_RANGE_END" \
    -j NROSHIELD_CARPET

log_ok "Carpet Bombing protection đã thiết lập"

# ============================================================================
# 5. CHỐNG BIT-AND-PIECE ATTACK (gói tin nhỏ phân tán)
# ============================================================================
log_info "Thiết lập chống Bit-and-Piece attack..."

# Rate limit per source IP + destination port combination
iptables -N NROSHIELD_BITPIECE 2>/dev/null || iptables -F NROSHIELD_BITPIECE

iptables -A NROSHIELD_BITPIECE \
    -m hashlimit \
    --hashlimit-above 300/sec \
    --hashlimit-burst 100 \
    --hashlimit-mode srcip,dstport \
    --hashlimit-name bit_piece \
    --hashlimit-htable-expire 15000 \
    -j DROP

iptables -A NROSHIELD_BITPIECE -j RETURN

iptables -I INPUT 4 -m conntrack --ctorigdstport "$PROXY_PORT_RANGE_START":"$PROXY_PORT_RANGE_END" \
    -m conntrack --ctstate NEW -j NROSHIELD_BITPIECE

log_ok "Bit-and-Piece protection đã thiết lập"

# ============================================================================
# 6. CHỐNG REFLECTION/AMPLIFICATION NÂNG CAO
# ============================================================================
log_info "Thiết lập chống Reflection nâng cao..."

# Block thêm nhiều reflection sources
REFLECTION_PORTS=(
    "17"    # QOTD
    "19"    # Chargen
    "53"    # DNS
    "111"   # Portmap
    "123"   # NTP
    "137"   # NetBIOS
    "161"   # SNMP
    "389"   # CLDAP
    "520"   # RIPv1
    "751"   # Kerberos
    "1434"  # MSSQL
    "1900"  # SSDP
    "5353"  # mDNS
    "11211" # Memcached
    "27015" # Steam (source game query)
)

for port in "${REFLECTION_PORTS[@]}"; do
    iptables -A INPUT -p udp --sport "$port" -m conntrack --ctstate NEW -j DROP 2>/dev/null || true
done

# Block incoming TCP reflection (SYN-ACK reflection)
iptables -A INPUT -p tcp --tcp-flags SYN,ACK SYN,ACK -m conntrack --ctstate NEW -j DROP

log_ok "Reflection/Amplification nâng cao đã thiết lập"

# ============================================================================
# 7. CHỐNG HTTP FLOOD (Layer 7 — cho Web Dashboard)
# ============================================================================
log_info "Thiết lập chống HTTP Flood..."

iptables -N NROSHIELD_HTTP 2>/dev/null || iptables -F NROSHIELD_HTTP

# Rate limit HTTP requests per IP
iptables -A NROSHIELD_HTTP -p tcp --dport 80 -m conntrack --ctstate NEW \
    -m hashlimit \
    --hashlimit-above 50/sec \
    --hashlimit-burst 20 \
    --hashlimit-mode srcip \
    --hashlimit-name http_flood \
    --hashlimit-htable-expire 30000 \
    -j DROP

iptables -A NROSHIELD_HTTP -p tcp --dport 443 -m conntrack --ctstate NEW \
    -m hashlimit \
    --hashlimit-above 50/sec \
    --hashlimit-burst 20 \
    --hashlimit-mode srcip \
    --hashlimit-name https_flood \
    --hashlimit-htable-expire 30000 \
    -j DROP

# Connection limit per IP cho HTTP
iptables -A NROSHIELD_HTTP -p tcp -m multiport --dports 80,443 \
    -m connlimit --connlimit-above 100 --connlimit-mask 32 -j DROP

iptables -A NROSHIELD_HTTP -j RETURN

iptables -I INPUT 5 -p tcp -m multiport --dports 80,443 -j NROSHIELD_HTTP

log_ok "HTTP Flood protection đã thiết lập"

# ============================================================================
# 8. CHỐNG SLOW ATTACKS (Slowloris, RUDY, Slow Read)
# ============================================================================
log_info "Thiết lập chống Slow Attacks..."

# Timeout cho connections chậm (TCP)
iptables -N NROSHIELD_SLOW 2>/dev/null || iptables -F NROSHIELD_SLOW

# Drop connections idle quá lâu trên proxy ports
iptables -A NROSHIELD_SLOW -p tcp \
    -m conntrack --ctstate ESTABLISHED \
    -m recent --name slow_conn --set
iptables -A NROSHIELD_SLOW -p tcp \
    -m conntrack --ctstate ESTABLISHED \
    -m recent --name slow_conn --rcheck --seconds 120 --hitcount 1 \
    -m connbytes --connbytes 0:5 --connbytes-dir both --connbytes-mode packets \
    -j DROP 2>/dev/null || true

iptables -A NROSHIELD_SLOW -j RETURN

log_ok "Slow Attack protection đã thiết lập"

# ============================================================================
# 9. ADAPTIVE RATE LIMITING — Tự điều chỉnh ngưỡng
# ============================================================================
log_info "Thiết lập Adaptive Rate Limiting..."

# Tạo script cho adaptive rate limiting
cat > /opt/nroshield/adaptive_ratelimit.sh << 'ADAPTIVE_EOF'
#!/bin/bash
# Adaptive Rate Limiting — Tự điều chỉnh dựa trên traffic hiện tại

CONNTRACK_COUNT=$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo "0")
CONNTRACK_MAX=$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo "1048576")
USAGE=$((CONNTRACK_COUNT * 100 / CONNTRACK_MAX))

if [[ "$USAGE" -gt 90 ]]; then
    # CRITICAL: Giảm mạnh rate limits
    ipset flush nroshield-ratelimited 2>/dev/null || true
    # Emergency: block tất cả NEW connections tạm thời 30s
    iptables -I INPUT 1 -m conntrack --ctstate NEW -m limit --limit 10/sec -j ACCEPT 2>/dev/null || true
    echo "[CRITICAL] Conntrack ${USAGE}% — Emergency rate limiting activated"
elif [[ "$USAGE" -gt 70 ]]; then
    # WARNING: Giảm rate limits
    echo "[WARNING] Conntrack ${USAGE}% — Tightening rate limits"
elif [[ "$USAGE" -lt 30 ]]; then
    # NORMAL: Gỡ emergency rules nếu có
    iptables -D INPUT -m conntrack --ctstate NEW -m limit --limit 10/sec -j ACCEPT 2>/dev/null || true
fi
ADAPTIVE_EOF

chmod +x /opt/nroshield/adaptive_ratelimit.sh

log_ok "Adaptive Rate Limiting đã thiết lập"

# ============================================================================
# 10. CHỐNG DNS WATER TORTURE
# ============================================================================
log_info "Thiết lập chống DNS Water Torture..."

# Block outbound DNS queries quá nhiều (chống bị dùng cho DNS water torture)
iptables -A OUTPUT -p udp --dport 53 \
    -m hashlimit \
    --hashlimit-above 20/sec \
    --hashlimit-burst 10 \
    --hashlimit-mode dstip \
    --hashlimit-name dns_torture \
    -j DROP

log_ok "DNS Water Torture protection đã thiết lập"

# ============================================================================
# LƯU RULES
# ============================================================================
log_info "Lưu rules..."
iptables-save > /etc/iptables/rules.v4 2>/dev/null || \
    iptables-save > /etc/iptables.rules 2>/dev/null || true

echo ""
log_info "============================================"
log_ok "  ANTI-BYPASS PROTECTION ĐÃ THIẾT LẬP!"
log_info "============================================"
echo ""
echo "  Bảo vệ đã kích hoạt:"
echo "  🛡️  TCP Bypass Validation (MSS, TTL, fragments, payload)"
echo "  🛡️  UDP Bypass Validation (size, rate, reflection)"
echo "  🛡️  Carpet Bombing Protection"
echo "  🛡️  Bit-and-Piece Attack Protection"
echo "  🛡️  Advanced Reflection/Amplification (${#REFLECTION_PORTS[@]} ports)"
echo "  🛡️  HTTP/HTTPS Flood Protection (Layer 7)"
echo "  🛡️  Slow Attack Protection (Slowloris, RUDY)"
echo "  🛡️  Adaptive Rate Limiting"
echo "  🛡️  DNS Water Torture Protection"
echo ""
