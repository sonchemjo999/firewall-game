#!/bin/bash
# ============================================================================
# NRO Shield v2 — Multi-Game Support Engine
# ============================================================================
# Mô tả: Hỗ trợ nhiều loại game server với cấu hình firewall riêng biệt
# Games: NRO, SA:MP, MU Online, Lineage, Minecraft, FiveM, Rust, ARK, CS2
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../.env"
GAME_CONFIG_DIR="/opt/nroshield/games"

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
log_info "  NRO Shield v2 — Multi-Game Engine"
log_info "============================================"

mkdir -p "$GAME_CONFIG_DIR"

# ============================================================================
# GAME PROFILES — Cấu hình cho từng loại game
# ============================================================================

create_game_profiles() {
    log_info "Tạo game profiles..."

    # NRO (Ngọc Rồng Online)
    cat > "$GAME_CONFIG_DIR/nro.conf" << 'EOF'
GAME_NAME="NRO (Ngoc Rong Online)"
GAME_TYPE="nro"
PROTOCOL="udp"
DEFAULT_PORTS="14445,20000,1875"
MAX_PACKET_SIZE=1500
MIN_PACKET_SIZE=28
UDP_RATE_PER_IP="500/sec"
UDP_BURST=200
TCP_RATE_PER_IP="100/sec"
TCP_BURST=50
MAX_CONN_PER_IP=100
NEW_CONN_RATE="50/sec"
NEW_CONN_BURST=20
ENABLE_RAKNET_FILTER=true
ENABLE_PAYLOAD_CHECK=true
TIMEOUT_IDLE=300
EOF

    # SA:MP (San Andreas Multiplayer)
    cat > "$GAME_CONFIG_DIR/samp.conf" << 'EOF'
GAME_NAME="SA:MP (San Andreas Multiplayer)"
GAME_TYPE="samp"
PROTOCOL="udp"
DEFAULT_PORTS="7777,7778"
MAX_PACKET_SIZE=2048
MIN_PACKET_SIZE=28
UDP_RATE_PER_IP="500/sec"
UDP_BURST=200
TCP_RATE_PER_IP="50/sec"
TCP_BURST=20
MAX_CONN_PER_IP=50
NEW_CONN_RATE="30/sec"
NEW_CONN_BURST=15
ENABLE_RAKNET_FILTER=true
ENABLE_QUERY_LIMITER=true
TIMEOUT_IDLE=300
EOF

    # Minecraft
    cat > "$GAME_CONFIG_DIR/minecraft.conf" << 'EOF'
GAME_NAME="Minecraft"
GAME_TYPE="minecraft"
PROTOCOL="tcp"
DEFAULT_PORTS="25565"
MAX_PACKET_SIZE=32767
MIN_PACKET_SIZE=1
UDP_RATE_PER_IP="50/sec"
UDP_BURST=20
TCP_RATE_PER_IP="200/sec"
TCP_BURST=80
MAX_CONN_PER_IP=20
NEW_CONN_RATE="10/sec"
NEW_CONN_BURST=5
ENABLE_MOTD_CACHE=true
ENABLE_LOGIN_THROTTLE=true
TIMEOUT_IDLE=1200
EOF

    # FiveM (GTA V Multiplayer)
    cat > "$GAME_CONFIG_DIR/fivem.conf" << 'EOF'
GAME_NAME="FiveM (GTA V MP)"
GAME_TYPE="fivem"
PROTOCOL="both"
DEFAULT_PORTS="30120"
MAX_PACKET_SIZE=4096
MIN_PACKET_SIZE=28
UDP_RATE_PER_IP="600/sec"
UDP_BURST=300
TCP_RATE_PER_IP="200/sec"
TCP_BURST=80
MAX_CONN_PER_IP=50
NEW_CONN_RATE="30/sec"
NEW_CONN_BURST=15
ENABLE_CFXAUTH_CHECK=true
TIMEOUT_IDLE=600
EOF

    # MU Online
    cat > "$GAME_CONFIG_DIR/muonline.conf" << 'EOF'
GAME_NAME="MU Online"
GAME_TYPE="muonline"
PROTOCOL="tcp"
DEFAULT_PORTS="44405,55901,55902,55903"
MAX_PACKET_SIZE=4096
MIN_PACKET_SIZE=4
UDP_RATE_PER_IP="100/sec"
UDP_BURST=50
TCP_RATE_PER_IP="300/sec"
TCP_BURST=100
MAX_CONN_PER_IP=30
NEW_CONN_RATE="20/sec"
NEW_CONN_BURST=10
ENABLE_PACKET_HEADER_CHECK=true
TIMEOUT_IDLE=600
EOF

    # Rust
    cat > "$GAME_CONFIG_DIR/rust.conf" << 'EOF'
GAME_NAME="Rust"
GAME_TYPE="rust"
PROTOCOL="udp"
DEFAULT_PORTS="28015,28016"
MAX_PACKET_SIZE=4096
MIN_PACKET_SIZE=28
UDP_RATE_PER_IP="1000/sec"
UDP_BURST=500
TCP_RATE_PER_IP="100/sec"
TCP_BURST=50
MAX_CONN_PER_IP=50
NEW_CONN_RATE="30/sec"
NEW_CONN_BURST=15
ENABLE_STEAMQUERY_LIMITER=true
TIMEOUT_IDLE=600
EOF

    # ARK: Survival Evolved
    cat > "$GAME_CONFIG_DIR/ark.conf" << 'EOF'
GAME_NAME="ARK: Survival Evolved"
GAME_TYPE="ark"
PROTOCOL="udp"
DEFAULT_PORTS="7777,7778,27015"
MAX_PACKET_SIZE=4096
MIN_PACKET_SIZE=28
UDP_RATE_PER_IP="800/sec"
UDP_BURST=400
TCP_RATE_PER_IP="100/sec"
TCP_BURST=50
MAX_CONN_PER_IP=50
NEW_CONN_RATE="30/sec"
NEW_CONN_BURST=15
ENABLE_STEAMQUERY_LIMITER=true
TIMEOUT_IDLE=600
EOF

    # CS2 (Counter-Strike 2)
    cat > "$GAME_CONFIG_DIR/cs2.conf" << 'EOF'
GAME_NAME="CS2 (Counter-Strike 2)"
GAME_TYPE="cs2"
PROTOCOL="udp"
DEFAULT_PORTS="27015,27016"
MAX_PACKET_SIZE=4096
MIN_PACKET_SIZE=28
UDP_RATE_PER_IP="800/sec"
UDP_BURST=400
TCP_RATE_PER_IP="100/sec"
TCP_BURST=50
MAX_CONN_PER_IP=50
NEW_CONN_RATE="30/sec"
NEW_CONN_BURST=15
ENABLE_STEAMQUERY_LIMITER=true
ENABLE_A2S_CACHE=true
TIMEOUT_IDLE=600
EOF

    # Lineage 2
    cat > "$GAME_CONFIG_DIR/lineage2.conf" << 'EOF'
GAME_NAME="Lineage 2"
GAME_TYPE="lineage2"
PROTOCOL="tcp"
DEFAULT_PORTS="7777,2106,2108"
MAX_PACKET_SIZE=8192
MIN_PACKET_SIZE=4
UDP_RATE_PER_IP="50/sec"
UDP_BURST=20
TCP_RATE_PER_IP="200/sec"
TCP_BURST=80
MAX_CONN_PER_IP=20
NEW_CONN_RATE="10/sec"
NEW_CONN_BURST=5
ENABLE_PACKET_HEADER_CHECK=true
TIMEOUT_IDLE=900
EOF

    log_ok "Đã tạo $(ls "$GAME_CONFIG_DIR"/*.conf 2>/dev/null | wc -l) game profiles"
}

