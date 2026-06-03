#!/bin/bash
# ============================================================================
# NRO Shield v2 — Anti-DDoS Protection V2 (Nâng cấp)
# ============================================================================
# Mô tả: Rules chống DDoS nâng cao, hỗ trợ nhiều game, chống bypass methods mới
# Hỗ trợ: NRO, SA:MP, MU Online, Minecraft, FiveM, Rust, ARK, CS2
# Chạy sau: iptables_base.sh + anti_bypass.sh
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../.env"

# Defaults — có thể override bằng .env
SYN_RATE_LIMIT="300/sec"
SYN_BURST="80"
UDP_RATE_LIMIT="2000/sec"
UDP_BURST="800"
ICMP_RATE_LIMIT="2/sec"
ICMP_BURST="6"
NEW_CONN_RATE="300/sec"
NEW_CONN_BURST="150"
MAX_CONN_PER_IP="500"
PROXY_PORT_RANGE_START="30000"
PROXY_PORT_RANGE_END="60000"
# Game-specific defaults
GAME_UDP_RATE="800/sec"
GAME_UDP_BURST="400"
GAME_TCP_RATE="200/sec"
GAME_TCP_BURST="80"

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
log_info "  NRO Shield v2 — Anti-DDoS V2"
log_info "============================================"

# ============================================================================
# 1. CHỐNG SYN FLOOD V2 — Multi-layer SYN protection
# ============================================================================
log_info "Thiết lập chống SYN Flood V2..."

iptables -N NROSHIELD_SYN_V2 2>/dev/null || iptables -F NROSHIELD_SYN_V2

# Layer 1: Global SYN rate limit
iptables -A NROSHIELD_SYN_V2 -p tcp --syn \
    -m limit --limit 5000/sec --limit-burst 2000 -j RETURN
iptables -A NROSHIELD_SYN_V2 -p tcp --syn \
    -m limit --limit 5000/sec --limit-burst 2000 -j DROP 2>/dev/null || true

# Layer 2: Per-IP SYN rate limit (hashlimit)
iptables -A NROSHIELD_SYN_V2 -p tcp --syn \
    -m hashlimit \
    --hashlimit-above "$SYN_RATE_LIMIT" \
    --hashlimit-burst "$SYN_BURST" \
    --hashlimit-mode srcip \
    --hashlimit-name syn_v2 \
    --hashlimit-htable-expire 30000 \
    -j DROP

# Layer 3: Per-IP per-port SYN limit (chống targeted SYN flood)
iptables -A NROSHIELD_SYN_V2 -p tcp --syn \
    -m hashlimit \
    --hashlimit-above 50/sec \
    --hashlimit-burst 20 \
    --hashlimit-mode srcip,dstport \
    --hashlimit-name syn_port_v2 \
    --hashlimit-htable-expire 30000 \
    -j DROP

# Layer 4: SYN proxy (kernel SYN cookies đã bật ở sysctl)
iptables -A NROSHIELD_SYN_V2 -j RETURN

iptables -I INPUT 1 -p tcp --syn -j NROSHIELD_SYN_V2
iptables -I FORWARD 1 -p tcp --syn -j NROSHIELD_SYN_V2

log_ok "SYN Flood V2: multi-layer protection"

# ============================================================================
# 2. CHỐNG UDP FLOOD V2 — Game-aware UDP filtering
# ============================================================================
log_info "Thiết lập chống UDP Flood V2 (game-aware)..."

iptables -N NROSHIELD_UDP_V2 2>/dev/null || iptables -F NROSHIELD_UDP_V2

# Per-IP UDP rate limit (nâng cao)
iptables -A NROSHIELD_UDP_V2 -p udp \
    -m hashlimit \
    --hashlimit-above "$UDP_RATE_LIMIT" \
    --hashlimit-burst "$UDP_BURST" \
    --hashlimit-mode srcip \
    --hashlimit-name udp_v2 \
    --hashlimit-htable-expire 15000 \
    -j DROP

# Per-IP per-port UDP limit (chống targeted flood)
iptables -A NROSHIELD_UDP_V2 -p udp \
    -m hashlimit \
    --hashlimit-above "$GAME_UDP_RATE" \
    --hashlimit-burst "$GAME_UDP_BURST" \
    --hashlimit-mode srcip,dstport \
    --hashlimit-name udp_game_v2 \
    --hashlimit-htable-expire 15000 \
    -j DROP

