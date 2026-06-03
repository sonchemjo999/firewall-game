const db = require('../config/database');

/**
 * Tạo notification cho user
 */
async function createNotification(userId, title, message, type = 'info', link = null) {
    try {
        await db.query(
            'INSERT INTO notifications (user_id, title, message, type, link) VALUES (?, ?, ?, ?, ?)',
            [userId, title, message, type, link]
        );
    } catch (err) {
        console.error('[NOTIFICATION] Create error:', err.message);
    }
}

/**
 * Tạo notification cho tất cả users
 */
async function broadcastNotification(title, message, type = 'info') {
    try {
        const [users] = await db.query('SELECT id FROM users WHERE is_active = TRUE');
        for (const user of users) {
            await createNotification(user.id, title, message, type);
        }
    } catch (err) {
        console.error('[NOTIFICATION] Broadcast error:', err.message);
    }
}

/**
 * Lấy notifications chưa đọc
 */
async function getUnreadCount(userId) {
    const [[{ count }]] = await db.query(
        'SELECT COUNT(*) as count FROM notifications WHERE user_id = ? AND is_read = FALSE',
        [userId]
    );
    return count;
}

module.exports = { createNotification, broadcastNotification, getUnreadCount };
