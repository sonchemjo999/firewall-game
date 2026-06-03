const express = require('express');
const db = require('../config/database');
const config = require('../config/config');
const { authenticate } = require('../middleware/auth');
const { addNatRule, removeNatRule } = require('../services/nat.service');

const router = express.Router();
router.use(authenticate);

// Tìm port trống ngẫu nhiên
async function findAvailablePort() {
    const { PROXY_PORT_RANGE_START, PROXY_PORT_RANGE_END } = config;
    const [used] = await db.query('SELECT proxy_port FROM proxy_ports');
    const usedPorts = new Set(used.map(r => r.proxy_port));

    for (let i = 0; i < 1000; i++) {
        const port = Math.floor(Math.random() * (PROXY_PORT_RANGE_END - PROXY_PORT_RANGE_START) + PROXY_PORT_RANGE_START);
        if (!usedPorts.has(port)) return port;
    }
    return null;
}

// GET /api/proxy — Danh sách proxy của user
router.get('/', async (req, res) => {
    try {
        const [proxies] = await db.query(`
      SELECT pp.*, s.name as server_name, s.target_ip
      FROM proxy_ports pp
      JOIN servers s ON pp.server_id = s.id
      WHERE s.user_id = ?
      ORDER BY pp.created_at DESC
    `, [req.user.id]);

        res.json(proxies.map(p => ({
            ...p,
            proxy_address: `${config.VPS_PUBLIC_IP}:${p.proxy_port}`,
            target_address: `${p.target_ip}:${p.target_port}`
        })));
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// POST /api/proxy/create — Tạo proxy mới
router.post('/create', async (req, res) => {
    try {
        const { server_id, target_port, protocol, custom_port } = req.body;

        if (!server_id || !target_port) {
            return res.status(400).json({ error: 'Cần server_id và target_port' });
        }

        // Validate target_port
        if (target_port < 1 || target_port > 65535) {
            return res.status(400).json({ error: 'target_port phải từ 1-65535' });
        }

        // Kiểm tra server thuộc user
        const [servers] = await db.query(
            'SELECT s.*, k.max_ports_per_server FROM servers s JOIN license_keys k ON s.key_id = k.id WHERE s.id = ? AND s.user_id = ?',
            [server_id, req.user.id]
        );
        if (!servers.length) return res.status(404).json({ error: 'Server không tồn tại' });

        // Kiểm tra quota
        const [existingPorts] = await db.query(
            'SELECT COUNT(*) as count FROM proxy_ports WHERE server_id = ?', [server_id]
        );
        if (existingPorts[0].count >= servers[0].max_ports_per_server) {
            return res.status(400).json({ error: `Đã đạt giới hạn ${servers[0].max_ports_per_server} port/server` });
        }

        // Tìm hoặc dùng port tùy chỉnh
        let proxyPort = custom_port || await findAvailablePort();
        if (!proxyPort) return res.status(500).json({ error: 'Không tìm được port trống' });

        // Validate custom port
        if (custom_port && (custom_port < config.PROXY_PORT_RANGE_START || custom_port > config.PROXY_PORT_RANGE_END)) {
            return res.status(400).json({ error: `Port phải trong khoảng ${config.PROXY_PORT_RANGE_START}-${config.PROXY_PORT_RANGE_END}` });
        }

        // Tạo NAT rule
        const natResult = await addNatRule(proxyPort, servers[0].target_ip, target_port, protocol || 'tcp');
        if (!natResult.success) {
            return res.status(500).json({ error: 'Không thể tạo NAT rule: ' + natResult.error });
        }

        // Lưu DB
        const [result] = await db.query(
            'INSERT INTO proxy_ports (server_id, proxy_port, target_port, protocol) VALUES (?, ?, ?, ?)',
            [server_id, proxyPort, target_port, protocol || 'tcp']
        );

        res.status(201).json({
            message: 'Proxy đã tạo',
            proxy: {
                id: result.insertId,
                proxy_address: `${config.VPS_PUBLIC_IP}:${proxyPort}`,
                target_address: `${servers[0].target_ip}:${target_port}`,
                protocol: protocol || 'tcp'
            }
        });
    } catch (err) {
        console.error('[PROXY] Create error:', err);
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// PUT /api/proxy/:id/toggle — Bật/tắt proxy
router.put('/:id/toggle', async (req, res) => {
    try {
        const [proxies] = await db.query(`
      SELECT pp.*, s.target_ip FROM proxy_ports pp
      JOIN servers s ON pp.server_id = s.id
      WHERE pp.id = ? AND s.user_id = ?
    `, [req.params.id, req.user.id]);

        if (!proxies.length) return res.status(404).json({ error: 'Proxy không tồn tại' });

        const proxy = proxies[0];
        const newStatus = !proxy.is_active;

        if (newStatus) {
            await addNatRule(proxy.proxy_port, proxy.target_ip, proxy.target_port, proxy.protocol);
        } else {
            await removeNatRule(proxy.proxy_port, proxy.target_ip, proxy.target_port, proxy.protocol);
        }

        await db.query('UPDATE proxy_ports SET is_active = ? WHERE id = ?', [newStatus, req.params.id]);

        res.json({ message: newStatus ? 'Proxy đã bật' : 'Proxy đã tắt', is_active: newStatus });
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// DELETE /api/proxy/:id
router.delete('/:id', async (req, res) => {
    try {
        const [proxies] = await db.query(`
      SELECT pp.*, s.target_ip FROM proxy_ports pp
      JOIN servers s ON pp.server_id = s.id
      WHERE pp.id = ? AND s.user_id = ?
    `, [req.params.id, req.user.id]);

        if (!proxies.length) return res.status(404).json({ error: 'Proxy không tồn tại' });

        await removeNatRule(proxies[0].proxy_port, proxies[0].target_ip, proxies[0].target_port, proxies[0].protocol);
        await db.query('DELETE FROM proxy_ports WHERE id = ?', [req.params.id]);

        res.json({ message: 'Proxy đã xóa' });
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

module.exports = router;
