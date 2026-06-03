const express = require('express');
const db = require('../config/database');
const { authenticate, requireAdmin, requireFeature, auditLog } = require('../middleware/auth');
const { addCustomRule, removeCustomRule, getLastSyncStatus } = require('../services/firewall_v2.service');

const router = express.Router();
router.use(authenticate);

// GET /api/firewall/rules — Danh sách firewall rules
router.get('/rules', async (req, res) => {
    try {
        let query, params;

        if (req.user.role === 'admin') {
            query = `SELECT fr.*, pp.proxy_port, s.name as server_name, u.username as created_by_name
                     FROM firewall_rules fr
                     LEFT JOIN proxy_ports pp ON fr.proxy_port_id = pp.id
                     LEFT JOIN servers s ON fr.server_id = s.id
                     LEFT JOIN users u ON fr.created_by = u.id
                     ORDER BY fr.priority ASC`;
            params = [];
        } else {
            query = `SELECT fr.*, pp.proxy_port, s.name as server_name
                     FROM firewall_rules fr
                     LEFT JOIN proxy_ports pp ON fr.proxy_port_id = pp.id
                     LEFT JOIN servers s ON fr.server_id = s.id
                     WHERE fr.is_global = TRUE OR s.user_id = ?
                     ORDER BY fr.priority ASC`;
            params = [req.user.id];
        }

        const [rules] = await db.query(query, params);
        res.json(rules);
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// POST /api/firewall/rules — Thêm custom rule
router.post('/rules', requireFeature('enable_custom_rules'), auditLog('create_rule', 'firewall_rule'), async (req, res) => {
    try {
        const { name, rule_type, priority, protocol, source_ip, source_port,
            dest_port, action, rate_limit, rate_burst, conditions,
            is_global, server_id, proxy_port_id } = req.body;

        if (!name || !rule_type) {
            return res.status(400).json({ error: 'Cần name và rule_type' });
        }

        // Non-admin không được tạo global rules
        if (is_global && req.user.role !== 'admin') {
            return res.status(403).json({ error: 'Chỉ admin mới tạo được global rules' });
        }

        // Validate server thuộc user (nếu không phải admin)
        if (server_id && req.user.role !== 'admin') {
            const [servers] = await db.query(
                'SELECT id FROM servers WHERE id = ? AND user_id = ?',
                [server_id, req.user.id]
            );
            if (!servers.length) return res.status(404).json({ error: 'Server không tồn tại' });
        }

        const result = await addCustomRule({
            name, rule_type, priority, protocol, source_ip, source_port,
            dest_port, action, rate_limit, rate_burst, conditions,
            is_global: is_global || false, server_id, proxy_port_id,
            created_by: req.user.id
        });

        // Broadcast rule change qua WebSocket
        const broadcast = req.app.get('broadcast');
        if (broadcast) {
            broadcast({ type: 'FIREWALL_RULE_ADDED', data: { rule_id: result.id, name } });
        }

        res.status(201).json({ message: 'Rule đã thêm và áp dụng', id: result.id });
    } catch (err) {
        console.error('[FIREWALL] Add rule error:', err);
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// PUT /api/firewall/rules/:id — Sửa rule
router.put('/rules/:id', requireFeature('enable_custom_rules'), async (req, res) => {
    try {
        const [rules] = await db.query('SELECT * FROM firewall_rules WHERE id = ?', [req.params.id]);
        if (!rules.length) return res.status(404).json({ error: 'Rule không tồn tại' });

        // Check ownership
        if (req.user.role !== 'admin' && rules[0].created_by !== req.user.id) {
            return res.status(403).json({ error: 'Không có quyền sửa rule này' });
        }

        const fields = [];
        const values = [];
        const allowed = ['name', 'priority', 'protocol', 'source_ip', 'source_port',
            'dest_port', 'action', 'rate_limit', 'rate_burst', 'is_active'];

        for (const key of allowed) {
            if (req.body[key] !== undefined) {
                fields.push(`${key} = ?`);
                values.push(req.body[key]);
            }
        }

        if (req.body.conditions) {
            fields.push('conditions = ?');
            values.push(JSON.stringify(req.body.conditions));
        }

        if (!fields.length) return res.status(400).json({ error: 'Không có gì để cập nhật' });

        // Mark as needing re-apply
        fields.push('applied = FALSE');

        values.push(req.params.id);
        await db.query(`UPDATE firewall_rules SET ${fields.join(', ')} WHERE id = ?`, values);

        res.json({ message: 'Rule đã cập nhật (cần sync lại firewall)' });
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// DELETE /api/firewall/rules/:id — Xóa rule
router.delete('/rules/:id', requireFeature('enable_custom_rules'), auditLog('delete_rule', 'firewall_rule'), async (req, res) => {
    try {
        const [rules] = await db.query('SELECT * FROM firewall_rules WHERE id = ?', [req.params.id]);
        if (!rules.length) return res.status(404).json({ error: 'Rule không tồn tại' });

        if (req.user.role !== 'admin' && rules[0].created_by !== req.user.id) {
            return res.status(403).json({ error: 'Không có quyền xóa rule này' });
        }

        await removeCustomRule(req.params.id);

        const broadcast = req.app.get('broadcast');
        if (broadcast) {
            broadcast({ type: 'FIREWALL_RULE_REMOVED', data: { rule_id: parseInt(req.params.id) } });
        }

        res.json({ message: 'Rule đã xóa' });
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// POST /api/firewall/sync — Đồng bộ firewall (admin)
router.post('/sync', requireAdmin, auditLog('sync_firewall', 'firewall'), async (req, res) => {
    try {
        const { syncFirewallRules } = require('../services/firewall_v2.service');
        const result = await syncFirewallRules();

        const broadcast = req.app.get('broadcast');
        if (broadcast) {
            broadcast({ type: 'FIREWALL_SYNCED', data: result });
        }

        res.json({ message: 'Firewall đã sync', ...result });
    } catch (err) {
        res.status(500).json({ error: 'Lỗi sync firewall' });
    }
});

// GET /api/firewall/sync-status — Trạng thái sync gần nhất
router.get('/sync-status', async (req, res) => {
    try {
        const status = await getLastSyncStatus();
        res.json(status || { message: 'Chưa có sync nào' });
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// GET /api/firewall/geo-blocks — Danh sách quốc gia bị chặn
router.get('/geo-blocks', requireFeature('enable_geoblock'), async (req, res) => {
    try {
        let query, params;
        if (req.user.role === 'admin') {
            query = 'SELECT gb.*, u.username as created_by_name FROM geo_blocks gb LEFT JOIN users u ON gb.created_by = u.id ORDER BY gb.country_name ASC';
            params = [];
        } else {
            query = `SELECT gb.* FROM geo_blocks gb
                     LEFT JOIN servers s ON gb.server_id = s.id
                     WHERE gb.is_global = TRUE OR s.user_id = ?
                     ORDER BY gb.country_name ASC`;
            params = [req.user.id];
        }

        const [blocks] = await db.query(query, params);
        res.json(blocks);
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// POST /api/firewall/geo-blocks — Thêm geo block
router.post('/geo-blocks', requireFeature('enable_geoblock'), async (req, res) => {
    try {
        const { country_code, country_name, server_id, is_global } = req.body;
        if (!country_code) return res.status(400).json({ error: 'Cần country_code' });

        if (is_global && req.user.role !== 'admin') {
            return res.status(403).json({ error: 'Chỉ admin mới tạo được global geo block' });
        }

        await db.query(
            `INSERT INTO geo_blocks (country_code, country_name, is_global, server_id, created_by)
             VALUES (?, ?, ?, ?, ?)`,
            [country_code.toUpperCase(), country_name || country_code, is_global || false,
                server_id || null, req.user.id]
        );

        res.status(201).json({ message: 'Geo block đã thêm' });
    } catch (err) {
        if (err.code === 'ER_DUP_ENTRY') {
            return res.status(400).json({ error: 'Quốc gia đã bị chặn' });
        }
        res.status(500).json({ error: 'Lỗi server' });
    }
});

// DELETE /api/firewall/geo-blocks/:id — Xóa geo block
router.delete('/geo-blocks/:id', requireFeature('enable_geoblock'), async (req, res) => {
    try {
        const [blocks] = await db.query('SELECT gb.*, s.user_id as server_owner FROM geo_blocks gb LEFT JOIN servers s ON gb.server_id = s.id WHERE gb.id = ?', [req.params.id]);
        if (!blocks.length) return res.status(404).json({ error: 'Geo block không tồn tại' });

        if (req.user.role !== 'admin') {
            const block = blocks[0];
            if (block.is_global || (block.server_owner && block.server_owner !== req.user.id)) {
                return res.status(403).json({ error: 'Không có quyền xóa geo block này' });
            }
        }

        await db.query('DELETE FROM geo_blocks WHERE id = ?', [req.params.id]);
        res.json({ message: 'Geo block đã xóa' });
    } catch (err) {
        res.status(500).json({ error: 'Lỗi server' });
    }
});

module.exports = router;
