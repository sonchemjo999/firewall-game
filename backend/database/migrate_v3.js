const db = require('../config/database');

async function migrateV3() {
    console.log('[Migrate v3] Starting...');

    const queries = [
        `ALTER TABLE users ADD COLUMN IF NOT EXISTS totp_secret VARCHAR(64) DEFAULT NULL`,
        `ALTER TABLE users ADD COLUMN IF NOT EXISTS totp_enabled TINYINT(1) DEFAULT 0`,
        `ALTER TABLE users ADD COLUMN IF NOT EXISTS backup_codes TEXT DEFAULT NULL`,

        `CREATE TABLE IF NOT EXISTS server_health (
            id INT AUTO_INCREMENT PRIMARY KEY,
            server_id INT NOT NULL,
            status ENUM('online', 'offline', 'degraded') DEFAULT 'offline',
            latency_ms INT DEFAULT NULL,
            port_open TINYINT(1) DEFAULT 0,
            cpu_usage FLOAT DEFAULT NULL,
            memory_usage FLOAT DEFAULT NULL,
            checked_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (server_id) REFERENCES servers(id) ON DELETE CASCADE,
            INDEX idx_server_checked (server_id, checked_at)
        )`,

        `CREATE TABLE IF NOT EXISTS attack_analytics (
            id INT AUTO_INCREMENT PRIMARY KEY,
            server_id INT DEFAULT NULL,
            attack_type VARCHAR(50) NOT NULL,
            source_ip VARCHAR(45) DEFAULT NULL,
            source_country VARCHAR(10) DEFAULT NULL,
            packets_count BIGINT DEFAULT 0,
            bytes_count BIGINT DEFAULT 0,
            duration_seconds INT DEFAULT 0,
            peak_pps BIGINT DEFAULT 0,
            peak_mbps FLOAT DEFAULT 0,
            mitigation_method VARCHAR(100) DEFAULT NULL,
            started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            ended_at TIMESTAMP NULL,
            FOREIGN KEY (server_id) REFERENCES servers(id) ON DELETE SET NULL,
            INDEX idx_started (started_at),
            INDEX idx_type (attack_type)
        )`,

        `CREATE TABLE IF NOT EXISTS webhooks (
            id INT AUTO_INCREMENT PRIMARY KEY,
            user_id INT NOT NULL,
            name VARCHAR(100) NOT NULL,
            url VARCHAR(500) NOT NULL,
            type ENUM('discord', 'slack', 'telegram', 'custom') DEFAULT 'custom',
            events JSON DEFAULT NULL,
            is_active TINYINT(1) DEFAULT 1,
            last_triggered_at TIMESTAMP NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
        )`,

        `CREATE TABLE IF NOT EXISTS firewall_backups (
            id INT AUTO_INCREMENT PRIMARY KEY,
            user_id INT NOT NULL,
            name VARCHAR(100) NOT NULL,
            backup_data JSON NOT NULL,
            rules_count INT DEFAULT 0,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
        )`,

        `CREATE TABLE IF NOT EXISTS alert_rules (
            id INT AUTO_INCREMENT PRIMARY KEY,
            user_id INT NOT NULL,
            name VARCHAR(100) NOT NULL,
            metric VARCHAR(50) NOT NULL,
            operator ENUM('gt', 'lt', 'eq', 'gte', 'lte') NOT NULL,
            threshold FLOAT NOT NULL,
            duration_seconds INT DEFAULT 60,
            action ENUM('notify', 'block', 'rate_limit') DEFAULT 'notify',
            is_active TINYINT(1) DEFAULT 1,
            last_triggered_at TIMESTAMP NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
        )`,

        `CREATE TABLE IF NOT EXISTS api_usage (
            id INT AUTO_INCREMENT PRIMARY KEY,
            user_id INT NOT NULL,
            endpoint VARCHAR(200) NOT NULL,
            request_count INT DEFAULT 0,
            window_start TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
            INDEX idx_user_window (user_id, window_start)
        )`
    ];

    for (const q of queries) {
        try {
            await db.query(q);
        } catch (err) {
            if (!err.message.includes('Duplicate column') && !err.message.includes('already exists')) {
                console.error('[Migrate v3] Error:', err.message);
            }
        }
    }

    console.log('[Migrate v3] Complete!');
    process.exit(0);
}

migrateV3();
