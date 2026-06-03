require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

const { Bot, InlineKeyboard, session } = require('grammy');
const axios = require('axios');

const API_URL = `http://127.0.0.1:${process.env.API_PORT || 5000}`;
const BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN;

if (!BOT_TOKEN) {
    console.log('[BOT] TELEGRAM_BOT_TOKEN chưa cấu hình trong .env');
    process.exit(1);
}

const bot = new Bot(BOT_TOKEN);

// Session storage
bot.use(session({ initial: () => ({ token: null, step: null, data: {} }) }));

// === Helper ===
async function apiCall(method, endpoint, data = null, token = null) {
    try {
        const headers = {};
        if (token) headers['Authorization'] = `Bearer ${token}`;

        const url = `${API_URL}${endpoint}`;
        const config = {
            method: method.toLowerCase(),
            url,
            headers,
            timeout: 10000
        };

        // Chỉ gửi body + Content-Type cho POST/PUT (không gửi cho GET/DELETE)
        if (data && ['post', 'put', 'patch'].includes(config.method)) {
            config.data = data;
            config.headers['Content-Type'] = 'application/json';
        }

        const res = await axios(config);
        return res.data;
    } catch (err) {
        return { error: err.response?.data?.error || err.message };
    }
}

// === /start ===
bot.command('start', async (ctx) => {
    const kb = new InlineKeyboard()
        .text('🔑 Đăng nhập', 'login')
        .text('📝 Đăng ký', 'register').row()
        .text('📊 Trạng thái', 'status')
        .text('❓ Hướng dẫn', 'help');

    await ctx.reply(
        `🛡️ *NRO Shield Bot*\n\nChào ${ctx.from.first_name}! Tôi là bot quản lý NRO Shield.\n\nChọn một tùy chọn:`,
        { parse_mode: 'Markdown', reply_markup: kb }
    );
});

// === /help ===
bot.command('help', async (ctx) => {
    await ctx.reply(
        `📖 *NRO Shield Bot — Hướng dẫn*\n\n` +
        `*🔐 Tài khoản:*\n` +
        `/login — Đăng nhập\n` +
        `/start — Menu chính\n\n` +
        `*🖥️ Server:*\n` +
        `/servers — Danh sách server\n` +
        `/addserver — Thêm server mới\n` +
        `/delserver — Xóa server\n\n` +
        `*🔀 Proxy:*\n` +
        `/proxies — Danh sách proxy\n` +
        `/addproxy — Tạo proxy mới\n` +
        `/delproxy — Xóa proxy\n` +
        `/toggleproxy — Bật/Tắt proxy\n\n` +
        `*📊 Theo dõi:*\n` +
        `/stats — Dashboard tổng quan\n` +
        `/attacks — Tấn công gần đây\n\n` +
        `*👑 Admin:*\n` +
        `/createkey — Tạo license key\n` +
        `/delkey — Thu hồi/xóa key\n` +
        `/keys — Danh sách keys\n` +
        `/users — Danh sách users\n` +
        `/system — Trạng thái VPS\n` +
        `/firewall — Xem firewall rules`,
        { parse_mode: 'Markdown' }
    );
});

// === /login ===
bot.command('login', async (ctx) => {
    ctx.session.step = 'login_username';
    await ctx.reply('👤 Nhập username:');
});

// === /addserver ===
bot.command('addserver', async (ctx) => {
    if (!ctx.session.token) return ctx.reply('❌ Đăng nhập trước: /login');
    ctx.session.step = 'add_server_name';
    await ctx.reply('📛 Nhập tên server (ví dụ: NRO Server 1):');
});

// === /delserver ===
bot.command('delserver', async (ctx) => {
    if (!ctx.session.token) return ctx.reply('❌ Đăng nhập trước: /login');
    const data = await apiCall('get', '/api/servers', null, ctx.session.token);
    if (data.error) return ctx.reply('❌ ' + data.error);
    if (!data.length) return ctx.reply('📭 Bạn chưa có server nào.');

    const kb = new InlineKeyboard();
    let msg = '🗑️ *Chọn server muốn xóa:*\n\n';
    data.forEach(s => {
        msg += `• *${s.name}* (${s.target_ip})\n`;
        kb.text(`🗑️ Xóa ${s.name}`, `confirm_del_srv_${s.id}`).row();
    });

    await ctx.reply(msg, { parse_mode: 'Markdown', reply_markup: kb });
});

