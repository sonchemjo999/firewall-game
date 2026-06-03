module.exports = {
    DB_HOST: process.env.DB_HOST || '127.0.0.1',
    DB_PORT: parseInt(process.env.DB_PORT || '3306'),
    DB_USER: process.env.DB_USER || 'nroshield',
    DB_PASS: process.env.DB_PASS || '',
    DB_NAME: process.env.DB_NAME || 'nroshield',
    JWT_SECRET: process.env.JWT_SECRET || 'change-this-secret',
    JWT_EXPIRES_IN: process.env.JWT_EXPIRES_IN || '7d',
    API_PORT: parseInt(process.env.API_PORT || '80'),
    VPS_PUBLIC_IP: process.env.VPS_PUBLIC_IP || '',
    PROXY_PORT_RANGE_START: parseInt(process.env.PROXY_PORT_RANGE_START || '30000'),
    PROXY_PORT_RANGE_END: parseInt(process.env.PROXY_PORT_RANGE_END || '60000'),
    MAX_CONN_PER_IP: parseInt(process.env.MAX_CONN_PER_IP || '50'),
    TELEGRAM_BOT_TOKEN: process.env.TELEGRAM_BOT_TOKEN || '',
    TELEGRAM_CHAT_ID: process.env.TELEGRAM_CHAT_ID || '',
    AI_ENGINE_PORT: parseInt(process.env.AI_ENGINE_PORT || '8000'),
    AI_BLOCK_THRESHOLD: parseFloat(process.env.AI_BLOCK_THRESHOLD || '0.8'),
    AI_RATE_LIMIT_THRESHOLD: parseFloat(process.env.AI_RATE_LIMIT_THRESHOLD || '0.6')
};
