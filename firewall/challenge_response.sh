#!/bin/bash
# NRO Shield - Challenge-Response System
# He thong xac thuc ket noi TCP/UDP bang cookie

CHAIN_NAME="NROSHIELD_CHALLENGE"
COOKIE_TTL=300
LOG_FILE="/var/log/nroshield/challenge.log"
VERIFIED_SET="nroshield_verified"
CHALLENGE_SET="nroshield_challenged"

mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

setup_ipsets() {
    ipset create "$VERIFIED_SET" hash:ip timeout "$COOKIE_TTL" maxelem 100000 2>/dev/null || true
    ipset create "$CHALLENGE_SET" hash:ip timeout 30 maxelem 50000 2>/dev/null || true
    log "Ipsets da san sang"
}

setup_chain() {
    iptables -N "$CHAIN_NAME" 2>/dev/null || iptables -F "$CHAIN_NAME"

    # IP da xac thuc -> cho qua
    iptables -A "$CHAIN_NAME" -m set --match-set "$VERIFIED_SET" src -j RETURN

    # TCP SYN Cookie (kernel-level)
    sysctl -w net.ipv4.tcp_syncookies=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_max_syn_backlog=65535 >/dev/null 2>&1

    # TCP challenge: yeu cau 3-way handshake hoan chinh
    iptables -A "$CHAIN_NAME" -p tcp --syn -m conntrack --ctstate NEW \
        -m hashlimit --hashlimit-above 10/sec --hashlimit-burst 20 \
        --hashlimit-mode srcip --hashlimit-name tcp_challenge \
        -j SET --add-set "$CHALLENGE_SET" src
    iptables -A "$CHAIN_NAME" -m set --match-set "$CHALLENGE_SET" src \
        -p tcp --syn -j DROP

    # UDP challenge: kiem tra ket noi UDP hop le
    iptables -A "$CHAIN_NAME" -p udp -m conntrack --ctstate NEW \
        -m hashlimit --hashlimit-above 20/sec --hashlimit-burst 40 \
        --hashlimit-mode srcip --hashlimit-name udp_challenge \
        -j SET --add-set "$CHALLENGE_SET" src
    iptables -A "$CHAIN_NAME" -m set --match-set "$CHALLENGE_SET" src \
        -p udp -m conntrack --ctstate NEW -j DROP

    # Ket noi hop le (ESTABLISHED) -> danh dau verified
    iptables -A "$CHAIN_NAME" -m conntrack --ctstate ESTABLISHED,RELATED \
        -j SET --add-set "$VERIFIED_SET" src

    log "Challenge chain da thiet lap"
}

apply_to_ports() {
    local ports="${1:-7777,7778,7779,8037,14300,30000:60000}"

    if ! iptables -C INPUT -p tcp -m multiport --dports "$ports" -j "$CHAIN_NAME" 2>/dev/null; then
        iptables -I INPUT -p tcp -m multiport --dports "$ports" -j "$CHAIN_NAME"
        log "Da ap dung challenge cho TCP ports: $ports"
    fi

    if ! iptables -C INPUT -p udp -m multiport --dports "$ports" -j "$CHAIN_NAME" 2>/dev/null; then
        iptables -I INPUT -p udp -m multiport --dports "$ports" -j "$CHAIN_NAME"
        log "Da ap dung challenge cho UDP ports: $ports"
    fi
}

show_stats() {
    local verified
    verified=$(ipset list "$VERIFIED_SET" 2>/dev/null | grep -c "^[0-9]" || echo 0)
    local challenged
    challenged=$(ipset list "$CHALLENGE_SET" 2>/dev/null | grep -c "^[0-9]" || echo 0)
    echo "=== Challenge-Response Stats ==="
    echo "IP da xac thuc: $verified"
    echo "IP dang challenge: $challenged"
    echo "Cookie TTL: ${COOKIE_TTL}s"
}

cleanup() {
    iptables -F "$CHAIN_NAME" 2>/dev/null
    iptables -X "$CHAIN_NAME" 2>/dev/null
    ipset destroy "$VERIFIED_SET" 2>/dev/null
    ipset destroy "$CHALLENGE_SET" 2>/dev/null
    log "Da don dep challenge system"
}

case "${1:-start}" in
    start)
        setup_ipsets
        setup_chain
        apply_to_ports "$2"
        log "=== Challenge-Response da kich hoat ==="
        ;;
    stats)
        show_stats
        ;;
    verify)
        ipset add "$VERIFIED_SET" "$2" timeout "$COOKIE_TTL" 2>/dev/null
        log "Da xac thuc IP: $2"
        ;;
    cleanup)
        cleanup
        ;;
    *)
        echo "Su dung: $0 {start [ports]|stats|verify <ip>|cleanup}"
        exit 1
        ;;
esac
