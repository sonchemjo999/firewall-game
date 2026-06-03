/* NRO Shield — Dashboard JS v2 */
const API = `https://firewall.bacsycay.click`;

let token = localStorage.getItem('nroshield_token');
let user = JSON.parse(localStorage.getItem('nroshield_user') || 'null');

// === API Helper ===
async function api(method, endpoint, data = null) {
  const opts = { method, headers: { 'Content-Type': 'application/json' } };
  if (token) opts.headers['Authorization'] = `Bearer ${token}`;
  if (data) opts.body = JSON.stringify(data);
  const res = await fetch(`${API}${endpoint}`, opts);
  const json = await res.json();
  if (!res.ok) throw new Error(json.error || 'Request failed');
  return json;
}

// === Chart.js Realtime Setup ===
let trafficChartInstance = null;
const maxChartPoints = 20;
let chartLabels = Array(maxChartPoints).fill('');
let chartDataConnections = Array(maxChartPoints).fill(0);

function initTrafficChart() {
  const ctx = document.getElementById('trafficChart');
  if (!ctx || trafficChartInstance) return;

  Chart.defaults.color = '#94a3b8';
  Chart.defaults.font.family = 'Inter';

  trafficChartInstance = new Chart(ctx, {
    type: 'line',
    data: {
      labels: chartLabels,
      datasets: [{
        label: 'Active Connections',
        data: chartDataConnections,
        borderColor: '#3b82f6',
        backgroundColor: 'rgba(59, 130, 246, 0.1)',
        borderWidth: 2,
        tension: 0.4,
        fill: true,
        pointRadius: 0,
        pointHitRadius: 10
      }]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      animation: { duration: 400, easing: 'linear' },
      plugins: {
        legend: { display: false },
        tooltip: {
          mode: 'index',
          intersect: false,
          backgroundColor: 'rgba(15, 21, 32, 0.9)',
          titleColor: '#fff',
          bodyColor: '#e2e8f0',
          borderColor: 'rgba(255,255,255,0.1)',
          borderWidth: 1
        }
      },
      scales: {
        x: { display: false, grid: { display: false } },
        y: {
          grid: { color: 'rgba(255,255,255,0.05)' },
          beginAtZero: true,
          suggestedMax: 100
        }
      }
    }
  });
}

function updateTrafficChart(metrics) {
  if (!trafficChartInstance) return;
  const now = new Date().toLocaleTimeString('vi', { hour: '2-digit', minute: '2-digit', second: '2-digit' });

  chartLabels.push(now);
  chartDataConnections.push(metrics.total_connections || 0);

  if (chartLabels.length > maxChartPoints) {
    chartLabels.shift();
    chartDataConnections.shift();
  }

  trafficChartInstance.update('none'); // Update without full animation for smoother real-time

  if (metrics.cpu_usage !== undefined) document.getElementById('stat-cpu').textContent = metrics.cpu_usage + '%';
  if (metrics.ram_usage !== undefined) document.getElementById('stat-ram').textContent = metrics.ram_usage + '%';
}

// === Toast ===
function toast(msg, type = 'info') {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.className = `toast ${type} show`;
  setTimeout(() => t.classList.remove('show'), 3000);
}

// === Custom Confirm Modal (thay thế window.confirm) ===
function customConfirm(message) {
  return new Promise((resolve) => {
    const overlay = document.createElement('div');
    overlay.className = 'modal-overlay';
    overlay.innerHTML = `
      <div class="modal-content">
        <h3>⚠️ Xác nhận</h3>
        <p style="margin:12px 0;color:#94a3b8">${message}</p>
        <div style="display:flex;gap:8px;margin-top:16px;justify-content:flex-end">
          <button class="btn btn-ghost" id="confirm-cancel">Hủy</button>
          <button class="btn btn-danger" id="confirm-ok">Xóa</button>
        </div>
      </div>`;
    document.body.appendChild(overlay);
    overlay.querySelector('#confirm-ok').addEventListener('click', () => { overlay.remove(); resolve(true); });
    overlay.querySelector('#confirm-cancel').addEventListener('click', () => { overlay.remove(); resolve(false); });
  });
}

