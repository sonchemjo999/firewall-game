#!/bin/bash
# ============================================================================
# NRO Shield — Clean Firewall Rules
# ============================================================================

if [[ $EUID -ne 0 ]]; then
   echo "Cần chạy với quyền root"
   exit 1
fi

echo "🧹 Đang dọn dẹp firewall rules..."

# Flush all rules
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# Destroy ipsets
ipset flush
ipset destroy

echo "✅ Đã gỡ bỏ tất cả rules và ipsets."
echo "⚠️  Lưu ý: NAT rules cho người dùng đã bị xóa. Hãy restart nroshield-api để nạp lại."
