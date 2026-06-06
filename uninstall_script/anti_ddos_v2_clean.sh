#!/bin/bash
# ============================================================================
# NRO Shield v2 — Cleanup Anti-DDoS V2 rules
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../.env"

PROXY_PORT_RANGE_START="30000"
PROXY_PORT_RANGE_END="60000"
NEW_CONN_RATE="300/sec"
NEW_CONN_BURST="150"
MAX_CONN_PER_IP="500"
AMPLIFY_PORTS_PRIMARY="17,19,53,111,123,137,161,389,520,751,1434,1900,5353,11211,27015"
AMPLIFY_PORTS_SECONDARY="32414"

[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
log_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
    log_err "Cần quyền root"
    exit 1
fi

remove_rule_all() {
    local chain="$1"
    shift

    while iptables -C "$chain" "$@" 2>/dev/null; do
        iptables -D "$chain" "$@"
    done
}

flush_and_delete_chain() {
    local chain="$1"

    if iptables -L "$chain" -n >/dev/null 2>&1; then
        iptables -F "$chain"
        iptables -X "$chain"
    fi
}

log_info "============================================"
log_info "  Cleanup Anti-DDoS V2 rules"
log_info "============================================"

log_info "Gỡ các hook INPUT/FORWARD..."
remove_rule_all INPUT -p tcp --syn -j NROSHIELD_SYN_V2
remove_rule_all FORWARD -p tcp --syn -j NROSHIELD_SYN_V2
remove_rule_all INPUT -p udp -m conntrack --ctstate NEW -j NROSHIELD_UDP_V2
remove_rule_all FORWARD -p udp -m conntrack --ctstate NEW -j NROSHIELD_UDP_V2
remove_rule_all INPUT -p tcp -j NROSHIELD_TCPFLOOD_V2
remove_rule_all INPUT -p icmp -j NROSHIELD_ICMP_V2

log_info "Gỡ các rule trực tiếp của V2..."
remove_rule_all INPUT -p udp -m multiport --sports "$AMPLIFY_PORTS_PRIMARY" -m conntrack --ctstate NEW -j DROP
remove_rule_all INPUT -p udp -m multiport --sports "$AMPLIFY_PORTS_SECONDARY" -m conntrack --ctstate NEW -j DROP
remove_rule_all INPUT -p tcp --tcp-flags SYN,ACK SYN,ACK -m multiport --sports 80,443,8080,8443 -m conntrack --ctstate NEW -j DROP
remove_rule_all INPUT -p gre -j DROP
remove_rule_all INPUT -p ipencap -j DROP
remove_rule_all INPUT -p esp -j DROP
remove_rule_all INPUT -p ah -j DROP
remove_rule_all INPUT -p sctp -j DROP

remove_rule_all FORWARD -m conntrack --ctorigdstport "$PROXY_PORT_RANGE_START":"$PROXY_PORT_RANGE_END" -m conntrack --ctstate NEW -m limit --limit 10000/sec --limit-burst 5000 -j ACCEPT
remove_rule_all FORWARD -p udp -m conntrack --ctorigdstport "$PROXY_PORT_RANGE_START":"$PROXY_PORT_RANGE_END" -m conntrack --ctstate NEW -m hashlimit --hashlimit-above "$NEW_CONN_RATE" --hashlimit-burst "$NEW_CONN_BURST" --hashlimit-mode srcip --hashlimit-name fwd_udp_v2 --hashlimit-htable-expire 30000 -j DROP
remove_rule_all FORWARD -p tcp -m conntrack --ctorigdstport "$PROXY_PORT_RANGE_START":"$PROXY_PORT_RANGE_END" -m conntrack --ctstate NEW -m hashlimit --hashlimit-above "$NEW_CONN_RATE" --hashlimit-burst "$NEW_CONN_BURST" --hashlimit-mode srcip --hashlimit-name fwd_tcp_v2 --hashlimit-htable-expire 30000 -j DROP
remove_rule_all FORWARD -p udp -m conntrack --ctorigdstport "$PROXY_PORT_RANGE_START":"$PROXY_PORT_RANGE_END" -m connlimit --connlimit-above "$MAX_CONN_PER_IP" --connlimit-mask 32 -j DROP
remove_rule_all FORWARD -p tcp -m conntrack --ctorigdstport "$PROXY_PORT_RANGE_START":"$PROXY_PORT_RANGE_END" -m connlimit --connlimit-above "$MAX_CONN_PER_IP" --connlimit-mask 32 -j DROP

log_info "Xóa chain NROSHIELD V2..."
flush_and_delete_chain NROSHIELD_DYNBAN
flush_and_delete_chain NROSHIELD_GAME_FIVEM
flush_and_delete_chain NROSHIELD_GAME_MC
flush_and_delete_chain NROSHIELD_GAME_NRO
flush_and_delete_chain NROSHIELD_GAME_SAMP
flush_and_delete_chain NROSHIELD_ICMP_V2
flush_and_delete_chain NROSHIELD_SYN_V2
flush_and_delete_chain NROSHIELD_TCPFLOOD_V2
flush_and_delete_chain NROSHIELD_UDP_V2

log_ok "Đã cleanup Anti-DDoS V2 rules"
