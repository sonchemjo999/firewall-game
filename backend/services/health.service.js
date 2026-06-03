const db = require('../config/database');
const { exec } = require('child_process');
const net = require('net');

function pingHost(host, timeout = 5000) {
    return new Promise((resolve) => {
        const safeHost = host.replace(/[^0-9.]/g, '');
        exec(`ping -c 1 -W 3 ${safeHost}`, { timeout }, (err, stdout) => {
            if (err) return resolve({ alive: false, latency: null });
            const match = stdout.match(/time=([\d.]+)/);
            resolve({ alive: true, latency: match ? parseFloat(match[1]) : null });
        });
    });
}

function checkPort(host, port, timeout = 3000) {
    return new Promise((resolve) => {
        const socket = new net.Socket();
        const safeHost = host.replace(/[^0-9.]/g, '');
        socket.setTimeout(timeout);
        socket.on('connect', () => { socket.destroy(); resolve(true); });
        socket.on('error', () => { socket.destroy(); resolve(false); });
        socket.on('timeout', () => { socket.destroy(); resolve(false); });
        socket.connect(port, safeHost);
    });
}

async function checkServerHealth(server) {
    const ip = server.target_ip;
    const ping = await pingHost(ip);
    let portOpen = false;

    const [proxies] = await db.query(
        'SELECT target_port FROM proxies WHERE server_id = ? AND is_active = 1 LIMIT 1',
        [server.id]
    );
    if (proxies.length > 0) {
        portOpen = await checkPort(ip, proxies[0].target_port);
    }

    const status = ping.alive ? (portOpen ? 'online' : 'degraded') : 'offline';

    await db.query(
        'INSERT INTO server_health (server_id, status, latency_ms, port_open) VALUES (?, ?, ?, ?)',
        [server.id, status, ping.latency, portOpen ? 1 : 0]
    );

    return { server_id: server.id, status, latency: ping.latency, port_open: portOpen };
}

async function checkAllServers() {
    const [servers] = await db.query('SELECT id, target_ip, name FROM servers');
    const results = [];
    for (const server of servers) {
        try {
            const result = await checkServerHealth(server);
            results.push(result);
        } catch (err) {
            results.push({ server_id: server.id, status: 'offline', error: err.message });
        }
    }
    return results;
}

async function getHealthHistory(serverId, hours = 24) {
    const [rows] = await db.query(
        `SELECT status, latency_ms, port_open, checked_at
         FROM server_health WHERE server_id = ?
         AND checked_at >= DATE_SUB(NOW(), INTERVAL ? HOUR)
         ORDER BY checked_at DESC`,
        [serverId, hours]
    );
    return rows;
}

async function getHealthSummary() {
    const [rows] = await db.query(
        `SELECT s.id, s.name, s.target_ip,
                (SELECT sh.status FROM server_health sh WHERE sh.server_id = s.id ORDER BY sh.checked_at DESC LIMIT 1) as current_status,
                (SELECT sh.latency_ms FROM server_health sh WHERE sh.server_id = s.id ORDER BY sh.checked_at DESC LIMIT 1) as latency,
                (SELECT COUNT(*) FROM server_health sh WHERE sh.server_id = s.id AND sh.status = 'offline' AND sh.checked_at >= DATE_SUB(NOW(), INTERVAL 24 HOUR)) as offline_count_24h
         FROM servers s ORDER BY s.name`
    );
    return rows;
}

module.exports = { checkServerHealth, checkAllServers, getHealthHistory, getHealthSummary };
