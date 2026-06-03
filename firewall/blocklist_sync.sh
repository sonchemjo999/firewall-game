#!/bin/bash
# NRO Shield - Automatic Blocklist Sync
# Tu dong dong bo danh sach IP doc hai tu nhieu nguon

BLOCKLIST_DIR="/etc/nroshield/blocklists"
IPSET_NAME="nroshield_blocklist"
LOG_FILE="/var/log/nroshield/blocklist_sync.log"

mkdir -p "$BLOCKLIST_DIR" "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

SOURCES=(
    "https://raw.githubusercontent.com/stamparm/ipsum/master/levels/3.txt"
    "https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/firehol_level1.netset"
    "https://www.spamhaus.org/drop/drop.txt"
    "https://cinsscore.com/list/ci-badguys.txt"
    "https://rules.emergingthreats.net/fwrules/emerging-Block-IPs.txt"
)

download_blocklists() {
    log "=== Bat dau dong bo blocklist ==="
    local total=0

    for url in "${SOURCES[@]}"; do
        local filename
        filename=$(basename "$url" | sed 's/[^a-zA-Z0-9._-]/_/g')
        local output="$BLOCKLIST_DIR/$filename"

        if curl -sfL --max-time 30 "$url" -o "$output.tmp" 2>/dev/null; then
            grep -oE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}(/[0-9]{1,2})?' "$output.tmp" | \
                sort -u > "$output"
            local count
            count=$(wc -l < "$output")
            total=$((total + count))
            log "  [OK] $filename: $count IPs"
            rm -f "$output.tmp"
        else
            log "  [FAIL] $filename: download failed"
            rm -f "$output.tmp"
        fi
    done

    log "Tong cong: $total IPs tu ${#SOURCES[@]} nguon"
}

create_ipset() {
    if ! ipset list "$IPSET_NAME" &>/dev/null; then
        ipset create "$IPSET_NAME" hash:net maxelem 500000 timeout 86400
        log "Da tao ipset: $IPSET_NAME"
    fi

    local tmp_set="${IPSET_NAME}_tmp"
    ipset create "$tmp_set" hash:net maxelem 500000 timeout 86400 2>/dev/null || true

    ipset flush "$tmp_set"

    local count=0
    for file in "$BLOCKLIST_DIR"/*; do
        [ -f "$file" ] || continue
        while IFS= read -r ip; do
            [[ "$ip" =~ ^[0-9] ]] || continue
            [[ "$ip" =~ ^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.) ]] && continue
            ipset add "$tmp_set" "$ip" timeout 86400 2>/dev/null && ((count++))
        done < "$file"
    done

    ipset swap "$tmp_set" "$IPSET_NAME"
    ipset destroy "$tmp_set" 2>/dev/null

    log "Da nap $count IPs vao ipset $IPSET_NAME"
}

apply_iptables() {
    if ! iptables -C INPUT -m set --match-set "$IPSET_NAME" src -j DROP 2>/dev/null; then
        iptables -I INPUT 1 -m set --match-set "$IPSET_NAME" src -j DROP
        log "Da them iptables rule cho $IPSET_NAME"
    fi

    if ! iptables -C FORWARD -m set --match-set "$IPSET_NAME" src -j DROP 2>/dev/null; then
        iptables -I FORWARD 1 -m set --match-set "$IPSET_NAME" src -j DROP
        log "Da them iptables FORWARD rule cho $IPSET_NAME"
    fi
}

add_custom_ip() {
    local ip="$1"
    local timeout="${2:-86400}"
    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}(/[0-9]{1,2})?$ ]]; then
        ipset add "$IPSET_NAME" "$ip" timeout "$timeout" 2>/dev/null
        log "Da them IP: $ip (timeout: ${timeout}s)"
    else
        log "IP khong hop le: $ip"
    fi
}

remove_custom_ip() {
    local ip="$1"
    ipset del "$IPSET_NAME" "$ip" 2>/dev/null
    log "Da xoa IP: $ip"
}

show_stats() {
    local count
    count=$(ipset list "$IPSET_NAME" 2>/dev/null | grep -c "^[0-9]" || echo 0)
    echo "=== Blocklist Stats ==="
    echo "Ipset: $IPSET_NAME"
    echo "So luong IP: $count"
    echo "Nguon: ${#SOURCES[@]}"
    echo "Cap nhat cuoi: $(stat -c %y "$BLOCKLIST_DIR"/* 2>/dev/null | tail -1 | cut -d. -f1)"
}

case "${1:-sync}" in
    sync)
        download_blocklists
        create_ipset
        apply_iptables
        log "=== Dong bo hoan tat ==="
        ;;
    add)
        add_custom_ip "$2" "$3"
        ;;
    remove)
        remove_custom_ip "$2"
        ;;
    stats)
        show_stats
        ;;
    *)
        echo "Su dung: $0 {sync|add <ip> [timeout]|remove <ip>|stats}"
        exit 1
        ;;
esac
