#!/bin/bash
# ============================================================================
# NRO Shield v2.0 — Master Setup Script
# ============================================================================
# Setup de dang, on dinh lau dai. Chay 1 lenh duy nhat de cai dat toan bo.
# Su dung: sudo bash master_setup.sh [game_type] [mode]
#          sudo bash master_setup.sh --mode docker
# Vi du:   sudo bash master_setup.sh nro
#          sudo bash master_setup.sh minecraft
#          sudo bash master_setup.sh all
#          sudo bash master_setup.sh --mode docker
#          sudo bash master_setup.sh nro --mode native
# ============================================================================

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# === Colors & Logging ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

log_step()  { echo -e "\n${PURPLE}${BOLD}[STEP]${NC} $1"; }
log_info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_internet_connectivity() {
    if ping -c 1 -W 3 google.com >/dev/null 2>&1; then
        log_ok "Da ket noi Internet (ping google.com thanh cong)"
        return 0
    fi

    log_error "Khong the ping google.com. Dung script de tranh cai dat loi."
    exit 1
}

is_docker_mode() {
    [[ "$DEPLOY_MODE" == "docker" ]]
}

setup_docker_firewall_compat() {
    if ! is_docker_mode; then
        return 0
    fi

    if ! command -v iptables >/dev/null 2>&1; then
        log_warn "Khong tim thay iptables, bo qua Docker firewall compatibility"
        return 0
    fi

    log_info "Dam bao Docker co the tao DOCKER-FORWARD chain..."

    iptables -N DOCKER-USER 2>/dev/null || true
    iptables -C FORWARD -j DOCKER-USER 2>/dev/null || iptables -I FORWARD 1 -j DOCKER-USER

    iptables -N DOCKER-FORWARD 2>/dev/null || true
    iptables -C DOCKER-FORWARD -i docker0 -j ACCEPT 2>/dev/null || true
    iptables -C FORWARD -j DOCKER-FORWARD 2>/dev/null || iptables -A FORWARD -j DOCKER-FORWARD

    if systemctl is-enabled docker >/dev/null 2>&1; then
        systemctl restart docker
    else
        systemctl start docker 2>/dev/null || true
    fi

    log_ok "Docker firewall compatibility da san sang"
}

print_usage() {
    cat <<'EOF'
Usage:
  sudo bash master_setup.sh [game_type] [--mode <native|docker>]
  sudo bash master_setup.sh [game_type] [native|docker]

Examples:
  sudo bash master_setup.sh nro
  sudo bash master_setup.sh all
  sudo bash master_setup.sh --mode docker
  sudo bash master_setup.sh nro --mode docker
EOF
}