// === /addproxy ===
bot.command('addproxy', async (ctx) => {
    if (!ctx.session.token) return ctx.reply('❌ Đăng nhập trước: /login');
    ctx.session.step = 'add_proxy_server';

    const data = await apiCall('get', '/api/servers', null, ctx.session.token);
    if (data.error) return ctx.reply('❌ ' + data.error);
    if (!Array.isArray(data) || !data.length) return ctx.reply('❌ Chưa có server. Dùng /addserver');

    let msg = '🖥️ *Chọn server:*\n\n';
    const kb = new InlineKeyboard();
    data.forEach((s) => {
        msg += `ID ${s.id}: ${s.name} (${s.target_ip})\n`;
        kb.text(`${s.id}: ${s.name}`, `select_server_${s.id}`).row();
    });

    await ctx.reply(msg, { parse_mode: 'Markdown', reply_markup: kb });
});

// === /servers ===
bot.command('servers', async (ctx) => {
    if (!ctx.session.token) return ctx.reply('❌ /login trước');
    const data = await apiCall('get', '/api/servers', null, ctx.session.token);
    if (data.error) return ctx.reply('❌ ' + data.error);
    if (!data.length) return ctx.reply('📭 Chưa có server. Dùng /addserver');

    let msg = '🖥️ *Danh sách server:*\n\n';
    data.forEach(s => { msg += `• *${s.name}* — ${s.target_ip} (${s.port_count || 0} ports)\n`; });
    await ctx.reply(msg, { parse_mode: 'Markdown' });
});

// === /proxies ===
bot.command('proxies', async (ctx) => {
    if (!ctx.session.token) return ctx.reply('❌ /login trước');
    const data = await apiCall('get', '/api/proxy', null, ctx.session.token);
    if (data.error) return ctx.reply('❌ ' + data.error);
    if (!data.length) return ctx.reply('📭 Chưa có proxy. Dùng /addproxy');

    let msg = '🔀 *Danh sách proxy:*\n\n';
    data.forEach(p => {
        const status = p.is_active ? '🟢' : '🔴';
        msg += `${status} \`${p.proxy_address}\` → ${p.target_address} (${p.protocol})\n`;
    });
    await ctx.reply(msg, { parse_mode: 'Markdown' });
});

// === /stats (enhanced) ===
bot.command('stats', async (ctx) => {
    if (!ctx.session.token) return ctx.reply('❌ /login trước');
    const data = await apiCall('get', '/api/stats/summary', null, ctx.session.token);
    if (data.error) return ctx.reply('❌ ' + data.error);

    // Thêm AI status
    let aiStatus = 'Offline';
    try {
        const aiRes = await axios.get(`${API_URL.replace(':5000', ':8000')}/status`, { timeout: 3000 });
        aiStatus = aiRes.data.models_loaded ? '🟢 Active' : '📚 Learning';
    } catch { }

    await ctx.reply(
        `📊 *NRO Shield Dashboard*\n\n` +
        `🖥️ Servers: *${data.total_servers}*\n` +
        `🔀 Active Ports: *${data.active_ports}/${data.total_ports}*\n` +
        `⚡ Attacks today: *${data.attacks_today}*\n` +
        `🤖 AI Engine: ${aiStatus}\n\n` +
        `⏰ _${new Date().toLocaleString('vi-VN')}_`,
        { parse_mode: 'Markdown' }
    );
});

// === /attacks ===
bot.command('attacks', async (ctx) => {
    if (!ctx.session.token) return ctx.reply('❌ /login trước');
    const data = await apiCall('get', '/api/stats/attacks?limit=5', null, ctx.session.token);
    if (data.error) return ctx.reply('❌ ' + data.error);
    if (!data.length) return ctx.reply('✅ Chưa có tấn công nào!');

    let msg = '🚨 *Tấn công gần đây:*\n\n';
    data.forEach(a => {
        msg += `• \`${a.attack_type}\` — ${a.attacker_ip} (${a.packets_blocked || 0} pkts)\n`;
    });
    await ctx.reply(msg, { parse_mode: 'Markdown' });
});

