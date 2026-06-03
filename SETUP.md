# 🛠️ NRO Shield — Hướng dẫn Cài đặt Hoàn Chỉnh (Zero to Hero)

Tài liệu này là hướng dẫn **cầm tay chỉ việc từng lệnh một**. Chỉ cần copy và dán tuần tự từ máy chủ trống (VPS mới mua) cho đến khi NRO Shield hoạt động 100%.

**Yêu cầu môi trường:** Ubuntu 20.04 LTS hoặc Ubuntu 22.04 LTS.

---

## 📌 Bước 1: Đăng nhập VPS và Chuẩn bị Hệ thống

Kết nối SSH vào VPS và chuyển sang quyền `root`:
```bash
ssh root@<IP_VPS_CUA_BAN>
```

Cập nhật hệ điều hành và cài đặt toàn bộ công cụ cần thiết:
```bash
export DEBIAN_FRONTEND=noninteractive
apt-get update -y && apt-get upgrade -y
apt-get install -y curl wget git nano unzip build-essential \
  python3 python3-pip python3-venv python3-dev \
  mariadb-server mariadb-client \
  iptables ipset iptables-persistent netfilter-persistent conntrack \
  net-tools iproute2 htop iftop vnstat tcpdump nmap jq bc \
  nginx \
  fail2ban \
  software-properties-common apt-transport-https ca-certificates gnupg lsb-release
```

Cài đặt Node.js phiên bản 18:
```bash
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
apt-get install -y nodejs
node -v
# Kết quả phải báo là v18.x.x
```

---

## 📌 Bước 2: Khởi tạo Cơ sở Dữ liệu (MariaDB)

Khởi động MariaDB:
```bash
systemctl enable mariadb
systemctl start mariadb
```

Tạo Database và User:
```bash
mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS nroshield CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'nroshield'@'localhost' IDENTIFIED BY 'Matkhau1@#\$';
GRANT ALL PRIVILEGES ON nroshield.* TO 'nroshield'@'localhost';
FLUSH PRIVILEGES;
EOF
```

Kiểm tra đã tạo thành công:
```bash
mysql -u nroshield -p'Matkhau1@#$' -e "SHOW DATABASES;" | grep nroshield
# Phải hiện ra dòng "nroshield"
```

---

## 📌 Bước 3: Tải Mã Nguồn về VPS

```bash
rm -rf /opt/nroshield
git clone https://github.com/hoangtuvungcao/firewall.git /opt/nroshield
cd /opt/nroshield
```

---

## 📌 Bước 4: Cấu hình File `.env` (Rất Quan Trọng)

File `.env` chứa toàn bộ cấu hình hệ thống. Tạo file `.env` từ mẫu `.env.example`:

```bash
cp /opt/nroshield/.env.example /opt/nroshield/.env
nano /opt/nroshield/.env
```

Trong file `.env`, bạn **BẮT BUỘC** phải sửa các dòng sau:

| Biến | Ý nghĩa | Ví dụ |
|------|---------|-------|
| `VPS_PUBLIC_IP` | IP công khai của VPS (BẮT BUỘC) | `103.77.246.157` |
| `DB_PASS` | Mật khẩu database đã tạo ở Bước 2 | `Matkhau1@#$` |
| `JWT_SECRET` | Chuỗi bí mật để mã hóa token đăng nhập | `ChuoiBiMat123!@#` |
| `TELEGRAM_BOT_TOKEN` | Token từ `@BotFather` trên Telegram | `7123456:AAF...` |
| `TELEGRAM_CHAT_ID` | Chat ID nhận thông báo (lấy từ `@userinfobot`) | `123456789` |
| `SSH_PORT` | Port SSH của VPS (mặc định `22`, nên đổi `2222`) | `2222` |

Các biến khác có thể giữ giá trị mặc định:

| Biến | Mặc định | Ý nghĩa |
|------|----------|---------|
| `API_PORT` | `5000` | Port API Backend |
| `AI_ENGINE_PORT` | `8000` | Port AI Engine |
| `PROXY_PORT_RANGE_START` | `30000` | Port bắt đầu cho proxy shield |
| `PROXY_PORT_RANGE_END` | `60000` | Port kết thúc cho proxy shield |
| `MAX_CONN_PER_IP` | `50` | Số kết nối tối đa mỗi IP |
| `SYN_RATE_LIMIT` | `200/sec` | Giới hạn SYN per IP |
| `UDP_RATE_LIMIT` | `100/sec` | Giới hạn UDP per IP |
| `AI_LEARNING_DAYS` | `7` | Số ngày AI học trước khi tự động chặn |
| `AI_BLOCK_THRESHOLD` | `0.8` | Ngưỡng anomaly để auto-block IP |
| `AI_RATE_LIMIT_THRESHOLD` | `0.6` | Ngưỡng anomaly để rate-limit IP |

Sau khi sửa xong, bấm `Ctrl + X` → `Y` → `Enter` để lưu.

---

## 📌 Bước 5: Cài đặt Libraries cho từng Module