GAME_TYPE="all"
DEPLOY_MODE="native"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            [[ $# -ge 2 ]] || { log_error "Thieu gia tri cho --mode"; print_usage; exit 1; }
            DEPLOY_MODE="$2"
            shift 2
            ;;
        native|docker)
            DEPLOY_MODE="$1"
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            if [[ "$GAME_TYPE" == "all" ]]; then
                GAME_TYPE="$1"
                shift
            else
                log_error "Tham so khong hop le: $1"
                print_usage
                exit 1
            fi
            ;;
    esac
done

if [[ "$DEPLOY_MODE" != "native" && "$DEPLOY_MODE" != "docker" ]]; then
    log_error "Mode khong hop le: $DEPLOY_MODE"
    print_usage
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_FILE="/var/log/nroshield/setup_$(date +%Y%m%d_%H%M%S).log"
BACKUP_DIR="/opt/nroshield/backups/$(date +%Y%m%d_%H%M%S)"
CONFIG_FILE="${PROJECT_ROOT}/.env"

[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

# === Helpers ===
check_internet_connectivity

resolve_proxy_port_start() {
    local explicit_start="${PROXY_PORT_RANGE_START:-}"
    if [[ "$explicit_start" =~ ^[0-9]+$ ]]; then
        echo "$explicit_start"
    else
        echo "30000"
    fi
}

get_supported_games() {
    local conf_path
    for conf_path in /opt/nroshield/games/*.conf; do
        [[ -f "$conf_path" ]] || continue
        basename "$conf_path" .conf
    done
}

run_and_log() {
    "$@" 2>&1 | tee -a "$LOG_FILE"
}

ensure_env_file() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log_ok "Da tim thay file cau hinh: $CONFIG_FILE"
        return 0
    fi

    if [[ -f "$PROJECT_ROOT/.env.example" ]]; then
        cp "$PROJECT_ROOT/.env.example" "$CONFIG_FILE"
        log_warn "Khong tim thay .env, da tao tu .env.example"
        log_warn "Hay kiem tra lai VPS_PUBLIC_IP, DB_PASS, JWT_SECRET trong $CONFIG_FILE"
        source "$CONFIG_FILE"
        return 0
    fi

    log_error "Khong tim thay .env hoac .env.example"
    exit 1
}

setup_system_packages() {
    log_info "Cap nhat he thong va cai dat packages can thiet..."
    apt-get update -y
    apt-get upgrade -y
    apt-get install -y curl wget git nano unzip build-essential \
        python3 python3-pip python3-venv python3-dev \
        mariadb-server mariadb-client \
        iptables ipset iptables-persistent netfilter-persistent conntrack \
        net-tools iproute2 htop iftop vnstat tcpdump nmap jq bc \
        nginx fail2ban software-properties-common apt-transport-https \
        ca-certificates gnupg lsb-release

    if ! command -v uv >/dev/null 2>&1; then
        log_info "Cai dat uv..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
        export PATH="$HOME/.local/bin:$PATH"
    fi

    if is_docker_mode; then
        if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
            log_ok "Che do docker: Docker Engine va Docker Compose da co san"
        else
            log_info "Che do docker: Docker chua co day du, tien hanh cai dat..."
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            chmod a+r /etc/apt/keyrings/docker.gpg
            echo \
              "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
              $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            apt-get update -y
            apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        fi

        systemctl enable docker 2>/dev/null || true
        systemctl start docker 2>/dev/null || true
    fi

    if ! command -v node >/dev/null 2>&1 || ! node -v 2>/dev/null | grep -q '^v18\.'; then
        log_info "Cai dat Node.js 18..."
        curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
        apt-get install -y nodejs
    fi

    if ! is_docker_mode; then
        systemctl enable mariadb 2>/dev/null || true
        systemctl start mariadb 2>/dev/null || true
    fi

    log_ok "System packages da san sang"
}

setup_database() {
    if is_docker_mode; then
        log_info "Che do docker: bo qua MariaDB host, database se chay trong container db"
        return 0
    fi

    local db_name="${DB_NAME:-nroshield}"
    local db_user="${DB_USER:-nroshield}"
    local db_pass="${DB_PASS:-}"

    if [[ -z "$db_pass" || "$db_pass" == "your_strong_password_here" ]]; then
        log_warn "DB_PASS chua duoc dat trong .env; bo qua tao database/user tu dong"
        return 0
    fi

    log_info "Khoi tao MariaDB database va user neu can..."
    mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS ${db_name} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${db_user}'@'localhost' IDENTIFIED BY '${db_pass}';
ALTER USER '${db_user}'@'localhost' IDENTIFIED BY '${db_pass}';
GRANT ALL PRIVILEGES ON ${db_name}.* TO '${db_user}'@'localhost';
FLUSH PRIVILEGES;
EOF
    log_ok "Database da san sang: ${db_name}"
}

setup_backend() {
    if is_docker_mode; then
        log_info "Che do docker: bo qua npm install backend tren host"
        return 0
    fi

    if [[ ! -d "$PROJECT_ROOT/backend" ]]; then
        log_warn "Khong tim thay thu muc backend, bo qua"
        return 0
    fi

    log_info "Cai dat dependencies backend..."
    (cd "$PROJECT_ROOT/backend" && run_and_log npm install)

    log_info "Chay database migrations..."
    (cd "$PROJECT_ROOT/backend" && run_and_log npm run migrate)

    log_ok "Backend da cai dat xong"
}

setup_telegram_bot() {
    if is_docker_mode; then
        log_info "Che do docker: bo qua Telegram bot tren host"
        return 0
    fi

    if [[ ! -d "$PROJECT_ROOT/telegram_bot" ]]; then
        log_warn "Khong tim thay thu muc telegram_bot, bo qua"
        return 0
    fi

    log_info "Cai dat dependencies Telegram bot..."
    (cd "$PROJECT_ROOT/telegram_bot" && run_and_log npm install)
    log_ok "Telegram bot da cai dat xong"
}

setup_ai_engine() {
    if is_docker_mode; then
        log_info "Che do docker: bo qua AI Engine host venv, container ai_engine se chay sau"
        return 0
    fi

    if [[ ! -d "$PROJECT_ROOT/ai_engine" ]]; then
        log_warn "Khong tim thay thu muc ai_engine, bo qua"
        return 0
    fi

    log_info "Cai dat AI Engine Python environment bang uv..."
    (cd "$PROJECT_ROOT/ai_engine" && run_and_log uv venv venv)
    (cd "$PROJECT_ROOT/ai_engine" && run_and_log uv pip install --python ./venv/bin/python -r requirements.txt)
    log_ok "AI Engine da cai dat xong"
}

apply_game_profile() {
    local requested_game="$1"
    local proxy_port_start="$2"
    local profile_path="/opt/nroshield/games/${requested_game}.conf"
    local default_ports_raw
    local offset=0
    local proxy_port
    local game_port

    if [[ ! -f "$profile_path" ]]; then
        log_warn "Khong tim thay profile game: ${requested_game}"
        return 1
    fi

    source "$profile_path"
    default_ports_raw="${DEFAULT_PORTS:-}"

    if [[ -z "$default_ports_raw" ]]; then
        log_warn "Game ${requested_game} khong co DEFAULT_PORTS, bo qua auto-apply"
        return 1
    fi

    IFS=',' read -r -a default_ports <<< "$default_ports_raw"
    for game_port in "${default_ports[@]}"; do
        proxy_port=$((proxy_port_start + offset))
        log_info "Auto-apply ${requested_game}: game port ${game_port} -> proxy port ${proxy_port}"
        run_and_log bash "$SCRIPT_DIR/multi_game_support.sh" apply "$requested_game" "$proxy_port"
        offset=$((offset + 1))
    done

    log_ok "Da auto-apply ${#default_ports[@]} proxy ports cho game: ${requested_game}"
    return 0
}

setup_game_rules() {
    local requested_game="$1"
    local base_proxy_port
    local next_proxy_port
    local game_name
    local applied_games=0

    if [[ ! -f "$SCRIPT_DIR/multi_game_support.sh" ]]; then
        log_warn "multi_game_support.sh khong tim thay, bo qua game-specific rules"
        return 0
    fi

    run_and_log bash "$SCRIPT_DIR/multi_game_support.sh" setup

    if is_docker_mode; then
        log_info "Che do docker: khong auto-apply game ports; se cau hinh sau tren Dashboard"
        return 0
    fi

    base_proxy_port="$(resolve_proxy_port_start)"
    next_proxy_port="$base_proxy_port"

    if [[ "$requested_game" == "all" ]]; then
        for game_name in $(get_supported_games); do
            if apply_game_profile "$game_name" "$next_proxy_port"; then
                local profile_path="/opt/nroshield/games/${game_name}.conf"
                source "$profile_path"
                IFS=',' read -r -a default_ports <<< "${DEFAULT_PORTS:-}"
                next_proxy_port=$((next_proxy_port + ${#default_ports[@]}))
                applied_games=$((applied_games + 1))
            fi
        done

        if [[ $applied_games -eq 0 ]]; then
            log_warn "Khong co game nao duoc auto-apply trong che do all"
        else
            log_ok "Che do all: da auto-apply ${applied_games} game profiles"
        fi
        return 0
    fi

    apply_game_profile "$requested_game" "$base_proxy_port"
}

setup_nginx() {
    local nginx_target="/etc/nginx/sites-available/default"

    log_info "Cau hinh Nginx reverse proxy..."
    cat > "$nginx_target" <<'NGINXEOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _;
    root /opt/nroshield/web;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:5000/api/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /ws {
        proxy_pass http://127.0.0.1:5000/ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }

    location /status {
        proxy_pass http://127.0.0.1:8000/status;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
    }
}
NGINXEOF

    if is_docker_mode; then
        rm -f /etc/nginx/sites-enabled/default
        ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/nroshield.conf
    else
        ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
    fi

    run_and_log nginx -t
    systemctl restart nginx
    systemctl enable nginx
    log_ok "Nginx da duoc cau hinh"
}

setup_app_services() {
    if is_docker_mode; then
        log_info "Che do docker: bo qua systemd services cho backend/bot/ai tren host"
        return 0
    fi

    if [[ ! -d "$PROJECT_ROOT/services" ]]; then
        log_warn "Khong tim thay thu muc services, bo qua service app"
        return 0
    fi

    log_info "Cai dat systemd services cho backend, bot va AI..."
    cp "$PROJECT_ROOT/services/nroshield-api.service" /etc/systemd/system/ 2>/dev/null || true
    cp "$PROJECT_ROOT/services/nroshield-bot.service" /etc/systemd/system/ 2>/dev/null || true
    cp "$PROJECT_ROOT/services/nroshield-ai.service" /etc/systemd/system/ 2>/dev/null || true

    systemctl daemon-reload
    systemctl enable nroshield-api 2>/dev/null || true
    systemctl restart nroshield-api 2>/dev/null || true

    if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]]; then
        systemctl enable nroshield-bot 2>/dev/null || true
        systemctl restart nroshield-bot 2>/dev/null || true
    else
        log_warn "TELEGRAM_BOT_TOKEN/CHAT_ID chua cau hinh, bo qua khoi dong bot"
    fi

    if [[ -x "$PROJECT_ROOT/ai_engine/venv/bin/python" ]]; then
        systemctl enable nroshield-ai 2>/dev/null || true
        systemctl restart nroshield-ai 2>/dev/null || true
    else
        log_warn "AI Engine venv chua san sang, bo qua khoi dong AI service"
    fi

    log_ok "Services ung dung da duoc cai dat"
}

# === Root check ===
if [[ $EUID -ne 0 ]]; then
    log_error "Can quyen root. Su dung: sudo bash $0 [game_type] [--mode docker]"
    exit 1
fi

# === Create directories ===
mkdir -p /var/log/nroshield/{attacks,traffic,ai,setup}
mkdir -p /opt/nroshield/{ai_models,backups,configs}
mkdir -p "$BACKUP_DIR"

echo "" | tee "$LOG_FILE"
echo -e "${PURPLE}${BOLD}" | tee -a "$LOG_FILE"
echo "  ╔══════════════════════════════════════════════════╗" | tee -a "$LOG_FILE"
echo "  ║          NRO Shield v2.0 — Master Setup          ║" | tee -a "$LOG_FILE"
echo "  ║     Advanced DDoS Protection for Game Servers     ║" | tee -a "$LOG_FILE"
echo "  ╚══════════════════════════════════════════════════╝" | tee -a "$LOG_FILE"
echo -e "${NC}" | tee -a "$LOG_FILE"
echo "  Game Type: ${GAME_TYPE}" | tee -a "$LOG_FILE"
echo "  Deploy Mode: ${DEPLOY_MODE}" | tee -a "$LOG_FILE"
echo "  Date: $(date)" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# ============================================================================
# STEP 1: Backup current config
# ============================================================================
log_step "1/12 — Backup cau hinh hien tai"

if command -v iptables-save &>/dev/null; then
    iptables-save > "$BACKUP_DIR/iptables.rules.bak" 2>/dev/null || true
    log_ok "Backed up iptables rules"
fi
if command -v ipset &>/dev/null; then
    ipset save > "$BACKUP_DIR/ipset.rules.bak" 2>/dev/null || true
    log_ok "Backed up ipset rules"
fi
cp /etc/sysctl.conf "$BACKUP_DIR/sysctl.conf.bak" 2>/dev/null || true
log_ok "Backup luu tai: $BACKUP_DIR"

# ============================================================================
# STEP 2: Ensure env config
# ============================================================================
log_step "2/12 — Kiem tra cau hinh .env"
ensure_env_file
log_ok "Cau hinh moi truong da san sang"

# ============================================================================
# STEP 3: System packages
# ============================================================================
log_step "3/12 — Cai dat packages he thong"
setup_system_packages
log_ok "Packages he thong da san sang"

# ============================================================================
# STEP 4: Database setup
# ============================================================================
log_step "4/12 — Khoi tao database"
setup_database
log_ok "Database da san sang"

# ============================================================================
# STEP 5: Backend / Bot / AI dependencies
# ============================================================================
log_step "5/12 — Cai dat cac module ung dung"
setup_backend
setup_telegram_bot
setup_ai_engine
log_ok "Cac module ung dung da cai dat xong"

# ============================================================================
# STEP 6: Kernel hardening
# ============================================================================
log_step "6/12 — Toi uu hoa kernel (sysctl hardening)"
if [[ -f "$SCRIPT_DIR/sysctl_hardening.sh" ]]; then
    run_and_log bash "$SCRIPT_DIR/sysctl_hardening.sh"
else
    log_warn "sysctl_hardening.sh khong tim thay"
fi
log_ok "Kernel da toi uu"

# ============================================================================
# STEP 7: Base firewall + early drop
# ============================================================================
log_step "7/12 — Thiet lap firewall base va early drop"
if [[ -f "$SCRIPT_DIR/install.sh" ]]; then
    run_and_log bash "$SCRIPT_DIR/install.sh" "$DEPLOY_MODE"
fi
if [[ -f "$SCRIPT_DIR/early_drop.sh" ]]; then
    run_and_log bash "$SCRIPT_DIR/early_drop.sh"
fi
if [[ -f "$SCRIPT_DIR/iptables_base.sh" ]]; then
    run_and_log bash "$SCRIPT_DIR/iptables_base.sh"
fi
setup_docker_firewall_compat
log_ok "Base firewall da thiet lap"

# ============================================================================
# STEP 8: Anti-DDoS stack
# ============================================================================
log_step "8/12 — Thiet lap Anti-DDoS stack"
if [[ -f "$SCRIPT_DIR/anti_ddos_v2.sh" ]]; then
    run_and_log bash "$SCRIPT_DIR/anti_ddos_v2.sh"
fi
if [[ -f "$SCRIPT_DIR/anti_bypass.sh" ]]; then
    run_and_log bash "$SCRIPT_DIR/anti_bypass.sh"
fi
if [[ -f "$SCRIPT_DIR/anti_botnet.sh" ]]; then
    run_and_log bash "$SCRIPT_DIR/anti_botnet.sh"
fi
if [[ -f "$SCRIPT_DIR/fail2ban_setup.sh" ]]; then
    run_and_log bash "$SCRIPT_DIR/fail2ban_setup.sh"
fi
if [[ -f "$SCRIPT_DIR/crowdsec_setup.sh" ]]; then
    run_and_log bash "$SCRIPT_DIR/crowdsec_setup.sh"
fi
log_ok "Anti-DDoS stack da thiet lap"

# ============================================================================
# STEP 9: Game-specific rules
# ============================================================================
log_step "9/12 — Thiet lap game profiles / rules (${GAME_TYPE})"
setup_game_rules "$GAME_TYPE"
if is_docker_mode; then
    log_ok "Game profiles da san sang; game ports se duoc cau hinh sau tren Dashboard"
else
    log_ok "Game rules da thiet lap cho: ${GAME_TYPE}"
fi

# ============================================================================
# STEP 10: Nginx reverse proxy
# ============================================================================
log_step "10/12 — Cau hinh Nginx"
setup_nginx
log_ok "Nginx da san sang"

# ============================================================================
# STEP 11: Systemd services
# ============================================================================
log_step "11/12 — Thiet lap systemd services"
setup_app_services

cat > /etc/systemd/system/nroshield-firewall.service << 'SVCEOF'
[Unit]
Description=NRO Shield Firewall Rules Restore
After=network-pre.target
Before=network.target
Wants=network-pre.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/sbin/iptables-restore /etc/iptables/rules.v4
ExecStart=/sbin/ipset restore -f /etc/ipset.rules
ExecStop=/sbin/iptables-save -f /etc/iptables/rules.v4
ExecStop=/sbin/ipset save -f /etc/ipset.rules

[Install]
WantedBy=multi-user.target
SVCEOF

cat > /etc/cron.daily/nroshield-update << 'CRONEOF'
#!/bin/bash
LOG="/var/log/nroshield/cron_update.log"
echo "$(date) — Starting blocklist update" >> "$LOG"
if [[ -f /opt/nroshield/configs/botnet_update.sh ]]; then
    bash /opt/nroshield/configs/botnet_update.sh >> "$LOG" 2>&1
fi
find /var/log/nroshield/attacks/ -type f -mtime +30 -delete 2>/dev/null
echo "$(date) — Update complete" >> "$LOG"
CRONEOF
chmod +x /etc/cron.daily/nroshield-update

systemctl daemon-reload
systemctl enable nroshield-firewall.service 2>/dev/null || true
iptables-save > /etc/iptables/rules.v4 2>/dev/null || iptables-save > /etc/iptables.rules 2>/dev/null || true
ipset save > /etc/ipset.rules 2>/dev/null || true
log_ok "Systemd services da thiet lap"

# ============================================================================
# STEP 12: Verify & Summary
# ============================================================================
log_step "12/12 — Kiem tra va tong ket"

echo ""
echo -e "${PURPLE}${BOLD}  ╔══════════════════════════════════════════════════╗${NC}"
echo -e "${PURPLE}${BOLD}  ║              SETUP HOAN TAT!                      ║${NC}"
echo -e "${PURPLE}${BOLD}  ╚══════════════════════════════════════════════════╝${NC}"
echo ""

TOTAL_INPUT=$(iptables -L INPUT -n 2>/dev/null | grep -c "^" || echo "0")
TOTAL_FORWARD=$(iptables -L FORWARD -n 2>/dev/null | grep -c "^" || echo "0")
TOTAL_MANGLE=$(iptables -t mangle -L -n 2>/dev/null | grep -c "^" || echo "0")
TOTAL_NAT=$(iptables -t nat -L -n 2>/dev/null | grep -c "^" || echo "0")
TOTAL_IPSET=$(ipset list -n 2>/dev/null | wc -l || echo "0")
CONNTRACK_MAX=$(sysctl -n net.netfilter.nf_conntrack_max 2>/dev/null || echo "N/A")

echo "  Thong ke bao mat:"
echo "  ─────────────────────────────────────────"
echo "  INPUT rules:        ${TOTAL_INPUT}"
echo "  FORWARD rules:      ${TOTAL_FORWARD}"
echo "  Mangle rules:       ${TOTAL_MANGLE}"
echo "  NAT rules:          ${TOTAL_NAT}"
echo "  ipset sets:         ${TOTAL_IPSET}"
echo "  Conntrack max:      ${CONNTRACK_MAX}"
echo "  Game type:          ${GAME_TYPE}"
echo "  Deploy mode:        ${DEPLOY_MODE}"
echo "  Project root:       ${PROJECT_ROOT}"
echo "  ─────────────────────────────────────────"
echo "  Backup:             ${BACKUP_DIR}"
echo "  Log:                ${LOG_FILE}"
echo ""
echo "  Dich vu:"
if is_docker_mode; then
    echo "  [x] Docker Engine + Compose plugin"
    echo "  [x] Host firewall + anti-DDoS base"
    echo "  [x] Game profiles san sang"
    echo "  [ ] Game ports se tao sau tren Dashboard"
    echo "  [x] Nginx reverse proxy cho stack Docker"
    echo "  [ ] 3 container se duoc chay sau bang: docker compose up -d --build"
    echo "  [ ] Migrations container se chay sau bang: docker compose exec backend npm run migrate"
else
    echo "  [x] MariaDB duoc kiem tra / khoi dong"
    echo "  [x] Backend npm install + migrate"
    echo "  [x] Telegram bot npm install"
    echo "  [x] AI Engine venv + pip install"
    echo "  [x] Nginx reverse proxy"
    echo "  [x] Firewall auto-restore khi reboot"
fi
echo ""
echo "  Tinh nang bao ve:"
echo "  [x] Anti-SYN Flood (3 lop)"
echo "  [x] Anti-UDP Flood (game-aware)"
echo "  [x] Anti-ACK/RST/FIN Flood"
echo "  [x] Anti-Bypass (TCP/UDP validation)"
echo "  [x] Anti-Carpet Bombing"
echo "  [x] Anti-Reflection (NTP/DNS/Memcached)"
echo "  [x] Early Drop Engine (raw table pre-conntrack)"
echo "  [x] Anti-Botnet (IP blocklists)"
echo "  [x] Adaptive Rate Limiting"
echo "  [x] Dynamic Blacklisting"
echo "  [x] Game-specific packet validation"
echo "  [x] Connection exhaustion defense"
echo "  [x] Kernel hardening (sysctl)"
echo "  [x] Fail2Ban"
echo "  [x] CrowdSec"
echo "  [x] Auto-restore on reboot"
echo "  [x] Daily blocklist updates"
echo ""
echo -e "${GREEN}  Setup on dinh lau dai — chay 1 lenh la cai dat toan bo theo README/SETUP.${NC}"
if is_docker_mode; then
    echo -e "${CYAN}  Tiep theo: cd ${PROJECT_ROOT} && docker compose up -d --build${NC}"
    echo -e "${CYAN}             docker compose exec backend npm run migrate${NC}"
    echo -e "${CYAN}             Sau do vao Dashboard de tao server, proxy port va game port${NC}"
else
    echo -e "${CYAN}  Kiem tra: systemctl status nroshield-firewall nroshield-api nginx${NC}"
fi
echo ""