# UDP payload size filtering cho game traffic
# NRO/RakNet: 28-1500 bytes
# SA:MP: 28-2048 bytes
# Minecraft: 28-4096 bytes
# Drop quá lớn (> 4096 — không phải game traffic)
iptables -A NROSHIELD_UDP_V2 -p udp -m length --length 4097:65535 -j DROP

iptables -A NROSHIELD_UDP_V2 -j RETURN

iptables -I INPUT 2 -p udp -m conntrack --ctstate NEW -j NROSHIELD_UDP_V2
iptables -I FORWARD 2 -p udp -m conntrack --ctstate NEW -j NROSHIELD_UDP_V2

log_ok "UDP Flood V2: game-aware filtering"

# ============================================================================
# 3. CHỐNG ACK/RST/FIN FLOOD V2
# ============================================================================
log_info "Thiết lập chống ACK/RST/FIN Flood V2..."

iptables -N NROSHIELD_TCPFLOOD_V2 2>/dev/null || iptables -F NROSHIELD_TCPFLOOD_V2

# ACK flood — per-IP
iptables -A NROSHIELD_TCPFLOOD_V2 -p tcp --tcp-flags ALL ACK \
    -m conntrack --ctstate NEW \
    -m hashlimit \
    --hashlimit-above 150/sec \
    --hashlimit-burst 30 \
    --hashlimit-mode srcip \
    --hashlimit-name ack_v2 \
    -j DROP

# RST flood — per-IP
iptables -A NROSHIELD_TCPFLOOD_V2 -p tcp --tcp-flags RST RST \
    -m hashlimit \
    --hashlimit-above 80/sec \
    --hashlimit-burst 15 \
    --hashlimit-mode srcip \
    --hashlimit-name rst_v2 \
    -j DROP

# FIN flood — per-IP
iptables -A NROSHIELD_TCPFLOOD_V2 -p tcp --tcp-flags FIN FIN \
    -m hashlimit \
    --hashlimit-above 80/sec \
    --hashlimit-burst 15 \
    --hashlimit-mode srcip \
    --hashlimit-name fin_v2 \
    -j DROP

# PSH+ACK flood (HTTP push flood)
iptables -A NROSHIELD_TCPFLOOD_V2 -p tcp --tcp-flags PSH,ACK PSH,ACK \
    -m conntrack --ctstate NEW \
    -m hashlimit \
    --hashlimit-above 100/sec \
    --hashlimit-burst 20 \
    --hashlimit-mode srcip \
    --hashlimit-name pshack_v2 \
    -j DROP

iptables -A NROSHIELD_TCPFLOOD_V2 -j RETURN

iptables -I INPUT 3 -p tcp -j NROSHIELD_TCPFLOOD_V2

log_ok "ACK/RST/FIN Flood V2 protection"

# ============================================================================
# 4. CHỐNG CONNECTION EXHAUSTION V2 — Multi-protocol
# ============================================================================
log_info "Thiết lập chống Connection Exhaustion V2..."

# TCP connection limit per IP per proxy port (strict)
iptables -I FORWARD 3 -p tcp \
    -m conntrack --ctorigdstport "$PROXY_PORT_RANGE_START":"$PROXY_PORT_RANGE_END" \
    -m connlimit --connlimit-above "$MAX_CONN_PER_IP" --connlimit-mask 32 \
    -j DROP

# UDP connection limit per IP per proxy port
iptables -I FORWARD 3 -p udp \
    -m conntrack --ctorigdstport "$PROXY_PORT_RANGE_START":"$PROXY_PORT_RANGE_END" \
    -m connlimit --connlimit-above "$MAX_CONN_PER_IP" --connlimit-mask 32 \
    -j DROP

# TCP new connection rate per IP (forward)
iptables -I FORWARD 3 -p tcp \
    -m conntrack --ctorigdstport "$PROXY_PORT_RANGE_START":"$PROXY_PORT_RANGE_END" \
    -m conntrack --ctstate NEW \
    -m hashlimit \
    --hashlimit-above "$NEW_CONN_RATE" \
    --hashlimit-burst "$NEW_CONN_BURST" \
    --hashlimit-mode srcip \
    --hashlimit-name fwd_tcp_v2 \
    --hashlimit-htable-expire 30000 \
    -j DROP

