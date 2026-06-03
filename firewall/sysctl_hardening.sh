#!/bin/bash
# ============================================================================
# NRO Shield — Kernel Hardening (sysctl)
# ============================================================================
# Mô tả: Tối ưu kernel TCP/IP stack để chống DDoS và tăng hiệu năng
# Hệ điều hành: Ubuntu 22.04 LTS
# ============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} Cần quyền root"
    exit 1
fi

SYSCTL_FILE="/etc/sysctl.d/99-nroshield.conf"

log_info "============================================"
log_info "  NRO Shield — Kernel Hardening"
log_info "============================================"

log_info "Ghi cấu hình vào $SYSCTL_FILE..."

cat > "$SYSCTL_FILE" << 'SYSCTL_EOF'
# ============================================================================
# NRO Shield — Kernel Hardening Configuration
# ============================================================================

# === 1. CHỐNG SYN FLOOD ===
# Bật SYN cookies — kernel tạo SYN cookie thay vì lưu connection vào backlog
net.ipv4.tcp_syncookies = 1
# Tăng SYN backlog (hàng đợi SYN) lên 65535
net.ipv4.tcp_max_syn_backlog = 65535
# Giảm số lần gửi lại SYN-ACK (mặc định 5, giảm xuống 2)
net.ipv4.tcp_synack_retries = 2
# Giảm số lần gửi lại SYN
net.ipv4.tcp_syn_retries = 2

# === 2. TỐI ƯU TCP CONNECTIONS ===
# Giảm thời gian FIN-WAIT-2 (mặc định 60s)
net.ipv4.tcp_fin_timeout = 15
# Giảm thời gian keepalive (mặc định 7200s = 2h)
net.ipv4.tcp_keepalive_time = 300
# Khoảng cách giữa các probe keepalive
net.ipv4.tcp_keepalive_intvl = 15
# Số probe trước khi đóng connection
net.ipv4.tcp_keepalive_probes = 5
# Bật TCP time-wait reuse
net.ipv4.tcp_tw_reuse = 1
# Tăng số TIME-WAIT buckets
net.ipv4.tcp_max_tw_buckets = 2000000
# Tăng port range cho outbound connections
net.ipv4.ip_local_port_range = 1024 65535

# === 3. CHỐNG IP SPOOFING ===
# Bật Reverse Path Filtering (kiểm tra source IP hợp lệ)
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# === 4. TẮT ICMP REDIRECT ===
# Không chấp nhận ICMP redirects (chống man-in-the-middle)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
# Không chấp nhận source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# === 5. ICMP HARDENING ===
# Giới hạn tốc độ ICMP (chống ping flood)
net.ipv4.icmp_ratelimit = 100
net.ipv4.icmp_ratemask = 88089
# Bỏ qua ICMP broadcast (chống Smurf attack)
net.ipv4.icmp_echo_ignore_broadcasts = 1
# Bỏ qua ICMP bogus responses
net.ipv4.icmp_ignore_bogus_error_responses = 1

# === 6. CONNECTION TRACKING (CONNTRACK) ===
# Tối đa connection tracking entries (1M connections)
net.netfilter.nf_conntrack_max = 1048576
# Hash table size (nên = nf_conntrack_max / 4)
# net.netfilter.nf_conntrack_buckets = 262144  # Set via modprobe
# Giảm timeout cho các trạng thái
net.netfilter.nf_conntrack_tcp_timeout_established = 600
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 15
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_syn_sent = 30
net.netfilter.nf_conntrack_tcp_timeout_syn_recv = 30
net.netfilter.nf_conntrack_udp_timeout = 30
net.netfilter.nf_conntrack_udp_timeout_stream = 60
net.netfilter.nf_conntrack_icmp_timeout = 10
# Bật accounting (cho traffic monitoring)
net.netfilter.nf_conntrack_acct = 1

# === 7. NETWORK BUFFERS ===
# Tăng buffer nhận/gửi mặc định và tối đa
net.core.rmem_default = 1048576
net.core.rmem_max = 16777216
net.core.wmem_default = 1048576
net.core.wmem_max = 16777216
net.core.optmem_max = 65536
# TCP buffer min/default/max
net.ipv4.tcp_rmem = 4096 1048576 2097152
net.ipv4.tcp_wmem = 4096 65536 16777216
# Tăng backlog tối đa
net.core.netdev_max_backlog = 50000
net.core.somaxconn = 65535

# === 8. IP FORWARDING (NAT PROXY) ===
net.ipv4.ip_forward = 1

# === 9. TẮT IPv6 (giảm attack surface) ===
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1

# === 10. TCP PERFORMANCE ===
# Bật TCP window scaling
net.ipv4.tcp_window_scaling = 1
# Bật TCP timestamps (cần cho SYN cookies)
net.ipv4.tcp_timestamps = 1
# Bật Selective ACK
net.ipv4.tcp_sack = 1
# Tắt TCP slow start after idle
net.ipv4.tcp_slow_start_after_idle = 0

# === 11. MEMORY & OVERCOMMIT ===
# Panic on out-of-memory
vm.panic_on_oom = 0
vm.overcommit_memory = 0

# === 12. CHỐNG ARP SPOOFING ===
net.ipv4.conf.all.arp_ignore = 1
net.ipv4.conf.all.arp_announce = 2
SYSCTL_EOF

# === Áp dụng cấu hình ===
log_info "Đang áp dụng cấu hình kernel..."
sysctl --system > /dev/null 2>&1

# === Cấu hình conntrack hash size qua modprobe ===
log_info "Cấu hình conntrack hash size..."
MODPROBE_FILE="/etc/modprobe.d/nf_conntrack.conf"
echo "options nf_conntrack hashsize=262144" > "$MODPROBE_FILE"

# Load module nếu chưa load
modprobe nf_conntrack 2>/dev/null || true

# === Verify ===
log_info "Kiểm tra cấu hình..."
echo ""
echo "  SYN Cookies:        $(sysctl -n net.ipv4.tcp_syncookies 2>/dev/null || echo 'N/A')"
echo "  SYN Backlog:        $(sysctl -n net.ipv4.tcp_max_syn_backlog 2>/dev/null || echo 'N/A')"
echo "  IP Forward:         $(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo 'N/A')"
echo "  RP Filter:          $(sysctl -n net.ipv4.conf.all.rp_filter 2>/dev/null || echo 'N/A')"
echo "  Conntrack Max:      $(sysctl -n net.netfilter.nf_conntrack_max 2>/dev/null || echo 'N/A')"
echo "  Somaxconn:          $(sysctl -n net.core.somaxconn 2>/dev/null || echo 'N/A')"
echo ""

log_ok "Kernel hardening hoàn tất!"
log_info "Bước tiếp: chạy iptables_base.sh"
