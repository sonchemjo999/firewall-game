require('dotenv').config({ path: require('path').join(__dirname, '../../.env') });
const db = require('../config/database');

async function runMigrationsV2() {
    console.log('[MIGRATE V2] Running v2 database migrations...');

    const alterations = [
        // 1. Mở rộng roles: admin, reseller, premium, basic
        `ALTER TABLE users MODIFY COLUMN role ENUM('admin','reseller','premium','basic') DEFAULT 'basic'`,

        // 2. Thêm cột plan_id cho users
        `ALTER TABLE users ADD COLUMN IF NOT EXISTS plan_id INT NULL AFTER role`,

        // 3. Thêm cột game_type cho servers
        `ALTER TABLE servers ADD COLUMN IF NOT EXISTS game_type VARCHAR(30) DEFAULT 'nro' AFTER name`,

        // 4. Thêm cột game_type cho proxy_ports
        `ALTER TABLE proxy_ports ADD COLUMN IF NOT EXISTS game_type VARCHAR(30) DEFAULT 'nro' AFTER protocol`,

        // 5. Thêm cột plan cho license_keys
        `ALTER TABLE license_keys ADD COLUMN IF NOT EXISTS plan_type ENUM('basic','standard','premium','enterprise') DEFAULT 'basic' AFTER max_bandwidth_mbps`,
    ];

    const tables = [
        // Bảng gói dịch vụ (plans)
        `CREATE TABLE IF NOT EXISTS plans (
            id INT AUTO_INCREMENT PRIMARY KEY,
            name VARCHAR(100) NOT NULL,
            slug VARCHAR(50) UNIQUE NOT NULL,
            description TEXT,
            max_servers INT DEFAULT 1,
            max_ports_per_server INT DEFAULT 3,
            max_bandwidth_mbps INT DEFAULT 100,
            allowed_games JSON,
            allowed_protocols JSON,
            enable_ai_protection BOOLEAN DEFAULT FALSE,
            enable_advanced_firewall BOOLEAN DEFAULT FALSE,
            enable_geoblock BOOLEAN DEFAULT FALSE,
            enable_custom_rules BOOLEAN DEFAULT FALSE,
            price_monthly DECIMAL(10,2) DEFAULT 0,
            price_yearly DECIMAL(10,2) DEFAULT 0,
            is_active BOOLEAN DEFAULT TRUE,
            sort_order INT DEFAULT 0,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        )`,

        // Bảng game types
        `CREATE TABLE IF NOT EXISTS game_types (
            id INT AUTO_INCREMENT PRIMARY KEY,
            code VARCHAR(30) UNIQUE NOT NULL,
            name VARCHAR(100) NOT NULL,
            protocol ENUM('tcp','udp','both') DEFAULT 'tcp',
            default_ports VARCHAR(255),
            max_packet_size INT DEFAULT 4096,
            min_packet_size INT DEFAULT 28,
            udp_rate_limit VARCHAR(20) DEFAULT '500/sec',
            tcp_rate_limit VARCHAR(20) DEFAULT '200/sec',
            max_conn_per_ip INT DEFAULT 50,
            icon VARCHAR(10),
            description TEXT,
            firewall_profile JSON,
            is_active BOOLEAN DEFAULT TRUE,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )`,

        // Bảng firewall rules (đồng bộ giữa DB, backend, firewall script)
        `CREATE TABLE IF NOT EXISTS firewall_rules (
            id INT AUTO_INCREMENT PRIMARY KEY,
            name VARCHAR(100) NOT NULL,
            rule_type ENUM('rate_limit','block','allow','challenge','geo_block','custom') NOT NULL,
            priority INT DEFAULT 100,
            protocol ENUM('tcp','udp','icmp','all') DEFAULT 'all',
            source_ip VARCHAR(45),
            source_port VARCHAR(20),
            dest_port VARCHAR(20),
            action ENUM('accept','drop','reject','rate_limit','challenge','log') DEFAULT 'drop',
            rate_limit VARCHAR(50),
            rate_burst INT,
            conditions JSON,
            is_global BOOLEAN DEFAULT FALSE,
            server_id INT NULL,
            proxy_port_id INT NULL,
            is_active BOOLEAN DEFAULT TRUE,
            applied BOOLEAN DEFAULT FALSE,
            created_by INT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            FOREIGN KEY (server_id) REFERENCES servers(id) ON DELETE CASCADE,
            FOREIGN KEY (proxy_port_id) REFERENCES proxy_ports(id) ON DELETE CASCADE,
            FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
            INDEX idx_priority (priority),
            INDEX idx_type (rule_type),
            INDEX idx_global (is_global)
        )`,

        // Bảng geo block (quốc gia bị chặn)
        `CREATE TABLE IF NOT EXISTS geo_blocks (
            id INT AUTO_INCREMENT PRIMARY KEY,
            country_code CHAR(2) NOT NULL,
            country_name VARCHAR(100),
            is_global BOOLEAN DEFAULT FALSE,
            server_id INT NULL,
            created_by INT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (server_id) REFERENCES servers(id) ON DELETE CASCADE,
            FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
            UNIQUE KEY uniq_geo (country_code, server_id)
        )`,

        // Bảng audit logs (lịch sử hành động)
        `CREATE TABLE IF NOT EXISTS audit_logs (
            id INT AUTO_INCREMENT PRIMARY KEY,
            user_id INT,
            action VARCHAR(100) NOT NULL,
            resource_type VARCHAR(50),
            resource_id INT,
            details JSON,
            ip_address VARCHAR(45),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL,
            INDEX idx_user (user_id),
            INDEX idx_action (action),
            INDEX idx_time (created_at)
        )`,

        // Bảng notifications
        `CREATE TABLE IF NOT EXISTS notifications (
            id INT AUTO_INCREMENT PRIMARY KEY,
            user_id INT NOT NULL,
            title VARCHAR(200) NOT NULL,
            message TEXT,
            type ENUM('info','warning','danger','success') DEFAULT 'info',
            is_read BOOLEAN DEFAULT FALSE,
            link VARCHAR(500),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
            INDEX idx_user_read (user_id, is_read),
            INDEX idx_time (created_at)
        )`,

        // Bảng rule sync status (trạng thái đồng bộ rules)
        `CREATE TABLE IF NOT EXISTS rule_sync_log (
            id INT AUTO_INCREMENT PRIMARY KEY,
            sync_type ENUM('full','partial','rule_add','rule_remove') NOT NULL,
            rules_synced INT DEFAULT 0,
            rules_failed INT DEFAULT 0,
            duration_ms INT,
            error_log TEXT,
            synced_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )`
    ];

    // Chạy ALTER statements (bỏ qua lỗi nếu cột đã tồn tại)
    for (const sql of alterations) {
        try {
            await db.query(sql);
            console.log(`  [ALT] OK`);
        } catch (err) {
            // Bỏ qua lỗi duplicate column
            if (!err.message.includes('Duplicate column') && !err.message.includes('already exists')) {
                console.warn(`  [ALT] Skip: ${err.message.substring(0, 80)}`);
            }
        }
    }

    // Tạo tables mới
    for (const sql of tables) {
        try {
            await db.query(sql);
            const match = sql.match(/CREATE TABLE IF NOT EXISTS (\w+)/);
            if (match) console.log(`  + ${match[1]}`);
        } catch (err) {
            console.error(`  x Error: ${err.message}`);
        }
    }

    // Seed game types
    await seedGameTypes();
    // Seed plans
    await seedPlans();

    console.log('[MIGRATE V2] Done!');
    process.exit(0);
}

