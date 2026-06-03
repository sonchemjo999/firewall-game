#!/bin/bash
# ============================================================================
# NRO Shield — Anti-Botnet Protection
# ============================================================================
# Mô tả: Tải và áp dụng blocklists botnet, cron tự động cập nhật
# ============================================================================

set -euo pipefail

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

BLOCKLIST_DIR="/opt/nroshield/blocklists"
IPSET_NAME="nroshield-botnet"
LOG_FILE="/var/log/nroshield/blocklist_update.log"

mkdir -p "$BLOCKLIST_DIR"

log_info "============================================"
log_info "  NRO Shield — Anti-Botnet Protection"
log_info "============================================"

# ============================================================================
# DANH SÁCH BLOCKLIST SOURCES
# ============================================================================
declare -A BLOCKLISTS=(
    ["spamhaus_drop"]="https://www.spamhaus.org/drop/drop.txt"
    ["spamhaus_edrop"]="https://www.spamhaus.org/drop/edrop.txt"
    ["firehol_level1"]="https://iplists.firehol.org/files/firehol_level1.netset"
    ["blocklist_de"]="https://lists.blocklist.de/lists/all.txt"
    ["emerging_threats"]="https://rules.emergingthreats.net/fwrules/emerging-Block-IPs.txt"
    ["dshield"]="https://feeds.dshield.org/block.txt"
    ["abuse_ch_feodo"]="https://feodotracker.abuse.ch/downloads/ipblocklist.txt"
    ["abuse_ch_sslip"]="https://sslbl.abuse.ch/blacklist/sslipblacklist.txt"
    ["tor_exit_nodes"]="https://check.torproject.org/torbulkexitlist"
    ["ci_army"]="https://cinsscore.com/list/ci-badguys.txt"
)

# ============================================================================
# HÀM TẢI VÀ PARSE BLOCKLIST
# ============================================================================
download_blocklist() {
    local name="$1"
    local url="$2"
    local output_file="${BLOCKLIST_DIR}/${name}.txt"

    log_info "Đang tải: ${name}..."

    if curl -sS --max-time 30 --retry 3 -o "$output_file" "$url" 2>/dev/null; then
        # Lọc chỉ lấy IP/CIDR, bỏ comments và dòng trống
        local clean_file="${BLOCKLIST_DIR}/${name}_clean.txt"
        grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?' "$output_file" \
            | sort -u > "$clean_file" 2>/dev/null || true

        local count
        count=$(wc -l < "$clean_file" 2>/dev/null || echo "0")
        log_ok "  ${name}: ${count} entries"
        echo "$clean_file"
    else
        log_warn "  Không tải được: ${name}"
        echo ""
    fi
}

# ============================================================================
# TẢI TẤT CẢ BLOCKLISTS
# ============================================================================
log_info "Đang tải blocklists từ ${#BLOCKLISTS[@]} nguồn..."
echo ""

ALL_IPS_FILE="${BLOCKLIST_DIR}/all_botnet_ips.txt"
> "$ALL_IPS_FILE"

TOTAL_SOURCES=0
TOTAL_IPS=0

for name in "${!BLOCKLISTS[@]}"; do
    result=$(download_blocklist "$name" "${BLOCKLISTS[$name]}")
    if [[ -n "$result" && -f "$result" ]]; then
        cat "$result" >> "$ALL_IPS_FILE"
        TOTAL_SOURCES=$((TOTAL_SOURCES + 1))
    fi
done

# Loại bỏ trùng lặp
sort -u "$ALL_IPS_FILE" -o "$ALL_IPS_FILE"
TOTAL_IPS=$(wc -l < "$ALL_IPS_FILE")

echo ""
log_info "Tổng: ${TOTAL_IPS} IPs/CIDRs từ ${TOTAL_SOURCES} nguồn"

# ============================================================================
# CẬP NHẬT IPSET
# ============================================================================
log_info "Đang cập nhật ipset ${IPSET_NAME}..."

# Tạo set tạm thời
TEMP_SET="${IPSET_NAME}-tmp"
ipset create -exist "$TEMP_SET" hash:net hashsize 65536 maxelem 1048576

# Thêm tất cả IPs vào set tạm
while IFS= read -r ip; do
    # Bỏ qua dòng trống hoặc private IPs
    [[ -z "$ip" ]] && continue
    [[ "$ip" =~ ^10\. ]] && continue
    [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]] && continue
    [[ "$ip" =~ ^192\.168\. ]] && continue
    [[ "$ip" =~ ^127\. ]] && continue

    ipset add "$TEMP_SET" "$ip" 2>/dev/null || true
done < "$ALL_IPS_FILE"

# Swap atomically
ipset swap "$TEMP_SET" "$IPSET_NAME"
ipset destroy "$TEMP_SET" 2>/dev/null || true

IPSET_COUNT=$(ipset list "$IPSET_NAME" | grep -c "^[0-9]" || echo "0")
log_ok "ipset ${IPSET_NAME}: ${IPSET_COUNT} entries active"

# Lưu ipset
ipset save > /etc/ipset.rules 2>/dev/null || true

# ============================================================================
# THIẾT LẬP CRON TỰ ĐỘNG CẬP NHẬT
# ============================================================================
log_info "Thiết lập cron job tự động cập nhật..."

SCRIPT_PATH="$(readlink -f "$0")"
CRON_JOB="0 */6 * * * ${SCRIPT_PATH} >> ${LOG_FILE} 2>&1"

# Thêm vào crontab nếu chưa có (dùng file tạm để tránh lỗi set -e với grep rỗng)
TMP_CRON=$(mktemp)
crontab -l > "$TMP_CRON" 2>/dev/null || true
grep -v "anti_botnet.sh" "$TMP_CRON" > "${TMP_CRON}.new" || true
echo "$CRON_JOB" >> "${TMP_CRON}.new"
crontab "${TMP_CRON}.new"
rm -f "$TMP_CRON" "${TMP_CRON}.new"

log_ok "Cron job: cập nhật mỗi 6 giờ"

# ============================================================================
# GHI LOG
# ============================================================================
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Updated: ${TOTAL_IPS} IPs from ${TOTAL_SOURCES} sources" >> "$LOG_FILE"

echo ""
log_info "============================================"
log_ok "  ANTI-BOTNET PROTECTION ĐÃ THIẾT LẬP!"
log_info "============================================"
echo ""
echo "  📋 Blocklist sources:    ${TOTAL_SOURCES}/${#BLOCKLISTS[@]}"
echo "  🤖 Total botnet IPs:     ${TOTAL_IPS}"
echo "  🔄 Auto-update:          Mỗi 6 giờ (cron)"
echo "  📁 Data dir:             ${BLOCKLIST_DIR}"
echo "  📝 Log file:             ${LOG_FILE}"
echo ""
log_info "Bước tiếp: chạy crowdsec_setup.sh"