### 5.1. Backend API (Node.js)
```bash
cd /opt/nroshield/backend
npm install
```

### 5.2. Khởi tạo Bảng Database
```bash
node database/migrate.js
```
Kết quả đúng sẽ hiện:
```
✅ users
✅ servers
✅ proxy_ports
✅ license_keys
✅ attack_logs
...
```

### 5.3. Telegram Bot (Node.js)
```bash
cd /opt/nroshield/telegram_bot
npm install
```

### 5.4. AI Engine (Python)
```bash
cd /opt/nroshield/ai_engine
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
deactivate
```

---

## 📌 Bước 6: Thiết lập Firewall & Hardening (Thư mục `firewall/`)

Thư mục `firewall/` chứa **9 scripts** bảo mật tự động. Dưới đây là danh sách đầy đủ và thứ tự chạy:

```bash
cd /opt/nroshield/firewall
chmod +x *.sh
```

### 6.1. Cài đặt Dependencies cho Firewall
Cài tất cả packages bảo mật (iptables, ipset, Fail2Ban, CrowdSec, hping3, GeoIP...):
```bash
./install.sh
```
*(Kết quả: Khi thấy `CÀI ĐẶT HOÀN TẤT!` là thành công)*

### 6.2. Tăng cường Nhân Linux (Kernel Hardening)
Tối ưu TCP stack để chống SYN Flood, tăng conntrack, tắt IPv6:
```bash
./sysctl_hardening.sh
```
*(Kết quả: Hiện bảng kiểm tra SYN Cookies, SYN Backlog, IP Forward...)*

### 6.3. Thiết lập Luật Tường lửa Gốc (IPTables + NAT)
Tạo ipset blacklist/whitelist, thiết lập INPUT DROP, NAT MASQUERADE, chống port scan:
```bash
./iptables_base.sh
```
*(Kết quả: Hiện số lượng rules đã tạo)*

### 6.4. Thiết lập Anti-DDoS
Rate-limit SYN/UDP/ICMP, chặn HTTP slowloris, connection flood:
```bash
./anti_ddos.sh
```

### 6.5. Chặn danh sách IP Botnet quốc tế
Tải và import blacklist IP từ các tổ chức bảo mật (Spamhaus, Firehol...):
```bash
./anti_botnet.sh
```

### 6.6. Cấu hình Fail2Ban (Chặn dò mật khẩu SSH)
```bash
./fail2ban_setup.sh
```

### 6.7. Cấu hình CrowdSec (Phát hiện tấn công cộng đồng)
```bash
./crowdsec_setup.sh
```

### 6.8. Giám sát Traffic tự động (Traffic Monitor)
Script `traffic_monitor.sh` chạy tự động mỗi phút bởi systemd timer (được cài trong `deploy.sh`). Không cần chạy thủ công.

### 6.9. Xóa tất cả quy tắc (Clean Rules) — Chỉ dùng khi cần Reset
Nếu muốn xóa hết toàn bộ iptables rules để bắt đầu lại:
```bash
./clean_rules.sh
```
⚠️ **CẢNH BÁO:** Lệnh này sẽ xóa sạch tường lửa. Chỉ chạy khi cần debug.

---

## 📌 Bước 7: Cấu hình Nginx (Web Server)

Copy khối lệnh sau để tạo file config Nginx:

```bash
cat <<'NGINX_EOF' > /etc/nginx/sites-available/default
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _;
    root /opt/nroshield/web;
    index index.html;

    # Frontend Dashboard
    location / {
        try_files $uri $uri/ /index.html;
    }

    # API Backend Proxy
    location /api/ {
        proxy_pass http://127.0.0.1:5000/api/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # WebSocket (Biểu đồ Realtime)
    location /ws {
        proxy_pass http://127.0.0.1:5000/ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }

    # AI Engine Status
    location /status {
        proxy_pass http://127.0.0.1:8000/status;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
    }
}
NGINX_EOF
```

Kiểm tra và khởi động lại Nginx:
```bash
ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
nginx -t
# Phải hiện "syntax is ok" và "test is successful"
systemctl restart nginx
systemctl enable nginx
```

---

## 📌 Bước 8: Tạo Systemd Services (Chạy ngầm tự động)

Dự án đã có sẵn các file service trong thư mục `services/`. Copy chúng trực tiếp:

```bash
cp /opt/nroshield/services/nroshield-api.service /etc/systemd/system/
cp /opt/nroshield/services/nroshield-bot.service /etc/systemd/system/
cp /opt/nroshield/services/nroshield-ai.service /etc/systemd/system/
```

Kích hoạt và chạy toàn bộ:
```bash
systemctl daemon-reload
systemctl enable nroshield-api nroshield-bot nroshield-ai
systemctl restart nroshield-api nroshield-bot nroshield-ai
```

Kiểm tra trạng thái (Phải hiện **Active: active (running)** cho cả 3):
```bash
systemctl status nroshield-api --no-pager
systemctl status nroshield-bot --no-pager
systemctl status nroshield-ai --no-pager
```