// === Auth ===
document.getElementById('login-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  try {
    const res = await api('POST', '/api/auth/login', {
      username: document.getElementById('login-username').value,
      password: document.getElementById('login-password').value,
    });
    token = res.token; user = res.user;
    localStorage.setItem('nroshield_token', token);
    localStorage.setItem('nroshield_user', JSON.stringify(user));
    showDashboard();
    toast('Đăng nhập thành công!', 'success');
  } catch (err) { document.getElementById('login-error').textContent = err.message; }
});

function showRegister() {
  document.getElementById('login-form').style.display = 'none';
  document.getElementById('register-form').style.display = 'block';
  document.getElementById('login-error').textContent = '';
}
function showLogin() {
  document.getElementById('login-form').style.display = 'block';
  document.getElementById('register-form').style.display = 'none';
  document.getElementById('login-error').textContent = '';
}

async function doRegister() {
  try {
    const res = await api('POST', '/api/auth/register', {
      username: document.getElementById('reg-username').value,
      password: document.getElementById('reg-password').value,
      key_code: document.getElementById('reg-key').value,
    });
    token = res.token; user = res.user;
    localStorage.setItem('nroshield_token', token);
    localStorage.setItem('nroshield_user', JSON.stringify(user));
    showDashboard();
    toast('Đăng ký thành công!', 'success');
  } catch (err) { document.getElementById('login-error').textContent = err.message; }
}

function logout() {
  token = null; user = null;
  localStorage.removeItem('nroshield_token');
  localStorage.removeItem('nroshield_user');
  document.getElementById('login-screen').classList.add('active');
  document.getElementById('dashboard-screen').classList.remove('active');

  // Reset UI states
  document.getElementById('admin-menu').style.display = 'none';
  document.getElementById('user-role').classList.remove('admin');
}

// === Navigation ===
document.querySelectorAll('.sidebar-menu li').forEach(li => {
  li.addEventListener('click', () => {
    const page = li.dataset.page;
    document.querySelectorAll('.sidebar-menu li').forEach(l => l.classList.remove('active'));
    li.classList.add('active');
    document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
    document.getElementById('page-' + page).classList.add('active');
    document.getElementById('page-title').textContent = li.textContent.trim();
    loadPage(page);
  });
});

// === Dashboard Init ===
function showDashboard() {
  document.getElementById('login-screen').classList.remove('active');
  document.getElementById('dashboard-screen').classList.add('active');
  document.getElementById('user-name').textContent = user?.username || '—';
  const badge = document.getElementById('user-role');
  const adminMenu = document.getElementById('admin-menu');

  badge.textContent = user?.role || 'user';
  badge.classList.remove('admin');
  adminMenu.style.display = 'none';

  if (user?.role === 'admin') {
    badge.classList.add('admin');
    adminMenu.style.display = '';
  }
  loadPage('overview');
}

async function loadPage(page) {
  try {
    if (page === 'overview') await loadOverview();
    else if (page === 'servers') await loadServers();
    else if (page === 'proxies') await loadProxies();
    else if (page === 'attacks') await loadAttacks();
    else if (page === 'ai') await loadAI();
    else if (page === 'admin') await loadAdmin();
  } catch (err) { console.error('Load error:', err); }
}

// === Overview ===
async function loadOverview() {
  const [summary, proxies] = await Promise.all([api('GET', '/api/stats/summary'), api('GET', '/api/proxy')]);
  document.getElementById('stat-servers').textContent = summary.total_servers || 0;
  document.getElementById('stat-ports').textContent = `${summary.active_ports || 0}/${summary.total_ports || 0}`;
  document.getElementById('stat-attacks').textContent = summary.attacks_today || 0;
  try {
    const r = await fetch(`${API}/api/health`);
    const ai = await r.json();
    document.getElementById('stat-ai').textContent = 'Active';
  } catch { document.getElementById('stat-ai').textContent = 'Offline'; }

  initTrafficChart();

  if (!proxies.length) {
    document.getElementById('recent-proxies').innerHTML = '<p class="muted">Chưa có proxy. Vào menu Servers → thêm server → menu Proxy → tạo proxy.</p>';
  } else {
    document.getElementById('recent-proxies').innerHTML = renderProxyTable(proxies.slice(0, 5));
  }
}

