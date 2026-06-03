#!/bin/bash
# ============================================================================
# NRO Shield — Traffic Monitor
# ============================================================================
# Mô tả: Giám sát traffic real-time, phát hiện bất thường, gửi cảnh báo
# Chạy liên tục hoặc qua cron mỗi phút
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../.env"

# Defaults
PROXY_PORT_RANGE_START="30000"
PROXY_PORT_RANGE_END="60000"
MAX_CONN_PER_IP="500"
CONN_ALERT_THRESHOLD="500"
PPS_ALERT_THRESHOLD="10000"
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""

[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

LOG_DIR="/var/log/nroshield"
LOG_FILE="${LOG_DIR}/traffic/$(date '+%Y-%m-%d').log"
ALERT_LOG="${LOG_DIR}/attacks/$(date '+%Y-%m-%d').log"

mkdir -p "${LOG_DIR}/traffic" "${LOG_DIR}/attacks"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# ============================================================================
# FUNCTIONS
# ============================================================================

# Gửi cảnh báo Telegram
send_telegram_alert() {
    local message="$1"
    if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d chat_id="$TELEGRAM_CHAT_ID" \
            -d text="$message" \
            -d parse_mode="HTML" \
            > /dev/null 2>&1 || true
    fi
}

# Đếm connection trên 1 port
count_connections() {
    local port="$1"
    ss -tn state established "( dport = :${port} or sport = :${port} )" 2>/dev/null | tail -n +2 | wc -l
}

# Đếm tổng connection proxy ports
count_total_proxy_connections() {
    ss -tn state established 2>/dev/null | \
        awk -v start="$PROXY_PORT_RANGE_START" -v end="$PROXY_PORT_RANGE_END" \
        '$4 ~ /:[0-9]+$/ { split($4, a, ":"); port=a[length(a)]; if (port >= start && port <= end) count++ } END { print count+0 }'
}

# Top IPs theo connection count
get_top_ips() {
    local limit="${1:-10}"
    ss -tn state established 2>/dev/null | \
        awk -v start="$PROXY_PORT_RANGE_START" -v end="$PROXY_PORT_RANGE_END" \
        '$4 ~ /:[0-9]+$/ { 
            split($4, a, ":"); port=a[length(a)]; 
            if (port >= start && port <= end) { 
                split($5, b, ":"); ip=b[1]; 
                count[ip]++ 
            }
        } END { for (ip in count) print count[ip], ip }' | \
        sort -rn | head -"$limit"
}

# Đếm SYN packets (từ conntrack)
count_syn_packets() {
    conntrack -C 2>/dev/null || echo "0"
}

# Packets per second (từ iptables counters)
get_pps() {
    # Đếm packets trong INPUT chain
    iptables -L INPUT -n -v 2>/dev/null | awk 'NR>2 { total+=$1 } END { print total+0 }'
}

# Bytes per second (từ interface)
get_interface_stats() {
    local iface
    iface=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}' || echo "eth0")
    cat "/sys/class/net/${iface}/statistics/rx_bytes" 2>/dev/null || echo "0"
}

# ============================================================================
# MAIN MONITORING
# ============================================================================

# === Thu thập metrics ===
TOTAL_CONN=$(count_total_proxy_connections)
CONNTRACK_COUNT=$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo "0")
CONNTRACK_MAX=$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo "0")
RX_BYTES=$(get_interface_stats)
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}')
RAM_USAGE=$(free -m | awk '/Mem:/ { printf("%.1f", $3/$2 * 100) }')

# === Top IPs ===
TOP_IPS=$(get_top_ips 5)

# === Ghi log ===
{
    echo "[$TIMESTAMP] connections=$TOTAL_CONN conntrack=$CONNTRACK_COUNT/$CONNTRACK_MAX rx_bytes=$RX_BYTES"
    if [[ -n "$TOP_IPS" ]]; then
        echo "  Top IPs:"
        echo "$TOP_IPS" | while read -r count ip; do
            echo "    ${ip}: ${count} connections"
        done
    fi
} >> "$LOG_FILE"

# ============================================================================
# PHÁT HIỆN BẤT THƯỜNG
# ============================================================================

ALERT_TRIGGERED=false
ALERT_MSG=""

# 1. Quá nhiều connection tổng
if [[ "$TOTAL_CONN" -gt "$CONN_ALERT_THRESHOLD" ]]; then
    ALERT_MSG+="⚠️ HIGH CONNECTIONS: ${TOTAL_CONN} (threshold: ${CONN_ALERT_THRESHOLD})\n"
    ALERT_TRIGGERED=true
fi

# 2. Conntrack table sắp đầy (>80%)
if [[ "$CONNTRACK_MAX" -gt 0 ]]; then
    USAGE=$((CONNTRACK_COUNT * 100 / CONNTRACK_MAX))
    if [[ "$USAGE" -gt 80 ]]; then
        ALERT_MSG+="🔴 CONNTRACK: ${USAGE}% (${CONNTRACK_COUNT}/${CONNTRACK_MAX})\n"
        ALERT_TRIGGERED=true
    fi
fi

# 3. Single IP có quá nhiều connection
while read -r count ip; do
    [[ -z "$count" ]] && continue
    if [[ "$count" -gt "$MAX_CONN_PER_IP" ]]; then
        ALERT_MSG+="🚨 IP ${ip}: ${count} connections (max: ${MAX_CONN_PER_IP})\n"
        ALERT_TRIGGERED=true

        # Tự động thêm vào danh sách rate-limited
        ipset add nroshield-ratelimited "$ip" timeout 300 2>/dev/null || true
        echo "[$TIMESTAMP] RATE_EXCEEDED src=${ip} connections=${count}" >> "$ALERT_LOG"
    fi
done <<< "$TOP_IPS"

# === Gửi cảnh báo nếu có ===
if [[ "$ALERT_TRIGGERED" == true ]]; then
    FULL_ALERT="🛡️ <b>NRO Shield Alert</b>\n\n${ALERT_MSG}\n⏰ ${TIMESTAMP}"

    # Ghi log
    echo "[$TIMESTAMP] ALERT: ${ALERT_MSG}" >> "$ALERT_LOG"

    # Gửi Telegram
    send_telegram_alert "$(echo -e "$FULL_ALERT")"

    # In ra console
    echo -e "${RED}[ALERT]${NC} ${ALERT_MSG}"
else
    echo -e "${GREEN}[OK]${NC} [$TIMESTAMP] connections=${TOTAL_CONN} conntrack=${CONNTRACK_COUNT}/${CONNTRACK_MAX}"
fi

# ============================================================================
# OUTPUT JSON (cho AI Engine đọc)
# ============================================================================
JSON_OUTPUT="${LOG_DIR}/traffic/current_metrics.json"
cat > "$JSON_OUTPUT" << JSONEOF
{
    "timestamp": "${TIMESTAMP}",
    "total_connections": ${TOTAL_CONN},
    "conntrack_count": ${CONNTRACK_COUNT},
    "conntrack_max": ${CONNTRACK_MAX},
    "rx_bytes": ${RX_BYTES},
    "cpu_usage": "${CPU_USAGE:-0}",
    "ram_usage": "${RAM_USAGE:-0}",
    "alert_triggered": ${ALERT_TRIGGERED}
}
JSONEOF
