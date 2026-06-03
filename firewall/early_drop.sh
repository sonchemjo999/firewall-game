#!/bin/bash
# ============================================================================
# NRO Shield v2.2 — Early Drop Engine (Kernel-Level Pre-Conntrack)
# ============================================================================
# GIẢI QUYẾT VẤN ĐỀ: Khi bị tấn công botnet, VPS thường tốn tài nguyên
# (CPU, RAM, băng thông) vì packets đi qua conntrack trước khi bị drop.
#
# GIẢI PHÁP: Drop packets tại tầng sớm nhất — raw table PREROUTING.
# Tại đây, packet bị loại BỎ TRƯỚC KHI vào conntrack, nghĩa là:
#   - KHÔNG tạo conntrack entry → KHÔNG tốn RAM
#   - KHÔNG xử lý connection state → KHÔNG tốn CPU
#   - Packet bị hủy ngay tại kernel → giảm tải tối đa
#
# THỨ TỰ XỬ LÝ TRONG NETFILTER:
#   raw PREROUTING → conntrack → mangle PREROUTING → nat PREROUTING → filter INPUT
#   ^^^^^^^^^^^^^
#   DROP TẠI ĐÂY = zero resource usage
#
# Chạy TRƯỚC tất cả scripts khác (trước iptables_base.sh)
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../.env"

# Defaults
PROXY_PORT_RANGE_START="30000"
PROXY_PORT_RANGE_END="60000"
SSH_PORT="22"
API_PORT="5000"

[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

log_info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} Can quyen root"; exit 1
fi

echo -e "${PURPLE}${BOLD}"
echo "  ============================================"
echo "  NRO Shield — Early Drop Engine"
echo "  Kernel-Level Pre-Conntrack Protection"
echo "  ============================================"
echo -e "${NC}"

# ============================================================================
# 1. IPSET CHO RAW TABLE — Blacklist kiem tra TRUOC conntrack
# ============================================================================
log_info "Tao ipset sets cho raw table..."

# Blacklist checked at raw table level — BEFORE conntrack
ipset create -exist nroshield-rawdrop hash:ip hashsize 65536 maxelem 1048576 timeout 3600
# Permanent blacklist (no timeout)
ipset create -exist nroshield-perma-ban hash:ip hashsize 65536 maxelem 1048576
# Blacklist subnets (botnet ranges)
ipset create -exist nroshield-rawdrop-net hash:net hashsize 65536 maxelem 1048576 timeout 86400
# Known botnet source ASNs/subnets
ipset create -exist nroshield-botnet-raw hash:net hashsize 65536 maxelem 1048576

log_ok "ipset sets cho raw table da tao"

# ============================================================================
# 2. RAW TABLE — Drop TRUOC conntrack (zero resource usage)
# ============================================================================
log_info "Thiet lap raw table PREROUTING rules..."

# Flush raw table
iptables -t raw -F PREROUTING 2>/dev/null || true
iptables -t raw -N NROSHIELD_EARLY 2>/dev/null || iptables -t raw -F NROSHIELD_EARLY

# --- 2a. Blacklist IP — Drop ngay, KHONG tao conntrack entry ---
iptables -t raw -A NROSHIELD_EARLY -m set --match-set nroshield-rawdrop src -j DROP
iptables -t raw -A NROSHIELD_EARLY -m set --match-set nroshield-perma-ban src -j DROP
iptables -t raw -A NROSHIELD_EARLY -m set --match-set nroshield-rawdrop-net src -j DROP
iptables -t raw -A NROSHIELD_EARLY -m set --match-set nroshield-botnet-raw src -j DROP

log_ok "Raw blacklist: 4 ipset → DROP truoc conntrack"

