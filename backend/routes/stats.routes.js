const express = require('express');
const db = require('../config/database');
const { authenticate } = require('../middleware/auth');

const router = express.Router();
router.use(authenticate);

// GET /api/stats/traffic — Traffic theo thời gian
router.get('/traffic', async (req, res) => {
    try {
        const { port_id, hours = 24 } = req.query;
        let query = `SELECT ts.* FROM traffic_stats ts JOIN proxy_ports pp ON ts.proxy_port_id = pp.id
                 JOIN servers s ON pp.server_id = s.id WHERE s.user_id = ? AND ts.hour >= DATE_SUB(NOW(), INTERVAL ? HOUR)`;
        const params = [req.user.id, parseInt(hours)];

        if (port_id) { query += ' AND ts.proxy_port_id = ?'; params.push(port_id); }
        query += ' ORDER BY ts.hour ASC';

        const [stats] = await db.query(query, params);
        res.json(stats);
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// GET /api/stats/attacks
router.get('/attacks', async (req, res) => {
    try {
        const { limit = 50 } = req.query;
        const [attacks] = await db.query(`
      SELECT al.*, pp.proxy_port, s.name as server_name, s.target_ip
      FROM attack_logs al
      JOIN proxy_ports pp ON al.proxy_port_id = pp.id
      JOIN servers s ON pp.server_id = s.id
      WHERE s.user_id = ?
      ORDER BY al.started_at DESC LIMIT ?
    `, [req.user.id, parseInt(limit)]);
        res.json(attacks);
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// GET /api/stats/summary
router.get('/summary', async (req, res) => {
    try {
        const userId = req.user.id;

        const [[{ total_servers }]] = await db.query('SELECT COUNT(*) as total_servers FROM servers WHERE user_id = ?', [userId]);
        const [[{ total_ports }]] = await db.query('SELECT COUNT(*) as total_ports FROM proxy_ports pp JOIN servers s ON pp.server_id = s.id WHERE s.user_id = ?', [userId]);
        const [[{ active_ports }]] = await db.query('SELECT COUNT(*) as active_ports FROM proxy_ports pp JOIN servers s ON pp.server_id = s.id WHERE s.user_id = ? AND pp.is_active = TRUE', [userId]);
        const [[{ attacks_today }]] = await db.query(`
      SELECT COUNT(*) as attacks_today FROM attack_logs al JOIN proxy_ports pp ON al.proxy_port_id = pp.id
      JOIN servers s ON pp.server_id = s.id WHERE s.user_id = ? AND al.started_at >= CURDATE()
    `, [userId]);

        res.json({ total_servers, total_ports, active_ports, attacks_today });
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

module.exports = router;
