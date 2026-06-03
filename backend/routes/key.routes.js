const express = require('express');
const { v4: uuidv4 } = require('uuid');
const db = require('../config/database');
const { authenticate, requireAdmin } = require('../middleware/auth');

const router = express.Router();

// Tất cả routes cần admin
router.use(authenticate, requireAdmin);

// GET /api/keys — Danh sách tất cả keys
router.get('/', async (req, res) => {
    try {
        const [keys] = await db.query(`
      SELECT k.*, u.username as assigned_to, c.username as created_by_name
      FROM license_keys k
      LEFT JOIN users u ON k.user_id = u.id
      LEFT JOIN users c ON k.created_by = c.id
      ORDER BY k.created_at DESC
    `);
        res.json(keys);
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// POST /api/keys — Tạo key mới
router.post('/', async (req, res) => {
    try {
        const { max_servers, max_ports_per_server, max_bandwidth_mbps, expires_days } = req.body;

        const keyCode = 'NRO-' + uuidv4().replace(/-/g, '').substring(0, 24).toUpperCase();
        const expiresAt = expires_days
            ? new Date(Date.now() + expires_days * 86400000).toISOString().slice(0, 19).replace('T', ' ')
            : null;

        const [result] = await db.query(
            `INSERT INTO license_keys (key_code, max_servers, max_ports_per_server, max_bandwidth_mbps, expires_at, created_by)
       VALUES (?, ?, ?, ?, ?, ?)`,
            [keyCode, max_servers || 1, max_ports_per_server || 3, max_bandwidth_mbps || 100, expiresAt, req.user.id]
        );

        res.status(201).json({
            message: 'Tạo key thành công',
            key: {
                id: result.insertId,
                key_code: keyCode,
                max_servers: max_servers || 1,
                max_ports_per_server: max_ports_per_server || 3,
                expires_at: expiresAt
            }
        });
    } catch (err) {
        console.error('[KEY] Create error:', err);
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// PUT /api/keys/:id — Sửa key (gia hạn, giới hạn)
router.put('/:id', async (req, res) => {
    try {
        const { max_servers, max_ports_per_server, max_bandwidth_mbps, extends_days, status } = req.body;
        const fields = [];
        const values = [];

        if (max_servers !== undefined) { fields.push('max_servers = ?'); values.push(max_servers); }
        if (max_ports_per_server !== undefined) { fields.push('max_ports_per_server = ?'); values.push(max_ports_per_server); }
        if (max_bandwidth_mbps !== undefined) { fields.push('max_bandwidth_mbps = ?'); values.push(max_bandwidth_mbps); }
        if (status) { fields.push('status = ?'); values.push(status); }
        if (extends_days) {
            fields.push('expires_at = DATE_ADD(COALESCE(expires_at, NOW()), INTERVAL ? DAY)');
            values.push(extends_days);
        }

        if (!fields.length) return res.status(400).json({ error: 'Không có gì để cập nhật' });

        values.push(req.params.id);
        await db.query(`UPDATE license_keys SET ${fields.join(', ')} WHERE id = ?`, values);

        res.json({ message: 'Cập nhật key thành công' });
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// DELETE /api/keys/:id — Thu hồi key
router.delete('/:id', async (req, res) => {
    try {
        // Deactivate tất cả proxy ports của key này
        await db.query(`
      UPDATE proxy_ports pp
      JOIN servers s ON pp.server_id = s.id
      SET pp.is_active = FALSE
      WHERE s.key_id = ?
    `, [req.params.id]);

        await db.query('UPDATE license_keys SET status = "suspended" WHERE id = ?', [req.params.id]);
        res.json({ message: 'Key đã thu hồi' });
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

module.exports = router;
