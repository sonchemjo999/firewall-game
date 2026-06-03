#!/bin/bash
# NRO Shield - Connection Fingerprinting
# Nhan dien thiet bi bang TCP/TLS fingerprint, phan biet player va bot

FP_DIR="/var/log/nroshield/fingerprints"
LOG_FILE="/var/log/nroshield/fingerprint.log"
KNOWN_BOTS_SET="nroshield_known_bots"
SUSPECT_SET="nroshield_suspect"

mkdir -p "$FP_DIR" "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

setup() {
    ipset create "$KNOWN_BOTS_SET" hash:ip timeout 3600 maxelem 50000 2>/dev/null || true
    ipset create "$SUSPECT_SET" hash:ip timeout 600 maxelem 100000 2>/dev/null || true

    # Nhan dien TCP fingerprint bat thuong
    # Window size 0 hoac qua nho -> bot
    iptables -N NROSHIELD_FP 2>/dev/null || iptables -F NROSHIELD_FP

    # TCP window size = 0 (scan tool)
    iptables -A NROSHIELD_FP -p tcp -m u32 \
        --u32 "0>>22&0x3C@14=0" -j SET --add-set "$KNOWN_BOTS_SET" src
    iptables -A NROSHIELD_FP -m set --match-set "$KNOWN_BOTS_SET" src -j DROP

    # TTL bat thuong (< 32 hoac > 200) -> proxy/tunnel
    iptables -A NROSHIELD_FP -m ttl --ttl-lt 32 \
        -j SET --add-set "$SUSPECT_SET" src
    iptables -A NROSHIELD_FP -m ttl --ttl-gt 200 \
        -j SET --add-set "$SUSPECT_SET" src

    # Nhieu ket noi tu 1 IP trong thoi gian ngan -> bot
    iptables -A NROSHIELD_FP -p tcp --syn -m conntrack --ctstate NEW \
        -m hashlimit --hashlimit-above 30/sec --hashlimit-burst 50 \
        --hashlimit-mode srcip --hashlimit-name fp_rate \
        -j SET --add-set "$SUSPECT_SET" src

    # Suspect bi rate limit
    iptables -A NROSHIELD_FP -m set --match-set "$SUSPECT_SET" src \
        -m hashlimit --hashlimit-above 5/sec --hashlimit-burst 10 \
        --hashlimit-mode srcip --hashlimit-name fp_suspect_limit \
        -j DROP

    log "Fingerprint chain da thiet lap"
}

analyze_connections() {
    log "=== Phan tich ket noi ==="

    # Thu thap TCP connection fingerprints
    ss -tnpi 2>/dev/null | while read -r line; do
        local ip
        ip=$(echo "$line" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        [ -z "$ip" ] && continue

        local rtt
        rtt=$(echo "$line" | grep -oP 'rtt:[0-9.]+' | head -1 | cut -d: -f2)
        local cwnd
        cwnd=$(echo "$line" | grep -oP 'cwnd:[0-9]+' | head -1 | cut -d: -f2)

        if [ -n "$rtt" ] && [ -n "$cwnd" ]; then
            echo "$ip rtt=$rtt cwnd=$cwnd ts=$(date +%s)" >> "$FP_DIR/tcp_fp.log"
        fi
    done

    # Dem ket noi per IP
    local conn_file="$FP_DIR/conn_count.tmp"
    ss -tn state established 2>/dev/null | awk '{print $4}' | \
        grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | \
        sort | uniq -c | sort -rn > "$conn_file"

    # IP co > 50 ket noi -> suspect
    while read -r count ip; do
        if [ "$count" -gt 50 ]; then
            ipset add "$SUSPECT_SET" "$ip" timeout 600 2>/dev/null
            log "  Suspect: $ip ($count connections)"
        fi
    done < "$conn_file"

    rm -f "$conn_file"
    log "=== Phan tich hoan tat ==="
}

detect_game_bots() {
    local game_port="${1:-7777}"
    log "=== Phan tich bot game (port $game_port) ==="

    # Thu thap IPs ket noi den game port
    local game_ips="$FP_DIR/game_ips.tmp"
    ss -tn state established "( dport = :$game_port )" 2>/dev/null | \
        awk '{print $4}' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | \
        sort | uniq -c | sort -rn > "$game_ips"

    local bot_count=0
    while read -r count ip; do
        # Nhieu ket noi dong thoi -> bot
        if [ "$count" -gt 5 ]; then
            ipset add "$KNOWN_BOTS_SET" "$ip" timeout 3600 2>/dev/null
            ((bot_count++))
            log "  Bot detected: $ip ($count connections to port $game_port)"
        fi
    done < "$game_ips"

    rm -f "$game_ips"
    log "  Tong bot phat hien: $bot_count"
}

show_stats() {
    local bots
    bots=$(ipset list "$KNOWN_BOTS_SET" 2>/dev/null | grep -c "^[0-9]" || echo 0)
    local suspects
    suspects=$(ipset list "$SUSPECT_SET" 2>/dev/null | grep -c "^[0-9]" || echo 0)
    echo "=== Fingerprint Stats ==="
    echo "Known bots: $bots"
    echo "Suspects: $suspects"
    echo "Fingerprint logs: $(wc -l < "$FP_DIR/tcp_fp.log" 2>/dev/null || echo 0) entries"
}

cleanup() {
    iptables -F NROSHIELD_FP 2>/dev/null
    iptables -X NROSHIELD_FP 2>/dev/null
    ipset destroy "$KNOWN_BOTS_SET" 2>/dev/null
    ipset destroy "$SUSPECT_SET" 2>/dev/null
    log "Da don dep fingerprint system"
}

case "${1:-setup}" in
    setup)
        setup
        log "=== Fingerprint system da kich hoat ==="
        ;;
    analyze)
        analyze_connections
        ;;
    detect-bots)
        detect_game_bots "$2"
        ;;
    stats)
        show_stats
        ;;
    cleanup)
        cleanup
        ;;
    *)
        echo "Su dung: $0 {setup|analyze|detect-bots [port]|stats|cleanup}"
        exit 1
        ;;
esac
