const express = require('express');
const db = require('../config/database');
const { authenticate } = require('../middleware/auth');

const router = express.Router();

router.get('/', authenticate, async (req, res) => {
    try {
        const [backups] = await db.query(
            'SELECT id, name, rules_count, created_at FROM firewall_backups WHERE user_id = ? ORDER BY created_at DESC',
            [req.user.id]
        );
        res.json(backups);
    } catch (err) {
        res.status(500).json({ error: 'Loi server' });
    }
});

router.post('/', authenticate, async (req, res) => {
    try {
        const { name } = req.body;
        const backupName = name || `Backup ${new Date().toISOString().split('T')[0]}`;

        const [rules] = await db.query(
            'SELECT * FROM firewall_rules WHERE created_by = ?', [req.user.id]
        );
        const [geoBlocks] = await db.query(
            `SELECT gb.* FROM geo_blocks gb
             LEFT JOIN servers s ON gb.server_id = s.id
             WHERE s.user_id = ? OR gb.is_global = 1`, [req.user.id]
        );

        const backupData = { rules, geo_blocks: geoBlocks, exported_at: new Date().toISOString() };

        const [result] = await db.query(
            'INSERT INTO firewall_backups (user_id, name, backup_data, rules_count) VALUES (?, ?, ?, ?)',
            [req.user.id, backupName, JSON.stringify(backupData), rules.length]
        );

        res.status(201).json({ id: result.insertId, message: 'Backup da tao', rules_count: rules.length });
    } catch (err) {
        res.status(500).json({ error: 'Loi server' });
    }
});

router.post('/:id/restore', authenticate, async (req, res) => {
    try {
        const [backups] = await db.query(
            'SELECT * FROM firewall_backups WHERE id = ? AND user_id = ?',
            [req.params.id, req.user.id]
        );
        if (!backups.length) return res.status(404).json({ error: 'Backup khong ton tai' });

        const backupData = JSON.parse(backups[0].backup_data);
        let restored = 0;

        for (const rule of (backupData.rules || [])) {
            try {
                await db.query(
                    `INSERT INTO firewall_rules (created_by, server_id, name, rule_type, source_ip, dest_port, protocol, action, rate_limit, rate_burst, priority, is_active)
                     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)`,
                    [req.user.id, rule.server_id, rule.name, rule.rule_type, rule.source_ip, rule.dest_port,
                     rule.protocol, rule.action, rule.rate_limit, rule.rate_burst, rule.priority || 100]
                );
                restored++;
            } catch (e) {
                // Skip duplicates
            }
        }

        res.json({ message: `Da phuc hoi ${restored} rules`, restored });
    } catch (err) {
        res.status(500).json({ error: 'Loi server' });
    }
});

router.delete('/:id', authenticate, async (req, res) => {
    try {
        const [backups] = await db.query(
            'SELECT * FROM firewall_backups WHERE id = ? AND user_id = ?',
            [req.params.id, req.user.id]
        );
        if (!backups.length) return res.status(404).json({ error: 'Backup khong ton tai' });

        await db.query('DELETE FROM firewall_backups WHERE id = ?', [req.params.id]);
        res.json({ message: 'Backup da xoa' });
    } catch (err) {
        res.status(500).json({ error: 'Loi server' });
    }
});

module.exports = router;
