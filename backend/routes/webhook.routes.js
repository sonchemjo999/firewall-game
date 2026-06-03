const express = require('express');
const db = require('../config/database');
const { authenticate } = require('../middleware/auth');
const axios = require('axios');

const router = express.Router();

router.get('/', authenticate, async (req, res) => {
    try {
        const [hooks] = await db.query(
            'SELECT id, name, url, type, events, is_active, last_triggered_at, created_at FROM webhooks WHERE user_id = ?',
            [req.user.id]
        );
        res.json(hooks);
    } catch (err) {
        res.status(500).json({ error: 'Loi server' });
    }
});

router.post('/', authenticate, async (req, res) => {
    try {
        const { name, url, type, events } = req.body;
        if (!name || !url) return res.status(400).json({ error: 'Can ten va URL' });

        const validTypes = ['discord', 'slack', 'telegram', 'custom'];
        const hookType = validTypes.includes(type) ? type : 'custom';

        const [result] = await db.query(
            'INSERT INTO webhooks (user_id, name, url, type, events) VALUES (?, ?, ?, ?, ?)',
            [req.user.id, name, url, hookType, JSON.stringify(events || ['all'])]
        );
        res.status(201).json({ id: result.insertId, message: 'Webhook da tao' });
    } catch (err) {
        res.status(500).json({ error: 'Loi server' });
    }
});

router.put('/:id', authenticate, async (req, res) => {
    try {
        const [hooks] = await db.query('SELECT * FROM webhooks WHERE id = ? AND user_id = ?',
            [req.params.id, req.user.id]);
        if (!hooks.length) return res.status(404).json({ error: 'Webhook khong ton tai' });

        const { name, url, type, events, is_active } = req.body;
        await db.query(
            'UPDATE webhooks SET name = COALESCE(?, name), url = COALESCE(?, url), type = COALESCE(?, type), events = COALESCE(?, events), is_active = COALESCE(?, is_active) WHERE id = ?',
            [name, url, type, events ? JSON.stringify(events) : null, is_active, req.params.id]
        );
        res.json({ message: 'Webhook da cap nhat' });
    } catch (err) {
        res.status(500).json({ error: 'Loi server' });
    }
});

router.delete('/:id', authenticate, async (req, res) => {
    try {
        const [hooks] = await db.query('SELECT * FROM webhooks WHERE id = ? AND user_id = ?',
            [req.params.id, req.user.id]);
        if (!hooks.length) return res.status(404).json({ error: 'Webhook khong ton tai' });

        await db.query('DELETE FROM webhooks WHERE id = ?', [req.params.id]);
        res.json({ message: 'Webhook da xoa' });
    } catch (err) {
        res.status(500).json({ error: 'Loi server' });
    }
});

router.post('/:id/test', authenticate, async (req, res) => {
    try {
        const [hooks] = await db.query('SELECT * FROM webhooks WHERE id = ? AND user_id = ?',
            [req.params.id, req.user.id]);
        if (!hooks.length) return res.status(404).json({ error: 'Webhook khong ton tai' });

        const testData = { event: 'test', message: 'Day la tin nhan thu tu NRO Shield', timestamp: new Date().toISOString() };
        await axios.post(hooks[0].url, testData, { timeout: 5000 });
        res.json({ message: 'Webhook test thanh cong' });
    } catch (err) {
        res.status(500).json({ error: 'Webhook test that bai: ' + err.message });
    }
});

module.exports = router;
