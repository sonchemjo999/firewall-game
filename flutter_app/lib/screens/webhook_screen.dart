import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';

class WebhookScreen extends StatefulWidget {
  const WebhookScreen({super.key});
  @override
  State<WebhookScreen> createState() => _WebhookScreenState();
}

class _WebhookScreenState extends State<WebhookScreen> {
  List _webhooks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = context.read<ApiService>();
      final data = await api.getWebhooks();
      if (!mounted) return;
      setState(() { _webhooks = data; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _showAddDialog() {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    String type = 'discord';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Them Webhook'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Ten')),
            const SizedBox(height: 12),
            TextField(controller: urlCtrl, decoration: const InputDecoration(labelText: 'URL', hintText: 'https://...')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: type,
              decoration: const InputDecoration(labelText: 'Loai'),
              items: const [
                DropdownMenuItem(value: 'discord', child: Text('Discord')),
                DropdownMenuItem(value: 'slack', child: Text('Slack')),
                DropdownMenuItem(value: 'telegram', child: Text('Telegram')),
                DropdownMenuItem(value: 'custom', child: Text('Custom')),
              ],
              onChanged: (v) => type = v ?? 'discord',
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huy')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.isEmpty || urlCtrl.text.isEmpty) return;
              Navigator.pop(ctx);
              try {
                final api = context.read<ApiService>();
                await api.createWebhook(nameCtrl.text, urlCtrl.text, type, ['all']);
                _load();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Loi: $e'), backgroundColor: const Color(0xFFEF4444)),
                );
              }
            },
            child: const Text('Tao'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Webhooks')),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        backgroundColor: cs.primary,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _webhooks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.webhook, size: 64, color: Colors.grey[600]),
                      const SizedBox(height: 12),
                      Text('Chua co webhook nao', style: TextStyle(color: Colors.grey[500])),
                      const SizedBox(height: 8),
                      const Text('Tao webhook de nhan thong bao qua Discord, Slack...', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _webhooks.length,
                    itemBuilder: (ctx, i) {
                      final w = _webhooks[i];
                      final isActive = w['is_active'] == 1;
                      IconData typeIcon;
                      switch (w['type']) {
                        case 'discord': typeIcon = Icons.discord; break;
                        case 'slack': typeIcon = Icons.chat; break;
                        case 'telegram': typeIcon = Icons.send; break;
                        default: typeIcon = Icons.webhook;
                      }

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: cs.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(typeIcon, color: cs.primary),
                          ),
                          title: Text(w['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            '${(w['type'] ?? '').toString().toUpperCase()} - ${isActive ? 'Hoat dong' : 'Tat'}',
                            style: TextStyle(fontSize: 12, color: isActive ? const Color(0xFF10B981) : Colors.grey),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.play_arrow, size: 20),
                                tooltip: 'Test',
                                onPressed: () async {
                                  try {
                                    final api = context.read<ApiService>();
                                    await api.testWebhook(w['id']);
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Test thanh cong!'), backgroundColor: Color(0xFF10B981)),
                                    );
                                  } catch (e) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('$e'), backgroundColor: const Color(0xFFEF4444)),
                                    );
                                  }
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, size: 20, color: Color(0xFFEF4444)),
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Xoa webhook?'),
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
                                      await api.deleteWebhook(w['id']);
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
