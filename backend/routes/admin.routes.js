const express = require('express');
const db = require('../config/database');
const { authenticate, requireAdmin, auditLog } = require('../middleware/auth');
const { exec } = require('child_process');
const util = require('util');
const execAsync = util.promisify(exec);

const router = express.Router();
router.use(authenticate, requireAdmin);

// GET /api/admin/users — Danh sách users (đầy đủ thông tin)
router.get('/users', async (req, res) => {
    try {
        const { search, role, status, page = 1, limit = 50 } = req.query;
        let query = `
            SELECT u.id, u.username, u.email, u.role, u.telegram_id, u.is_active, u.plan_id, u.created_at,
                p.name as plan_name, p.slug as plan_slug,
                (SELECT COUNT(*) FROM servers s WHERE s.user_id = u.id) as server_count,
                (SELECT COUNT(*) FROM proxy_ports pp JOIN servers s2 ON pp.server_id = s2.id WHERE s2.user_id = u.id AND pp.is_active = TRUE) as active_port_count,
                (SELECT k.key_code FROM license_keys k WHERE k.user_id = u.id AND k.status = 'active' LIMIT 1) as active_key,
                (SELECT k.expires_at FROM license_keys k WHERE k.user_id = u.id AND k.status = 'active' LIMIT 1) as key_expires_at
            FROM users u
            LEFT JOIN plans p ON u.plan_id = p.id
            WHERE 1=1
        `;
        const params = [];

        if (search) {
            query += ' AND (u.username LIKE ? OR u.email LIKE ?)';
            params.push(`%${search}%`, `%${search}%`);
        }
        if (role) {
            query += ' AND u.role = ?';
            params.push(role);
        }
        if (status === 'active') {
            query += ' AND u.is_active = TRUE';
        } else if (status === 'inactive') {
            query += ' AND u.is_active = FALSE';
        }

        query += ' ORDER BY u.created_at DESC LIMIT ? OFFSET ?';
        params.push(parseInt(limit), (parseInt(page) - 1) * parseInt(limit));

        const [users] = await db.query(query, params);

        // Total count with same filters
        let countQuery = 'SELECT COUNT(*) as total FROM users u WHERE 1=1';
        const countParams = [];
        if (search) {
            countQuery += ' AND (u.username LIKE ? OR u.email LIKE ?)';
            countParams.push(`%${search}%`, `%${search}%`);
        }
        if (role) {
            countQuery += ' AND u.role = ?';
            countParams.push(role);
        }
        if (status === 'active') {
            countQuery += ' AND u.is_active = TRUE';
        } else if (status === 'inactive') {
            countQuery += ' AND u.is_active = FALSE';
        }
        const [[{ total }]] = await db.query(countQuery, countParams);

        res.json({ users, total, page: parseInt(page), limit: parseInt(limit) });
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// PUT /api/admin/users/:id/role — Cấp quyền (mở rộng roles)
router.put('/users/:id/role', auditLog('change_role', 'user'), async (req, res) => {
    try {
        const { role } = req.body;
        const validRoles = ['admin', 'reseller', 'premium', 'basic'];
        if (!validRoles.includes(role)) {
            return res.status(400).json({ error: `Role phải là: ${validRoles.join(', ')}` });
        }
        await db.query('UPDATE users SET role = ? WHERE id = ?', [role, req.params.id]);
        res.json({ message: 'Cập nhật quyền thành công' });
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// PUT /api/admin/users/:id/plan — Gán gói dịch vụ cho user
router.put('/users/:id/plan', auditLog('change_plan', 'user'), async (req, res) => {
    try {
        const { plan_id } = req.body;
        if (plan_id) {
            const [plans] = await db.query('SELECT * FROM plans WHERE id = ? AND is_active = TRUE', [plan_id]);
            if (!plans.length) return res.status(404).json({ error: 'Gói không tồn tại' });
        }
        await db.query('UPDATE users SET plan_id = ? WHERE id = ?', [plan_id || null, req.params.id]);
        res.json({ message: 'Cập nhật gói thành công' });
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// PUT /api/admin/users/:id/toggle — Khóa/mở user
router.put('/users/:id/toggle', auditLog('toggle_user', 'user'), async (req, res) => {
    try {
        await db.query('UPDATE users SET is_active = NOT is_active WHERE id = ?', [req.params.id]);
        const [[user]] = await db.query('SELECT is_active FROM users WHERE id = ?', [req.params.id]);
        res.json({ message: 'Cập nhật trạng thái thành công', is_active: user.is_active });
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// DELETE /api/admin/users/:id — Xóa user (admin)
router.delete('/users/:id', auditLog('delete_user', 'user'), async (req, res) => {
    try {
        if (parseInt(req.params.id) === req.user.id) {
            return res.status(400).json({ error: 'Không thể xóa chính mình' });
        }
        await db.query('DELETE FROM users WHERE id = ?', [req.params.id]);
        res.json({ message: 'User đã xóa' });
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// GET /api/admin/stats — Thống kê hệ thống (mở rộng)
router.get('/stats', async (req, res) => {
    try {
        const [[{ total_users }]] = await db.query('SELECT COUNT(*) as total_users FROM users');
        const [[{ active_users }]] = await db.query('SELECT COUNT(*) as active_users FROM users WHERE is_active = TRUE');
        const [[{ active_keys }]] = await db.query('SELECT COUNT(*) as active_keys FROM license_keys WHERE status = "active"');
        const [[{ total_proxies }]] = await db.query('SELECT COUNT(*) as total_proxies FROM proxy_ports WHERE is_active = TRUE');
        const [[{ attacks_today }]] = await db.query('SELECT COUNT(*) as attacks_today FROM attack_logs WHERE started_at >= CURDATE()');
        const [[{ attacks_week }]] = await db.query('SELECT COUNT(*) as attacks_week FROM attack_logs WHERE started_at >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)');
        const [[{ total_servers }]] = await db.query('SELECT COUNT(*) as total_servers FROM servers');
        const [[{ ai_detections_24h }]] = await db.query('SELECT COUNT(*) as ai_detections_24h FROM ai_detections WHERE detected_at >= DATE_SUB(NOW(), INTERVAL 24 HOUR)');

        // Users by role
        const [usersByRole] = await db.query('SELECT role, COUNT(*) as count FROM users GROUP BY role');

        // Users by plan
        const [usersByPlan] = await db.query(`
            SELECT COALESCE(p.name, 'Không có gói') as plan_name, COUNT(*) as count
            FROM users u LEFT JOIN plans p ON u.plan_id = p.id
            GROUP BY p.name
        `);

        // Recent attacks (7 ngày)
        const [attacksByDay] = await db.query(`
            SELECT DATE(started_at) as date, COUNT(*) as count
            FROM attack_logs WHERE started_at >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
            GROUP BY DATE(started_at) ORDER BY date ASC
        `);

        // System stats
        let system = {};
        try {
            const { stdout: uptime } = await execAsync('uptime -p');
            const { stdout: loadavg } = await execAsync('cat /proc/loadavg');
            const { stdout: meminfo } = await execAsync("free -m | awk 'NR==2{printf \"%d/%dMB (%.1f%%)\", $3,$2,$3*100/$2 }'");
            const { stdout: conntrack } = await execAsync('cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo 0');
            const { stdout: conntrackMax } = await execAsync('cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo 0');
            const { stdout: diskInfo } = await execAsync("df -h / | awk 'NR==2{printf \"%s/%s (%s)\", $3,$2,$5}'");

            system = {
                uptime: uptime.trim(),
                load: loadavg.trim().split(' ').slice(0, 3).join(' '),
                memory: meminfo.trim(),
                disk: diskInfo.trim(),
                conntrack: `${conntrack.trim()}/${conntrackMax.trim()}`
            };
        } catch (e) {
            system = { error: 'Cannot get system stats' };
        }

        // Last sync status
        let lastSync = null;
        try {
            const [syncRows] = await db.query('SELECT * FROM rule_sync_log ORDER BY synced_at DESC LIMIT 1');
            lastSync = syncRows[0] || null;
        } catch (e) {
            // Table may not exist yet
        }

        res.json({
            total_users, active_users, active_keys, total_proxies, total_servers,
            attacks_today, attacks_week, ai_detections_24h,
            users_by_role: usersByRole,
            users_by_plan: usersByPlan,
            attacks_by_day: attacksByDay,
            system,
            last_sync: lastSync
        });
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// POST /api/admin/firewall/reload — Reload firewall (dùng V2 service)
router.post('/firewall/reload', auditLog('reload_firewall', 'firewall'), async (req, res) => {
    try {
        const { syncFirewallRules } = require('../services/firewall_v2.service');
        const result = await syncFirewallRules();
        res.json({ message: 'Firewall rules đã reload', ...result });
    } catch (err) {
        res.status(500).json({ error: 'Lỗi reload firewall' });
    }
});

// GET /api/admin/servers — Tất cả servers (admin) — mở rộng
router.get('/servers', async (req, res) => {
    try {
        const [servers] = await db.query(`
            SELECT s.*, s.game_type, u.username as owner, u.role as owner_role, k.key_code, k.status as key_status,
                gt.name as game_name,
                (SELECT COUNT(*) FROM proxy_ports pp WHERE pp.server_id = s.id) as port_count,
                (SELECT COUNT(*) FROM proxy_ports pp WHERE pp.server_id = s.id AND pp.is_active = TRUE) as active_port_count
            FROM servers s
            JOIN users u ON s.user_id = u.id
            JOIN license_keys k ON s.key_id = k.id
            LEFT JOIN game_types gt ON s.game_type = gt.code
            ORDER BY s.created_at DESC
        `);
        res.json(servers);
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// GET /api/admin/proxies — Tất cả proxies (admin) — mở rộng
router.get('/proxies', async (req, res) => {
    try {
        const config = require('../config/config');
        const [proxies] = await db.query(`
            SELECT pp.*, pp.game_type, s.name as server_name, s.target_ip, u.username as owner,
                gt.name as game_name
            FROM proxy_ports pp
            JOIN servers s ON pp.server_id = s.id
            JOIN users u ON s.user_id = u.id
            LEFT JOIN game_types gt ON pp.game_type = gt.code
            ORDER BY pp.created_at DESC
        `);
        res.json(proxies.map(p => ({
            ...p,
            proxy_address: `${config.VPS_PUBLIC_IP}:${p.proxy_port}`,
            target_address: `${p.target_ip}:${p.target_port}`
        })));
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// GET /api/admin/audit-logs — Lịch sử hành động
router.get('/audit-logs', async (req, res) => {
    try {
        const { limit = 100, user_id, action } = req.query;
        let query = `
            SELECT al.*, u.username
            FROM audit_logs al
            LEFT JOIN users u ON al.user_id = u.id
            WHERE 1=1
        `;
        const params = [];

        if (user_id) {
            query += ' AND al.user_id = ?';
            params.push(user_id);
        }
        if (action) {
            query += ' AND al.action = ?';
            params.push(action);
        }

        query += ' ORDER BY al.created_at DESC LIMIT ?';
        params.push(parseInt(limit));

        const [logs] = await db.query(query, params);
        res.json(logs);
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// POST /api/admin/broadcast — Gửi thông báo cho tất cả users
router.post('/broadcast', auditLog('broadcast_notification', 'notification'), async (req, res) => {
    try {
        const { title, message, type } = req.body;
        if (!title || !message) return res.status(400).json({ error: 'Cần title và message' });

        const { broadcastNotification } = require('../services/notification.service');
        await broadcastNotification(title, message, type || 'info');

        // WebSocket broadcast
        const broadcast = req.app.get('broadcast');
        if (broadcast) {
            broadcast({ type: 'NOTIFICATION', data: { title, message, notif_type: type || 'info' } });
        }

        res.json({ message: 'Đã gửi thông báo' });
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

module.exports = router;