// === /system — Admin: System info ===
bot.command('system', async (ctx) => {
    if (!ctx.session.token) return ctx.reply('❌ /login trước');

    try {
        const { execSync } = require('child_process');
        const uptime = execSync('uptime -p').toString().trim();
        const load = execSync("cat /proc/loadavg | awk '{print $1, $2, $3}'").toString().trim();
        const mem = execSync("free -m | awk '/Mem:/ {printf \"%d/%dMB (%.0f%%)\", $3, $2, $3*100/$2}'").toString().trim();
        const disk = execSync("df -h / | awk 'NR==2 {printf \"%s/%s (%s)\", $3, $2, $5}'").toString().trim();
        const conns = execSync("ss -s | head -2").toString().trim();

        // Service statuses
        const services = ['nginx', 'nroshield-api', 'nroshield-ai', 'nroshield-bot'];
        let svcStatus = '';
        services.forEach(svc => {
            try {
                execSync(`systemctl is-active ${svc}`, { encoding: 'utf8' });
                svcStatus += `  🟢 ${svc}\n`;
            } catch {
                svcStatus += `  🔴 ${svc}\n`;
            }
        });

        // IPtables rules count
        const iptRules = execSync("iptables -L INPUT -n | wc -l").toString().trim();

        await ctx.reply(
            `🖥️ *System Status*\n\n` +
            `⏱ Uptime: ${uptime}\n` +
            `📈 Load: ${load}\n` +
            `💾 RAM: ${mem}\n` +
            `💿 Disk: ${disk}\n\n` +
            `*Services:*\n${svcStatus}\n` +
            `🔥 Firewall rules: ${iptRules}\n` +
            `🔌 ${conns}`,
            { parse_mode: 'Markdown' }
        );
    } catch (err) {
        await ctx.reply('❌ Lỗi: ' + err.message);
    }
});

// === /createkey — Admin: Create license key ===
bot.command('createkey', async (ctx) => {
    if (!ctx.session.token) return ctx.reply('❌ /login trước');
    ctx.session.step = 'create_key';
    await ctx.reply(
        '🔑 *Tạo Key mới*\n\n' +
        'Nhập theo format: `servers ports days`\n' +
        'Ví dụ: `2 5 30` = 2 server, 5 port/server, 30 ngày\n\n' +
        'Hoặc nhập `1 3 30` cho key mặc định.',
        { parse_mode: 'Markdown' }
    );
});

// === /keys — Admin: List all keys ===
bot.command('keys', async (ctx) => {
    if (!ctx.session.token) return ctx.reply('❌ /login trước');
    const data = await apiCall('get', '/api/keys', null, ctx.session.token);
    if (data.error) return ctx.reply('❌ ' + data.error);
    if (!data.length) return ctx.reply('📭 Chưa có key nào.');

    let msg = '🔑 *Danh sách License Keys:*\n\n';
    data.forEach(k => {
        const status = k.status === 'active' ? '🟢' : '🔴';
        const user = k.assigned_to || '_chưa assign_';
        const expire = k.expires_at ? new Date(k.expires_at).toLocaleDateString('vi') : '∞';
        msg += `${status} \`${k.key_code}\`\n` +
            `   User: ${user} | ${k.max_servers}sv/${k.max_ports_per_server}port | Hạn: ${expire}\n\n`;
    });

    await ctx.reply(msg, { parse_mode: 'Markdown' });
});

// === /users — Admin: List all users ===
bot.command('users', async (ctx) => {
    if (!ctx.session.token) return ctx.reply('❌ /login trước');
    const data = await apiCall('get', '/api/admin/users', null, ctx.session.token);
    if (data.error) return ctx.reply('❌ ' + data.error);
    if (!data.length) return ctx.reply('📭 Chưa có user nào.');

    let msg = '👥 *Danh sách Users:*\n\n';
    data.forEach(u => {
        const status = u.is_active ? '🟢' : '🔴';
        const role = u.role === 'admin' ? '👑' : '👤';
        msg += `${status} ${role} *${u.username}* (ID: ${u.id})\n` +
            `   Key: \`${u.active_key || u.key_code || 'không có'}\` | Svr: ${u.server_count || 0} | Tạo: ${new Date(u.created_at).toLocaleDateString('vi')}\n\n`;
    });

    await ctx.reply(msg, { parse_mode: 'Markdown' });
});

