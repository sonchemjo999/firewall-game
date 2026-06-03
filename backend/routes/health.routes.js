const express = require('express');
const { authenticate, requireAdmin } = require('../middleware/auth');
const { checkAllServers, getHealthHistory, getHealthSummary } = require('../services/health.service');

const router = express.Router();

router.get('/summary', authenticate, async (req, res) => {
    try {
        const summary = await getHealthSummary();
        res.json(summary);
    } catch (err) {
        res.status(500).json({ error: 'Loi server' });
    }
});

router.get('/:serverId/history', authenticate, async (req, res) => {
    try {
        const hours = parseInt(req.query.hours) || 24;
        const history = await getHealthHistory(req.params.serverId, hours);
        res.json(history);
    } catch (err) {
        res.status(500).json({ error: 'Loi server' });
    }
});

router.post('/check', authenticate, requireAdmin, async (req, res) => {
    try {
        const results = await checkAllServers();
        const broadcast = req.app.get('broadcast');
        if (broadcast) {
            broadcast({ type: 'HEALTH_UPDATE', data: results });
        }
        res.json({ message: 'Da kiem tra', results });
    } catch (err) {
        res.status(500).json({ error: 'Loi server' });
    }
});

module.exports = router;
