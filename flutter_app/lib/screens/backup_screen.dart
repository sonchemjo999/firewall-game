import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  List _backups = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = context.read<ApiService>();
      final data = await api.getBackups();
      if (!mounted) return;
      setState(() { _backups = data; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _createBackup() async {
    final nameCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tao backup'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Ten backup (tuy chon)', hintText: 'VD: Backup truoc thay doi'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huy')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Tao')),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final api = context.read<ApiService>();
        final result = await api.createBackup(name: nameCtrl.text.isNotEmpty ? nameCtrl.text : null);
        _load();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup da tao - ${result['rules_count']} rules'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Loi: $e'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Phuc hoi')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createBackup,
        backgroundColor: cs.primary,
        icon: const Icon(Icons.backup),
        label: const Text('Tao backup'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _backups.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_off, size: 64, color: Colors.grey[600]),
                      const SizedBox(height: 12),
                      Text('Chua co backup nao', style: TextStyle(color: Colors.grey[500])),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _backups.length,
                    itemBuilder: (ctx, i) {
                      final b = _backups[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: cs.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.cloud_done, color: cs.primary),
                          ),
                          title: Text(b['name'] ?? 'Backup', style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('${b['rules_count'] ?? 0} rules - ${b['created_at'] ?? ''}',
                              style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.restore, color: cs.tertiary, size: 20),
                                tooltip: 'Phuc hoi',
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Phuc hoi backup?'),
                                      content: const Text('Cac rules tu backup se duoc phuc hoi.'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huy')),
                                        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Phuc hoi')),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    try {
                                      final api = context.read<ApiService>();
                                      final result = await api.restoreBackup(b['id']);
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Da phuc hoi ${result['restored']} rules'),
                                          backgroundColor: const Color(0xFF10B981),
                                        ),
                                      );
                                    } catch (e) {
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('$e'), backgroundColor: const Color(0xFFEF4444)),
                                      );
                                    }
                                  }
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, size: 20, color: Color(0xFFEF4444)),
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Xoa backup?'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huy')),
                                        ElevatedButton(
                                          onPressed: () => Navigator.pop(ctx, true),
                                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                                          child: const Text('Xoa'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    try {
                                      final api = context.read<ApiService>();
                                      await api.deleteBackup(b['id']);
                                      _load();
                                    } catch (e) {
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('$e'), backgroundColor: const Color(0xFFEF4444)),
                                      );
                                    }
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
