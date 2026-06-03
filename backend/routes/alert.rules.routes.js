const express = require('express');
const db = require('../config/database');
const { authenticate } = require('../middleware/auth');

const router = express.Router();

router.get('/', authenticate, async (req, res) => {
    try {
        const [rules] = await db.query(
            'SELECT * FROM alert_rules WHERE user_id = ? ORDER BY created_at DESC',
            [req.user.id]
        );
        res.json(rules);
    } catch (err) {
        res.status(500).json({ error: 'Loi server' });
    }
});

router.post('/', authenticate, async (req, res) => {
    try {
        const { name, metric, operator, threshold, duration_seconds, action } = req.body;
        if (!name || !metric || !operator || threshold == null) {
            return res.status(400).json({ error: 'Thieu thong tin bat buoc' });
        }

        const validMetrics = ['pps', 'mbps', 'connections', 'latency', 'cpu', 'memory'];
        const validOps = ['gt', 'lt', 'eq', 'gte', 'lte'];
        const validActions = ['notify', 'block', 'rate_limit'];

        if (!validMetrics.includes(metric)) return res.status(400).json({ error: 'Metric khong hop le' });
        if (!validOps.includes(operator)) return res.status(400).json({ error: 'Operator khong hop le' });

        const [result] = await db.query(
            `INSERT INTO alert_rules (user_id, name, metric, operator, threshold, duration_seconds, action)
             VALUES (?, ?, ?, ?, ?, ?, ?)`,
            [req.user.id, name, metric, operator, threshold,
             duration_seconds || 60, validActions.includes(action) ? action : 'notify']
        );

        res.status(201).json({ id: result.insertId, message: 'Alert rule da tao' });
    } catch (err) {
        res.status(500).json({ error: 'Loi server' });
    }
});

router.put('/:id/toggle', authenticate, async (req, res) => {
    try {
        const [rules] = await db.query('SELECT * FROM alert_rules WHERE id = ? AND user_id = ?',
            [req.params.id, req.user.id]);
        if (!rules.length) return res.status(404).json({ error: 'Rule khong ton tai' });

        await db.query('UPDATE alert_rules SET is_active = NOT is_active WHERE id = ?', [req.params.id]);
        res.json({ message: 'Da cap nhat trang thai' });
    } catch (err) {
        res.status(500).json({ error: 'Loi server' });
    }
});

router.delete('/:id', authenticate, async (req, res) => {
    try {
        const [rules] = await db.query('SELECT * FROM alert_rules WHERE id = ? AND user_id = ?',
            [req.params.id, req.user.id]);
        if (!rules.length) return res.status(404).json({ error: 'Rule khong ton tai' });

        await db.query('DELETE FROM alert_rules WHERE id = ?', [req.params.id]);
        res.json({ message: 'Alert rule da xoa' });
    } catch (err) {
        res.status(500).json({ error: 'Loi server' });
    }
});

module.exports = router;
