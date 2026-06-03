#!/bin/bash
# NRO Shield - Backup & Restore
# Sao luu va phuc hoi cau hinh firewall

BACKUP_DIR="/var/backups/nroshield"
CONFIG_DIR="/etc/nroshield"
LOG_FILE="/var/log/nroshield/backup.log"

mkdir -p "$BACKUP_DIR" "$CONFIG_DIR" "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

backup() {
    local name="${1:-$(date +%Y%m%d_%H%M%S)}"
    local backup_path="$BACKUP_DIR/$name"
    mkdir -p "$backup_path"

    log "=== Bat dau backup: $name ==="

    # Backup iptables rules
    iptables-save > "$backup_path/iptables.rules" 2>/dev/null
    log "  iptables rules: $(wc -l < "$backup_path/iptables.rules") dong"

    # Backup ip6tables rules
    ip6tables-save > "$backup_path/ip6tables.rules" 2>/dev/null
    log "  ip6tables rules: $(wc -l < "$backup_path/ip6tables.rules") dong"

    # Backup ipset
    ipset save > "$backup_path/ipset.save" 2>/dev/null
    log "  ipset: $(wc -l < "$backup_path/ipset.save") dong"

    # Backup sysctl settings
    sysctl -a 2>/dev/null | grep -E '^net\.' > "$backup_path/sysctl_net.conf"
    log "  sysctl net: $(wc -l < "$backup_path/sysctl_net.conf") dong"

    # Backup NRO Shield configs
    if [ -d "$CONFIG_DIR" ]; then
        cp -r "$CONFIG_DIR" "$backup_path/config"
        log "  Config dir: copied"
    fi

    # Backup firewall scripts
    local script_dir
    script_dir="$(dirname "$0")"
    if [ -d "$script_dir" ]; then
        cp "$script_dir"/*.sh "$backup_path/" 2>/dev/null
        log "  Scripts: copied"
    fi

    # Backup conntrack settings
    if [ -f /proc/sys/net/netfilter/nf_conntrack_max ]; then
        cat /proc/sys/net/netfilter/nf_conntrack_max > "$backup_path/conntrack_max"
    fi

    # Tao metadata
    cat > "$backup_path/metadata.json" << EOF
{
    "name": "$name",
    "created_at": "$(date -Iseconds)",
    "hostname": "$(hostname)",
    "kernel": "$(uname -r)",
    "iptables_rules": $(iptables -L -n 2>/dev/null | wc -l),
    "ipset_entries": $(ipset list 2>/dev/null | grep -c "^[0-9]" || echo 0),
    "version": "2.2"
}
EOF

    # Nen backup
    tar -czf "$BACKUP_DIR/${name}.tar.gz" -C "$BACKUP_DIR" "$name" 2>/dev/null
    rm -rf "$backup_path"

    log "=== Backup hoan tat: ${name}.tar.gz ==="
    echo "$BACKUP_DIR/${name}.tar.gz"
}

restore() {
    local backup_file="$1"
    if [ ! -f "$backup_file" ]; then
        # Thu tim trong backup dir
        backup_file="$BACKUP_DIR/${1}.tar.gz"
        if [ ! -f "$backup_file" ]; then
            log "ERROR: Backup khong ton tai: $1"
            exit 1
        fi
    fi

    log "=== Bat dau phuc hoi: $backup_file ==="

    local tmp_dir
    tmp_dir=$(mktemp -d)
    tar -xzf "$backup_file" -C "$tmp_dir" 2>/dev/null

    local restore_dir
    restore_dir=$(find "$tmp_dir" -maxdepth 1 -type d ! -name "$(basename "$tmp_dir")" | head -1)
    [ -z "$restore_dir" ] && restore_dir="$tmp_dir"

    # Phuc hoi iptables
    if [ -f "$restore_dir/iptables.rules" ]; then
        iptables-restore < "$restore_dir/iptables.rules"
        log "  iptables: restored"
    fi

    # Phuc hoi ip6tables
    if [ -f "$restore_dir/ip6tables.rules" ]; then
        ip6tables-restore < "$restore_dir/ip6tables.rules"
        log "  ip6tables: restored"
    fi

    # Phuc hoi ipset
    if [ -f "$restore_dir/ipset.save" ]; then
        ipset restore < "$restore_dir/ipset.save" 2>/dev/null
        log "  ipset: restored"
    fi

    # Phuc hoi sysctl
    if [ -f "$restore_dir/sysctl_net.conf" ]; then
        sysctl -p "$restore_dir/sysctl_net.conf" >/dev/null 2>&1
        log "  sysctl: restored"
    fi

    # Phuc hoi config
    if [ -d "$restore_dir/config" ]; then
        cp -r "$restore_dir/config"/* "$CONFIG_DIR/" 2>/dev/null
        log "  Config: restored"
    fi

    rm -rf "$tmp_dir"
    log "=== Phuc hoi hoan tat ==="
}

list_backups() {
    echo "=== Danh sach backup ==="
    if [ -d "$BACKUP_DIR" ]; then
        for f in "$BACKUP_DIR"/*.tar.gz; do
            [ -f "$f" ] || continue
            local name
            name=$(basename "$f" .tar.gz)
            local size
            size=$(du -h "$f" | cut -f1)
            local date
            date=$(stat -c %y "$f" 2>/dev/null | cut -d. -f1)
            echo "  $name ($size) - $date"
        done
    fi
}

auto_backup() {
    # Giu 7 backup gan nhat
    local max_backups=7
    local count
    count=$(find "$BACKUP_DIR" -name "*.tar.gz" -type f 2>/dev/null | wc -l)

    if [ "$count" -ge "$max_backups" ]; then
        find "$BACKUP_DIR" -name "*.tar.gz" -type f -printf '%T@ %p\n' | \
            sort -n | head -$((count - max_backups + 1)) | \
            cut -d' ' -f2- | while read -r old_file; do
                rm -f "$old_file"
                log "Auto-cleanup: removed $old_file"
            done
    fi

    backup "auto_$(date +%Y%m%d_%H%M%S)"
}

case "${1:-help}" in
    backup)
        backup "$2"
        ;;
    restore)
        restore "$2"
        ;;
    list)
        list_backups
        ;;
    auto)
        auto_backup
        ;;
    *)
        echo "Su dung: $0 {backup [name]|restore <name|path>|list|auto}"
        exit 1
        ;;
esac
