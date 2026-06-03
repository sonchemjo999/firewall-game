#!/bin/bash
# ============================================================================
# NRO Shield — Cleanup Logs & Temp Files
# ============================================================================

if [[ $EUID -ne 0 ]]; then
   echo "Cần chạy với quyền root"
   exit 1
fi

echo "🧹 Đang dọn dẹp hệ thống..."

# 1. Clean system logs
echo "  - Dọn dẹp logs dịch vụ..."
truncate -s 0 /var/log/nroshield/*.log 2>/dev/null || true
truncate -s 0 /var/log/nroshield/**/*.log 2>/dev/null || true

# 2. Clean deploy logs
echo "  - Dọn dẹp logs cài đặt..."
rm -f /opt/nroshield/deploy.log

# 3. Clean temporary files
echo "  - Dọn dẹp file tạm..."
rm -rf /tmp/nroshield_*

echo "✅ Hoàn tất dọn dẹp."