// === /delproxy — Delete a proxy ===
bot.command('delproxy', async (ctx) => {
    if (!ctx.session.token) return ctx.reply('❌ /login trước');
    const data = await apiCall('get', '/api/proxy', null, ctx.session.token);
    if (data.error) return ctx.reply('❌ ' + data.error);
    if (!data.length) return ctx.reply('📭 Chưa có proxy nào.');

    const kb = new InlineKeyboard();
    let msg = '🗑️ *Chọn proxy muốn xóa:*\n\n';
    data.forEach(p => {
        const status = p.is_active ? '🟢' : '🔴';
        msg += `${status} \`${p.proxy_address}\` → ${p.target_address}\n`;
        kb.text(`🗑️ ${p.proxy_address}`, `del_proxy_${p.id}`).row();
    });

    await ctx.reply(msg, { parse_mode: 'Markdown', reply_markup: kb });
});

// === /toggleproxy — Toggle proxy on/off ===
bot.command('toggleproxy', async (ctx) => {
    if (!ctx.session.token) return ctx.reply('❌ /login trước');
    const data = await apiCall('get', '/api/proxy', null, ctx.session.token);
    if (data.error) return ctx.reply('❌ ' + data.error);
    if (!data.length) return ctx.reply('📭 Chưa có proxy nào.');

    const kb = new InlineKeyboard();
    let msg = '🔀 *Bật/Tắt proxy:*\n\n';
    data.forEach(p => {
        const status = p.is_active ? '🟢 ON' : '🔴 OFF';
        const action = p.is_active ? 'Tắt' : 'Bật';
        msg += `${status} \`${p.proxy_address}\` → ${p.target_address}\n`;
        kb.text(`${p.is_active ? '🔴' : '🟢'} ${action} ${p.proxy_address}`, `toggle_${p.id}`).row();
    });

    await ctx.reply(msg, { parse_mode: 'Markdown', reply_markup: kb });
});

// === /delkey — Admin: Delete/Revoke a key ===
bot.command('delkey', async (ctx) => {
    if (!ctx.session.token) return ctx.reply('❌ /login trước');
    const data = await apiCall('get', '/api/keys', null, ctx.session.token);
    if (data.error) return ctx.reply('❌ ' + data.error);
    if (!Array.isArray(data) || !data.length) return ctx.reply('📭 Chưa có key nào.');

    const kb = new InlineKeyboard();
    let msg = '🗑️ *Chọn key muốn thu hồi/xóa:*\n\n';
    data.forEach(k => {
        const status = k.status === 'active' ? '🟢' : '🔴';
        const user = k.assigned_to || 'chưa assign';
        msg += `${status} \`${k.key_code.substring(0, 16)}...\` (${user})\n`;
        kb.text(`${status} ${k.key_code.substring(0, 12)}...`, `revoke_key_${k.id}`).row();
    });

    await ctx.reply(msg, { parse_mode: 'Markdown', reply_markup: kb });
});

// === /firewall — Quick firewall info ===
bot.command('firewall', async (ctx) => {
    if (!ctx.session.token) return ctx.reply('❌ /login trước');
    try {
        const { execSync } = require('child_process');
        const inputCount = execSync("iptables -L INPUT -n | wc -l").toString().trim();
        const natCount = execSync("iptables -t nat -L PREROUTING -n | wc -l").toString().trim();
        const fwdCount = execSync("iptables -L FORWARD -n | wc -l").toString().trim();
        const nat = execSync("iptables -t nat -L PREROUTING -n --line-numbers | tail -10").toString().trim();

        // Giới hạn độ dài để không bị Telegram chặn (max 4096 chars)
        const natTruncated = nat.length > 2000 ? nat.substring(0, 2000) + '\n...(truncated)' : nat;

        await ctx.reply(
            `🔥 *Firewall Status*\n\n` +
            `📋 INPUT rules: *${inputCount}*\n` +
            `📋 FORWARD rules: *${fwdCount}*\n` +
            `📋 NAT PREROUTING rules: *${natCount}*\n\n` +
            `*NAT rules (last 10):*\n\`\`\`\n${natTruncated}\n\`\`\``,
            { parse_mode: 'Markdown' }
        );
    } catch (err) {
        await ctx.reply('❌ ' + err.message);
    }
});

