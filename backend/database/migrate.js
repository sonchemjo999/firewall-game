require('dotenv').config({ path: require('path').join(__dirname, '../../.env') });
const db = require('../config/database');

async function runMigrations() {
    console.log('[MIGRATE] Running database migrations...');

    const tables = [
        // 1. Users
        `CREATE TABLE IF NOT EXISTS users (
      id INT AUTO_INCREMENT PRIMARY KEY,
      username VARCHAR(50) UNIQUE NOT NULL,
      email VARCHAR(100) UNIQUE,
      password_hash VARCHAR(255) NOT NULL,
      role ENUM('admin','user') DEFAULT 'user',
      telegram_id BIGINT,
      is_active BOOLEAN DEFAULT TRUE,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      INDEX idx_role (role),
      INDEX idx_telegram (telegram_id)
    )`,

        // 2. License Keys
        `CREATE TABLE IF NOT EXISTS license_keys (
      id INT AUTO_INCREMENT PRIMARY KEY,
      key_code VARCHAR(64) UNIQUE NOT NULL,
      user_id INT,
      max_servers INT DEFAULT 1,
      max_ports_per_server INT DEFAULT 3,
      max_bandwidth_mbps INT DEFAULT 100,
      status ENUM('active','expired','suspended') DEFAULT 'active',
      expires_at TIMESTAMP NULL,
      created_by INT,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL,
      FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
      INDEX idx_status (status),
      INDEX idx_key (key_code),
      INDEX idx_expires (expires_at)
    )`,

        // 3. Servers
        `CREATE TABLE IF NOT EXISTS servers (
      id INT AUTO_INCREMENT PRIMARY KEY,
      user_id INT NOT NULL,
      key_id INT NOT NULL,
      name VARCHAR(100) DEFAULT 'My Server',
      target_ip VARCHAR(45) NOT NULL,
      status ENUM('active','inactive') DEFAULT 'active',
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
      FOREIGN KEY (key_id) REFERENCES license_keys(id) ON DELETE CASCADE,
      INDEX idx_user (user_id)
    )`,

        // 4. Proxy Ports
        `CREATE TABLE IF NOT EXISTS proxy_ports (
      id INT AUTO_INCREMENT PRIMARY KEY,
      server_id INT NOT NULL,
      proxy_port INT NOT NULL,
      target_port INT NOT NULL,
      protocol ENUM('tcp','udp','both') DEFAULT 'tcp',
      is_active BOOLEAN DEFAULT TRUE,
      bytes_in BIGINT DEFAULT 0,
      bytes_out BIGINT DEFAULT 0,
      connections_count INT DEFAULT 0,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (server_id) REFERENCES servers(id) ON DELETE CASCADE,
      UNIQUE KEY uniq_proxy_port (proxy_port),
      INDEX idx_server (server_id),
      INDEX idx_active (is_active)
    )`,

        // 5. Attack Logs
        `CREATE TABLE IF NOT EXISTS attack_logs (
      id INT AUTO_INCREMENT PRIMARY KEY,
      proxy_port_id INT,
      attacker_ip VARCHAR(45),
      attack_type VARCHAR(50),
      packets_blocked BIGINT DEFAULT 0,
      anomaly_score FLOAT,
      ai_detected BOOLEAN DEFAULT FALSE,
      started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      ended_at TIMESTAMP NULL,
      FOREIGN KEY (proxy_port_id) REFERENCES proxy_ports(id) ON DELETE SET NULL,
      INDEX idx_time (started_at),
      INDEX idx_type (attack_type)
    )`,

        // 6. IP Lists
        `CREATE TABLE IF NOT EXISTS ip_lists (
      id INT AUTO_INCREMENT PRIMARY KEY,
      user_id INT,
      ip_address VARCHAR(45) NOT NULL,
      list_type ENUM('black','white') NOT NULL,
      reason VARCHAR(255),
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
      INDEX idx_user_type (user_id, list_type)
    )`,

        // 7. Traffic Stats
        `CREATE TABLE IF NOT EXISTS traffic_stats (
      id INT AUTO_INCREMENT PRIMARY KEY,
      proxy_port_id INT,
      hour TIMESTAMP NOT NULL,
      bytes_in BIGINT DEFAULT 0,
      bytes_out BIGINT DEFAULT 0,
      connections INT DEFAULT 0,
      blocked_packets INT DEFAULT 0,
      FOREIGN KEY (proxy_port_id) REFERENCES proxy_ports(id) ON DELETE CASCADE,
      INDEX idx_hour (hour),
      INDEX idx_port_hour (proxy_port_id, hour)
    )`,

        // 8. AI Baselines
        `CREATE TABLE IF NOT EXISTS ai_baselines (
      id INT AUTO_INCREMENT PRIMARY KEY,
      proxy_port_id INT,
      hour_of_day TINYINT NOT NULL,
      day_of_week TINYINT NOT NULL,
      avg_pps FLOAT DEFAULT 0, std_pps FLOAT DEFAULT 0,
      avg_bps FLOAT DEFAULT 0, std_bps FLOAT DEFAULT 0,
      avg_conn FLOAT DEFAULT 0, std_conn FLOAT DEFAULT 0,
      avg_syn_ratio FLOAT DEFAULT 0, std_syn_ratio FLOAT DEFAULT 0,
      avg_unique_ips FLOAT DEFAULT 0, std_unique_ips FLOAT DEFAULT 0,
      sample_count INT DEFAULT 0,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      FOREIGN KEY (proxy_port_id) REFERENCES proxy_ports(id) ON DELETE CASCADE,
      UNIQUE KEY uniq_baseline (proxy_port_id, hour_of_day, day_of_week)
    )`,

        // 9. AI Models
        `CREATE TABLE IF NOT EXISTS ai_models (
      id INT AUTO_INCREMENT PRIMARY KEY,
      model_name VARCHAR(100) NOT NULL,
      model_type ENUM('isolation_forest','autoencoder','ensemble') NOT NULL,
      version INT DEFAULT 1,
      accuracy FLOAT,
      false_positive_rate FLOAT,
      model_path VARCHAR(500),
      features_config JSON,
      trained_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      training_samples INT DEFAULT 0,
      is_active BOOLEAN DEFAULT FALSE,
      INDEX idx_active (is_active, model_type)
    )`,

        // 10. AI Detections
        `CREATE TABLE IF NOT EXISTS ai_detections (
      id INT AUTO_INCREMENT PRIMARY KEY,
      proxy_port_id INT,
      model_id INT,
      anomaly_score FLOAT NOT NULL,
      anomaly_type VARCHAR(50),
      features_snapshot JSON,
      action_taken ENUM('log','alert','rate_limit','block') DEFAULT 'log',
      false_positive BOOLEAN DEFAULT FALSE,
      reviewed_by INT,
      detected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (proxy_port_id) REFERENCES proxy_ports(id) ON DELETE SET NULL,
      FOREIGN KEY (model_id) REFERENCES ai_models(id) ON DELETE SET NULL,
      INDEX idx_time (detected_at),
      INDEX idx_score (anomaly_score)
    )`,

        // 11. AI Traffic Snapshots
        `CREATE TABLE IF NOT EXISTS ai_traffic_snapshots (
      id INT AUTO_INCREMENT PRIMARY KEY,
      proxy_port_id INT,
      timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      pps FLOAT, bps FLOAT, conn_count INT, syn_count INT, ack_count INT,
      udp_count INT, unique_src_ips INT, avg_pkt_size FLOAT,
      syn_ack_ratio FLOAT, new_conn_rate FLOAT, geo_entropy FLOAT,
      is_attack BOOLEAN DEFAULT FALSE,
      FOREIGN KEY (proxy_port_id) REFERENCES proxy_ports(id) ON DELETE CASCADE,
      INDEX idx_time (timestamp),
      INDEX idx_port_time (proxy_port_id, timestamp)
    )`
    ];

    for (const sql of tables) {
        try {
            await db.query(sql);
            const match = sql.match(/CREATE TABLE IF NOT EXISTS (\w+)/);
            if (match) console.log(`  ✅ ${match[1]}`);
        } catch (err) {
            console.error(`  ❌ Error: ${err.message}`);
        }
    }

    console.log('[MIGRATE] Done!');
    process.exit(0);
}

runMigrations();