// === Servers ===
async function loadServers() {
  const data = await api('GET', '/api/servers');
  if (!data.length) return document.getElementById('servers-list').innerHTML = '<p class="muted">Chưa có server. Bấm "+ Thêm Server" ở trên.</p>';
  document.getElementById('servers-list').innerHTML = `<table>
    <tr><th>ID</th><th>Tên Server</th><th>IP Game (đích)</th><th>Key</th><th>Ports đang dùng</th><th>Max Ports</th><th></th></tr>
    ${data.map(s => `<tr>
      <td>${s.id}</td>
      <td><strong>${s.name}</strong></td>
      <td class="ip-addr">${s.target_ip}</td>
      <td style="font-size:11px;font-family:monospace">${s.key_code || '—'}</td>
      <td>${s.port_count || 0}</td>
      <td>${s.max_ports_per_server || '—'}</td>
      <td><button class="btn btn-danger btn-sm" onclick="deleteServer(${s.id})">Xóa</button></td>
    </tr>`).join('')}</table>`;
}
function showAddServer() { document.getElementById('add-server-form').style.display = ''; }
function hideAddServer() { document.getElementById('add-server-form').style.display = 'none'; }
async function addServer() {
  const name = document.getElementById('srv-name').value;
  const target_ip = document.getElementById('srv-ip').value;
  if (!name || !target_ip) return toast('Nhập đủ thông tin', 'error');
  try { await api('POST', '/api/servers', { name, target_ip }); toast('Server đã thêm!', 'success'); hideAddServer(); loadServers(); }
  catch (err) { toast(err.message, 'error'); }
}
async function deleteServer(id) {
  const confirmed = await customConfirm('Xóa server này? Tất cả proxy sẽ bị xóa!');
  if (!confirmed) return;
  try { await api('DELETE', `/api/servers/${id}`); toast('Đã xóa', 'success'); loadServers(); } catch (err) { toast(err.message, 'error'); }
}

// === Proxies ===
async function loadProxies() {
  const data = await api('GET', '/api/proxy');
  if (!data.length) return document.getElementById('proxies-list').innerHTML = '<p class="muted">Chưa có proxy. Bấm "+ Tạo Proxy" và chọn server + port game.</p>';
  document.getElementById('proxies-list').innerHTML = renderProxyTable(data);
}

function renderProxyTable(data) {
  return `<table>
    <tr><th>Status</th><th>IP Shield (kết nối qua đây)</th><th></th><th>Server Game (IP gốc:port)</th><th>Port Game</th><th>Protocol</th><th>Hành động</th></tr>
    ${data.map(p => `<tr>
      <td><span class="${p.is_active ? 'status-active' : 'status-inactive'}">${p.is_active ? '● ON' : '● OFF'}</span></td>
      <td><span class="proxy-addr">${p.proxy_address}</span>
        <button class="btn btn-ghost btn-sm" onclick="navigator.clipboard.writeText('${p.proxy_address}');toast('Đã copy!','success')" title="Copy">📋</button></td>
      <td style="font-size:18px">→</td>
      <td class="ip-addr">${p.target_address}</td>
      <td><strong style="color:#f59e0b">${p.target_port}</strong></td>
      <td>${(p.protocol || 'tcp').toUpperCase()}</td>
      <td>
        <button class="btn ${p.is_active ? 'btn-danger' : 'btn-success'} btn-sm" onclick="toggleProxy(${p.id})">${p.is_active ? 'Tắt' : 'Bật'}</button>
        <button class="btn btn-ghost btn-sm" onclick="deleteProxy(${p.id})">🗑️</button>
      </td>
    </tr>`).join('')}</table>
    <div style="margin-top:12px;padding:12px;background:rgba(59,130,246,0.1);border-radius:8px;font-size:13px">
      <strong>💡 Hướng dẫn:</strong> Copy IP Shield bên trái → dán vào game client thay IP server gốc. Game sẽ kết nối qua Shield, ẩn IP gốc.
    </div>`;
}