# --- 2b. Invalid TCP flags — Drop ngay tai raw ---
# Packets voi TCP flags bat thuong 100% la tan cong, drop truoc khi ton tai nguyen
iptables -t raw -A NROSHIELD_EARLY -p tcp --tcp-flags ALL NONE -j DROP
iptables -t raw -A NROSHIELD_EARLY -p tcp --tcp-flags ALL ALL -j DROP
iptables -t raw -A NROSHIELD_EARLY -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP
iptables -t raw -A NROSHIELD_EARLY -p tcp --tcp-flags SYN,RST SYN,RST -j DROP
iptables -t raw -A NROSHIELD_EARLY -p tcp --tcp-flags FIN,RST FIN,RST -j DROP
iptables -t raw -A NROSHIELD_EARLY -p tcp --tcp-flags ACK,FIN FIN -j DROP
iptables -t raw -A NROSHIELD_EARLY -p tcp --tcp-flags ACK,PSH PSH -j DROP
iptables -t raw -A NROSHIELD_EARLY -p tcp --tcp-flags ACK,URG URG -j DROP

log_ok "Invalid TCP flags: 8 rules → DROP tai raw (zero CPU)"

# --- 2c. Bogon/Spoofed source IPs — Drop ngay ---
# RFC 1918 private IPs tu WAN (spoof)
iptables -t raw -A NROSHIELD_EARLY -i eth0 -s 10.0.0.0/8 -j DROP 2>/dev/null || true
iptables -t raw -A NROSHIELD_EARLY -i eth0 -s 172.16.0.0/12 -j DROP 2>/dev/null || true
iptables -t raw -A NROSHIELD_EARLY -i eth0 -s 192.168.0.0/16 -j DROP 2>/dev/null || true
# Multicast/broadcast source
iptables -t raw -A NROSHIELD_EARLY -s 224.0.0.0/4 -j DROP
iptables -t raw -A NROSHIELD_EARLY -s 240.0.0.0/4 -j DROP
# Loopback from WAN
iptables -t raw -A NROSHIELD_EARLY -i eth0 -s 127.0.0.0/8 -j DROP 2>/dev/null || true
# Unspecified
iptables -t raw -A NROSHIELD_EARLY -s 0.0.0.0/8 -j DROP

log_ok "Bogon/spoof IPs: DROP truoc conntrack"

# --- 2d. UDP amplification source ports — Drop ngay ---
# Cac cong thuong dung trong amplification attack
# Drop tai raw = KHONG tao conntrack entry cho moi packet tan cong
AMPLIFY_PORTS="17,19,53,111,123,137,161,389,520,751,1434,1900,5353,11211"
iptables -t raw -A NROSHIELD_EARLY -p udp -m multiport --sports $AMPLIFY_PORTS -j DROP

log_ok "UDP amplification: $AMPLIFY_PORTS → DROP tai raw"

# --- 2e. Fragmented packets — Drop tai raw ---
# Game traffic khong can fragments, tat ca fragments tu WAN la dang nghi
iptables -t raw -A NROSHIELD_EARLY -f -j DROP 2>/dev/null || true

log_ok "IP fragments: DROP tai raw"

# --- 2f. NOTRACK cho traffic hop le — giam tai conntrack ---
# Traffic da biet la an toan, khong can theo doi connection state
# Loopback traffic
iptables -t raw -A NROSHIELD_EARLY -i lo -j NOTRACK 2>/dev/null || \
    iptables -t raw -A NROSHIELD_EARLY -i lo -j CT --notrack 2>/dev/null || true

log_ok "NOTRACK: loopback traffic bypass conntrack"

# Apply chain
iptables -t raw -A PREROUTING -j NROSHIELD_EARLY

log_ok "Raw table PREROUTING da thiet lap"

# ============================================================================
# 3. MANGLE TABLE — Lop bao ve thu 2 (sau raw, truoc conntrack result)
# ============================================================================
log_info "Thiet lap mangle PREROUTING rules..."

iptables -t mangle -N NROSHIELD_MANGLE 2>/dev/null || iptables -t mangle -F NROSHIELD_MANGLE

# --- 3a. TTL bat thuong — spoof/proxy detection ---
# TTL < 20: packet da di qua qua nhieu hop (proxy/tunnel)
# TTL > 200: giá tri bat thuong (spoofed)
iptables -t mangle -A NROSHIELD_MANGLE -m ttl --ttl-lt 20 -j DROP
iptables -t mangle -A NROSHIELD_MANGLE -m ttl --ttl-gt 200 -j DROP

# --- 3b. TCP MSS bat thuong ---
iptables -t mangle -A NROSHIELD_MANGLE -p tcp -m conntrack --ctstate NEW \
    -m tcpmss ! --mss 536:65535 -j DROP