# ============================================================================
# APPLY GAME RULES — Áp dụng rules cho game cụ thể
# ============================================================================

apply_game_rules() {
    local GAME_TYPE="$1"
    local PROXY_PORT="$2"
    local CONFIG_FILE="$GAME_CONFIG_DIR/${GAME_TYPE}.conf"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_warn "Không tìm thấy profile cho game: $GAME_TYPE"
        log_info "Games hỗ trợ: nro, samp, minecraft, fivem, muonline, rust, ark, cs2, lineage2"
        return 1
    fi

    source "$CONFIG_FILE"

    local CHAIN_NAME="GAME_${GAME_TYPE^^}_${PROXY_PORT}"

    log_info "Áp dụng rules cho $GAME_NAME trên port $PROXY_PORT..."

    # Tạo chain riêng cho game+port
    iptables -N "$CHAIN_NAME" 2>/dev/null || iptables -F "$CHAIN_NAME"

    # Packet size filtering
    if [[ "$PROTOCOL" == "udp" || "$PROTOCOL" == "both" ]]; then
        iptables -A "$CHAIN_NAME" -p udp -m length --length 0:$((MIN_PACKET_SIZE-1)) -j DROP
        iptables -A "$CHAIN_NAME" -p udp -m length --length $((MAX_PACKET_SIZE+1)):65535 -j DROP

        iptables -A "$CHAIN_NAME" -p udp \
            -m hashlimit \
            --hashlimit-above "$UDP_RATE_PER_IP" \
            --hashlimit-burst "$UDP_BURST" \
            --hashlimit-mode srcip \
            --hashlimit-name "${GAME_TYPE}_${PROXY_PORT}_udp" \
            --hashlimit-htable-expire 15000 \
            -j DROP
    fi

    if [[ "$PROTOCOL" == "tcp" || "$PROTOCOL" == "both" ]]; then
        iptables -A "$CHAIN_NAME" -p tcp \
            -m hashlimit \
            --hashlimit-above "$TCP_RATE_PER_IP" \
            --hashlimit-burst "$TCP_BURST" \
            --hashlimit-mode srcip \
            --hashlimit-name "${GAME_TYPE}_${PROXY_PORT}_tcp" \
            --hashlimit-htable-expire 30000 \
            -j DROP

        iptables -A "$CHAIN_NAME" -p tcp \
            -m connlimit --connlimit-above "$MAX_CONN_PER_IP" --connlimit-mask 32 \
            -j DROP
    fi

    # New connection rate limiting
    iptables -A "$CHAIN_NAME" -m conntrack --ctstate NEW \
        -m hashlimit \
        --hashlimit-above "$NEW_CONN_RATE" \
        --hashlimit-burst "$NEW_CONN_BURST" \
        --hashlimit-mode srcip \
        --hashlimit-name "${GAME_TYPE}_${PROXY_PORT}_new" \
        --hashlimit-htable-expire 30000 \
        -j DROP

    iptables -A "$CHAIN_NAME" -j RETURN

    # Hook vào FORWARD chain cho proxy port
    iptables -I FORWARD 1 -m conntrack --ctorigdstport "$PROXY_PORT" -j "$CHAIN_NAME"

    log_ok "$GAME_NAME: rules applied for port $PROXY_PORT"
}

