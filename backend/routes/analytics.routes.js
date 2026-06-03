const express = require('express');
const db = require('../config/database');
const { authenticate } = require('../middleware/auth');

const router = express.Router();

router.get('/overview', authenticate, async (req, res) => {
    try {
        const days = parseInt(req.query.days) || 7;
        const [[totals]] = await db.query(
            `SELECT COUNT(*) as total_attacks,
                    COALESCE(SUM(packets_count), 0) as total_packets,
                    COALESCE(SUM(bytes_count), 0) as total_bytes,
                    COALESCE(MAX(peak_pps), 0) as max_pps,
                    COALESCE(MAX(peak_mbps), 0) as max_mbps,
                    COALESCE(AVG(duration_seconds), 0) as avg_duration
             FROM attack_analytics
             WHERE started_at >= DATE_SUB(NOW(), INTERVAL ? DAY)`, [days]
        );

        const [byType] = await db.query(
            `SELECT attack_type, COUNT(*) as count,
                    COALESCE(SUM(packets_count), 0) as total_packets
             FROM attack_analytics
             WHERE started_at >= DATE_SUB(NOW(), INTERVAL ? DAY)
             GROUP BY attack_type ORDER BY count DESC`, [days]
        );

        const [byDay] = await db.query(
            `SELECT DATE(started_at) as date, COUNT(*) as count
             FROM attack_analytics
             WHERE started_at >= DATE_SUB(NOW(), INTERVAL ? DAY)
             GROUP BY DATE(started_at) ORDER BY date`, [days]
        );

        const [topSources] = await db.query(
            `SELECT source_ip, source_country, COUNT(*) as count,
                    COALESCE(SUM(packets_count), 0) as total_packets
             FROM attack_analytics
             WHERE started_at >= DATE_SUB(NOW(), INTERVAL ? DAY)
             AND source_ip IS NOT NULL
             GROUP BY source_ip, source_country
             ORDER BY count DESC LIMIT 20`, [days]
        );

        res.json({ totals, by_type: byType, by_day: byDay, top_sources: topSources });
    } catch (err) {
        res.status(500).json({ error: 'Loi server' });
    }
});

router.get('/timeline', authenticate, async (req, res) => {
    try {
        const hours = parseInt(req.query.hours) || 24;
        const [rows] = await db.query(
            `SELECT id, attack_type, source_ip, source_country,
                    packets_count, bytes_count, duration_seconds,
                    peak_pps, peak_mbps, mitigation_method,
                    started_at, ended_at
             FROM attack_analytics
             WHERE started_at >= DATE_SUB(NOW(), INTERVAL ? HOUR)
             ORDER BY started_at DESC LIMIT 100`, [hours]
        );
        res.json(rows);
    } catch (err) {
        res.status(500).json({ error: 'Loi server' });
    }
});

router.get('/countries', authenticate, async (req, res) => {
    try {
        const [rows] = await db.query(
            `SELECT source_country as country, COUNT(*) as count,
                    COALESCE(SUM(packets_count), 0) as total_packets
             FROM attack_analytics
             WHERE source_country IS NOT NULL
             AND started_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
             GROUP BY source_country ORDER BY count DESC`
        );
        res.json(rows);
    } catch (err) {
        res.status(500).json({ error: 'Loi server' });
    }
});

module.exports = router;
