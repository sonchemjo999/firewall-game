#!/bin/bash

# ==========================================================
# KERNEL TUNING FOR SA:MP GAMING (Ubuntu 22.04)
# ==========================================================

echo "[INFO] Đang tối ưu hóa Kernel System..."

# Sao lưu cấu hình cũ
cp /etc/sysctl.conf /etc/sysctl.conf.bak

# Áp dụng cấu hình tối ưu cho UDP và Network
cat <<EOF > /etc/sysctl.d/99-samp-optimizations.conf
# Tăng bộ nhớ đệm cho UDP (Xử lý gói tin RakNet nhanh hơn)
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.udp_mem = 4096 87380 16777216

# Tăng hàng đợi gói tin (Tránh drop khi bị nhấn kết nối hàng loạt)
net.core.netdev_max_backlog = 5000

# Tắt IP Forwarding nếu không cần (Tăng bảo mật)
net.ipv4.ip_forward = 0

# Tắt RP Filter (Tránh drop gói tin khi dùng NAT)
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.eth0.rp_filter = 0

# Tối ưu hóa TCP cho Web Panel (Nếu có)
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_keepalive_time = 600

# Tăng giới hạn file mở (Tránh lỗi out of descriptors)
fs.file-max = 2097152
EOF

# Áp dụng ngay lập tức
sysctl -p /etc/sysctl.d/99-samp-optimizations.conf

echo "[OK] Kernel đã được tối ưu hóa cho Gaming!"
