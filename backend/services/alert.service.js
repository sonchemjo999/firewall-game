const axios = require('axios');
const config = require('../config/config');

/**
 * Gửi cảnh báo qua Telegram Bot
 */
async function sendAlert(message, parseMode = 'HTML') {
    if (!config.TELEGRAM_BOT_TOKEN || !config.TELEGRAM_CHAT_ID) return;

    try {
        await axios.post(`https://api.telegram.org/bot${config.TELEGRAM_BOT_TOKEN}/sendMessage`, {
            chat_id: config.TELEGRAM_CHAT_ID,
            text: message,
            parse_mode: parseMode
        }, { timeout: 5000 });
    } catch (err) {
        console.error('[ALERT] Telegram send error:', err.message);
    }
}

/**
 * Gửi cảnh báo tấn công
 */
async function sendAttackAlert({ serverName, proxyPort, targetAddress, attackType, anomalyScore, attackerIp, packetsBlocked }) {
    const msg = `🚨 <b>CẢNH BÁO TẤN CÔNG</b>

🎯 Server: ${serverName}
🔀 Proxy: ${proxyPort} → ${targetAddress}
⚡ Loại: ${attackType}
📊 Anomaly Score: ${anomalyScore}/1.0
📌 Top IP: ${attackerIp}
📈 Packets blocked: ${packetsBlocked?.toLocaleString() || 'N/A'}
⏰ ${new Date().toLocaleString('vi-VN')}`;

    await sendAlert(msg);
}

/**
 * Gửi cảnh báo key sắp hết hạn
 */
async function sendKeyExpiryAlert(username, keyCode, daysLeft) {
    const msg = `⏳ <b>KEY SẮP HẾT HẠN</b>

👤 User: ${username}
🔑 Key: ${keyCode}
📅 Còn lại: ${daysLeft} ngày
⏰ ${new Date().toLocaleString('vi-VN')}`;

    await sendAlert(msg);
}

module.exports = { sendAlert, sendAttackAlert, sendKeyExpiryAlert };