# --- 3c. TCP NEW without SYN ---
iptables -t mangle -A NROSHIELD_MANGLE -p tcp ! --syn -m conntrack --ctstate NEW -j DROP

# --- 3d. Conntrack INVALID ---
iptables -t mangle -A NROSHIELD_MANGLE -m conntrack --ctstate INVALID -j DROP

# --- 3e. Per-IP packet rate limit tai mangle (truoc filter table) ---
# Neu 1 IP gui > 10000 pps → drop tai mangle, khong vao filter
iptables -t mangle -A NROSHIELD_MANGLE \
    -m hashlimit \
    --hashlimit-above 10000/sec \
    --hashlimit-burst 5000 \
    --hashlimit-mode srcip \
    --hashlimit-name mangle_pps \
    --hashlimit-htable-expire 10000 \
    -j DROP

iptables -t mangle -A NROSHIELD_MANGLE -j RETURN

iptables -t mangle -A PREROUTING -j NROSHIELD_MANGLE

log_ok "Mangle PREROUTING: TTL, MSS, INVALID, PPS limit"

# ============================================================================
# 4. KERNEL TUNING — Toi uu xu ly packet o tang kernel
# ============================================================================
log_info "Toi uu kernel cho early drop..."

# Tang conntrack hash table
sysctl -w net.netfilter.nf_conntrack_max=2097152 2>/dev/null || true

# Giam conntrack timeout de giai phong nhanh hon
sysctl -w net.netfilter.nf_conntrack_tcp_timeout_syn_sent=10 2>/dev/null || true
sysctl -w net.netfilter.nf_conntrack_tcp_timeout_syn_recv=10 2>/dev/null || true
sysctl -w net.netfilter.nf_conntrack_tcp_timeout_established=300 2>/dev/null || true
sysctl -w net.netfilter.nf_conntrack_tcp_timeout_time_wait=10 2>/dev/null || true
sysctl -w net.netfilter.nf_conntrack_tcp_timeout_close_wait=10 2>/dev/null || true
sysctl -w net.netfilter.nf_conntrack_tcp_timeout_fin_wait=10 2>/dev/null || true
sysctl -w net.netfilter.nf_conntrack_udp_timeout=15 2>/dev/null || true
sysctl -w net.netfilter.nf_conntrack_udp_timeout_stream=30 2>/dev/null || true
sysctl -w net.netfilter.nf_conntrack_icmp_timeout=5 2>/dev/null || true

# Tang SYN backlog
sysctl -w net.ipv4.tcp_max_syn_backlog=131072 2>/dev/null || true
sysctl -w net.core.somaxconn=131072 2>/dev/null || true

# Tang netdev backlog (xu ly nhieu packets/s hon)
sysctl -w net.core.netdev_max_backlog=250000 2>/dev/null || true

# Bat SYN cookies (kernel drop SYN flood ma KHONG tao connection)
sysctl -w net.ipv4.tcp_syncookies=1 2>/dev/null || true

# Giam SYN-ACK retries (nhanh giai phong connection bi treo)
sysctl -w net.ipv4.tcp_synack_retries=1 2>/dev/null || true

# Reverse Path Filter (kernel drop spoofed IPs)
sysctl -w net.ipv4.conf.all.rp_filter=1 2>/dev/null || true
sysctl -w net.ipv4.conf.default.rp_filter=1 2>/dev/null || true

log_ok "Kernel tuning cho early drop"

# ============================================================================
# 5. AUTO-BLACKLIST SCRIPT — Tu dong them IP vao raw blacklist
# ============================================================================
log_info "Tao script tu dong blacklist..."

mkdir -p /opt/nroshield

cat > /opt/nroshield/auto_rawdrop.sh << 'RAWDROP_EOF'
#!/bin/bash
# Auto-blacklist: Kiem tra conntrack va tu dong them IP tan cong vao raw blacklist
# Chay moi 10 giay qua cron hoac systemd timer

THRESHOLD_CONN=500    # IP co > 500 connections
THRESHOLD_PPS=5000    # IP gui > 5000 packets (kiem tra qua iptables counters)
WHITELIST_SET="nroshield-whitelist"
RAWDROP_SET="nroshield-rawdrop"

