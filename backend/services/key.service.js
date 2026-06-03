const db = require('../config/database');
const { removeNatRule } = require('./nat.service');

/**
 * Kiểm tra và xử lý key hết hạn
 * Chạy mỗi phút qua cron job
 */
async function checkExpiredKeys() {
    try {
        // Tìm key vừa hết hạn
        const [expired] = await db.query(`
      SELECT id, key_code, user_id FROM license_keys
      WHERE status = 'active' AND expires_at IS NOT NULL AND expires_at <= NOW()
    `);

        if (!expired.length) return;

        for (const key of expired) {
            console.log(`[KEY] Expired: ${key.key_code} (user_id: ${key.user_id})`);

            // Tắt tất cả proxy ports
            const [proxies] = await db.query(`
        SELECT pp.id, pp.proxy_port, pp.target_port, pp.protocol, s.target_ip
        FROM proxy_ports pp JOIN servers s ON pp.server_id = s.id
        WHERE s.key_id = ? AND pp.is_active = TRUE
      `, [key.id]);

            for (const proxy of proxies) {
                await removeNatRule(proxy.proxy_port, proxy.target_ip, proxy.target_port, proxy.protocol);
                await db.query('UPDATE proxy_ports SET is_active = FALSE WHERE id = ?', [proxy.id]);
            }

            // Cập nhật trạng thái key
            await db.query('UPDATE license_keys SET status = "expired" WHERE id = ?', [key.id]);
        }

        if (expired.length) {
            console.log(`[KEY] Processed ${expired.length} expired keys`);
        }
    } catch (err) {
        console.error('[KEY] Check expired error:', err.message);
    }
}

module.exports = { checkExpiredKeys };
