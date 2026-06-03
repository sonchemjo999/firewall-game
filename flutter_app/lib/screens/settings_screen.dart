import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/theme_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _twoFaEnabled = false;
  bool _loading = true;
  String? _totpSecret;
  String? _otpAuthUrl;
  List<String> _backupCodes = [];
  final _tokenCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    try {
      final api = context.read<ApiService>();
      final data = await api.get2faStatus();
      if (!mounted) return;
      setState(() {
        _twoFaEnabled = data['enabled'] == true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _setup2FA() async {
    try {
      final api = context.read<ApiService>();
      final data = await api.setup2fa();
      if (!mounted) return;
      setState(() {
        _totpSecret = data['secret'];
        _otpAuthUrl = data['otpAuthUrl'];
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Loi: $e'), backgroundColor: const Color(0xFFEF4444)),
      );
    }
  }

  Future<void> _verify2FA() async {
    if (_tokenCtrl.text.isEmpty) return;
    try {
      final api = context.read<ApiService>();
      final data = await api.verify2fa(_tokenCtrl.text);
      if (!mounted) return;
      final codes = (data['backup_codes'] as List?)?.cast<String>() ?? [];
      setState(() {
        _twoFaEnabled = true;
        _backupCodes = codes;
        _totpSecret = null;
        _tokenCtrl.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('2FA da kich hoat!'), backgroundColor: Color(0xFF10B981)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Loi: $e'), backgroundColor: const Color(0xFFEF4444)),
      );
    }
  }

  Future<void> _disable2FA() async {
    if (_tokenCtrl.text.isEmpty) return;
    try {
      final api = context.read<ApiService>();
      await api.disable2fa(_tokenCtrl.text);
      if (!mounted) return;
      setState(() {
        _twoFaEnabled = false;
        _tokenCtrl.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('2FA da tat'), backgroundColor: Color(0xFF10B981)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Loi: $e'), backgroundColor: const Color(0xFFEF4444)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final theme = context.watch<ThemeService>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Cai dat')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sectionTitle('Tai khoan'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _infoRow(Icons.person, 'Username', auth.username ?? ''),
                        const Divider(height: 24),
                        _infoRow(Icons.shield, 'Role', (auth.role ?? 'basic').toUpperCase()),
                        if (auth.planName != null) ...[
                          const Divider(height: 24),
                          _infoRow(Icons.card_membership, 'Goi', auth.planName!),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _sectionTitle('Giao dien'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(theme.isDark ? Icons.dark_mode : Icons.light_mode,
                            color: cs.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Che do toi', style: TextStyle(fontWeight: FontWeight.w600)),
                              Text(theme.isDark ? 'Dang bat' : 'Dang tat',
                                  style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                            ],
                          ),
                        ),
                        Switch(
                          value: theme.isDark,
                          onChanged: (_) => theme.toggle(),
                          activeColor: cs.primary,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _sectionTitle('Bao mat 2FA'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.security, color: _twoFaEnabled ? const Color(0xFF10B981) : Colors.grey),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Xac thuc 2 buoc (TOTP)', style: TextStyle(fontWeight: FontWeight.w600)),
                                  Text(_twoFaEnabled ? 'Da kich hoat' : 'Chua kich hoat',
                                      style: TextStyle(fontSize: 12,
                                          color: _twoFaEnabled ? const Color(0xFF10B981) : Colors.grey[500])),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: (_twoFaEnabled ? const Color(0xFF10B981) : Colors.grey).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(_twoFaEnabled ? 'ON' : 'OFF',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                                      color: _twoFaEnabled ? const Color(0xFF10B981) : Colors.grey)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (!_twoFaEnabled && _totpSecret == null)
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _setup2FA,
                              icon: const Icon(Icons.qr_code),
                              label: const Text('Thiet lap 2FA'),
                            ),
                          ),
                        if (_totpSecret != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: cs.primary.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: cs.primary.withOpacity(0.2)),
                            ),
                            child: Column(
                              children: [
                                const Text('Nhap secret nay vao app xac thuc (Google Authenticator, Authy...)',
                                    style: TextStyle(fontSize: 13)),
                                const SizedBox(height: 8),
                                SelectableText(_totpSecret!,
                                    style: const TextStyle(fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _tokenCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Ma xac thuc 6 so',
                              prefixIcon: Icon(Icons.pin),
                            ),
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _verify2FA,
                              child: const Text('Xac nhan va kich hoat'),
                            ),
                          ),
                        ],
                        if (_twoFaEnabled) ...[
                          TextField(
                            controller: _tokenCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Ma xac thuc de tat 2FA',
                              prefixIcon: Icon(Icons.pin),
                            ),
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _disable2FA,
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                              child: const Text('Tat 2FA'),
                            ),
                          ),
                        ],
                        if (_backupCodes.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.2)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.warning_amber, color: Color(0xFFF59E0B), size: 18),
                                    SizedBox(width: 8),
                                    Text('Ma du phong (luu lai!)', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFF59E0B))),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: _backupCodes.map((c) => Chip(
                                    label: Text(c, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                                    backgroundColor: const Color(0xFFF59E0B).withOpacity(0.1),
                                  )).toList(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _sectionTitle('Thong tin'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _infoRow(Icons.info_outline, 'Phien ban', 'NRO Shield v2.2'),
                        const Divider(height: 24),
                        _infoRow(Icons.code, 'API', 'v2.2.0'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      context.read<AuthService>().logout();
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('Dang xuat'),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: Colors.grey[500])),
        const Spacer(),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}
