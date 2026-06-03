const db = require('../config/database');
const { addNatRule, removeNatRule } = require('./nat.service');

/**
 * Đồng bộ firewall rules từ DB
 * Đảm bảo tất cả active proxy ports có NAT rule đúng
 */
async function syncFirewallRules() {
    try {
        const [proxies] = await db.query(`
      SELECT pp.proxy_port, pp.target_port, pp.protocol, pp.is_active, s.target_ip
      FROM proxy_ports pp
      JOIN servers s ON pp.server_id = s.id
      WHERE pp.is_active = TRUE
    `);

        console.log(`[FIREWALL] Syncing ${proxies.length} active proxy rules...`);

        for (const proxy of proxies) {
            await addNatRule(proxy.proxy_port, proxy.target_ip, proxy.target_port, proxy.protocol);
        }

        console.log(`[FIREWALL] Sync complete: ${proxies.length} rules`);
    } catch (err) {
        console.error('[FIREWALL] Sync error:', err.message);
    }
}

module.exports = { syncFirewallRules };