// === Updated Callback queries (add new handlers) ===
bot.on('callback_query:data', async (ctx) => {
    const data = ctx.callbackQuery.data;

    if (data === 'login') {
        ctx.session.step = 'login_username';
        await ctx.reply('👤 Nhập username:');
    } else if (data === 'register') {
        ctx.session.step = 'register_username';
        await ctx.reply('👤 Nhập username mới:');
    } else if (data === 'status') {
        await ctx.reply('Dùng /stats để xem thống kê');
    } else if (data === 'help') {
        await ctx.reply('Dùng /help để xem hướng dẫn');
    } else if (data.startsWith('select_server_')) {
        const serverId = data.replace('select_server_', '');
        ctx.session.data.server_id = parseInt(serverId);
        ctx.session.step = 'add_proxy_port';
        await ctx.reply('🔢 Nhập port game cần bảo vệ (ví dụ: 14445):');
    } else if (data.startsWith('confirm_del_srv_')) {
        const serverId = data.replace('confirm_del_srv_', '');
        const res = await apiCall('delete', `/api/servers/${serverId}`, null, ctx.session.token);
        await ctx.reply(res.error ? '❌ Lỗi: ' + res.error : '✅ Đã xóa server và các proxy liên quan.');
    } else if (data.startsWith('del_proxy_')) {
        const proxyId = data.replace('del_proxy_', '');
        const res = await apiCall('delete', `/api/proxy/${proxyId}`, null, ctx.session.token);
        await ctx.reply(res.error ? '❌ Lỗi: ' + res.error : '✅ Proxy đã xóa, NAT rule đã gỡ.');
    } else if (data.startsWith('revoke_key_')) {
        const keyId = data.replace('revoke_key_', '');
        const res = await apiCall('delete', `/api/keys/${keyId}`, null, ctx.session.token);
        await ctx.reply(res.error ? '❌ Lỗi: ' + res.error : '✅ Key đã thu hồi, proxy đã tắt.');
    } else if (data.startsWith('toggle_')) {
        const proxyId = data.replace('toggle_', '');
        const res = await apiCall('put', `/api/proxy/${proxyId}/toggle`, {}, ctx.session.token);
        await ctx.reply(res.error ? '❌ ' + res.error : `✅ ${res.message}`);
    }

    await ctx.answerCallbackQuery();
});