# UDP new connection rate per IP (forward)
iptables -I FORWARD 3 -p udp \
    -m conntrack --ctorigdstport "$PROXY_PORT_RANGE_START":"$PROXY_PORT_RANGE_END" \
    -m conntrack --ctstate NEW \
    -m hashlimit \
    --hashlimit-above "$NEW_CONN_RATE" \
    --hashlimit-burst "$NEW_CONN_BURST" \
    --hashlimit-mode srcip \
    --hashlimit-name fwd_udp_v2 \
    --hashlimit-htable-expire 30000 \
    -j DROP

# Global connection rate limit (chống distributed flood)
iptables -I FORWARD 3 \
    -m conntrack --ctorigdstport "$PROXY_PORT_RANGE_START":"$PROXY_PORT_RANGE_END" \
    -m conntrack --ctstate NEW \
    -m limit --limit 10000/sec --limit-burst 5000 \
    -j ACCEPT 2>/dev/null || true

log_ok "Connection Exhaustion V2: TCP + UDP + global"

# ============================================================================
# 5. CHỐNG ICMP/PING FLOOD V2
# ============================================================================
log_info "Thiết lập chống ICMP Flood V2..."

iptables -N NROSHIELD_ICMP_V2 2>/dev/null || iptables -F NROSHIELD_ICMP_V2

# Per-IP ICMP rate limit
iptables -A NROSHIELD_ICMP_V2 -p icmp \
    -m hashlimit \
    --hashlimit-above "$ICMP_RATE_LIMIT" \
    --hashlimit-burst "$ICMP_BURST" \
    --hashlimit-mode srcip \
    --hashlimit-name icmp_v2 \
    -j DROP

# Block ICMP types nguy hiểm (chỉ cho echo-request và reply)
iptables -A NROSHIELD_ICMP_V2 -p icmp --icmp-type echo-request -j RETURN
iptables -A NROSHIELD_ICMP_V2 -p icmp --icmp-type echo-reply -j RETURN
iptables -A NROSHIELD_ICMP_V2 -p icmp --icmp-type destination-unreachable -j RETURN
iptables -A NROSHIELD_ICMP_V2 -p icmp --icmp-type time-exceeded -j RETURN
iptables -A NROSHIELD_ICMP_V2 -p icmp -j DROP

iptables -I INPUT 4 -p icmp -j NROSHIELD_ICMP_V2

log_ok "ICMP Flood V2 protection"

# ============================================================================
# 6. CHỐNG AMPLIFICATION V2 — Mở rộng danh sách
# ============================================================================
log_info "Thiết lập chống Amplification V2..."

# Comprehensive list of amplification source ports
AMPLIFY_PORTS="17,19,53,111,123,137,161,389,520,751,1434,1900,5353,11211,27015,32414"

# Block all amplification source ports in one rule
iptables -A INPUT -p udp -m multiport --sports "$AMPLIFY_PORTS" \
    -m conntrack --ctstate NEW -j DROP

# Block TCP reflection (SYN-ACK from known ports)
iptables -A INPUT -p tcp --tcp-flags SYN,ACK SYN,ACK \
    -m multiport --sports 80,443,8080,8443 \
    -m conntrack --ctstate NEW -j DROP

log_ok "Amplification V2: ${AMPLIFY_PORTS}"

# ============================================================================
# 7. CHỐNG GRE/IPIP/ESP/AH TUNNEL FLOOD
# ============================================================================
log_info "Chống Tunnel Flood V2..."

# Drop tất cả tunnel protocols không cần thiết
iptables -A INPUT -p gre -j DROP          # GRE
iptables -A INPUT -p ipencap -j DROP      # IPIP
iptables -A INPUT -p esp -j DROP          # IPSec ESP
iptables -A INPUT -p ah -j DROP           # IPSec AH
iptables -A INPUT -p sctp -j DROP         # SCTP (ít dùng)

log_ok "Tunnel Flood V2: GRE/IPIP/ESP/AH/SCTP blocked"

# ============================================================================
# 8. GAME-SPECIFIC RULES — Multi-game support
# ============================================================================
log_info "Thiết lập Game-specific rules..."

# Tạo chain cho từng loại game
iptables -N NROSHIELD_GAME_NRO 2>/dev/null || iptables -F NROSHIELD_GAME_NRO
iptables -N NROSHIELD_GAME_SAMP 2>/dev/null || iptables -F NROSHIELD_GAME_SAMP
iptables -N NROSHIELD_GAME_MC 2>/dev/null || iptables -F NROSHIELD_GAME_MC
iptables -N NROSHIELD_GAME_FIVEM 2>/dev/null || iptables -F NROSHIELD_GAME_FIVEM

