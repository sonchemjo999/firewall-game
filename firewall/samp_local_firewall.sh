#!/bin/bash

# ==========================================================
# SA:MP LOCAL FIREWALL - OPTIMIZED FOR UBUNTU 22.04
# (Run this on your GAME SERVER VPS: 103.77.246.150)
# ==========================================================

# 1. Khai báo IP Proxy (IP của VPS Firewall NRO Shield)
PROXY_IP="103.77.246.157"
GAME_PORT="7777"

echo "[INFO] Đang thiết lập tường lửa nội bộ cho SA:MP..."

# 2. Flush rules cũ
iptables -F
iptables -X
iptables -t nat -F
iptables -t mangle -F

# 3. Chính sách mặc định
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# 4. Cho phép Loopback (Nội bộ máy)
iptables -A INPUT -i lo -j ACCEPT

# 5. Cho phép các kết nối đã thiết lập (SSH, etc.)
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# 6. QUAN TRỌNG: Whitelist Tuyệt đối IP của Proxy
# Điều này giúp bỏ qua mọi giới hạn MTU/Size cho Proxy
iptables -A INPUT -s $PROXY_IP -j ACCEPT
echo "[OK] Đã Whitelist IP Proxy: $PROXY_IP"

# 7. Cho phép UDP Port Game (Nếu có ai kết nối trực tiếp - Hạn chế)
iptables -A INPUT -p udp --dport $GAME_PORT -m limit --limit 50/sec --limit-burst 100 -j ACCEPT

# 8. Chống tràn UDP (UDP Flood Protection) - Layer 4
# Chỉ áp dụng cho các IP lạ, không phải Proxy
iptables -N SAMP_CHECK
iptables -A INPUT -p udp --dport $GAME_PORT -j SAMP_CHECK
iptables -A SAMP_CHECK -s $PROXY_IP -j RETURN # Tin tưởng Proxy
iptables -A SAMP_CHECK -m limit --limit 10/sec -j ACCEPT
iptables -A SAMP_CHECK -j DROP

# 9. Tối ưu hóa MSS (Nếu có vấn đề gói tin lớn)
iptables -t mangle -A PREROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

# 10. Lưu Rules
apt-get install -y iptables-persistent
netfilter-persistent save

echo "=========================================================="
echo "[SUCCESS] Tường lửa cục bộ đã kích hoạt!"
echo "IP Proxy $PROXY_IP đã được ưu tiên cao nhất."
echo "=========================================================="
