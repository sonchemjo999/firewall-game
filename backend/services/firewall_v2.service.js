const db = require('../config/database');
const { addNatRule, removeNatRule } = require('./nat.service');
const { exec } = require('child_process');
const util = require('util');
const execAsync = util.promisify(exec);

/**
 * Đồng bộ firewall rules từ DB — V2 với game-specific rules
 */
async function syncFirewallRules() {
    const startTime = Date.now();
    let synced = 0;
    let failed = 0;
    const errors = [];

    try {
        // 1. Sync NAT rules (giữ nguyên logic cũ)
        const [proxies] = await db.query(`
            SELECT pp.proxy_port, pp.target_port, pp.protocol, pp.is_active,
                   pp.game_type, s.target_ip
            FROM proxy_ports pp
            JOIN servers s ON pp.server_id = s.id
            WHERE pp.is_active = TRUE
        `);

        console.log(`[FIREWALL V2] Syncing ${proxies.length} active proxy rules...`);

        for (const proxy of proxies) {
            try {
                await addNatRule(proxy.proxy_port, proxy.target_ip, proxy.target_port, proxy.protocol);
                synced++;
            } catch (err) {
                failed++;
                errors.push(`NAT ${proxy.proxy_port}: ${err.message}`);
            }
        }

        // 2. Sync custom firewall rules
        const [rules] = await db.query(`
            SELECT fr.*, pp.proxy_port, s.target_ip
            FROM firewall_rules fr
            LEFT JOIN proxy_ports pp ON fr.proxy_port_id = pp.id
            LEFT JOIN servers s ON fr.server_id = s.id
            WHERE fr.is_active = TRUE
            ORDER BY fr.priority ASC
        `);

        for (const rule of rules) {
            try {
                await applyFirewallRule(rule);
                await db.query('UPDATE firewall_rules SET applied = TRUE WHERE id = ?', [rule.id]);
                synced++;
            } catch (err) {
                failed++;
                errors.push(`Rule ${rule.id} (${rule.name}): ${err.message}`);
            }
        }

        // 3. Apply game-specific rules
        for (const proxy of proxies) {
            if (proxy.game_type) {
                try {
                    await applyGameRules(proxy.game_type, proxy.proxy_port);
                    synced++;
                } catch (err) {
                    failed++;
                    errors.push(`Game ${proxy.game_type}:${proxy.proxy_port}: ${err.message}`);
                }
            }
        }

        const duration = Date.now() - startTime;

        // Log sync result
        await db.query(
            `INSERT INTO rule_sync_log (sync_type, rules_synced, rules_failed, duration_ms, error_log) VALUES (?, ?, ?, ?, ?)`,
            ['full', synced, failed, duration, errors.length ? JSON.stringify(errors) : null]
        ).catch(() => {});

        console.log(`[FIREWALL V2] Sync complete: ${synced} synced, ${failed} failed (${duration}ms)`);

        return { synced, failed, duration, errors };
    } catch (err) {
        console.error('[FIREWALL V2] Sync error:', err.message);
        return { synced, failed, duration: Date.now() - startTime, errors: [err.message] };
    }
}

/**
 * Validate input to prevent command injection
 */