async function showAddProxy() {
  document.getElementById('add-proxy-form').style.display = '';
  const servers = await api('GET', '/api/servers');
  if (!servers.length) { toast('Thêm server trước!', 'error'); document.getElementById('add-proxy-form').style.display = 'none'; return; }
  document.getElementById('proxy-server').innerHTML = servers.map(s => `<option value="${s.id}">${s.name} — ${s.target_ip}</option>`).join('');
}
function hideAddProxy() { document.getElementById('add-proxy-form').style.display = 'none'; }
async function addProxy() {
  const server_id = parseInt(document.getElementById('proxy-server').value);
  const target_port = parseInt(document.getElementById('proxy-port').value);
  const protocol = document.getElementById('proxy-proto').value;
  if (!target_port) return toast('Nhập port game cần bảo vệ', 'error');
  try {
    const res = await api('POST', '/api/proxy/create', { server_id, target_port, protocol });
    toast(`Proxy tạo thành công! ${res.proxy.proxy_address} → ${res.proxy.target_address}`, 'success');
    hideAddProxy(); loadProxies();
  } catch (err) { toast(err.message, 'error'); }
}
async function toggleProxy(id) {
  try { await api('PUT', `/api/proxy/${id}/toggle`); loadProxies(); loadOverview(); } catch (err) { toast(err.message, 'error'); }
}
async function deleteProxy(id) {
  const confirmed = await customConfirm('Xóa proxy này? NAT rule sẽ bị gỡ.');
  if (!confirmed) return;
  try { await api('DELETE', `/api/proxy/${id}`); toast('Đã xóa', 'success'); loadProxies(); } catch (err) { toast(err.message, 'error'); }
}

// === Attacks ===
async function loadAttacks() {
  const data = await api('GET', '/api/stats/attacks?limit=20');
  if (!data.length) return document.getElementById('attacks-list').innerHTML = '<p class="muted">✅ Chưa có tấn công nào! AI Engine đang giám sát.</p>';
  document.getElementById('attacks-list').innerHTML = `<table>
    <tr><th>Thời gian</th><th>Loại</th><th>IP tấn công</th><th>Packets blocked</th><th>Duration</th></tr>
    ${data.map(a => `<tr>
      <td>${new Date(a.detected_at).toLocaleString('vi')}</td>
      <td><span class="badge">${a.attack_type}</span></td>
      <td class="ip-addr">${a.attacker_ip || '—'}</td>
      <td>${a.packets_blocked || 0}</td>
      <td>${a.duration_seconds || 0}s</td>
    </tr>`).join('')}</table>`;
}

// === AI ===
async function loadAI() {
  try {
    const r = await fetch(`/status`);
    const ai = await r.json();
    document.getElementById('ai-models').textContent = ai.models_loaded ? '1' : '0';
    document.getElementById('ai-detections-list').innerHTML = `
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-bottom:16px">
        <div style="padding:12px;background:rgba(139,92,246,0.1);border-radius:8px">
          <div style="font-size:13px;color:#64748b">Mode</div>
          <div style="font-size:18px;font-weight:700">${ai.learning_mode ? '📚 Learning' : '🛡️ Active'}</div>
        </div>
        <div style="padding:12px;background:rgba(59,130,246,0.1);border-radius:8px">
          <div style="font-size:13px;color:#64748b">Collect Interval</div>
          <div style="font-size:18px;font-weight:700">${ai.collect_interval}s</div>
        </div>
        <div style="padding:12px;background:rgba(239,68,68,0.1);border-radius:8px">
          <div style="font-size:13px;color:#64748b">Block Threshold</div>
          <div style="font-size:18px;font-weight:700">${ai.thresholds?.block || '0.8'}</div>
        </div>
        <div style="padding:12px;background:rgba(245,158,11,0.1);border-radius:8px">
          <div style="font-size:13px;color:#64748b">Rate Limit Threshold</div>
          <div style="font-size:18px;font-weight:700">${ai.thresholds?.rate_limit || '0.6'}</div>
        </div>
      </div>
      <p class="muted">AI Engine đang thu thập dữ liệu traffic. Khi đủ 100+ samples sẽ tự train model IsolationForest.</p>`;
  } catch {
    document.getElementById('ai-detections-list').innerHTML = '<p class="muted">❌ AI Engine offline. Kiểm tra systemctl status nroshield-ai</p>';
  }
}