# Tim IP co qua nhieu connections
if command -v conntrack &>/dev/null; then
    conntrack -L 2>/dev/null | awk '{print $0}' | \
        grep -oP 'src=\K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | \
        sort | uniq -c | sort -rn | \
        while read count ip; do
            if [[ "$count" -gt "$THRESHOLD_CONN" ]]; then
                # Kiem tra khong nam trong whitelist
                if ! ipset test "$WHITELIST_SET" "$ip" 2>/dev/null; then
                    ipset add "$RAWDROP_SET" "$ip" timeout 3600 2>/dev/null || true
                    echo "$(date) AUTO-BAN: $ip ($count connections) → raw DROP" >> /var/log/nroshield/auto_rawdrop.log
                fi
            fi
        done
fi
RAWDROP_EOF

chmod +x /opt/nroshield/auto_rawdrop.sh

log_ok "Script tu dong blacklist tai /opt/nroshield/auto_rawdrop.sh"

# ============================================================================
# 6. SYSTEMD TIMER — Chay auto-blacklist moi 10 giay
# ============================================================================
log_info "Tao systemd timer cho auto-blacklist..."

cat > /etc/systemd/system/nroshield-autoban.service << 'SVCEOF'
[Unit]
Description=NRO Shield Auto-Blacklist Service

[Service]
Type=oneshot
ExecStart=/opt/nroshield/auto_rawdrop.sh
SVCEOF

cat > /etc/systemd/system/nroshield-autoban.timer << 'TMREOF'
[Unit]
Description=NRO Shield Auto-Blacklist Timer (every 10 seconds)

[Timer]
OnBootSec=30
OnUnitActiveSec=10
AccuracySec=1

[Install]
WantedBy=timers.target
TMREOF

systemctl daemon-reload 2>/dev/null || true
systemctl enable nroshield-autoban.timer 2>/dev/null || true

log_ok "Systemd timer: auto-blacklist moi 10 giay"

# ============================================================================
# TONG KET
# ============================================================================
echo ""
echo -e "${PURPLE}${BOLD}  ============================================${NC}"
echo -e "${GREEN}${BOLD}  EARLY DROP ENGINE DA THIET LAP!${NC}"
echo -e "${PURPLE}${BOLD}  ============================================${NC}"
echo ""

RAW_RULES=$(iptables -t raw -L NROSHIELD_EARLY -n 2>/dev/null | grep -c "^[A-Z]" || echo "0")
MANGLE_RULES=$(iptables -t mangle -L NROSHIELD_MANGLE -n 2>/dev/null | grep -c "^[A-Z]" || echo "0")

echo "  Bao ve truoc conntrack:"
echo "  ────────────────────────────────────────"
echo "  Raw table rules:     ${RAW_RULES}"
echo "  Mangle table rules:  ${MANGLE_RULES}"
echo "  ipset raw sets:      4"
echo ""
echo "  Thu tu xu ly packet:"
echo "  ────────────────────────────────────────"
echo "  1. raw PREROUTING    → Blacklist, invalid flags, bogon, amplification"
echo "                          (DROP = zero CPU/RAM/bandwidth)"
echo "  2. conntrack         → Chi xu ly packet hop le"
echo "  3. mangle PREROUTING → TTL, MSS, PPS limit"
echo "  4. filter INPUT      → Game-specific rules (chi packet sach)"
echo ""
echo "  Ket qua khi bi botnet tan cong:"
echo "  ────────────────────────────────────────"
echo "  - IP botnet bi drop TAI RAW → khong tao conntrack"
echo "  - Khong ton RAM cho connection tracking"
echo "  - Khong ton CPU cho packet processing"
echo "  - Chi bang thong mang bi anh huong (khong the tranh)"
echo "  - Auto-blacklist: IP > ${THRESHOLD_CONN:-500} conn → raw DROP"
echo ""
echo -e "${CYAN}  Luu y: Bandwidth DDoS chi co the giam bang upstream"
echo -e "  filtering (ISP/CDN/Cloudflare). Script nay toi uu"
echo -e "  xu ly tai VPS de giam CPU/RAM toi da.${NC}"
echo ""
