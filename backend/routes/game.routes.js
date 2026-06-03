const express = require('express');
const db = require('../config/database');
const { authenticate, requireAdmin } = require('../middleware/auth');

const router = express.Router();

// GET /api/games — Danh sách game types (public)
router.get('/', async (req, res) => {
    try {
        const [games] = await db.query(
            'SELECT * FROM game_types WHERE is_active = TRUE ORDER BY name ASC'
        );
        res.json(games);
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// GET /api/games/:code — Chi tiết game type
router.get('/:code', async (req, res) => {
    try {
        const [games] = await db.query('SELECT * FROM game_types WHERE code = ?', [req.params.code]);
        if (!games.length) return res.status(404).json({ error: 'Game type không tồn tại' });
        res.json(games[0]);
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// POST /api/games — Thêm game type mới (admin)
router.post('/', authenticate, requireAdmin, async (req, res) => {
    try {
        const { code, name, protocol, default_ports, max_packet_size, min_packet_size,
            udp_rate_limit, tcp_rate_limit, max_conn_per_ip, icon, description, firewall_profile } = req.body;

        if (!code || !name) return res.status(400).json({ error: 'Cần code và name' });

        const [result] = await db.query(
            `INSERT INTO game_types (code, name, protocol, default_ports, max_packet_size,
                min_packet_size, udp_rate_limit, tcp_rate_limit, max_conn_per_ip, icon, description, firewall_profile)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [code, name, protocol || 'tcp', default_ports || '', max_packet_size || 4096,
                min_packet_size || 28, udp_rate_limit || '500/sec', tcp_rate_limit || '200/sec',
                max_conn_per_ip || 50, icon || null, description || null,
                firewall_profile ? JSON.stringify(firewall_profile) : null]
        );

        res.status(201).json({ message: 'Game type đã thêm', id: result.insertId });
    } catch (err) {
        if (err.code === 'ER_DUP_ENTRY') {
            return res.status(400).json({ error: 'Game code đã tồn tại' });
        }
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// PUT /api/games/:id — Sửa game type (admin)
router.put('/:id', authenticate, requireAdmin, async (req, res) => {
    try {
        const fields = [];
        const values = [];
        const allowed = ['name', 'protocol', 'default_ports', 'max_packet_size', 'min_packet_size',
            'udp_rate_limit', 'tcp_rate_limit', 'max_conn_per_ip', 'icon', 'description', 'is_active'];

        for (const key of allowed) {
            if (req.body[key] !== undefined) {
                fields.push(`${key} = ?`);
                values.push(req.body[key]);
            }
        }

        if (req.body.firewall_profile) {
            fields.push('firewall_profile = ?');
            values.push(JSON.stringify(req.body.firewall_profile));
        }

        if (!fields.length) return res.status(400).json({ error: 'Không có gì để cập nhật' });

        values.push(req.params.id);
        await db.query(`UPDATE game_types SET ${fields.join(', ')} WHERE id = ?`, values);

        res.json({ message: 'Game type đã cập nhật' });
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// DELETE /api/games/:id — Xóa game type (admin)
router.delete('/:id', authenticate, requireAdmin, async (req, res) => {
    try {
        await db.query('UPDATE game_types SET is_active = FALSE WHERE id = ?', [req.params.id]);
        res.json({ message: 'Game type đã ẩn' });
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

module.exports = router;
