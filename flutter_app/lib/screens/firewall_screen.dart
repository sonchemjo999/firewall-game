import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class FirewallScreen extends StatefulWidget {
  const FirewallScreen({super.key});
  @override
  State<FirewallScreen> createState() => _FirewallScreenState();
}

class _FirewallScreenState extends State<FirewallScreen> {
  List _rules = [];
  Map<String, dynamic> _syncStatus = {};
  bool _loading = true;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<ApiService>();
    api.setToken(context.read<AuthService>().token!);
    try {
      final results = await Future.wait([
        api.getFirewallRules(),
        api.getSyncStatus(),
      ]);
      if (!mounted) return;
      setState(() {
        _rules = results[0] as List;
        _syncStatus = results[1] as Map<String, dynamic>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _triggerSync() async {
    setState(() => _syncing = true);
    try {
      await context.read<ApiService>().triggerSync();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dong bo thanh cong!'), backgroundColor: Color(0xFF10B981)),
        );
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Loi: $e'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    }
    if (mounted) setState(() => _syncing = false);
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.read<AuthService>().isAdmin;

    if (_loading) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Sync Status Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _syncStatus['status'] == 'success'
                              ? const Color(0xFF10B981)
                              : const Color(0xFFF59E0B),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('Trang thai Firewall',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      if (isAdmin)
                        SizedBox(
                          height: 32,
                          child: ElevatedButton.icon(
                            onPressed: _syncing ? null : _triggerSync,
                            icon: _syncing
                                ? const SizedBox(
                                    width: 14, height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.sync, size: 16),
                            label: Text(_syncing ? 'Dang...' : 'Dong bo', style: const TextStyle(fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              backgroundColor: const Color(0xFF10B981),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _infoChip('Lan cuoi', _syncStatus['synced_at']?.toString().substring(0, 16) ?? 'N/A'),
                      const SizedBox(width: 8),
                      _infoChip('Trang thai', _syncStatus['status']?.toString() ?? 'unknown'),
                      const SizedBox(width: 8),
                      _infoChip('Rules', _syncStatus['rules_applied']?.toString() ?? '0'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Rules List
          Row(
            children: [
              const Text('Firewall Rules', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('${_rules.length} rules', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
            ],
          ),
          const SizedBox(height: 12),

          if (_rules.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.security, size: 48, color: Colors.grey[700]),
                      const SizedBox(height: 12),
                      Text('Chua co custom rules', style: TextStyle(color: Colors.grey[500])),
                    ],
                  ),
                ),
              ),
            )
          else
            ..._rules.map((r) => _ruleCard(r)),
        ],
      ),
    );
  }

  Widget _ruleCard(Map<String, dynamic> rule) {
    final isEnabled = rule['is_enabled'] == 1 || rule['is_enabled'] == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isEnabled ? const Color(0xFF10B981) : Colors.grey,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(rule["name"] ?? "Rule #${rule["id"]}",
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(rule['chain'] ?? 'INPUT',
                      style: const TextStyle(fontSize: 10, color: Color(0xFF3B82F6), fontFamily: 'monospace')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0E17),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                rule['rule_content'] ?? '',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF10B981)),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                if (rule['protocol'] != null)
                  _tagChip(rule['protocol'].toString().toUpperCase()),
                if (rule['source_ip'] != null) ...[
                  const SizedBox(width: 6),
                  _tagChip("Src: ${rule["source_ip"]}"),
                ],
                if (rule['dest_port'] != null) ...[
                  const SizedBox(width: 6),
                  _tagChip("Port: ${rule["dest_port"]}"),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0E17),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          children: [
            Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  Widget _tagChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
    );
  }
}