async function seedGameTypes() {
    console.log('[SEED] Game types...');

    const games = [
        ['nro', 'Ngoc Rong Online', 'udp', '14445,20000,1875', 1500, 28, '500/sec', '100/sec', 100],
        ['samp', 'SA:MP', 'udp', '7777,7778', 2048, 28, '500/sec', '50/sec', 50],
        ['minecraft', 'Minecraft', 'tcp', '25565', 32767, 1, '50/sec', '200/sec', 20],
        ['fivem', 'FiveM (GTA V)', 'both', '30120', 4096, 28, '600/sec', '200/sec', 50],
        ['muonline', 'MU Online', 'tcp', '44405,55901,55902,55903', 4096, 4, '100/sec', '300/sec', 30],
        ['rust', 'Rust', 'udp', '28015,28016', 4096, 28, '1000/sec', '100/sec', 50],
        ['ark', 'ARK: Survival', 'udp', '7777,7778,27015', 4096, 28, '800/sec', '100/sec', 50],
        ['cs2', 'Counter-Strike 2', 'udp', '27015,27016', 4096, 28, '800/sec', '100/sec', 50],
        ['lineage2', 'Lineage 2', 'tcp', '7777,2106,2108', 8192, 4, '50/sec', '200/sec', 20],
        ['web', 'Web Server', 'tcp', '80,443', 65535, 1, '100/sec', '500/sec', 200],
    ];

    for (const g of games) {
        try {
            await db.query(
                `INSERT INTO game_types (code, name, protocol, default_ports, max_packet_size, min_packet_size,
                    udp_rate_limit, tcp_rate_limit, max_conn_per_ip)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                 ON DUPLICATE KEY UPDATE name = VALUES(name)`,
                g
            );
        } catch (err) {
            // Ignore duplicates
        }
    }
    console.log(`  + ${games.length} game types seeded`);
}

async function seedPlans() {
    console.log('[SEED] Plans...');

    const plans = [
        ['Basic', 'basic', 'Goi co ban cho 1 server', 1, 2, 50, '["nro","samp"]', '["tcp","udp"]', false, false, false, false, 50000, 500000, 1],
        ['Standard', 'standard', 'Goi tieu chuan cho 3 servers', 3, 5, 200, '["nro","samp","minecraft","fivem"]', '["tcp","udp","both"]', true, false, false, false, 150000, 1500000, 2],
        ['Premium', 'premium', 'Goi cao cap cho 10 servers', 10, 10, 500, 'null', '["tcp","udp","both"]', true, true, true, false, 300000, 3000000, 3],
        ['Enterprise', 'enterprise', 'Goi doanh nghiep khong gioi han', 100, 50, 10000, 'null', '["tcp","udp","both"]', true, true, true, true, 1000000, 10000000, 4],
    ];

    for (const p of plans) {
        try {
            await db.query(
                `INSERT INTO plans (name, slug, description, max_servers, max_ports_per_server, max_bandwidth_mbps,
                    allowed_games, allowed_protocols, enable_ai_protection, enable_advanced_firewall,
                    enable_geoblock, enable_custom_rules, price_monthly, price_yearly, sort_order)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                 ON DUPLICATE KEY UPDATE name = VALUES(name)`,
                p
            );
        } catch (err) {
            // Ignore duplicates
        }
    }
    console.log(`  + ${plans.length} plans seeded`);
}

runMigrationsV2();
