import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List _notifications = [];
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
      final data = await api.getNotifications();
      if (!mounted) return;
      setState(() {
        _notifications = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  IconData _typeIcon(String? type) {
    switch (type) {
      case 'attack':
        return Icons.warning_amber;
      case 'system':
        return Icons.settings;
      case 'success':
        return Icons.check_circle;
      default:
        return Icons.info_outline;
    }
  }

  Color _typeColor(String? type) {
    switch (type) {
      case 'attack':
        return const Color(0xFFEF4444);
      case 'system':
        return const Color(0xFFF59E0B);
      case 'success':
        return const Color(0xFF10B981);
      default:
        return const Color(0xFF3B82F6);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1520),
        title: const Text('Thong bao', style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          if (_notifications.isNotEmpty)
            TextButton(
              onPressed: () async {
                await context.read<ApiService>().markAllNotificationsRead();
                _load();
              },
              child: const Text('Doc tat ca', style: TextStyle(fontSize: 13)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_none, size: 64, color: Colors.grey[700]),
                      const SizedBox(height: 12),
                      Text('Khong co thong bao', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _notifications.length,
                    itemBuilder: (_, i) {
                      final n = _notifications[i];
                      final isRead = n['is_read'] == 1 || n['is_read'] == true;
                      return Card(
                        color: isRead ? null : const Color(0xFF1A2332),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: _typeColor(n['type']).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(_typeIcon(n['type']), color: _typeColor(n['type']), size: 20),
                          ),
                          title: Text(
                            n['title'] ?? '',
                            style: TextStyle(
                              fontWeight: isRead ? FontWeight.w400 : FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(n['message'] ?? '', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                              const SizedBox(height: 4),
                              Text(
                                n['created_at']?.toString().substring(0, 16) ?? '',
                                style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                          trailing: !isRead
                              ? Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF3B82F6),
                                    shape: BoxShape.circle,
                                  ),
                                )
                              : null,
                          onTap: () async {
                            if (!isRead) {
                              await context.read<ApiService>().markNotificationRead(n['id']);
                              _load();
                            }
                          },
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
