const { exec } = require('child_process');
const util = require('util');
const execAsync = util.promisify(exec);

/**
 * Thêm NAT rule (DNAT + SNAT) cho proxy port
 */
async function addNatRule(proxyPort, targetIp, targetPort, protocol = 'tcp') {
    try {
        // Validate inputs chống injection
        if (!/^\d+$/.test(String(proxyPort)) || !/^\d+$/.test(String(targetPort))) {
            return { success: false, error: 'Port không hợp lệ' };
        }
        if (!/^(\d{1,3}\.){3}\d{1,3}$/.test(targetIp)) {
            return { success: false, error: 'IP không hợp lệ' };
        }

        const proto = protocol === 'both' ? ['tcp', 'udp'] : [protocol];

        for (const p of proto) {
            // Kiểm tra xem rule đã tồn tại chưa để tránh trùng lặp
            const checkDnat = `iptables -t nat -C PREROUTING -p ${p} --dport ${proxyPort} -j DNAT --to-destination ${targetIp}:${targetPort} 2>/dev/null`;
            const { stdout: exists } = await execAsync(checkDnat).catch(() => ({ stdout: '' }));

            if (!exists) {
                // DNAT: redirect incoming traffic tới target
                await execAsync(
                    `iptables -t nat -I PREROUTING -p ${p} --dport ${proxyPort} -j DNAT --to-destination ${targetIp}:${targetPort}`
                );

                // Allow FORWARD cho traffic này
                await execAsync(
                    `iptables -I FORWARD -p ${p} -d ${targetIp} --dport ${targetPort} -j ACCEPT`
                );

                // SNAT: Sử dụng SNAT thay vì MASQUERADE để tăng độ ổn định cho RakNet/UDP
                // Cần biến môi trường VPS_PUBLIC_IP
                const vpsIp = process.env.VPS_PUBLIC_IP || '';
                if (vpsIp) {
                    await execAsync(
                        `iptables -t nat -I POSTROUTING -p ${p} -d ${targetIp} --dport ${targetPort} -j SNAT --to-source ${vpsIp}`
                    );
                } else {
                    await execAsync(
                        `iptables -t nat -I POSTROUTING -p ${p} -d ${targetIp} --dport ${targetPort} -j MASQUERADE`
                    );
                }
            }
        }

        // Lưu rules
        await execAsync('iptables-save > /etc/iptables/rules.v4 2>/dev/null || true');

        console.log(`[NAT] Added: :${proxyPort} → ${targetIp}:${targetPort} (${protocol})`);
        return { success: true };
    } catch (err) {
        console.error('[NAT] Add error:', err.message);
        return { success: false, error: err.message };
    }
}

/**
 * Xóa NAT rule
 */
async function removeNatRule(proxyPort, targetIp, targetPort, protocol = 'tcp') {
    try {
        const proto = protocol === 'both' ? ['tcp', 'udp'] : [protocol];

        for (const p of proto) {
            await execAsync(
                `iptables -t nat -D PREROUTING -p ${p} --dport ${proxyPort} -j DNAT --to-destination ${targetIp}:${targetPort} 2>/dev/null || true`
            );
            await execAsync(
                `iptables -D FORWARD -p ${p} -d ${targetIp} --dport ${targetPort} -j ACCEPT 2>/dev/null || true`
            );
            await execAsync(
                `iptables -t nat -D POSTROUTING -p ${p} -d ${targetIp} --dport ${targetPort} -j MASQUERADE 2>/dev/null || true`
            );
            const vpsIp = process.env.VPS_PUBLIC_IP || '';
            if (vpsIp) {
                await execAsync(
                    `iptables -t nat -D POSTROUTING -p ${p} -d ${targetIp} --dport ${targetPort} -j SNAT --to-source ${vpsIp} 2>/dev/null || true`
                );
            }
        }

        await execAsync('iptables-save > /etc/iptables/rules.v4 2>/dev/null || true');

        console.log(`[NAT] Removed: :${proxyPort} → ${targetIp}:${targetPort}`);
        return { success: true };
    } catch (err) {
        console.error('[NAT] Remove error:', err.message);
        return { success: false, error: err.message };
    }
}

module.exports = { addNatRule, removeNatRule };
