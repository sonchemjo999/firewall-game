const express = require('express');
const db = require('../config/database');
const { authenticate, requireAdmin } = require('../middleware/auth');
const { sendAttackAlert } = require('../services/alert.service');

const router = express.Router();

// POST /api/ai/alert — Webhook từ AI Engine (Không cần JWT, chỉ localhost)
router.post('/alert', async (req, res) => {
    const ip = req.ip || req.socket.remoteAddress || '';
    if (!ip.includes('127.0.0.1') && !ip.includes('::1') && !ip.includes('::ffff:127.0.0.1') && ip !== '::ffff:103.77.246.157' && ip !== '103.77.246.157') {
        console.warn('[AI Alert] Blocked external request from:', ip);
        return res.status(403).json({ error: 'Forbidden' });
    }

    try {
        const { score, type, connections, unique_ips } = req.body;

        // Lấy 1 proxy port đang active (AI hiện monitor toàn cục, ta gán vào proxy đầu tiên để hiện lên Dashboard)
        const [ports] = await db.query(`
            SELECT pp.id, pp.proxy_port, s.name as server_name, s.target_ip
            FROM proxy_ports pp JOIN servers s ON pp.server_id = s.id 
            WHERE pp.is_active = TRUE LIMIT 1
        `);

        if (ports.length > 0) {
            const port = ports[0];
            const attackerIp = `Multiple (${unique_ips} IPs)`;

            // 1. Lưu vào attack_logs
            await db.query(
                `INSERT INTO attack_logs (proxy_port_id, attacker_ip, attack_type, packets_blocked, anomaly_score, ai_detected)
                 VALUES (?, ?, ?, ?, ?, ?)`,
                [port.id, attackerIp, type, connections * 10, score, true]
            );

            // 2. Gửi cảnh báo Telegram
            await sendAttackAlert({
                serverName: port.server_name,
                proxyPort: port.proxy_port,
                targetAddress: port.target_ip,
                attackType: type,
                anomalyScore: score.toFixed(2),
                attackerIp: attackerIp,
                packetsBlocked: connections * 10
            });
        }

        res.json({ message: 'Alert processed' });
    } catch (err) {
        console.error('[AI Alert Endpoint Error]', err);
        res.status(500).json({ error: 'Internal server error' });
    }
});

router.use(authenticate);

// GET /api/ai/status
router.get('/status', async (req, res) => {
    try {
        const [[{ active_models }]] = await db.query('SELECT COUNT(*) as active_models FROM ai_models WHERE is_active = TRUE');
        const [[{ total_detections }]] = await db.query('SELECT COUNT(*) as total_detections FROM ai_detections WHERE detected_at >= DATE_SUB(NOW(), INTERVAL 24 HOUR)');
        const [[latest]] = await db.query('SELECT anomaly_score, anomaly_type, detected_at FROM ai_detections ORDER BY detected_at DESC LIMIT 1');

        res.json({
            active_models,
            detections_24h: total_detections,
            latest_detection: latest || null,
            engine_url: `http://127.0.0.1:${process.env.AI_ENGINE_PORT || 8000}`
        });
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// GET /api/ai/detections
router.get('/detections', async (req, res) => {
    try {
        const { limit = 50 } = req.query;
        let query, params;

        if (req.user.role === 'admin') {
            query = `SELECT d.*, pp.proxy_port, m.model_name FROM ai_detections d
               LEFT JOIN proxy_ports pp ON d.proxy_port_id = pp.id
               LEFT JOIN ai_models m ON d.model_id = m.id
               ORDER BY d.detected_at DESC LIMIT ?`;
            params = [parseInt(limit)];
        } else {
            query = `SELECT d.*, pp.proxy_port, m.model_name FROM ai_detections d
               LEFT JOIN proxy_ports pp ON d.proxy_port_id = pp.id
               LEFT JOIN servers s ON pp.server_id = s.id
               LEFT JOIN ai_models m ON d.model_id = m.id
               WHERE s.user_id = ? ORDER BY d.detected_at DESC LIMIT ?`;
            params = [req.user.id, parseInt(limit)];
        }

        const [detections] = await db.query(query, params);
        res.json(detections);
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// GET /api/ai/models
router.get('/models', authenticate, requireAdmin, async (req, res) => {
    try {
        const [models] = await db.query('SELECT * FROM ai_models ORDER BY trained_at DESC');
        res.json(models);
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// PUT /api/ai/detections/:id/feedback — Đánh dấu false positive
router.put('/detections/:id/feedback', async (req, res) => {
    try {
        const { false_positive } = req.body;
        await db.query(
            'UPDATE ai_detections SET false_positive = ?, reviewed_by = ? WHERE id = ?',
            [!!false_positive, req.user.id, req.params.id]
        );
        res.json({ message: 'Feedback đã lưu' });
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// POST /api/ai/retrain — Trigger retrain (admin)
router.post('/retrain', authenticate, requireAdmin, async (req, res) => {
    try {
        const axios = require('axios');
        const aiUrl = `http://127.0.0.1:${process.env.AI_ENGINE_PORT || 8000}/retrain`;
        await axios.post(aiUrl, {}, { timeout: 5000 });
        res.json({ message: 'Retrain đã trigger' });
    } catch (err) {
        res.json({ message: 'Retrain request sent (AI engine may be offline)', warning: true });
    }
});

module.exports = router;
