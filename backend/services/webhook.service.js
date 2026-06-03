const db = require('../config/database');
const axios = require('axios');

async function triggerWebhooks(eventType, data) {
    try {
        const [hooks] = await db.query(
            'SELECT * FROM webhooks WHERE is_active = 1'
        );

        for (const hook of hooks) {
            const events = hook.events ? JSON.parse(hook.events) : ['all'];
            if (!events.includes('all') && !events.includes(eventType)) continue;

            try {
                let payload;
                switch (hook.type) {
                    case 'discord':
                        payload = formatDiscord(eventType, data);
                        break;
                    case 'slack':
                        payload = formatSlack(eventType, data);
                        break;
                    default:
                        payload = { event: eventType, data, timestamp: new Date().toISOString() };
                }

                await axios.post(hook.url, payload, { timeout: 5000 });
                await db.query('UPDATE webhooks SET last_triggered_at = NOW() WHERE id = ?', [hook.id]);
            } catch (err) {
                console.error(`[Webhook] Failed to send to ${hook.name}:`, err.message);
            }
        }
    } catch (err) {
        console.error('[Webhook] Error:', err.message);
    }
}

function formatDiscord(event, data) {
    const colors = { attack_detected: 0xFF4757, attack_mitigated: 0x00F5A0, server_offline: 0xFFA500 };
    return {
        embeds: [{
            title: `NRO Shield: ${event.replace(/_/g, ' ').toUpperCase()}`,
            description: data.message || JSON.stringify(data),
            color: colors[event] || 0x6C63FF,
            timestamp: new Date().toISOString(),
            footer: { text: 'NRO Shield v2.1' }
        }]
    };
}

function formatSlack(event, data) {
    const emoji = { attack_detected: ':rotating_light:', attack_mitigated: ':white_check_mark:', server_offline: ':warning:' };
    return {
        text: `${emoji[event] || ':shield:'} *NRO Shield*: ${event.replace(/_/g, ' ')}`,
        attachments: [{
            color: event.includes('attack') ? '#FF4757' : '#6C63FF',
            text: data.message || JSON.stringify(data),
            ts: Math.floor(Date.now() / 1000)
        }]
    };
}

module.exports = { triggerWebhooks };
