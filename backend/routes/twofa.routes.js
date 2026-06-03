const express = require('express');
const db = require('../config/database');
const { authenticate } = require('../middleware/auth');
const { generateSecret, verifyTOTP, generateBackupCodes, getOtpAuthUrl } = require('../services/totp.service');

const router = express.Router();

router.post('/setup', authenticate, async (req, res) => {
    try {
        const [users] = await db.query('SELECT totp_enabled FROM users WHERE id = ?', [req.user.id]);
        if (users.length && users[0].totp_enabled) {
            return res.status(400).json({ error: '2FA da duoc kich hoat' });
        }
        const secret = generateSecret();
        await db.query('UPDATE users SET totp_secret = ? WHERE id = ?', [secret, req.user.id]);
        const otpAuthUrl = getOtpAuthUrl(secret, req.user.username);
        res.json({ secret, otpAuthUrl, message: 'Quet QR code hoac nhap secret vao app xac thuc' });
    } catch (err) {
        res.status(500).json({ error: 'Loi server' });
    }
});

router.post('/verify', authenticate, async (req, res) => {
    try {
        const { token } = req.body;
        if (!token) return res.status(400).json({ error: 'Can nhap ma xac thuc' });

        const [users] = await db.query('SELECT totp_secret FROM users WHERE id = ?', [req.user.id]);
        if (!users.length || !users[0].totp_secret) {
            return res.status(400).json({ error: 'Chua thiet lap 2FA' });
        }

        if (!verifyTOTP(users[0].totp_secret, token)) {
            return res.status(400).json({ error: 'Ma xac thuc khong dung' });
        }

        const backupCodes = generateBackupCodes();
        await db.query('UPDATE users SET totp_enabled = 1, backup_codes = ? WHERE id = ?',
            [JSON.stringify(backupCodes), req.user.id]);

        res.json({ message: '2FA da kich hoat thanh cong', backup_codes: backupCodes });
    } catch (err) {
        res.status(500).json({ error: 'Loi server' });
    }
});

router.post('/disable', authenticate, async (req, res) => {
    try {
        const { token } = req.body;
        if (!token) return res.status(400).json({ error: 'Can nhap ma xac thuc' });

        const [users] = await db.query('SELECT totp_secret FROM users WHERE id = ?', [req.user.id]);
        if (!users.length || !users[0].totp_secret) {
            return res.status(400).json({ error: '2FA chua duoc kich hoat' });
        }

        if (!verifyTOTP(users[0].totp_secret, token)) {
            return res.status(400).json({ error: 'Ma xac thuc khong dung' });
        }

        await db.query('UPDATE users SET totp_enabled = 0, totp_secret = NULL, backup_codes = NULL WHERE id = ?',
            [req.user.id]);
        res.json({ message: '2FA da tat' });
    } catch (err) {
        res.status(500).json({ error: 'Loi server' });
    }
});

router.get('/status', authenticate, async (req, res) => {
    try {
        const [users] = await db.query('SELECT totp_enabled FROM users WHERE id = ?', [req.user.id]);
        res.json({ enabled: users.length > 0 && users[0].totp_enabled === 1 });
    } catch (err) {
        res.status(500).json({ error: 'Loi server' });
    }
});

module.exports = router;
