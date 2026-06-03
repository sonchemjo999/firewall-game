const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const db = require('../config/database');
const config = require('../config/config');
const { authenticate } = require('../middleware/auth');

const router = express.Router();

// POST /api/auth/register — Đăng ký (cần key)
router.post('/register', async (req, res) => {
    try {
        const { username, password, key_code, email, telegram_id } = req.body;

        if (!username || !password || !key_code) {
            return res.status(400).json({ error: 'Cần username, password và key_code' });
        }

        // Validate key
        const [keys] = await db.query(
            'SELECT * FROM license_keys WHERE key_code = ? AND status = "active" AND user_id IS NULL',
            [key_code]
        );

        if (!keys.length) {
            return res.status(400).json({ error: 'Key không hợp lệ hoặc đã được sử dụng' });
        }

        // Check username exists
        const [existing] = await db.query('SELECT id FROM users WHERE username = ?', [username]);
        if (existing.length) {
            return res.status(400).json({ error: 'Username đã tồn tại' });
        }

        // Create user
        const hash = await bcrypt.hash(password, 12);
        const [result] = await db.query(
            'INSERT INTO users (username, email, password_hash, telegram_id) VALUES (?, ?, ?, ?)',
            [username, email || null, hash, telegram_id || null]
        );

        // Assign key to user
        await db.query('UPDATE license_keys SET user_id = ? WHERE id = ?', [result.insertId, keys[0].id]);

        const token = jwt.sign({ id: result.insertId, role: 'user' }, config.JWT_SECRET, {
            expiresIn: config.JWT_EXPIRES_IN
        });

        res.status(201).json({
            message: 'Đăng ký thành công',
            token,
            user: { id: result.insertId, username, role: 'user' }
        });
    } catch (err) {
        console.error('[AUTH] Register error:', err);
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// POST /api/auth/login
router.post('/login', async (req, res) => {
    try {
        const { username, password } = req.body;

        if (!username || !password) {
            return res.status(400).json({ error: 'Cần username và password' });
        }

        const [users] = await db.query(
            'SELECT id, username, password_hash, role, is_active FROM users WHERE username = ?',
            [username]
        );

        if (!users.length) {
            return res.status(401).json({ error: 'Sai username hoặc password' });
        }

        if (!users[0].is_active) {
            return res.status(403).json({ error: 'Tài khoản đã bị khóa' });
        }

        const valid = await bcrypt.compare(password, users[0].password_hash);
        if (!valid) {
            return res.status(401).json({ error: 'Sai username hoặc password' });
        }

        const token = jwt.sign({ id: users[0].id, role: users[0].role }, config.JWT_SECRET, {
            expiresIn: config.JWT_EXPIRES_IN
        });

        res.json({
            token,
            user: { id: users[0].id, username: users[0].username, role: users[0].role }
        });
    } catch (err) {
        console.error('[AUTH] Login error:', err);
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// GET /api/auth/me
router.get('/me', authenticate, async (req, res) => {
    try {
        const [keys] = await db.query(
            'SELECT key_code, max_servers, max_ports_per_server, status, expires_at FROM license_keys WHERE user_id = ? AND status = "active"',
            [req.user.id]
        );

        res.json({
            user: req.user,
            license: keys[0] || null
        });
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

module.exports = router;