Nếu dịch vụ nào báo lỗi, xem log chi tiết:
```bash
journalctl -u nroshield-api -n 30 --no-pager
journalctl -u nroshield-bot -n 30 --no-pager
journalctl -u nroshield-ai -n 30 --no-pager
```

---

## 📌 Bước 9: Tạo Thư mục Log & Logrotate

```bash
mkdir -p /var/log/nroshield/{attacks,traffic,ai}
chmod 750 /var/log/nroshield
```

Cấu hình Log tự động xoay vòng (giữ 7 ngày):
```bash
cat <<'EOF' > /etc/logrotate.d/nroshield
/var/log/nroshield/*.log
/var/log/nroshield/**/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 640 root root
    sharedscripts
}
EOF
```

---

## 📌 Bước 10: Tạo License Key Admin & Đăng Nhập

Tạo 1 License Key quyền lực vô hạn:
```bash
mysql -u nroshield -p'Matkhau1@#$' nroshield -e "INSERT INTO license_keys (key_code, max_servers, max_ports_per_server, max_bandwidth_mbps) VALUES ('ADMIN-123456', 99, 99, 9999);"
```

Kiểm tra Key đã tạo thành công:
```bash
mysql -u nroshield -p'Matkhau1@#$' nroshield -e "SELECT * FROM license_keys;"
```

---

## 🎉 Bước 11: Kiểm tra & Sử dụng

### 11.1. Mở Web Dashboard
Truy cập trình duyệt: `http://<IP_VPS_CUA_BAN>/`
→ Đăng ký tài khoản mới với mã Key `ADMIN-123456`

### 11.2. Sử dụng Telegram Bot
1. Mở Telegram, tìm Bot bạn đã tạo
2. Gõ `/start` → `/login`
3. Đăng nhập bằng tài khoản đã tạo ở trên

### 11.3. Kiểm tra sức khỏe toàn hệ thống
```bash
cd /opt/nroshield
chmod +x *.sh
./master_check.sh
```

---

## 🚀 Phụ lục: Cách Nhanh nhất — Cài 1 lệnh duy nhất (deploy.sh)

Nếu bạn **KHÔNG MUỐN** làm thủ công từng bước ở trên, dự án đã có script `deploy.sh` tự động hóa toàn bộ phần Firewall (Bước 6). Chỉ cần đảm bảo đã hoàn thành Bước 1-5 và Bước 7, sau đó chạy:

```bash
cd /opt/nroshield
chmod +x deploy.sh
./deploy.sh
```

Script này sẽ tự động:
- Chạy tất cả 6 script firewall (`install.sh` → `crowdsec_setup.sh`)
- Tạo systemd timer cho traffic monitor (chạy mỗi phút)
- Cấu hình logrotate
- Hiện báo cáo tổng kết

---

## 📋 Phụ lục: Các Script Tiện Ích

| Script | Công dụng | Lệnh |
|--------|----------|------|
| `master_check.sh` | Kiểm tra trạng thái toàn bộ hệ thống | `./master_check.sh` |
| `deploy.sh` | Cài đặt/cập nhật toàn bộ Firewall | `./deploy.sh` |
| `cleanup_logs.sh` | Xóa log cũ hơn 30 ngày trong DB | `./cleanup_logs.sh` |
| `firewall/clean_rules.sh` | Xóa hết IPtables rules (Reset) | `./firewall/clean_rules.sh` |
| `firewall/traffic_monitor.sh` | Thu thập traffic metrics (tự động) | Chạy bởi systemd timer |

---

## ❓ Xử lý Lỗi Thường Gặp

### Lỗi: Bot báo "TELEGRAM_BOT_TOKEN chưa cấu hình"
```bash
nano /opt/nroshield/.env
# Sửa dòng TELEGRAM_BOT_TOKEN và TELEGRAM_CHAT_ID
systemctl restart nroshield-bot
```

### Lỗi: API báo "ECONNREFUSED" khi kết nối Database
```bash
systemctl status mariadb
# Nếu không chạy:
systemctl start mariadb
systemctl restart nroshield-api
```

### Lỗi: Nginx báo "502 Bad Gateway"
API Backend chưa chạy. Kiểm tra:
```bash
systemctl status nroshield-api
journalctl -u nroshield-api -n 20 --no-pager
systemctl restart nroshield-api
```

### Lỗi: Proxy Port không forward được
IP Forwarding chưa bật:
```bash
sysctl net.ipv4.ip_forward
# Nếu = 0, chạy:
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-ipforward.conf
sysctl -p /etc/sysctl.d/99-ipforward.conf
```

### Lỗi: AI Engine không chạy
```bash
journalctl -u nroshield-ai -n 20 --no-pager
# Nếu thiếu thư viện Python:
cd /opt/nroshield/ai_engine
source venv/bin/activate
pip install -r requirements.txt
deactivate
systemctl restart nroshield-ai
```

### Lỗi: CrowdSec chưa cài
```bash
curl -s https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.deb.sh | bash
apt-get install -y crowdsec crowdsec-firewall-bouncer-iptables
systemctl enable crowdsec
systemctl start crowdsec
```
