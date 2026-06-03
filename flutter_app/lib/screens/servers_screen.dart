import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class ServersScreen extends StatefulWidget {
  const ServersScreen({super.key});
  @override
  State<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends State<ServersScreen> {
  List _servers = [];
  List _games = [];
  bool _loading = true;

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
        api.getServers(),
        api.getGames(),
      ]);
      if (!mounted) return;
      setState(() {
        _servers = results[0] as List;
        _games = results[1] as List;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  IconData _gameIcon(String? code) {
    switch (code?.toLowerCase()) {
      case 'nro':
        return Icons.sports_esports;
      case 'samp':
        return Icons.directions_car;
      case 'minecraft':
        return Icons.landscape;
      case 'fivem':
        return Icons.local_police;
      case 'mu_online':
        return Icons.auto_awesome;
      case 'rust':
        return Icons.build;
      case 'ark':
        return Icons.pets;
      case 'cs2':
        return Icons.gps_fixed;
      case 'lineage2':
        return Icons.castle;
      default:
        return Icons.gamepad;
    }
  }

  void _showAdd() {
    final nameCtrl = TextEditingController();
    final ipCtrl = TextEditingController();
    String selectedGame = 'nro';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setBS) => Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Them Server', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Ten server',
                  hintText: 'VD: NRO Server 1',
                  prefixIcon: Icon(Icons.label_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ipCtrl,
                decoration: const InputDecoration(
                  labelText: 'IP Game Server',
                  hintText: '103.77.246.xxx',
                  prefixIcon: Icon(Icons.language),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedGame,
                decoration: const InputDecoration(
                  labelText: 'Loai game',
                  prefixIcon: Icon(Icons.sports_esports),
                ),
                items: _games.isEmpty
                    ? [const DropdownMenuItem(value: 'nro', child: Text('NRO (Dragon Boy)'))]
                    : _games.map<DropdownMenuItem<String>>((g) {
                        return DropdownMenuItem(
                          value: g['code']?.toString() ?? 'nro',
                          child: Text(g['name']?.toString() ?? g['code']?.toString() ?? 'Unknown'),
                        );
                      }).toList(),
                onChanged: (v) => setBS(() => selectedGame = v ?? 'nro'),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    if (ipCtrl.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Vui long nhap IP'), backgroundColor: Color(0xFFEF4444)),
                      );
                      return;
                    }
                    try {
                      final api = context.read<ApiService>();
                      await api.addServer(nameCtrl.text, ipCtrl.text, gameType: selectedGame);
                      Navigator.pop(context);
                      _load();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Server da them!'), backgroundColor: Color(0xFF10B981)),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Loi: $e'), backgroundColor: const Color(0xFFEF4444)),
                      );
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Them Server'),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: _servers.isEmpty
            ? ListView(
                children: [
                  const SizedBox(height: 100),
                  Center(
                    child: Column(
                      children: [
                        Icon(Icons.dns_outlined, size: 64, color: Colors.grey[700]),
                        const SizedBox(height: 12),
                        Text('Chua co server', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
                        const SizedBox(height: 8),
                        Text('Them server game de bat dau', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _servers.length,
                itemBuilder: (_, i) {
                  final s = _servers[i];
                  final gameType = s['game_type']?.toString() ?? 'nro';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF3B82F6).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(_gameIcon(gameType), color: const Color(0xFF3B82F6), size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(s['name']?.toString() ?? 'Server',
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                    const SizedBox(height: 2),
                                    Text(s['target_ip']?.toString() ?? '',
                                        style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Color(0xFF64748B))),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 20),
                                onPressed: () => _confirmDelete(s),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8B5CF6).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(_gameIcon(gameType), size: 12, color: const Color(0xFF8B5CF6)),
                                    const SizedBox(width: 4),
                                    Text(gameType.toUpperCase(),
                                        style: const TextStyle(fontSize: 10, color: Color(0xFF8B5CF6), fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('${s['port_count'] ?? 0} ports',
                                    style: const TextStyle(fontSize: 10, color: Color(0xFF10B981), fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAdd,
        backgroundColor: const Color(0xFF3B82F6),
        icon: const Icon(Icons.add),
        label: const Text('Them Server'),
      ),
    );
  }

  Future<void> _confirmDelete(dynamic server) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Xac nhan xoa'),
        content: Text('Ban co chac muon xoa server "${server['name']}"? Tat ca proxy lien quan cung se bi go bo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huy', style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xoa', style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await context.read<ApiService>().deleteServer(server['id']);
        _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Da xoa server'), backgroundColor: Color(0xFF10B981)),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Loi: $e'), backgroundColor: const Color(0xFFEF4444)),
          );
        }
      }
    }
  }
}
