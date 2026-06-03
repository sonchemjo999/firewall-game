const crypto = require('crypto');

const BASE32_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

function generateSecret(length = 20) {
    const bytes = crypto.randomBytes(length);
    let secret = '';
    for (let i = 0; i < bytes.length; i++) {
        secret += BASE32_CHARS[bytes[i] % 32];
    }
    return secret;
}

function base32Decode(encoded) {
    let bits = '';
    for (const c of encoded.toUpperCase()) {
        const val = BASE32_CHARS.indexOf(c);
        if (val === -1) continue;
        bits += val.toString(2).padStart(5, '0');
    }
    const bytes = [];
    for (let i = 0; i + 8 <= bits.length; i += 8) {
        bytes.push(parseInt(bits.substr(i, 8), 2));
    }
    return Buffer.from(bytes);
}

function generateTOTP(secret, timeStep = 30, digits = 6) {
    const time = Math.floor(Date.now() / 1000 / timeStep);
    const buffer = Buffer.alloc(8);
    buffer.writeUInt32BE(0, 0);
    buffer.writeUInt32BE(time, 4);

    const key = base32Decode(secret);
    const hmac = crypto.createHmac('sha1', key).update(buffer).digest();
    const offset = hmac[hmac.length - 1] & 0xf;
    const code = ((hmac[offset] & 0x7f) << 24 |
                  (hmac[offset + 1] & 0xff) << 16 |
                  (hmac[offset + 2] & 0xff) << 8 |
                  (hmac[offset + 3] & 0xff)) % Math.pow(10, digits);

    return code.toString().padStart(digits, '0');
}

function verifyTOTP(secret, token, window = 1) {
    for (let i = -window; i <= window; i++) {
        const time = Math.floor(Date.now() / 1000 / 30) + i;
        const buffer = Buffer.alloc(8);
        buffer.writeUInt32BE(0, 0);
        buffer.writeUInt32BE(time, 4);

        const key = base32Decode(secret);
        const hmac = crypto.createHmac('sha1', key).update(buffer).digest();
        const offset = hmac[hmac.length - 1] & 0xf;
        const code = ((hmac[offset] & 0x7f) << 24 |
                      (hmac[offset + 1] & 0xff) << 16 |
                      (hmac[offset + 2] & 0xff) << 8 |
                      (hmac[offset + 3] & 0xff)) % 1000000;

        if (code.toString().padStart(6, '0') === token) {
            return true;
        }
    }
    return false;
}

function generateBackupCodes(count = 8) {
    const codes = [];
    for (let i = 0; i < count; i++) {
        codes.push(crypto.randomBytes(4).toString('hex').toUpperCase());
    }
    return codes;
}

function getOtpAuthUrl(secret, username, issuer = 'NROShield') {
    return `otpauth://totp/${issuer}:${encodeURIComponent(username)}?secret=${secret}&issuer=${issuer}&algorithm=SHA1&digits=6&period=30`;
}

module.exports = { generateSecret, verifyTOTP, generateBackupCodes, getOtpAuthUrl, generateTOTP };
