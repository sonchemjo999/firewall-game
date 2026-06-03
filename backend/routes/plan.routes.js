const express = require('express');
const db = require('../config/database');
const { authenticate, requireAdmin } = require('../middleware/auth');

const router = express.Router();

// GET /api/plans — Danh sách gói dịch vụ (public)
router.get('/', async (req, res) => {
    try {
        const [plans] = await db.query(
            'SELECT * FROM plans WHERE is_active = TRUE ORDER BY sort_order ASC'
        );
        res.json(plans);
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// GET /api/plans/:id — Chi tiết gói
router.get('/:id', async (req, res) => {
    try {
        const [plans] = await db.query('SELECT * FROM plans WHERE id = ?', [req.params.id]);
        if (!plans.length) return res.status(404).json({ error: 'Gói không tồn tại' });
        res.json(plans[0]);
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// POST /api/plans — Tạo gói mới (admin)
router.post('/', authenticate, requireAdmin, async (req, res) => {
    try {
        const { name, slug, description, max_servers, max_ports_per_server, max_bandwidth_mbps,
            allowed_games, allowed_protocols, enable_ai_protection, enable_advanced_firewall,
            enable_geoblock, enable_custom_rules, price_monthly, price_yearly, sort_order } = req.body;

        if (!name || !slug) return res.status(400).json({ error: 'Cần name và slug' });

        const [result] = await db.query(
            `INSERT INTO plans (name, slug, description, max_servers, max_ports_per_server,
                max_bandwidth_mbps, allowed_games, allowed_protocols, enable_ai_protection,
                enable_advanced_firewall, enable_geoblock, enable_custom_rules,
                price_monthly, price_yearly, sort_order)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [name, slug, description || '', max_servers || 1, max_ports_per_server || 3,
                max_bandwidth_mbps || 100,
                allowed_games ? JSON.stringify(allowed_games) : null,
                allowed_protocols ? JSON.stringify(allowed_protocols) : '["tcp","udp"]',
                enable_ai_protection || false, enable_advanced_firewall || false,
                enable_geoblock || false, enable_custom_rules || false,
                price_monthly || 0, price_yearly || 0, sort_order || 0]
        );

        res.status(201).json({ message: 'Gói đã tạo', id: result.insertId });
    } catch (err) {
        if (err.code === 'ER_DUP_ENTRY') {
            return res.status(400).json({ error: 'Slug đã tồn tại' });
        }
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// PUT /api/plans/:id — Sửa gói (admin)
router.put('/:id', authenticate, requireAdmin, async (req, res) => {
    try {
        const fields = [];
        const values = [];
        const allowed = ['name', 'description', 'max_servers', 'max_ports_per_server',
            'max_bandwidth_mbps', 'enable_ai_protection', 'enable_advanced_firewall',
            'enable_geoblock', 'enable_custom_rules', 'price_monthly', 'price_yearly',
            'sort_order', 'is_active'];

        for (const key of allowed) {
            if (req.body[key] !== undefined) {
                fields.push(`${key} = ?`);
                values.push(req.body[key]);
            }
        }

        if (req.body.allowed_games !== undefined) {
            fields.push('allowed_games = ?');
            values.push(JSON.stringify(req.body.allowed_games));
        }
        if (req.body.allowed_protocols !== undefined) {
            fields.push('allowed_protocols = ?');
            values.push(JSON.stringify(req.body.allowed_protocols));
        }

        if (!fields.length) return res.status(400).json({ error: 'Không có gì để cập nhật' });

        values.push(req.params.id);
        await db.query(`UPDATE plans SET ${fields.join(', ')} WHERE id = ?`, values);

        res.json({ message: 'Gói đã cập nhật' });
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// DELETE /api/plans/:id — Xóa gói (admin, soft delete)
router.delete('/:id', authenticate, requireAdmin, async (req, res) => {
    try {
        await db.query('UPDATE plans SET is_active = FALSE WHERE id = ?', [req.params.id]);
        res.json({ message: 'Gói đã ẩn' });
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

module.exports = router;