# ============================================================================
# REMOVE GAME RULES — Gỡ rules cho game cụ thể
# ============================================================================

remove_game_rules() {
    local GAME_TYPE="$1"
    local PROXY_PORT="$2"
    local CHAIN_NAME="GAME_${GAME_TYPE^^}_${PROXY_PORT}"

    log_info "Gỡ rules cho $GAME_TYPE trên port $PROXY_PORT..."

    iptables -D FORWARD -m conntrack --ctorigdstport "$PROXY_PORT" -j "$CHAIN_NAME" 2>/dev/null || true
    iptables -F "$CHAIN_NAME" 2>/dev/null || true
    iptables -X "$CHAIN_NAME" 2>/dev/null || true

    log_ok "Rules đã gỡ: $GAME_TYPE port $PROXY_PORT"
}

# ============================================================================
# LIST SUPPORTED GAMES
# ============================================================================

list_games() {
    echo ""
    echo "=== GAMES HỖ TRỢ ==="
    echo ""
    for conf in "$GAME_CONFIG_DIR"/*.conf; do
        [[ -f "$conf" ]] || continue
        source "$conf"
        local game_file
        game_file=$(basename "$conf" .conf)
        printf "  %-12s  %-30s  Protocol: %-5s  Ports: %s\n" \
            "$game_file" "$GAME_NAME" "$PROTOCOL" "$DEFAULT_PORTS"
    done
    echo ""
}

# ============================================================================
# MAIN
# ============================================================================

case "${1:-setup}" in
    setup)
        create_game_profiles
        list_games
        ;;
    apply)
        if [[ $# -lt 3 ]]; then
            echo "Usage: $0 apply <game_type> <proxy_port>"
            echo "Example: $0 apply nro 30001"
            exit 1
        fi
        apply_game_rules "$2" "$3"
        ;;
    remove)
        if [[ $# -lt 3 ]]; then
            echo "Usage: $0 remove <game_type> <proxy_port>"
            exit 1
        fi
        remove_game_rules "$2" "$3"
        ;;
    list)
        list_games
        ;;
    *)
        echo "Usage: $0 {setup|apply|remove|list}"
        echo ""
        echo "  setup          Tạo game profiles"
        echo "  apply <game> <port>  Áp dụng rules cho game"
        echo "  remove <game> <port> Gỡ rules cho game"
        echo "  list           Liệt kê games hỗ trợ"
        ;;
esac
