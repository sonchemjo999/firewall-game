const express = require('express');
const db = require('../config/database');
const { authenticate } = require('../middleware/auth');

const router = express.Router();
router.use(authenticate);

// GET /api/servers
router.get('/', async (req, res) => {
    try {
        const [servers] = await db.query(`
      SELECT s.*, k.key_code, k.max_ports_per_server,
        (SELECT COUNT(*) FROM proxy_ports pp WHERE pp.server_id = s.id) as port_count
      FROM servers s
      JOIN license_keys k ON s.key_id = k.id
      WHERE s.user_id = ?
      ORDER BY s.created_at DESC
    `, [req.user.id]);
        res.json(servers);
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// POST /api/servers
router.post('/', async (req, res) => {
    try {
        const { name, target_ip, game_type } = req.body;

        if (!target_ip) return res.status(400).json({ error: 'Cần target_ip' });

        // Validate IP format
        const ipRegex = /^(\d{1,3}\.){3}\d{1,3}$/;
        if (!ipRegex.test(target_ip)) return res.status(400).json({ error: 'IP không hợp lệ' });

        // Validate game_type nếu có
        if (game_type) {
            const [games] = await db.query('SELECT code FROM game_types WHERE code = ? AND is_active = TRUE', [game_type]);
            if (!games.length) return res.status(400).json({ error: 'Game type không hợp lệ' });
        }

        // Lấy key của user
        const [keys] = await db.query(
            'SELECT * FROM license_keys WHERE user_id = ? AND status = "active"', [req.user.id]
        );
        if (!keys.length) return res.status(400).json({ error: 'Không có key active' });

        const key = keys[0];

        // Kiểm tra quota server (ưu tiên plan nếu có)
        const maxServers = req.user.plan_max_servers || key.max_servers;
        const [count] = await db.query(
            'SELECT COUNT(*) as c FROM servers WHERE key_id = ?', [key.id]
        );
        if (count[0].c >= maxServers) {
            return res.status(400).json({ error: `Đã đạt giới hạn ${maxServers} server` });
        }

        const [result] = await db.query(
            'INSERT INTO servers (user_id, key_id, name, target_ip, game_type) VALUES (?, ?, ?, ?, ?)',
            [req.user.id, key.id, name || 'My Server', target_ip, game_type || 'nro']
        );

        res.status(201).json({
            message: 'Server đã thêm',
            server: { id: result.insertId, name: name || 'My Server', target_ip, game_type: game_type || 'nro' }
        });
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// DELETE /api/servers/:id
router.delete('/:id', async (req, res) => {
    try {
        const [result] = await db.query(
            'DELETE FROM servers WHERE id = ? AND user_id = ?', [req.params.id, req.user.id]
        );
        if (!result.affectedRows) return res.status(404).json({ error: 'Server không tồn tại' });
        res.json({ message: 'Server đã xóa' });
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

module.exports = router;