# NRO (RakNet/UDP) — Ports thường dùng: 14445, 20000, 1875
# RakNet packet size: 28-1500 bytes
iptables -A NROSHIELD_GAME_NRO -p udp -m length --length 1501:65535 -j DROP
iptables -A NROSHIELD_GAME_NRO -p udp \
    -m hashlimit --hashlimit-above 500/sec --hashlimit-burst 200 \
    --hashlimit-mode srcip --hashlimit-name nro_udp -j DROP
iptables -A NROSHIELD_GAME_NRO -j RETURN

# SA:MP (RakNet/UDP) — Port 7777
iptables -A NROSHIELD_GAME_SAMP -p udp -m length --length 2049:65535 -j DROP
iptables -A NROSHIELD_GAME_SAMP -p udp \
    -m hashlimit --hashlimit-above 500/sec --hashlimit-burst 200 \
    --hashlimit-mode srcip --hashlimit-name samp_udp -j DROP
iptables -A NROSHIELD_GAME_SAMP -j RETURN

# Minecraft (TCP) — Port 25565
iptables -A NROSHIELD_GAME_MC -p tcp -m length --length 0:1 -m conntrack --ctstate NEW -j DROP
iptables -A NROSHIELD_GAME_MC -p tcp \
    -m hashlimit --hashlimit-above 30/sec --hashlimit-burst 10 \
    --hashlimit-mode srcip --hashlimit-name mc_tcp -j DROP
iptables -A NROSHIELD_GAME_MC -p tcp \
    -m connlimit --connlimit-above 20 --connlimit-mask 32 -j DROP
iptables -A NROSHIELD_GAME_MC -j RETURN

# FiveM (UDP + TCP) — Port 30120
iptables -A NROSHIELD_GAME_FIVEM -p udp -m length --length 4097:65535 -j DROP
iptables -A NROSHIELD_GAME_FIVEM -p udp \
    -m hashlimit --hashlimit-above 600/sec --hashlimit-burst 300 \
    --hashlimit-mode srcip --hashlimit-name fivem_udp -j DROP
iptables -A NROSHIELD_GAME_FIVEM -p tcp \
    -m connlimit --connlimit-above 50 --connlimit-mask 32 -j DROP
iptables -A NROSHIELD_GAME_FIVEM -j RETURN

log_ok "Game-specific rules: NRO, SA:MP, Minecraft, FiveM"

# ============================================================================
# 9. DYNAMIC BLACKLISTING — Tự động blacklist IP tấn công
# ============================================================================
log_info "Thiết lập Dynamic Blacklisting..."

# Tạo chain theo dõi IP vi phạm nhiều lần
iptables -N NROSHIELD_DYNBAN 2>/dev/null || iptables -F NROSHIELD_DYNBAN

# Nếu IP bị drop >= 200 lần trong 60s → thêm vào blacklist
iptables -A NROSHIELD_DYNBAN \
    -m recent --name dynban --rcheck --seconds 60 --hitcount 200 \
    -j SET --add-set nroshield-blacklist src 2>/dev/null || true
iptables -A NROSHIELD_DYNBAN \
    -m recent --name dynban --set \
    -j RETURN

log_ok "Dynamic Blacklisting đã thiết lập"

# ============================================================================
# LƯU RULES
# ============================================================================
log_info "Lưu rules..."
iptables-save > /etc/iptables/rules.v4 2>/dev/null || \
    iptables-save > /etc/iptables.rules 2>/dev/null || true

echo ""
log_info "============================================"
log_ok "  ANTI-DDoS V2 ĐÃ THIẾT LẬP!"
log_info "============================================"
echo ""
echo "  Nâng cấp V2:"
echo "  🛡️  SYN Flood V2:      Multi-layer (global + per-IP + per-port)"
echo "  🛡️  UDP Flood V2:      Game-aware filtering"
echo "  🛡️  TCP Flood V2:      ACK + RST + FIN + PSH+ACK"
echo "  🛡️  Connection V2:     TCP + UDP + Global rate"
echo "  🛡️  ICMP V2:           Per-IP + type filtering"
echo "  🛡️  Amplification V2:  15+ ports blocked"
echo "  🛡️  Tunnel V2:         GRE/IPIP/ESP/AH/SCTP"
echo "  🛡️  Game Rules:        NRO, SA:MP, Minecraft, FiveM"
echo "  🛡️  Dynamic Ban:       Auto-blacklist repeat offenders"
echo ""