// === Admin ===
async function loadAdmin() {
  if (user?.role !== 'admin') return;
  try {
    const [keys, users] = await Promise.all([api('GET', '/api/keys'), api('GET', '/api/admin/users')]);
    document.getElementById('admin-keys').textContent = keys.filter(k => k.status === 'active').length;
    document.getElementById('admin-users').textContent = users.length;
    document.getElementById('admin-proxies').textContent = keys.reduce((a, k) => a + (k.max_ports_per_server || 0), 0);

    // Keys table with edit buttons
    document.getElementById('keys-list').innerHTML = `<table>
      <tr><th>Key Code</th><th>Status</th><th>Assigned To</th><th>Max Servers</th><th>Max Ports/Server</th><th>Hết hạn</th><th>Hành động</th></tr>
      ${keys.map(k => `<tr>
        <td style="font-family:monospace;font-size:11px">${k.key_code}
          <button class="btn btn-ghost btn-sm" onclick="navigator.clipboard.writeText('${k.key_code}');toast('Đã copy key!','success')">📋</button></td>
        <td><span class="${k.status === 'active' ? 'status-active' : 'status-inactive'}">${k.status}</span></td>
        <td>${k.assigned_to || '<em style="color:#64748b">chưa assign</em>'}</td>
        <td><strong>${k.max_servers}</strong></td>
        <td><strong>${k.max_ports_per_server}</strong></td>
        <td>${k.expires_at ? new Date(k.expires_at).toLocaleDateString('vi') : '∞'}</td>
        <td>
          <button class="btn btn-primary btn-sm" onclick="showEditKey(${k.id}, ${k.max_servers}, ${k.max_ports_per_server}, '${k.status}')">✏️ Sửa</button>
          ${k.status === 'active' ? `<button class="btn btn-danger btn-sm" onclick="revokeKey(${k.id})">Thu hồi</button>` :
        `<button class="btn btn-success btn-sm" onclick="reactivateKey(${k.id})">Kích hoạt</button>`}
        </td>
      </tr>`).join('')}</table>`;

    // Users table
    document.getElementById('users-list').innerHTML = `<table>
      <tr><th>ID</th><th>Username</th><th>Role</th><th>Status</th><th>Key</th><th>Created</th></tr>
      ${users.map(u => `<tr>
        <td>${u.id}</td><td><strong>${u.username}</strong></td>
        <td><span class="badge ${u.role === 'admin' ? 'admin' : ''}">${u.role}</span></td>
        <td><span class="${u.is_active ? 'status-active' : 'status-inactive'}">${u.is_active ? 'Active' : 'Disabled'}</span></td>
        <td style="font-size:11px;font-family:monospace">${u.key_code || '—'}</td>
        <td>${new Date(u.created_at).toLocaleDateString('vi')}</td>
      </tr>`).join('')}</table>`;
  } catch (err) { console.error(err); }
}

// === Admin: Edit Key Modal ===
function showEditKey(keyId, maxServers, maxPorts, currentStatus) {
  const modal = document.createElement('div');
  modal.className = 'modal-overlay';
  modal.id = 'edit-key-modal';
  modal.innerHTML = `
    <div class="modal-content">
      <h3>✏️ Chỉnh sửa Key #${keyId}</h3>
      <div class="form-group">
        <label>Max Servers</label>
        <input type="number" id="edit-max-servers" value="${maxServers}" min="1" max="100">
      </div>
      <div class="form-group">
        <label>Max Ports/Server</label>
        <input type="number" id="edit-max-ports" value="${maxPorts}" min="1" max="100">
      </div>
      <div class="form-group">
        <label>Gia hạn thêm (ngày)</label>
        <input type="number" id="edit-extends-days" value="0" min="0" placeholder="0 = không đổi">
      </div>
      <div class="form-group">
        <label>Max Bandwidth (Mbps)</label>
        <input type="number" id="edit-max-bw" value="100" min="1">
      </div>
      <div style="display:flex;gap:8px;margin-top:16px">
        <button class="btn btn-primary" onclick="saveEditKey(${keyId})">💾 Lưu</button>
        <button class="btn btn-ghost" onclick="closeEditKey()">Hủy</button>
      </div>
    </div>`;
  document.body.appendChild(modal);
}
function closeEditKey() { document.getElementById('edit-key-modal')?.remove(); }

