import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/websocket_service.dart';
import '../widgets/shield_logo.dart';
import 'servers_screen.dart';
import 'proxies_screen.dart';
import 'admin_screen.dart';
import 'notifications_screen.dart';
import 'firewall_screen.dart';
import 'attacks_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;
  Map<String, dynamic> _summary = {};
  bool _loading = true;
  int _unreadNotifications = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
    _connectWebSocket();
  }

  void _connectWebSocket() {
    final auth = context.read<AuthService>();
    final ws = context.read<WebSocketService>();
    if (auth.token != null) {
      ws.connect('https://firewall.bacsycay.click', auth.token!);
    }
  }

  Future<void> _loadData() async {
    try {
      final api = context.read<ApiService>();
      api.setToken(context.read<AuthService>().token!);
      final results = await Future.wait([
        api.getSummary(),
        api.getNotificationCount(),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as Map<String, dynamic>;
        final countData = results[1] as Map<String, dynamic>;
        _unreadNotifications = countData['unread'] ?? 0;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final ws = context.watch<WebSocketService>();
    final isAdmin = auth.isAdmin;

    final screens = <Widget>[
      _buildOverview(ws),
      const ServersScreen(),
      const ProxiesScreen(),
      const FirewallScreen(),
      if (isAdmin) const AdminScreen(),
    ];

    if (_currentIndex >= screens.length) _currentIndex = 0;

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const ShieldLogo(size: 32),
          const SizedBox(width: 10),
          ShaderMask(
            shaderCallback: (b) => const LinearGradient(
              colors: [Color(0xFF6C63FF), Color(0xFF00D9FF)],
            ).createShader(b),
            child: const Text('NRO Shield',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Colors.white)),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [const Color(0xFF00F5A0).withOpacity(0.2), const Color(0xFF00D9FF).withOpacity(0.2)],
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ws.connected ? const Color(0xFF00F5A0) : const Color(0xFFFF4757),
                ),
              ),
              const SizedBox(width: 4),
              Text(ws.connected ? 'LIVE' : 'OFFLINE',
                  style: TextStyle(fontSize: 9, color: ws.connected ? const Color(0xFF00F5A0) : const Color(0xFFFF4757),
                      fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            ]),
          ),
        ]),
        actions: [
          Stack(children: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined, size: 22),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
            ),
            if (_unreadNotifications > 0)
              Positioned(right: 8, top: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFFF4757), Color(0xFFFF6B81)]),
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  child: Text('$_unreadNotifications',
                      style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center),
                ),
              ),
          ]),
          PopupMenuButton(
            icon: Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [_roleColor(auth.role), _roleColor(auth.role).withOpacity(0.7)]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(child: Text((auth.username ?? '?')[0].toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14))),
            ),
            itemBuilder: (_) => [
              PopupMenuItem(enabled: false,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(auth.username ?? '', style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                  const SizedBox(height: 4),
                  Row(children: [
                    _roleBadge(auth.role),
                    if (auth.planName != null) ...[
                      const SizedBox(width: 6),
                      Text(auth.planName!, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                    ],
                  ]),
                ]),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                child: const Row(children: [Icon(Icons.history, size: 18), SizedBox(width: 8), Text('Lich su tan cong')]),
                onTap: () => Future.delayed(Duration.zero, () {
                  if (!mounted) return;
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const AttacksScreen()));
                }),
              ),
              PopupMenuItem(
                child: const Row(children: [
                  Icon(Icons.logout, size: 18, color: Color(0xFFFF4757)),
                  SizedBox(width: 8),
                  Text('Dang xuat', style: TextStyle(color: Color(0xFFFF4757))),
                ]),
                onTap: () {
                  context.read<WebSocketService>().disconnect();
                  auth.logout();
                },
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: screens[_currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0F1520),
          border: Border(top: BorderSide(color: const Color(0xFF1A2332).withOpacity(0.5))),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (i) => setState(() => _currentIndex = i),
          items: [
            const BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), activeIcon: Icon(Icons.dashboard_rounded), label: 'Tong quan'),
            const BottomNavigationBarItem(icon: Icon(Icons.dns_outlined), activeIcon: Icon(Icons.dns), label: 'Servers'),
            const BottomNavigationBarItem(icon: Icon(Icons.swap_horiz_outlined), activeIcon: Icon(Icons.swap_horiz), label: 'Proxy'),
            const BottomNavigationBarItem(icon: Icon(Icons.security_outlined), activeIcon: Icon(Icons.security), label: 'Firewall'),
            if (isAdmin)
              const BottomNavigationBarItem(icon: Icon(Icons.admin_panel_settings_outlined), activeIcon: Icon(Icons.admin_panel_settings), label: 'Admin'),
          ],
        ),
      ),
    );
  }

  Color _roleColor(String? role) {
    switch (role) {
      case 'admin': return const Color(0xFF8B5CF6);
      case 'reseller': return const Color(0xFFF59E0B);
      case 'premium': return const Color(0xFF10B981);
      default: return const Color(0xFF6C63FF);
    }
  }

  Widget _roleBadge(String? role) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [_roleColor(role).withOpacity(0.3), _roleColor(role).withOpacity(0.1)]),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _roleColor(role).withOpacity(0.3)),
      ),
      child: Text((role ?? 'user').toUpperCase(),
          style: TextStyle(fontSize: 10, color: _roleColor(role), fontWeight: FontWeight.w700, letterSpacing: 0.5)),
    );
  }

  Widget _buildOverview(WebSocketService ws) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF)));
    return RefreshIndicator(
      onRefresh: _loadData,
      color: const Color(0xFF6C63FF),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        // Live status bar
        if (ws.connected && ws.liveMetrics.isNotEmpty) ...[
          _liveMetricsBar(ws),
          const SizedBox(height: 16),
        ],
        // Stats grid
        Row(children: [
          _statCard(Icons.dns_rounded, '${_summary['total_servers'] ?? 0}', 'Servers',
              const Color(0xFF6C63FF), const Color(0xFF8B7DFF)),
          const SizedBox(width: 12),
          _statCard(Icons.swap_horiz_rounded, '${_summary['active_ports'] ?? 0}/${_summary['total_ports'] ?? 0}', 'Ports',
              const Color(0xFF00D9FF), const Color(0xFF00F5A0)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _statCard(Icons.warning_amber_rounded, '${_summary['attacks_today'] ?? 0}', 'Tan cong',
              const Color(0xFFFF4757), const Color(0xFFFF6B81)),
          const SizedBox(width: 12),
          _statCard(Icons.smart_toy_rounded, 'Active', 'AI Engine',
              const Color(0xFF00F5A0), const Color(0xFF00D9FF)),
        ]),
        const SizedBox(height: 20),
        // Quick actions
        Card(
          child: Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.flash_on_rounded, color: Color(0xFFF59E0B), size: 18),
                ),
                const SizedBox(width: 10),
                const Text('Thao tac nhanh', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _actionBtn(Icons.add_rounded, 'Them Server', const Color(0xFF6C63FF), () => setState(() => _currentIndex = 1))),
                const SizedBox(width: 10),
                Expanded(child: _actionBtn(Icons.swap_horiz_rounded, 'Tao Proxy', const Color(0xFF00D9FF), () => setState(() => _currentIndex = 2))),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _actionBtn(Icons.history_rounded, 'Tan cong', const Color(0xFFFF4757), () =>
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const AttacksScreen())))),
                const SizedBox(width: 10),
                Expanded(child: _actionBtn(Icons.security_rounded, 'Firewall', const Color(0xFF00F5A0), () => setState(() => _currentIndex = 3))),
              ]),
            ],
          )),
        ),
        const SizedBox(height: 16),
        // Guide
        Card(
          child: Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C63FF).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.menu_book_rounded, color: Color(0xFF6C63FF), size: 18),
                ),
                const SizedBox(width: 10),
                const Text('Huong dan su dung', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 14),
              _stepRow(1, 'Them server game (nhap IP that)', Icons.dns_rounded),
              _stepRow(2, 'Chon loai game phu hop', Icons.sports_esports_rounded),
              _stepRow(3, 'Tao proxy port -> nhan IP Shield', Icons.swap_horiz_rounded),
              _stepRow(4, 'Dung IP Shield de ket noi game', Icons.link_rounded),
              _stepRow(5, 'AI tu bao ve khoi DDoS', Icons.smart_toy_rounded),
            ],
          )),
        ),
      ]),
    );
  }

  Widget _liveMetricsBar(WebSocketService ws) {
    final m = ws.liveMetrics;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF6C63FF).withOpacity(0.1), const Color(0xFF00D9FF).withOpacity(0.05)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.2)),
      ),
      child: Row(children: [
        Container(
          width: 8, height: 8,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF00F5A0)),
        ),
        const SizedBox(width: 8),
        const Text('LIVE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF00F5A0), letterSpacing: 0.5)),
        const SizedBox(width: 16),
        Expanded(child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _metricItem('PPS', '${m['pps'] ?? 0}'),
          _metricItem('Mbps', '${m['mbps'] ?? 0}'),
          _metricItem('Conn', '${m['connections'] ?? 0}'),
        ])),
      ]),
    );
  }

  Widget _metricItem(String label, String value) {
    return Column(children: [
      Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF00D9FF))),
      Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
    ]);
  }

  Widget _statCard(IconData icon, String value, String label, Color c1, Color c2) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1520),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF1A2332)),
        ),
        child: Row(children: [
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [c1.withOpacity(0.2), c2.withOpacity(0.1)]),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c1.withOpacity(0.2)),
            ),
            child: Icon(icon, color: c1, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500]), overflow: TextOverflow.ellipsis),
          ])),
        ]),
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return Material(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }

  Widget _stepRow(int step, String text, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [const Color(0xFF6C63FF).withOpacity(0.2), const Color(0xFF00D9FF).withOpacity(0.1)],
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(child: Text('$step', style: const TextStyle(fontSize: 12, color: Color(0xFF6C63FF), fontWeight: FontWeight.w700))),
        ),
        const SizedBox(width: 12),
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: Colors.grey[400], fontSize: 13))),
      ]),
    );
  }
}
