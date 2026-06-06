<div align="center">
  <img src="icon.ico" width="120" alt="NRO Shield Logo">
  <h1>NRO Shield v2.2</h1>
  <p><strong>Hệ thống Chống DDoS Đa tầng cho Game Server & Web Server</strong></p>
  <p>AI-Powered | Multi-Game | Real-time | Flutter App</p>

  [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
  [![Node.js](https://img.shields.io/badge/Node.js-v18+-green.svg)](https://nodejs.org/)
  [![Python](https://img.shields.io/badge/Python-3.9+-blue.svg)](https://www.python.org/)
  [![Docker](https://img.shields.io/badge/Docker-Ready-2496ED.svg)](https://www.docker.com/)
  [![CI](https://github.com/sonchemjo999/firewall-game/actions/workflows/ci.yml/badge.svg)](https://github.com/sonchemjo999/firewall-game/actions)
</div>

---

## Mục lục

- [Giới thiệu](#giới-thiệu)
- [Tính năng](#tính-năng)
- [Kiến trúc hệ thống](#kiến-trúc-hệ-thống)
- [Cấu trúc thư mục](#cấu-trúc-thư-mục)
- [Yêu cầu hệ thống](#yêu-cầu-hệ-thống)
- [Cài đặt nhanh](#cài-đặt-nhanh)
- [Cài đặt chi tiết](#cài-đặt-chi-tiết)
- [Cấu hình](#cấu-hình)
- [Hệ thống Firewall](#hệ-thống-firewall)
- [Backend API](#backend-api)
- [Flutter App](#flutter-app)
- [AI Engine](#ai-engine)
- [Docker](#docker)
- [Game được hỗ trợ](#game-được-hỗ-trợ)
- [Xử lý sự cố](#xử-lý-sự-cố)
- [Đóng góp](#đóng-góp)

---

## Giới thiệu

NRO Shield là hệ thống phòng chống tấn công DDoS toàn diện, được thiết kế chuyên biệt cho game server và web server. Hệ thống kết hợp:

- **Kernel-level packet filtering** -- Drop tấn công tại tầng `raw` table (trước conntrack), không tốn CPU/RAM
- **AI anomaly detection** -- Machine Learning phát hiện tấn công zero-day
- **Multi-game profiles** -- Tối ưu cho 9+ loại game server khác nhau
- **Real-time monitoring** -- WebSocket đồng bộ giữa firewall, backend và app
- **Mobile management** -- Flutter app quản lý từ xa trên điện thoại

### Vấn đề giải quyết

Khi VPS bị tấn công DDoS (botnet), các giải pháp thông thường xử lý packet ở tầng ứng dụng -- **tốn CPU, RAM và gây nghẽn conntrack**. NRO Shield giải quyết bằng cách:

```
Packet tấn công --> raw PREROUTING (DROP ngay) --> KHÔNG tạo conntrack --> KHÔNG tốn tài nguyên
                    ^^^^^^^^^^^^^^^^^^^^^^^^
                    Xử lý tại đây = zero resource usage
```

---

## Tính năng

### Chống tấn công (20+ scripts)

| Tính năng | Mô tả |
|-----------|--------|
| Early Drop Engine | Drop tại `raw` table trước conntrack -- zero CPU/RAM |
| Anti-SYN Flood | 3 lớp: global rate, per-IP, per-IP-per-port |
| Anti-UDP Flood | Game-aware filtering với packet size validation |
| Anti-Bypass | TCP validation (MSS, TTL, flags), UDP pattern detection |
| Anti-Carpet Bombing | Giới hạn connections per destination port |
| Anti-Amplification | Block 14+ reflection source ports |
| Anti-Botnet | Tự động sync IP blacklist từ 5 threat intelligence sources |
| Challenge-Response | TCP SYN Cookie + UDP challenge tokens |
| Fingerprinting | Nhận diện bot qua TCP window, TTL, connection rate |
| Dynamic Blacklist | Auto-ban IP vượt ngưỡng (kiểm tra mỗi 10 giây) |
| Adaptive Rate Limit | Tự điều chỉnh ngưỡng theo mức conntrack usage |
| Backup/Restore | Sao lưu và phục hồi toàn bộ iptables/ipset/sysctl |

### Quản lý và Giám sát

| Tính năng | Mô tả |
|-----------|--------|
| 2FA Authentication | TOTP (Google Authenticator) + backup codes |
| Phân quyền 4 cấp | admin / reseller / premium / basic |
| Server Health | Auto ping/port check mỗi 5 phút |
| Attack Analytics | Phân tích xu hướng, top attackers, timeline |
| Webhook Alerts | Thông báo qua Discord/Slack khi có sự kiện |
| Alert Rules | Cảnh báo tùy chỉnh (ngưỡng PPS, Mbps, connections) |
| Audit Log | Ghi lại mọi hành động admin |
| Config Backup | Sao lưu/phục hồi cấu hình firewall |

### Hạ tầng

| Tính năng | Mô tả |
|-----------|--------|
| Docker Compose | Chỉ dùng cho `db` + `ai_engine`, backend chạy trực tiếp trên host |
| CI/CD | GitHub Actions (4 jobs: lint, syntax, security, docker) |
| Systemd | Auto-restore firewall khi reboot và quản lý backend host |
| Log Rotate | Tự động xoay log, giữ 30 ngày |

---

## Kiến trúc hệ thống

```
                     +------------------+
                     |   Flutter App    |
                     |   (iOS/Android)  |
                     +--------+---------+
                              | REST + WebSocket
                     +--------v---------+
                     |  Web Dashboard   |
                     |  (Browser)       |
                     +--------+---------+
                              |
           +------------------v------------------+
           |        Backend API (Node.js)        |
           |            Port 5000                |
           +------------+----------+-------------+
           | Auth/2FA   | WebSocket | Cron Jobs  |
           | CRUD APIs  | Real-time | Health Mon |
           | Analytics  | Sync      | Blocklist  |
           +-----+------+-----+----+-------------+
                 |            |
      +----------v---+ +-----v----------+
      |   MariaDB    | |   AI Engine    |
      |   Database   | |   (Python)     |
      |   25 tables  | |   Port 8000    |
      +--------------+ +----------------+
                 |
      +----------v-----------------------+
      |      Firewall Scripts (20+)      |
      |      iptables / ipset / raw      |
      +----------------------------------+
      | raw PREROUTING --> Early Drop    |  <-- Zero resource
      | mangle PREROUTING --> Validate   |  <-- Minimal CPU
      | filter INPUT --> Game rules      |  <-- Only clean packets
      +----------------------------------+
```

### Thứ tự xử lý packet

```
1. raw PREROUTING     --> Blacklist, invalid flags, bogon IPs, amplification
                          (DROP ở đây = KHÔNG tốn CPU/RAM/conntrack)
2. conntrack          --> Chỉ xử lý packets hợp lệ
3. mangle PREROUTING  --> TTL, MSS, PPS rate limit
4. filter INPUT       --> Game-specific rules, connection limits
```

---

## Cấu trúc thư mục

```
nroshield/
|-- backend/                    # Node.js API Server
|   |-- config/                 # Database & app config
|   |-- database/               # Migrations (v1, v2, v3) + seed
|   |-- middleware/              # Auth, role check, audit log
|   |-- routes/                 # 17 route files
|   |-- services/               # Business logic (TOTP, health, webhook...)
|   |-- server.js               # Entry point
|   +-- package.json
|
|-- firewall/                   # Bash scripts (20 scripts)
|   |-- early_drop.sh           # Raw table pre-conntrack (v2.2)
|   |-- master_setup.sh         # One-command setup (9 steps)
|   |-- iptables_base.sh        # Base rules + ipset
|   |-- anti_ddos_v2.sh         # Multi-layer DDoS protection
|   |-- anti_bypass.sh          # TCP/UDP bypass prevention
|   |-- anti_botnet.sh          # Botnet IP blocking
|   |-- multi_game_support.sh   # 9 game profiles
|   |-- blocklist_sync.sh       # Threat intelligence sync
|   |-- challenge_response.sh   # Connection verification
|   |-- fingerprint.sh          # Bot detection
|   |-- backup_restore.sh       # Config backup/restore
|   |-- sysctl_hardening.sh     # Kernel optimization
|   |-- traffic_monitor.sh      # Traffic metrics
|   |-- install.sh              # Dependencies
|   |-- clean_rules.sh          # Reset all rules
|   |-- crowdsec_setup.sh       # CrowdSec integration
|   |-- fail2ban_setup.sh       # Fail2Ban setup
|   +-- samp_local_firewall.sh  # SA:MP local rules
|
|-- flutter_app/                # Flutter Mobile App
|   +-- lib/
|       |-- main.dart           # Entry + ThemeService
|       |-- screens/            # 12 screens
|       |-- services/           # API, auth, WebSocket, theme
|       +-- widgets/            # Custom widgets (ShieldLogo)
|
|-- web/                        # Web Dashboard (HTML/CSS/JS)
|   |-- index.html              # SPA entry
|   |-- css/                    # Styles
|   +-- js/                     # Chart.js, WebSocket, API calls
|
|-- ai_engine/                  # Python AI Engine
|   |-- main.py                 # FastAPI entry
|   |-- detector.py             # Isolation Forest model
|   |-- collector.py            # Traffic data collector
|   +-- requirements.txt
|
|-- telegram_bot/               # Telegram Bot
|   |-- bot.js                  # Bot (grammy)
|   +-- package.json
|
|-- Dockerfile                  # Docker image
|-- docker-compose.yml          # Multi-service deployment
|-- .github/workflows/ci.yml    # GitHub Actions CI/CD
|-- .env.example                # Environment template
|-- SETUP.md                    # Detailed setup guide
+-- README.md                   # This file
```

---

## Yêu cầu hệ thống

| Thành phần | Yêu cầu tối thiểu |
|------------|-------------------|
| OS | Ubuntu 20.04 / 22.04 LTS |
| CPU | 2 cores |
| RAM | 2 GB |
| Disk | 20 GB |
| Node.js | v18+ |
| Python | 3.9+ |
| MariaDB/MySQL | 10.6+ / 8.0+ |
| Root access | Bắt buộc (cho iptables) |

---

## Cài đặt nhanh

### Cách 1: Master Setup (khuyến nghị)

```bash
# 1. Clone repository
git clone https://github.com/sonchemjo999/firewall-game /opt/nroshield
cd /opt/nroshield

# 2. Cấu hình
cp .env.example .env
nano .env    # Sửa: VPS_PUBLIC_IP, DB_PASS, JWT_SECRET

# 3. Cài đặt dependencies
apt-get update && apt-get install -y mariadb-server nodejs npm iptables ipset
cd backend && npm install && cd ..

# 4. Khởi tạo database
mysql -e "CREATE DATABASE nroshield CHARACTER SET utf8mb4;"
mysql -e "CREATE USER 'nroshield'@'localhost' IDENTIFIED BY 'YOUR_PASSWORD';"
mysql -e "GRANT ALL ON nroshield.* TO 'nroshield'@'localhost'; FLUSH PRIVILEGES;"
cd backend && node database/migrate.js && node database/migrate_v2.js && node database/migrate_v3.js && cd ..

# 5. Setup firewall (1 lệnh duy nhất)
cd firewall && chmod +x *.sh && sudo bash master_setup.sh all

# 6. Khởi động backend
cd ../backend && node server.js
```

### Cách 2: Docker trên VPS mới tinh (khuyến nghị nếu dùng 3 container)

Mục tiêu của cách này:
- Anti-DDoS thật sự vẫn chạy trên host (`iptables`, `ipset`, `raw PREROUTING`)
- Ứng dụng chạy bằng Docker Compose với 3 container riêng: `db`, `ai_engine`, `backend`
- Web quản trị được public qua Nginx reverse proxy tại `80/443`

#### Bước 1: Đăng nhập vào VPS mới và cập nhật hệ thống

```bash
ssh root@YOUR_VPS_IP
export DEBIAN_FRONTEND=noninteractive
apt-get update -y && apt-get upgrade -y
apt-get install -y ca-certificates curl gnupg lsb-release git nano jq \
  iptables ipset iptables-persistent netfilter-persistent conntrack \
  nginx
```

#### Bước 2: Cài Docker Engine và Docker Compose plugin

```bash
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable docker
systemctl start docker
docker --version
docker compose version
```

#### Bước 3: Clone source code

```bash
rm -rf /opt/nroshield
git clone https://github.com/sonchemjo999/firewall-game /opt/nroshield
cd /opt/nroshield
```

#### Bước 4: Tạo file `.env` cho production

```bash
cp .env.example .env
nano .env
```

Tối thiểu cần sửa các biến sau:

```bash
VPS_PUBLIC_IP="YOUR_VPS_IP"
DB_PASS="MatKhauDBRatManh"
DB_ROOT_PASSWORD="MatKhauRootDBRatManh"
JWT_SECRET="ChuoiBiMatJWTRatDaiVaKhoDoan"
API_PORT=5000
DB_HOST=127.0.0.1
DB_PORT=3306
AI_ENGINE_HOST=127.0.0.1
AI_ENGINE_PORT=8000
AI_BASE_URL=http://127.0.0.1:8000
```

Nếu muốn gửi cảnh báo Telegram thì sửa thêm:

```bash
TELEGRAM_BOT_TOKEN="YOUR_BOT_TOKEN"
TELEGRAM_CHAT_ID="YOUR_CHAT_ID"
```

#### Lệnh all-in-one cho mô hình backend host

```bash
cd /opt/nroshield && cp .env.example .env 2>/dev/null || true && sudo bash firewall/master_setup.sh --mode docker && docker compose up -d db ai_engine && cd backend && npm install && npm run migrate && systemctl restart nroshield-backend && docker compose ps
```

Lệnh này sẽ tự:
- chuẩn bị firewall host theo Docker mode
- bootstrap Docker iptables chains
- chạy 2 container `db`, `ai_engine`
- cài dependencies backend trên host và chạy migrations
- restart backend host qua `systemd`
- in trạng thái container còn lại

#### Bước 5: Thiết lập firewall host trước khi chạy Docker

```bash
cd /opt/nroshield/firewall
chmod +x *.sh
bash master_setup.sh all

# Tao cac chain Docker de khong bi loi FORWARD sau khi bat firewall
iptables -N DOCKER-USER 2>/dev/null || true
iptables -C FORWARD -j DOCKER-USER 2>/dev/null || iptables -I FORWARD 1 -j DOCKER-USER
iptables -N DOCKER-FORWARD 2>/dev/null || true
iptables -C FORWARD -j DOCKER-FORWARD 2>/dev/null || iptables -A FORWARD -j DOCKER-FORWARD
```

Sau khi chạy xong, đảm bảo host cho phép các cổng cần thiết:
- `22` hoặc `SSH_PORT` cho SSH
- `80/443` cho web quản trị
- `5000` nếu bạn muốn public trực tiếp backend API
- các game port/proxy port bạn sử dụng

#### Bước 6: Chạy 2 container hỗ trợ và backend trên host

```bash
cd /opt/nroshield
docker compose up -d db ai_engine
docker compose ps

cd /opt/nroshield/backend
npm install
npm run migrate
systemctl restart nroshield-backend
```

Kết thúc bước này, kiến trúc sẽ là:
- `db`: MariaDB nội bộ, bind localhost để backend host truy cập
- `ai_engine`: Python AI nội bộ, bind localhost để backend host gọi qua HTTP
- `backend`: API + WebSocket chạy trực tiếp trên host ở cổng `5000`

#### Bước 7: Khởi tạo database migrations trên backend host

Sau khi `db` và `ai_engine` đã chạy, backend host sẽ dùng `.env` ở root project để kết nối localhost.

```bash
cd /opt/nroshield/backend
npm install
npm run migrate
systemctl restart nroshield-backend
journalctl -u nroshield-backend -n 50 --no-pager
```

#### Bước 8: Cấu hình Nginx để public web quản trị

Tao file `/etc/nginx/sites-available/nroshield.conf`:

```bash
cat <<'NGINX_EOF' > /etc/nginx/sites-available/nroshield.conf
server {
    listen 80;
    listen [::]:80;
    server_name _;

    root /opt/nroshield/web;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:5000/api/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /ws {
        proxy_pass http://127.0.0.1:5000/ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINX_EOF

rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/nroshield.conf /etc/nginx/sites-enabled/nroshield.conf
nginx -t
systemctl restart nginx
systemctl enable nginx
```

#### Bước 9: Kiểm tra hệ thống sau khi deploy

```bash
# Kiểm tra container
docker compose ps

# Kiểm tra backend health
curl http://127.0.0.1:5000/api/system/health

# Kiểm tra AI health
curl http://127.0.0.1:8000/health || true

# Kiểm tra web public
curl http://YOUR_VPS_IP/

# Kiểm tra WebSocket path
curl -I http://YOUR_VPS_IP/
```

Truy cập dashboard quản trị tại:

```bash
http://YOUR_VPS_IP/
```

Nếu đã gắn domain và SSL thì dùng:

```bash
https://YOUR_DOMAIN/
```

#### Bước 10: Lệnh quản trị thường dùng

```bash
# Xem logs backend host
journalctl -u nroshield-backend -f

# Xem logs AI
docker compose logs -f ai_engine

# Xem logs DB
docker compose logs -f db

# Restart rieng backend host
systemctl restart nroshield-backend

# Restart 2 container ho tro
docker compose restart db ai_engine

# Restart toan bo phan Docker con lai
docker compose down
docker compose up -d db ai_engine
```

### Cách 3: Hướng dẫn chi tiết từng bước

Xem **[SETUP.md](SETUP.md)** -- hướng dẫn cầm tay chỉ việc từ VPS trống đến hoạt động 100%.

---

## Cài đặt chi tiết

### 1. Chuan bi he thong

```bash
export DEBIAN_FRONTEND=noninteractive
apt-get update -y && apt-get upgrade -y
apt-get install -y curl wget git nano build-essential \
  python3 python3-pip python3-venv \
  mariadb-server mariadb-client \
  iptables ipset iptables-persistent netfilter-persistent conntrack \
  net-tools iproute2 htop jq bc fail2ban
```

### 2. Cai Node.js 18

```bash
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs
```

### 3. Cấu hình Database

```bash
systemctl enable --now mariadb

mysql -u root << 'SQL'
CREATE DATABASE IF NOT EXISTS nroshield CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'nroshield'@'localhost' IDENTIFIED BY 'MatKhauManh123!';
GRANT ALL PRIVILEGES ON nroshield.* TO 'nroshield'@'localhost';
FLUSH PRIVILEGES;
SQL
```

### 4. Clone và Cấu hình

```bash
git clone https://github.com/sonchemjo999/firewall-game /opt/nroshield
cd /opt/nroshield
cp .env.example .env
nano .env   # Sua cac gia tri theo VPS cua ban
```

### 5. Cai dat va Chay migrations

```bash
cd /opt/nroshield/backend
npm install
node database/migrate.js
node database/migrate_v2.js
node database/migrate_v3.js
```

### 6. Thiết lập Firewall

```bash
cd /opt/nroshield/firewall
chmod +x *.sh
sudo bash master_setup.sh all   # Hoac: nro, minecraft, samp, fivem...
```

**Master setup sẽ thực hiện 9 bước tự động:**
1. Backup cấu hình hiện tại
2. Cài đặt dependencies
3. Kernel hardening (sysctl)
4. **Early Drop Engine** (raw/mangle pre-conntrack)
5. Base firewall rules
6. Anti-DDoS v2 + Anti-Bypass + Anti-Botnet
7. Game-specific rules
8. Systemd services (auto-restore on reboot)
9. Kiểm tra và tổng kết

### 7. Khởi động Services

```bash
# Backend API
cd /opt/nroshield/backend && node server.js

# AI Engine
cd /opt/nroshield/ai_engine
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt
python3 main.py

# Telegram Bot (tuy chon)
cd /opt/nroshield/telegram_bot && npm install && node bot.js
```

---

## Cấu hình

### File `.env`

| Biến | Bắt buộc | Mặc định | Mô tả |
|------|----------|----------|--------|
| `VPS_PUBLIC_IP` | Có | -- | IP công khai VPS |
| `DB_PASS` | Có | -- | Mật khẩu MariaDB |
| `JWT_SECRET` | Có | -- | Secret key cho JWT token |
| `DB_HOST` | Không | `127.0.0.1` | Database host |
| `DB_PORT` | Không | `3306` | Database port |
| `DB_USER` | Không | `nroshield` | Database user |
| `DB_NAME` | Không | `nroshield` | Database name |
| `API_PORT` | Không | `5000` | Backend API port |
| `AI_ENGINE_PORT` | Không | `8000` | AI Engine port |
| `SSH_PORT` | Không | `22` | SSH port |
| `PROXY_PORT_RANGE_START` | Không | `30000` | Proxy port range start |
| `PROXY_PORT_RANGE_END` | Không | `60000` | Proxy port range end |
| `MAX_CONN_PER_IP` | Không | `500` | Max connections per IP |
| `SYN_RATE_LIMIT` | Không | `300/sec` | SYN rate limit |
| `UDP_RATE_LIMIT` | Không | `2000/sec` | UDP rate limit |
| `TELEGRAM_BOT_TOKEN` | Không | -- | Telegram bot token |
| `TELEGRAM_CHAT_ID` | Không | -- | Telegram chat ID |
| `AI_BLOCK_THRESHOLD` | Không | `0.8` | AI auto-block threshold |

---

## Hệ thống Firewall

### Early Drop Engine (Tính năng chính v2.2)

Script `early_drop.sh` xử lý packet tại `raw` table -- **trước conntrack**. Điều này có nghĩa:

- Packet bị DROP **không tạo conntrack entry** -- không tốn RAM
- Packet bị DROP **không qua connection tracking** -- không tốn CPU
- Chỉ có bandwidth mạng bị ảnh hưởng (không thể tránh ở tầng VPS)

```
Botnet 100K PPS --> raw PREROUTING: DROP (blacklist match)
                --> Conntrack: 0 entries created
                --> CPU: ~0% usage increase
                --> RAM: 0 bytes allocated
```

**So sánh với filter table (cách thông thường):**
```
Botnet 100K PPS --> conntrack: 100K entries created (tốn ~200MB RAM)
                --> filter INPUT: DROP (quá muộn, tài nguyên đã bị tiêu hao)
                --> CPU: 30-50% xử lý conntrack
```

### Các lớp bảo vệ trong Early Drop

| Lớp | Bảng | Chain | Mô tả |
|-----|------|-------|--------|
| 1 | raw | PREROUTING | Blacklist ipset (4 sets), invalid TCP flags, bogon IPs |
| 2 | raw | PREROUTING | UDP amplification source ports, IP fragments |
| 3 | mangle | PREROUTING | TTL validation, MSS check, PPS rate limit |
| 4 | filter | INPUT | Game-specific rules (chỉ clean packets) |

### Danh sách Scripts

| Script | Chức năng | Chạy tại |
|--------|-----------|----------|
| `early_drop.sh` | Blacklist, invalid flags, bogon, amplification | raw PREROUTING |
| `iptables_base.sh` | Ipset, default policy, SSH, NAT | filter + mangle |
| `anti_ddos_v2.sh` | SYN/UDP/ACK/RST/FIN flood, amplification | filter INPUT |
| `anti_bypass.sh` | TCP/UDP validation, carpet bombing, HTTP flood | filter + mangle |
| `anti_botnet.sh` | Botnet IP blocking | filter INPUT |
| `multi_game_support.sh` | Game-specific packet validation | filter FORWARD |
| `blocklist_sync.sh` | Threat intelligence sync (5 sources) | ipset |
| `challenge_response.sh` | TCP SYN cookie, UDP challenge | filter |
| `fingerprint.sh` | Bot detection (TTL, window, rate) | filter |
| `backup_restore.sh` | Backup/restore iptables, ipset, sysctl | -- |
| `sysctl_hardening.sh` | Kernel TCP/IP optimization | sysctl |
| `master_setup.sh` | One-command setup (9 steps) | All |

### Auto-Blacklist (Systemd Timer)

Mỗi 10 giây, systemd timer kiểm tra conntrack và tự động thêm IP có >500 connections vào raw blacklist:

```
IP có 1000 connections --> auto thêm vào nroshield-rawdrop (timeout 1h)
--> Mọi packet tiếp theo bị DROP tại raw table
--> Conntrack entries cũ timeout tự động
--> Tài nguyên server giải phóng dần
```

### Kernel Tuning

`early_drop.sh` tự động tối ưu kernel:

```
net.netfilter.nf_conntrack_max = 2000000    # Tang conntrack slots
net.core.netdev_max_backlog = 65536         # Tang network queue
net.ipv4.tcp_max_syn_backlog = 65536        # Tang SYN queue
net.ipv4.tcp_syncookies = 1                 # Bat SYN cookies
net.ipv4.tcp_fin_timeout = 15               # Giam FIN timeout
net.ipv4.tcp_tw_reuse = 1                   # Reuse TIME_WAIT
net.ipv4.conf.all.rp_filter = 1             # Reverse path filter
```

---

## Backend API

### Endpoints (17 route modules, 40+ endpoints)

| Module | Prefix | Endpoints chinh |
|--------|--------|-----------|
| Auth | `/api/auth` | register, login, profile |
| 2FA | `/api/2fa` | setup, verify, disable, status |
| Servers | `/api/servers` | CRUD, status |
| Proxy | `/api/proxy` | CRUD, toggle |
| Firewall | `/api/firewall` | rules, sync, geo-block |
| Admin | `/api/admin` | users, audit, broadcast |
| Health | `/api/health` | check, history, summary |
| Analytics | `/api/analytics` | overview, timeline, countries |
| Webhooks | `/api/webhooks` | CRUD, test |
| Backup | `/api/backups` | create, restore, delete |
| Alert Rules | `/api/alert-rules` | CRUD, toggle |
| Plans | `/api/plans` | list, details |
| Games | `/api/games` | list, profiles |
| Notifications | `/api/notifications` | list, read, count |
| Stats | `/api/stats` | system, traffic |
| AI | `/api/ai` | status, detections |
| Keys | `/api/keys` | validate, create |

### Phân quyền

| Role | Quyền |
|------|-------|
| `admin` | Toàn quyền: quản lý users, servers, firewall, audit |
| `reseller` | Quản lý khách hàng, tạo license key |
| `premium` | Nhiều server, tính năng nâng cao, AI protection |
| `basic` | 1 server, tính năng cơ bản |

### WebSocket

```
ws://YOUR_IP:5000/ws

Events:
- TRAFFIC_METRICS  --> PPS, Mbps, connections (mỗi 5 giây)
- attack_alert     --> Khi phát hiện tấn công
- rule_update      --> Khi firewall rule thay đổi
- sync_complete    --> Khi đồng bộ rules hoàn tất
```

### Cron Jobs tự động

- **Mỗi 5 phút**: Server health check (ping + port)
- **Mỗi 6 giờ**: Blocklist sync từ threat intelligence
- **Mỗi 10 giây**: Auto-blacklist IP tấn công (systemd timer)
- **Daily**: Rotate attack logs (giữ 30 ngày)

---

## Flutter App

### Cai dat

```bash
cd flutter_app
flutter pub get
flutter run
```

### Cấu hình kết nối Backend

Sửa `lib/services/api_service.dart`:
```dart
static const String baseUrl = 'http://YOUR_VPS_IP:5000';
```

### Màn hình

| Màn hình | Mô tả |
|----------|--------|
| Login | Đăng nhập với animations, grid background |
| Dashboard | Tổng quan: stats, servers, traffic real-time |
| Servers | Quản lý server + game type selection |
| Attacks | Danh sách tấn công + severity |
| Firewall | Quản lý rules + sync status |
| Notifications | Thông báo read/unread |
| Health | Server health status (green/yellow/red) |
| Analytics | Biểu đồ tấn công (fl_chart) |
| Webhooks | Quản lý Discord/Slack webhooks |
| Backup | Sao lưu/phục hồi cấu hình |
| Settings | 2FA setup, theme toggle, language |
| Admin | 5 tab: Users, Servers, Audit, Plans, Games |

### Tính năng

- **Dark/Light mode** với ThemeService
- **Real-time** qua WebSocket (auto-reconnect)
- **2FA setup** với QR code + backup codes
- **fl_chart** biểu đồ phân tích tấn công
- **Material 3** design system

---

## AI Engine

### Mô hình

- **Isolation Forest** -- Phát hiện anomaly dựa trên 11 features
- Features: PPS, Mbps, SYN ratio, UDP ratio, connections, unique IPs, avg packet size...

### Luồng xử lý

```
Traffic Monitor --> JSON metrics --> AI Engine phân tích
                                          |
                                  Anomaly Score (0-1)
                                          |
                          Score > 0.8 --> Auto-block IP
                          Score > 0.6 --> Rate-limit IP
                          Score < 0.6 --> Normal traffic
```

---

## Docker

### Docker Compose

Mô hình khuyến nghị cho production:
- `db` -- MariaDB nội bộ, bind localhost để backend host truy cập
- `ai_engine` -- Python AI nội bộ, bind localhost để backend host gọi qua HTTP
- `backend` -- Node.js API + WebSocket chạy trực tiếp trên host ở port `5000`
- Firewall anti-DDoS (`iptables`, `ipset`, `raw PREROUTING`) tiếp tục chạy trên host, không đưa vào container

```bash
cp .env.example .env
nano .env

# Dam bao Docker co chain rieng truoc khi start stack
iptables -N DOCKER-USER 2>/dev/null || true
iptables -C FORWARD -j DOCKER-USER 2>/dev/null || iptables -I FORWARD 1 -j DOCKER-USER
iptables -N DOCKER-FORWARD 2>/dev/null || true
iptables -C FORWARD -j DOCKER-FORWARD 2>/dev/null || iptables -A FORWARD -j DOCKER-FORWARD

docker compose up -d db ai_engine
cd backend && npm install && npm run migrate
systemctl restart nroshield-backend
```

Cổng public khuyến nghị:
- `80/443` -- web quản trị qua reverse proxy/static web server
- `5000` -- backend API/WebSocket nếu cần public trực tiếp
- Không public `3306` và `8000`

Luồng triển khai nên dùng:
1. Chạy firewall scripts trên host trước
2. Khởi động 2 container `db`, `ai_engine`
3. Chạy backend trực tiếp trên host bằng `systemd`
4. Public dashboard web qua domain và reverse proxy `/api` + `/ws` về backend

Services:
- `backend` -- Node.js API trên host (port 5000)
- `mariadb` -- Database container (bind localhost)
- `ai_engine` -- Python AI container (bind localhost)

### Dockerfile

Backend giờ chạy **trực tiếp trên host** (không còn trong container). File `Dockerfile` và `docker-entrypoint.sh` đã được xóa.

**Cách hoạt động:**
1. `db` container — MariaDB bind ra `127.0.0.1:3306`
2. `ai_engine` container — bind ra `127.0.0.1:8000`
3. Backend host — kết nối tới 2 container trên qua localhost

Sử dụng service file `backend/nroshield-backend.service` để systemd quản lý backend trên host.

---

## Game được hỗ trợ

| Game | Giao thức | Ports | Rate Limit | Packet Size |
|------|-----------|-------|------------|-------------|
| Ngọc Rồng Online (NRO) | UDP | 14300-14400 | 30/s | 28-1500 |
| SA:MP | UDP | 7777-7778 | 100/s | 28-2048 |
| Minecraft | TCP | 25565 | 20/s | 1-32767 |
| FiveM (GTA V) | UDP+TCP | 30120 | 200/s | 28-4096 |
| MU Online | TCP | 44405 | 25/s | 4-4096 |
| Rust | UDP+TCP | 28015-28016 | 150/s | 28-4096 |
| ARK: Survival | UDP | 7777-7778, 27015 | 120/s | 28-4096 |
| Counter-Strike 2 | UDP | 27015-27016 | 200/s | 28-4096 |
| Lineage 2 | TCP | 2106, 7777 | 20/s | 4-8192 |
| Web Server | TCP | 80, 443 | 500/s | 1-65535 |

Thêm game mới: Sửa `multi_game_support.sh` hoặc thêm qua Admin API.

---

## Xử lý sự cố

### Backend không kết nối được Database

```bash
systemctl status mariadb
# Nếu không chạy:
systemctl start mariadb

# Kiểm tra credentials:
mysql -u nroshield -p'YOUR_PASSWORD' -e "SHOW DATABASES;"
```

### Firewall rules bi mat sau reboot

```bash
# Kiểm tra systemd service:
systemctl status nroshield-firewall

# Chay lai master setup:
cd /opt/nroshield/firewall && sudo bash master_setup.sh all
```

### WebSocket không kết nối

Kiểm tra WebSocket path phải là `/ws`:
```
ws://YOUR_DOMAIN/ws
```
Nếu dùng HTTPS thì WebSocket sẽ là:
```
wss://YOUR_DOMAIN/ws
```

### Reset toàn bộ firewall

```bash
cd /opt/nroshield/firewall && sudo bash clean_rules.sh
# Sau đó chạy lại:
sudo bash master_setup.sh all
```

### Xem logs

```bash
# Backend
journalctl -u nroshield-api -f

# Firewall drops
tail -f /var/log/syslog | grep NROSHIELD

# Attack logs
ls /var/log/nroshield/attacks/

# Auto-blacklist
tail -f /var/log/nroshield/auto_rawdrop.log
```

---

## CI/CD

GitHub Actions chay 4 jobs khi push/PR:

| Job | Mô tả |
|-----|--------|
| Backend Lint | Require tất cả JS modules, kiểm tra syntax |
| Firewall Syntax | `bash -n` trên tất cả scripts |
| Security Check | Quét hardcoded secrets, command injection |
| Docker Build | Build Docker image thành công |

---

## Đóng góp

1. Fork repository
2. Tao branch: `git checkout -b feature/ten-tinh-nang`
3. Commit: `git commit -m "Add: mo ta"`
4. Push: `git push origin feature/ten-tinh-nang`
5. Tao Pull Request

---

## License

MIT License -- Xem [LICENSE](LICENSE) để biết chi tiết.

---

<div align="center">
  <p><strong>NRO Shield v2.2</strong> -- Bảo vệ game server của bạn khỏi mọi cuộc tấn công DDoS</p>
  <p>Made with love for the gaming community</p>
</div>