function sanitizeInput(value, type) {
    if (value == null) return null;
    const str = String(value);
    const shellMeta = /[;&|`$(){}[\]<>!\n\r\\]/;
    if (shellMeta.test(str)) return null;

    switch (type) {
        case 'ip':
            if (!/^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}(\/[0-9]{1,2})?$/.test(str)) return null;
            return str;
        case 'port':
            if (!/^[0-9]{1,5}(:[0-9]{1,5})?$/.test(str)) return null;
            return str;
        case 'protocol':
            if (!['tcp', 'udp', 'icmp', 'all'].includes(str.toLowerCase())) return null;
            return str.toLowerCase();
        case 'rate':
            if (!/^[0-9]+\/(sec|min|hour)$/.test(str)) return null;
            return str;
        case 'number':
            if (!/^[0-9]+$/.test(str)) return null;
            return str;
        default:
            return str;
    }
}

/**
 * Áp dụng một firewall rule cụ thể
 */
async function applyFirewallRule(rule) {
    const safeProto = sanitizeInput(rule.protocol, 'protocol') || 'all';
    const proto = safeProto === 'all' ? '' : `-p ${safeProto}`;
    let cmd = '';

    switch (rule.rule_type) {
        case 'rate_limit': {
            const safeRate = sanitizeInput(rule.rate_limit, 'rate');
            if (safeRate) {
                const safePort = sanitizeInput(rule.dest_port, 'port');
                const safeBurst = sanitizeInput(rule.rate_burst, 'number') || '50';
                const port = safePort ? `--dport ${safePort}` : '';
                cmd = `iptables -A FORWARD ${proto} ${port} -m hashlimit ` +
                    `--hashlimit-above ${safeRate} ` +
                    `--hashlimit-burst ${safeBurst} ` +
                    `--hashlimit-mode srcip ` +
                    `--hashlimit-name rule_${rule.id} -j DROP 2>/dev/null || true`;
            }
            break;
        }

        case 'block': {
            const safeIp = sanitizeInput(rule.source_ip, 'ip');
            if (safeIp) {
                cmd = `ipset add nroshield-blacklist ${safeIp} 2>/dev/null || true`;
            }
            break;
        }

        case 'allow': {
            const safeIp = sanitizeInput(rule.source_ip, 'ip');
            if (safeIp) {
                cmd = `ipset add nroshield-whitelist ${safeIp} 2>/dev/null || true`;
            }
            break;
        }

        case 'geo_block':
            break;

        default:
            break;
    }

    if (cmd) {
        await execAsync(cmd);
    }
}

/**
 * Áp dụng game-specific firewall rules
 */
async function applyGameRules(gameType, proxyPort) {
    const scriptPath = '/opt/nroshield/firewall/multi_game_support.sh';
    try {
        await execAsync(`bash ${scriptPath} apply ${gameType} ${proxyPort} 2>/dev/null || true`);
    } catch (err) {
        // Script may not exist on dev machines
        console.log(`[FIREWALL V2] Game rules script not found, skipping: ${gameType}`);
    }
}

/**
 * Thêm custom firewall rule
 */
async function addCustomRule(ruleData) {
    if (ruleData.source_ip && !sanitizeInput(ruleData.source_ip, 'ip')) {
        throw new Error('Invalid source_ip format');
    }
    if (ruleData.dest_port && !sanitizeInput(String(ruleData.dest_port), 'port')) {
        throw new Error('Invalid dest_port format');
    }
    if (ruleData.protocol && !sanitizeInput(ruleData.protocol, 'protocol')) {
        throw new Error('Invalid protocol (must be tcp/udp/icmp/all)');
    }
    if (ruleData.rate_limit && !sanitizeInput(ruleData.rate_limit, 'rate')) {
        throw new Error('Invalid rate_limit format (e.g. 100/sec)');
    }
    if (ruleData.rate_burst && !sanitizeInput(String(ruleData.rate_burst), 'number')) {
        throw new Error('Invalid rate_burst (must be a number)');
    }

    const [result] = await db.query(
        `INSERT INTO firewall_rules (name, rule_type, priority, protocol, source_ip, source_port,
            dest_port, action, rate_limit, rate_burst, conditions, is_global, server_id,
            proxy_port_id, created_by)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
            ruleData.name, ruleData.rule_type, ruleData.priority || 100,
            ruleData.protocol || 'all', ruleData.source_ip || null,
            ruleData.source_port || null, ruleData.dest_port || null,
            ruleData.action || 'drop', ruleData.rate_limit || null,
            ruleData.rate_burst || null, JSON.stringify(ruleData.conditions || {}),
            ruleData.is_global || false, ruleData.server_id || null,
            ruleData.proxy_port_id || null, ruleData.created_by
        ]
    );

    // Apply immediately
    const [rules] = await db.query('SELECT * FROM firewall_rules WHERE id = ?', [result.insertId]);
    if (rules.length) {
        await applyFirewallRule(rules[0]);
        await db.query('UPDATE firewall_rules SET applied = TRUE WHERE id = ?', [result.insertId]);
    }

    return { id: result.insertId };
}

/**
 * Xóa custom firewall rule
 */
async function removeCustomRule(ruleId) {
    const [rules] = await db.query('SELECT * FROM firewall_rules WHERE id = ?', [ruleId]);
    if (!rules.length) return { success: false, error: 'Rule không tồn tại' };

    // Remove from iptables if it was applied
    if (rules[0].applied && rules[0].source_ip) {
        const safeIp = sanitizeInput(rules[0].source_ip, 'ip');
        if (safeIp) {
            if (rules[0].rule_type === 'block') {
                await execAsync(`ipset del nroshield-blacklist ${safeIp} 2>/dev/null || true`);
            } else if (rules[0].rule_type === 'allow') {
                await execAsync(`ipset del nroshield-whitelist ${safeIp} 2>/dev/null || true`);
            }
        }
    }

    await db.query('DELETE FROM firewall_rules WHERE id = ?', [ruleId]);
    return { success: true };
}

/**
 * Lấy trạng thái đồng bộ gần nhất
 */
async function getLastSyncStatus() {
    const [rows] = await db.query('SELECT * FROM rule_sync_log ORDER BY synced_at DESC LIMIT 1');
    return rows[0] || null;
}

module.exports = {
    syncFirewallRules,
    applyFirewallRule,
    applyGameRules,
    addCustomRule,
    removeCustomRule,
    getLastSyncStatus
};
