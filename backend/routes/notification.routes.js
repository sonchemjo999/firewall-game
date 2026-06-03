const express = require('express');
const db = require('../config/database');
const { authenticate } = require('../middleware/auth');

const router = express.Router();
router.use(authenticate);

// GET /api/notifications — Danh sách notifications
router.get('/', async (req, res) => {
    try {
        const { limit = 50, unread_only } = req.query;
        let query = 'SELECT * FROM notifications WHERE user_id = ?';
        const params = [req.user.id];

        if (unread_only === 'true') {
            query += ' AND is_read = FALSE';
        }

        query += ' ORDER BY created_at DESC LIMIT ?';
        params.push(parseInt(limit));

        const [notifications] = await db.query(query, params);
        res.json(notifications);
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// GET /api/notifications/count — Số chưa đọc
router.get('/count', async (req, res) => {
    try {
        const [[{ count }]] = await db.query(
            'SELECT COUNT(*) as count FROM notifications WHERE user_id = ? AND is_read = FALSE',
            [req.user.id]
        );
        res.json({ unread: count });
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// PUT /api/notifications/:id/read — Đánh dấu đã đọc
router.put('/:id/read', async (req, res) => {
    try {
        await db.query(
            'UPDATE notifications SET is_read = TRUE WHERE id = ? AND user_id = ?',
            [req.params.id, req.user.id]
        );
        res.json({ message: 'Đã đánh dấu đọc' });
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// PUT /api/notifications/read-all — Đánh dấu tất cả đã đọc
router.put('/read-all', async (req, res) => {
    try {
        await db.query(
            'UPDATE notifications SET is_read = TRUE WHERE user_id = ? AND is_read = FALSE',
            [req.user.id]
        );
        res.json({ message: 'Đã đánh dấu tất cả đã đọc' });
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// DELETE /api/notifications/:id — Xóa notification
router.delete('/:id', async (req, res) => {
    try {
        await db.query(
            'DELETE FROM notifications WHERE id = ? AND user_id = ?',
            [req.params.id, req.user.id]
        );
        res.json({ message: 'Đã xóa' });
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

module.exports = router;
