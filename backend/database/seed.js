require('dotenv').config({ path: '../.env' });

const bcrypt = require('bcryptjs');
const { v4: uuidv4 } = require('uuid');
const db = require('../config/database');

async function seed() {
    console.log('[SEED] Creating initial data...');

    try {
        // 1. Tạo admin user
        const adminHash = await bcrypt.hash('admin123', 12);
        const [adminResult] = await db.query(
            `INSERT IGNORE INTO users (username, email, password_hash, role) VALUES (?, ?, ?, ?)`,
            ['admin', 'admin@nroshield.local', adminHash, 'admin']
        );
        const adminId = adminResult.insertId || 1;
        console.log('  ✅ Admin user: admin / admin123');

        // 2. Tạo 3 key mẫu
        const keys = [
            { max_servers: 1, max_ports: 3, days: 30 },
            { max_servers: 3, max_ports: 5, days: 90 },
            { max_servers: 5, max_ports: 10, days: 365 }
        ];

        for (const k of keys) {
            const keyCode = 'NRO-' + uuidv4().replace(/-/g, '').substring(0, 24).toUpperCase();
            const expiresAt = new Date(Date.now() + k.days * 86400000).toISOString().slice(0, 19).replace('T', ' ');

            await db.query(
                `INSERT IGNORE INTO license_keys (key_code, max_servers, max_ports_per_server, expires_at, created_by)
         VALUES (?, ?, ?, ?, ?)`,
                [keyCode, k.max_servers, k.max_ports, expiresAt, adminId]
            );
            console.log(`  ✅ Key: ${keyCode} (${k.max_servers} servers, ${k.max_ports} ports, ${k.days} days)`);
        }

        console.log('[SEED] Done!');
    } catch (err) {
        console.error('[SEED] Error:', err.message);
    }

    process.exit(0);
}

seed();