async function saveEditKey(keyId) {
  const data = {};
  const maxServers = parseInt(document.getElementById('edit-max-servers').value);
  const maxPorts = parseInt(document.getElementById('edit-max-ports').value);
  const extendsDays = parseInt(document.getElementById('edit-extends-days').value);
  const maxBw = parseInt(document.getElementById('edit-max-bw').value);

  if (maxServers) data.max_servers = maxServers;
  if (maxPorts) data.max_ports_per_server = maxPorts;
  if (extendsDays > 0) data.extends_days = extendsDays;
  if (maxBw) data.max_bandwidth_mbps = maxBw;

  try {
    await api('PUT', `/api/keys/${keyId}`, data);
    toast('Key đã cập nhật!', 'success');
    closeEditKey();
    loadAdmin();
  } catch (err) { toast(err.message, 'error'); }
}

async function revokeKey(keyId) {
  const confirmed = await customConfirm('Thu hồi key? Tất cả proxy sẽ bị tắt!');
  if (!confirmed) return;
  try { await api('DELETE', `/api/keys/${keyId}`); toast('Key đã thu hồi', 'success'); loadAdmin(); }
  catch (err) { toast(err.message, 'error'); }
}

async function reactivateKey(keyId) {
  try { await api('PUT', `/api/keys/${keyId}`, { status: 'active' }); toast('Key đã kích hoạt lại', 'success'); loadAdmin(); }
  catch (err) { toast(err.message, 'error'); }
}

async function createKey() {
  const max_servers = parseInt(document.getElementById('key-servers').value);
  const max_ports_per_server = parseInt(document.getElementById('key-ports').value);
  const expires_days = parseInt(document.getElementById('key-days').value);
  try {
    const res = await api('POST', '/api/keys', { max_servers, max_ports_per_server, expires_days });
    toast(`Key tạo: ${res.key.key_code}`, 'success');
    loadAdmin();
  } catch (err) { toast(err.message, 'error'); }
}

// === Mobile Menu ===
const sidebar = document.querySelector('.sidebar');
const menuToggle = document.getElementById('menu-toggle');
const overlay = document.createElement('div');
overlay.className = 'sidebar-overlay';
document.body.appendChild(overlay);

function toggleSidebar() {
  sidebar.classList.toggle('mobile-active');
  overlay.classList.toggle('active');
}

menuToggle.addEventListener('click', toggleSidebar);
overlay.addEventListener('click', toggleSidebar);

// Close sidebar on navigation (mobile)
document.querySelectorAll('.sidebar-menu li').forEach(li => {
  li.addEventListener('click', () => {
    if (window.innerWidth <= 768) {
      toggleSidebar();
    }
  });
});

// === WebSocket Logic ===
function initWebSocket() {
  if (!token) return;
  const wsUrl = API.replace('http', 'ws') + '/ws';
  const ws = new WebSocket(wsUrl);

  ws.onopen = () => {
    document.getElementById('api-status').textContent = 'Connected (Live)';
    document.getElementById('api-status').style.color = 'var(--success)';
  };

  ws.onmessage = (event) => {
    try {
      const msg = JSON.parse(event.data);
      if (msg.type === 'TRAFFIC_METRICS' && msg.data) {
        updateTrafficChart(msg.data);
      }
    } catch (e) { }
  };

  ws.onclose = () => {
    document.getElementById('api-status').textContent = 'Reconnecting...';
    document.getElementById('api-status').style.color = 'var(--warning)';
    setTimeout(initWebSocket, 1000);
  };
}

// === Init ===
if (token && user) {
  showDashboard();
  initWebSocket();
} else document.getElementById('login-screen').classList.add('active');
