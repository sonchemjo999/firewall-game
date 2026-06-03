const jwt = require('jsonwebtoken');
const config = require('../config/config');
const db = require('../config/database');

// Verify JWT token
const authenticate = async (req, res, next) => {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return res.status(401).json({ error: 'Token không hợp lệ' });
    }

    try {
        const token = authHeader.split(' ')[1];
        const decoded = jwt.verify(token, config.JWT_SECRET);

        const [rows] = await db.query(
            `SELECT u.id, u.username, u.email, u.role, u.telegram_id, u.is_active, u.plan_id,
                    p.slug as plan_slug, p.name as plan_name,
                    p.enable_ai_protection, p.enable_advanced_firewall,
                    p.enable_geoblock, p.enable_custom_rules,
                    p.max_servers as plan_max_servers, p.max_ports_per_server as plan_max_ports,
                    p.max_bandwidth_mbps as plan_max_bandwidth
             FROM users u
             LEFT JOIN plans p ON u.plan_id = p.id
             WHERE u.id = ?`,
            [decoded.id]
        );

        if (!rows.length || !rows[0].is_active) {
            return res.status(401).json({ error: 'Tài khoản không tồn tại hoặc bị khóa' });
        }

        req.user = rows[0];
        next();
    } catch (err) {
        return res.status(401).json({ error: 'Token hết hạn hoặc không hợp lệ' });
    }
};

// Require admin role
const requireAdmin = (req, res, next) => {
    if (req.user.role !== 'admin') {
        return res.status(403).json({ error: 'Cần quyền admin' });
    }
    next();
};

// Require admin or reseller role
const requireReseller = (req, res, next) => {
    if (req.user.role !== 'admin' && req.user.role !== 'reseller') {
        return res.status(403).json({ error: 'Cần quyền admin hoặc reseller' });
    }
    next();
};

// Require premium plan or above
const requirePremium = (req, res, next) => {
    const premiumRoles = ['admin', 'reseller', 'premium'];
    if (!premiumRoles.includes(req.user.role)) {
        return res.status(403).json({ error: 'Cần gói Premium trở lên' });
    }
    next();
};

// Check specific plan feature
const requireFeature = (feature) => {
    return (req, res, next) => {
        if (req.user.role === 'admin') return next();
        if (!req.user[feature]) {
            return res.status(403).json({
                error: `Tính năng này không có trong gói của bạn. Vui lòng nâng cấp.`
            });
        }
        next();
    };
};

// Audit log middleware
const auditLog = (action, resourceType) => {
    return async (req, res, next) => {
        const originalJson = res.json.bind(res);
        res.json = function (data) {
            if (res.statusCode < 400 && req.user) {
                db.query(
                    `INSERT INTO audit_logs (user_id, action, resource_type, resource_id, details, ip_address)
                     VALUES (?, ?, ?, ?, ?, ?)`,
                    [
                        req.user.id,
                        action,
                        resourceType,
                        req.params.id || null,
                        JSON.stringify({ method: req.method, path: req.originalUrl }),
                        req.ip
                    ]
                ).catch(() => {});
            }
            return originalJson(data);
        };
        next();
    };
};

module.exports = { authenticate, requireAdmin, requireReseller, requirePremium, requireFeature, auditLog };