// === Message handler (multi-step flows) ===
bot.on('message:text', async (ctx) => {
    const step = ctx.session.step;
    const text = ctx.message.text;

    if (!step) return;

    // Login flow
    if (step === 'login_username') {
        ctx.session.data.username = text;
        ctx.session.step = 'login_password';
        await ctx.reply('🔒 Nhập password:');

    } else if (step === 'login_password') {
        const res = await apiCall('post', '/api/auth/login', {
            username: ctx.session.data.username,
            password: text
        });
        ctx.session.step = null;

        if (res.error) {
            await ctx.reply('❌ ' + res.error);
        } else {
            ctx.session.token = res.token;
            const isAdmin = res.user.role === 'admin';
            let msg = `✅ Đăng nhập thành công! Xin chào *${res.user.username}*\n\n`;
            msg += `*Lệnh cơ bản:*\n`;
            msg += `/servers — Danh sách server\n`;
            msg += `/proxies — Danh sách proxy\n`;
            msg += `/addserver — Thêm server\n`;
            msg += `/addproxy — Tạo proxy\n`;
            msg += `/stats — Thống kê\n`;
            if (isAdmin) {
                msg += `\n*Lệnh Admin:*\n`;
                msg += `/createkey — Tạo key\n`;
                msg += `/keys — Danh sách keys\n`;
                msg += `/users — Danh sách users\n`;
                msg += `/system — Trạng thái VPS\n`;
                msg += `/firewall — Xem firewall rules\n`;
            }
            await ctx.reply(msg, { parse_mode: 'Markdown' });
        }

        // Register flow
    } else if (step === 'register_username') {
        ctx.session.data.username = text;
        ctx.session.step = 'register_password';
        await ctx.reply('🔒 Nhập password:');

    } else if (step === 'register_password') {
        ctx.session.data.password = text;
        ctx.session.step = 'register_key';
        await ctx.reply('🔑 Nhập key license (ví dụ: NRO-XXXX...):');

    } else if (step === 'register_key') {
        const res = await apiCall('post', '/api/auth/register', {
            username: ctx.session.data.username,
            password: ctx.session.data.password,
            key_code: text,
            telegram_id: ctx.from.id
        });
        ctx.session.step = null;

        if (res.error) {
            await ctx.reply('❌ ' + res.error);
        } else {
            ctx.session.token = res.token;
            await ctx.reply(`✅ Đăng ký thành công! Chào *${res.user.username}*\n\nDùng /addserver để thêm server game.`,
                { parse_mode: 'Markdown' });
        }

        // Add server flow
    } else if (step === 'add_server_name') {
        ctx.session.data.server_name = text;
        ctx.session.step = 'add_server_ip';
        await ctx.reply('🌐 Nhập IP server game (ví dụ: 103.77.246.157):');

    } else if (step === 'add_server_ip') {
        const res = await apiCall('post', '/api/servers', {
            name: ctx.session.data.server_name,
            target_ip: text
        }, ctx.session.token);
        ctx.session.step = null;

        if (res.error) {
            await ctx.reply('❌ ' + res.error);
        } else {
            await ctx.reply(`✅ Server "${res.server.name}" (${res.server.target_ip}) đã thêm!\n\nDùng /addproxy để tạo proxy.`);
        }

        // Add proxy flow
    } else if (step === 'add_proxy_port') {
        const port = parseInt(text);
        if (isNaN(port) || port < 1 || port > 65535) {
            return ctx.reply('❌ Port phải từ 1-65535');
        }

        const res = await apiCall('post', '/api/proxy/create', {
            server_id: ctx.session.data.server_id,
            target_port: port
        }, ctx.session.token);
        ctx.session.step = null;

        if (res.error) {
            await ctx.reply('❌ ' + res.error);
        } else {
            await ctx.reply(
                `✅ *Proxy đã tạo!*\n\n` +
                `📥 Kết nối game qua: \`${res.proxy.proxy_address}\`\n` +
                `📤 Forward tới: ${res.proxy.target_address}\n` +
                `📡 Protocol: ${res.proxy.protocol}\n\n` +
                `_Thay IP server game bằng IP trên để chơi qua Shield_`,
                { parse_mode: 'Markdown' }
            );
        }

        // Create key flow
    } else if (step === 'create_key') {
        const parts = text.trim().split(/\s+/);
        const max_servers = parseInt(parts[0]) || 1;
        const max_ports = parseInt(parts[1]) || 3;
        const days = parseInt(parts[2]) || 30;

        const res = await apiCall('post', '/api/keys', {
            max_servers,
            max_ports_per_server: max_ports,
            expires_days: days
        }, ctx.session.token);
        ctx.session.step = null;

        if (res.error) {
            await ctx.reply('❌ ' + res.error);
        } else {
            await ctx.reply(
                `✅ *Key đã tạo!*\n\n` +
                `🔑 \`${res.key.key_code}\`\n\n` +
                `📋 Max servers: ${max_servers}\n` +
                `📋 Max ports/server: ${max_ports}\n` +
                `📋 Hạn: ${days} ngày\n\n` +
                `_Gửi key này cho user để đăng ký_`,
                { parse_mode: 'Markdown' }
            );
        }
    }
});

// Error handler
bot.catch((err) => {
    console.error('[BOT] Error:', err.message);
});

// === Startup notification ===
const CHAT_ID = process.env.TELEGRAM_CHAT_ID;

bot.start();
console.log('[NRO Shield Bot] Started');

// Send startup alert
if (CHAT_ID) {
    setTimeout(async () => {
        try {
            await bot.api.sendMessage(CHAT_ID,
                `🛡️ *NRO Shield Bot Online!*\n\n` +
                `⏰ ${new Date().toLocaleString('vi-VN')}\n` +
                `🖥️ Server: ${process.env.VPS_PUBLIC_IP || 'N/A'}\n\n` +
                `Gõ /start để bắt đầu.`,
                { parse_mode: 'Markdown' }
            );
        } catch (err) {
            console.error('[BOT] Startup alert error:', err.message);
        }
    }, 2000);
}

