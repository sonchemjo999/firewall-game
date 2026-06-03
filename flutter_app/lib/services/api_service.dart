import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'https://firewall.bacsycay.click';
  String? _token;

  void setToken(String token) => _token = token;
  void clearToken() => _token = null;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  dynamic _process(http.Response res) {
    dynamic data;
    try {
      data = jsonDecode(res.body);
    } catch (e) {
      if (res.statusCode >= 200 && res.statusCode < 300) return null;
      throw Exception('Error ${res.statusCode}: ${res.body}');
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return data;
    final msg = data is Map && data['error'] != null
        ? data['error']
        : 'Failed with status ${res.statusCode}';
    throw Exception(msg);
  }

  // === AUTH ===
  Future<Map<String, dynamic>> login(String username, String password) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/auth/login'),
      headers: _headers,
      body: jsonEncode({'username': username, 'password': password}),
    );
    final data = _process(res);
    _token = data['token'];
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> register(
      String username, String password, String keyCode) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/auth/register'),
      headers: _headers,
      body: jsonEncode(
          {'username': username, 'password': password, 'key_code': keyCode}),
    );
    final data = _process(res);
    _token = data['token'];
    return data as Map<String, dynamic>;
  }

  // === STATS ===
  Future<Map<String, dynamic>> getSummary() async {
    final res = await http.get(Uri.parse('$baseUrl/api/stats/summary'),
        headers: _headers);
    return _process(res) as Map<String, dynamic>;
  }

  Future<List> getAttacks({int limit = 20}) async {
    final res = await http.get(
        Uri.parse('$baseUrl/api/stats/attacks?limit=$limit'),
        headers: _headers);
    return _process(res) as List;
  }

  // === SERVERS ===
  Future<List> getServers() async {
    final res =
        await http.get(Uri.parse('$baseUrl/api/servers'), headers: _headers);
    return _process(res) as List;
  }

  Future<Map<String, dynamic>> addServer(String name, String ip,
      {String gameType = 'nro'}) async {
    final res = await http.post(Uri.parse('$baseUrl/api/servers'),
        headers: _headers,
        body: jsonEncode(
            {'name': name, 'target_ip': ip, 'game_type': gameType}));
    return _process(res) as Map<String, dynamic>;
  }

  Future<void> deleteServer(int id) async {
    final res = await http.delete(Uri.parse('$baseUrl/api/servers/$id'),
        headers: _headers);
    _process(res);
  }

  // === PROXIES ===
  Future<List> getProxies() async {
    final res =
        await http.get(Uri.parse('$baseUrl/api/proxy'), headers: _headers);
    return _process(res) as List;
  }

  Future<Map<String, dynamic>> createProxy(int serverId, int targetPort,
      {String protocol = 'tcp'}) async {
    final res = await http.post(Uri.parse('$baseUrl/api/proxy/create'),
        headers: _headers,
        body: jsonEncode({
          'server_id': serverId,
          'target_port': targetPort,
          'protocol': protocol
        }));
    return _process(res) as Map<String, dynamic>;
  }

  Future<void> toggleProxy(int id) async {
    final res = await http.put(Uri.parse('$baseUrl/api/proxy/$id/toggle'),
        headers: _headers);
    _process(res);
  }

  Future<void> deleteProxy(int id) async {
    final res = await http.delete(Uri.parse('$baseUrl/api/proxy/$id'),
        headers: _headers);
    _process(res);
  }

  // === GAMES ===
  Future<List> getGames() async {
    final res =
        await http.get(Uri.parse('$baseUrl/api/games'), headers: _headers);
    return _process(res) as List;
  }

  // === PLANS ===
  Future<List> getPlans() async {
    final res =
        await http.get(Uri.parse('$baseUrl/api/plans'), headers: _headers);
    return _process(res) as List;
  }

  // === NOTIFICATIONS ===
  Future<List> getNotifications() async {
    final res = await http.get(Uri.parse('$baseUrl/api/notifications'),
        headers: _headers);
    return _process(res) as List;
  }

  Future<Map<String, dynamic>> getNotificationCount() async {
    final res = await http.get(Uri.parse('$baseUrl/api/notifications/count'),
        headers: _headers);
    return _process(res) as Map<String, dynamic>;
  }

  Future<void> markNotificationRead(int id) async {
    final res = await http.put(
        Uri.parse('$baseUrl/api/notifications/$id/read'),
        headers: _headers);
    _process(res);
  }

  Future<void> markAllNotificationsRead() async {
    final res = await http.put(
        Uri.parse('$baseUrl/api/notifications/read-all'),
        headers: _headers);
    _process(res);
  }

  // === FIREWALL ===
  Future<List> getFirewallRules() async {
    final res = await http.get(Uri.parse('$baseUrl/api/firewall/rules'),
        headers: _headers);
    return _process(res) as List;
  }

  Future<Map<String, dynamic>> addFirewallRule(
      Map<String, dynamic> rule) async {
    final res = await http.post(Uri.parse('$baseUrl/api/firewall/rules'),
        headers: _headers, body: jsonEncode(rule));
    return _process(res) as Map<String, dynamic>;
  }

  Future<void> deleteFirewallRule(int id) async {
    final res = await http.delete(
        Uri.parse('$baseUrl/api/firewall/rules/$id'),
        headers: _headers);
    _process(res);
  }

  Future<Map<String, dynamic>> getSyncStatus() async {
    final res = await http.get(
        Uri.parse('$baseUrl/api/firewall/sync-status'),
        headers: _headers);
    return _process(res) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> triggerSync() async {
    final res = await http.post(Uri.parse('$baseUrl/api/firewall/sync'),
        headers: _headers);
    return _process(res) as Map<String, dynamic>;
  }

  // === ADMIN ===
  Future<Map<String, dynamic>> getAdminStats() async {
    final res = await http.get(Uri.parse('$baseUrl/api/admin/stats'),
        headers: _headers);
    return _process(res) as Map<String, dynamic>;
  }

  Future<List> getAdminUsers({String? search, String? role}) async {
    String url = '$baseUrl/api/admin/users?';
    if (search != null && search.isNotEmpty) url += 'search=$search&';
    if (role != null && role.isNotEmpty) url += 'role=$role&';
    final res = await http.get(Uri.parse(url), headers: _headers);
    final data = _process(res);
    if (data is Map && data['users'] != null) return data['users'] as List;
    return data as List;
  }

  Future<List> getAdminKeys() async {
    final res =
        await http.get(Uri.parse('$baseUrl/api/keys'), headers: _headers);
    return _process(res) as List;
  }

  Future<List> getAdminServers() async {
    final res = await http.get(Uri.parse('$baseUrl/api/admin/servers'),
        headers: _headers);
    return _process(res) as List;
  }

  Future<List> getAdminProxies() async {
    final res = await http.get(Uri.parse('$baseUrl/api/admin/proxies'),
        headers: _headers);
    return _process(res) as List;
  }

  Future<List> getAuditLogs({int limit = 50}) async {
    final res = await http.get(
        Uri.parse('$baseUrl/api/admin/audit-logs?limit=$limit'),
        headers: _headers);
    return _process(res) as List;
  }

  Future<Map<String, dynamic>> createKey(
      {int maxServers = 1,
      int maxPorts = 3,
      int days = 30,
      int bandwidth = 100}) async {
    final res = await http.post(Uri.parse('$baseUrl/api/keys'),
        headers: _headers,
        body: jsonEncode({
          'max_servers': maxServers,
          'max_ports_per_server': maxPorts,
          'expires_days': days,
          'max_bandwidth_mbps': bandwidth
        }));
    return _process(res) as Map<String, dynamic>;
  }

  Future<void> updateKey(int id, Map<String, dynamic> updates) async {
    final res = await http.put(Uri.parse('$baseUrl/api/keys/$id'),
        headers: _headers, body: jsonEncode(updates));
    _process(res);
  }

  Future<void> toggleUser(int id) async {
    final res = await http.put(
        Uri.parse('$baseUrl/api/admin/users/$id/toggle'),
        headers: _headers);
    _process(res);
  }

  Future<void> changeUserRole(int id, String role) async {
    final res = await http.put(Uri.parse('$baseUrl/api/admin/users/$id/role'),
        headers: _headers, body: jsonEncode({'role': role}));
    _process(res);
  }

  Future<void> assignUserPlan(int userId, int planId) async {
    final res = await http.put(
        Uri.parse('$baseUrl/api/admin/users/$userId/plan'),
        headers: _headers,
        body: jsonEncode({'plan_id': planId}));
    _process(res);
  }

  Future<void> deleteUser(int id) async {
    final res = await http.delete(Uri.parse('$baseUrl/api/admin/users/$id'),
        headers: _headers);
    _process(res);
  }

  Future<void> broadcastNotification(String title, String message,
      {String type = 'info'}) async {
    final res = await http.post(Uri.parse('$baseUrl/api/admin/broadcast'),
        headers: _headers,
        body: jsonEncode({'title': title, 'message': message, 'type': type}));
    _process(res);
  }

  // === 2FA ===
  Future<Map<String, dynamic>> get2faStatus() async {
    final res = await http.get(Uri.parse('$baseUrl/api/2fa/status'),
        headers: _headers);
    return _process(res) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> setup2fa() async {
    final res = await http.post(Uri.parse('$baseUrl/api/2fa/setup'),
        headers: _headers);
    return _process(res) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> verify2fa(String token) async {
    final res = await http.post(Uri.parse('$baseUrl/api/2fa/verify'),
        headers: _headers, body: jsonEncode({'token': token}));
    return _process(res) as Map<String, dynamic>;
  }

  Future<void> disable2fa(String token) async {
    final res = await http.post(Uri.parse('$baseUrl/api/2fa/disable'),
        headers: _headers, body: jsonEncode({'token': token}));
    _process(res);
  }

  // === SERVER HEALTH ===
  Future<List> getHealthSummary() async {
    final res = await http.get(Uri.parse('$baseUrl/api/health/summary'),
        headers: _headers);
    return _process(res) as List;
  }

  Future<List> getHealthHistory(int serverId, {int hours = 24}) async {
    final res = await http.get(
        Uri.parse('$baseUrl/api/health/$serverId/history?hours=$hours'),
        headers: _headers);
    return _process(res) as List;
  }

  Future<Map<String, dynamic>> triggerHealthCheck() async {
    final res = await http.post(Uri.parse('$baseUrl/api/health/check'),
        headers: _headers);
    return _process(res) as Map<String, dynamic>;
  }

  // === ATTACK ANALYTICS ===
  Future<Map<String, dynamic>> getAnalyticsOverview({int days = 7}) async {
    final res = await http.get(
        Uri.parse('$baseUrl/api/analytics/overview?days=$days'),
        headers: _headers);
    return _process(res) as Map<String, dynamic>;
  }

  Future<List> getAnalyticsTimeline({int hours = 24}) async {
    final res = await http.get(
        Uri.parse('$baseUrl/api/analytics/timeline?hours=$hours'),
        headers: _headers);
    return _process(res) as List;
  }

  Future<List> getAnalyticsCountries() async {
    final res = await http.get(Uri.parse('$baseUrl/api/analytics/countries'),
        headers: _headers);
    return _process(res) as List;
  }

  // === WEBHOOKS ===
  Future<List> getWebhooks() async {
    final res = await http.get(Uri.parse('$baseUrl/api/webhooks'),
        headers: _headers);
    return _process(res) as List;
  }

  Future<Map<String, dynamic>> createWebhook(
      String name, String url, String type, List<String> events) async {
    final res = await http.post(Uri.parse('$baseUrl/api/webhooks'),
        headers: _headers,
        body: jsonEncode(
            {'name': name, 'url': url, 'type': type, 'events': events}));
    return _process(res) as Map<String, dynamic>;
  }

  Future<void> deleteWebhook(int id) async {
    final res = await http.delete(Uri.parse('$baseUrl/api/webhooks/$id'),
        headers: _headers);
    _process(res);
  }

  Future<void> testWebhook(int id) async {
    final res = await http.post(Uri.parse('$baseUrl/api/webhooks/$id/test'),
        headers: _headers);
    _process(res);
  }

  // === BACKUPS ===
  Future<List> getBackups() async {
    final res = await http.get(Uri.parse('$baseUrl/api/backups'),
        headers: _headers);
    return _process(res) as List;
  }

  Future<Map<String, dynamic>> createBackup({String? name}) async {
    final res = await http.post(Uri.parse('$baseUrl/api/backups'),
        headers: _headers,
        body: jsonEncode({'name': name}));
    return _process(res) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> restoreBackup(int id) async {
    final res = await http.post(Uri.parse('$baseUrl/api/backups/$id/restore'),
        headers: _headers);
    return _process(res) as Map<String, dynamic>;
  }

  Future<void> deleteBackup(int id) async {
    final res = await http.delete(Uri.parse('$baseUrl/api/backups/$id'),
        headers: _headers);
    _process(res);
  }

  // === ALERT RULES ===
  Future<List> getAlertRules() async {
    final res = await http.get(Uri.parse('$baseUrl/api/alert-rules'),
        headers: _headers);
    return _process(res) as List;
  }

  Future<Map<String, dynamic>> createAlertRule(
      Map<String, dynamic> rule) async {
    final res = await http.post(Uri.parse('$baseUrl/api/alert-rules'),
        headers: _headers, body: jsonEncode(rule));
    return _process(res) as Map<String, dynamic>;
  }

  Future<void> toggleAlertRule(int id) async {
    final res = await http.put(
        Uri.parse('$baseUrl/api/alert-rules/$id/toggle'),
        headers: _headers);
    _process(res);
  }

  Future<void> deleteAlertRule(int id) async {
    final res = await http.delete(Uri.parse('$baseUrl/api/alert-rules/$id'),
        headers: _headers);
    _process(res);
  }
}
