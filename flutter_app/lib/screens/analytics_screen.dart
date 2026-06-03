import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/api_service.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  Map<String, dynamic>? _overview;
  bool _loading = true;
  int _days = 7;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = context.read<ApiService>();
      final data = await api.getAnalyticsOverview(days: _days);
      if (!mounted) return;
      setState(() { _overview = data; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Phan tich tan cong'),
        actions: [
          PopupMenuButton<int>(
            icon: const Icon(Icons.calendar_today, size: 20),
            onSelected: (v) { _days = v; _load(); },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 1, child: Text('1 ngay')),
              const PopupMenuItem(value: 7, child: Text('7 ngay')),
              const PopupMenuItem(value: 30, child: Text('30 ngay')),
            ],
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _overview == null
              ? const Center(child: Text('Khong co du lieu'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildSummaryCards(cs),
                      const SizedBox(height: 20),
                      _buildAttackTypeChart(cs),
                      const SizedBox(height: 20),
                      _buildDailyChart(cs),
                      const SizedBox(height: 20),
                      _buildTopSources(cs),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSummaryCards(ColorScheme cs) {
    final totals = _overview!['totals'] ?? {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Tong quan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.8,
          children: [
            _statCard('Tan cong', '${totals['total_attacks'] ?? 0}', Icons.warning, const Color(0xFFEF4444)),
            _statCard('Max PPS', _formatNumber(totals['max_pps'] ?? 0), Icons.speed, cs.primary),
            _statCard('Max Mbps', '${(totals['max_mbps'] ?? 0).toStringAsFixed(1)}', Icons.trending_up, cs.secondary),
            _statCard('TB thoi gian', '${(totals['avg_duration'] ?? 0).toStringAsFixed(0)}s', Icons.timer, cs.tertiary),
          ],
        ),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ],
            ),
            const SizedBox(height: 6),
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildAttackTypeChart(ColorScheme cs) {
    final byType = (_overview!['by_type'] as List?) ?? [];
    if (byType.isEmpty) return const SizedBox.shrink();

    final colors = [
      const Color(0xFFEF4444), const Color(0xFFF59E0B), const Color(0xFF6C63FF),
      const Color(0xFF00D9FF), const Color(0xFF10B981), const Color(0xFFEC4899),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Loai tan cong', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                  sections: byType.asMap().entries.map((e) {
                    final d = e.value;
                    final color = colors[e.key % colors.length];
                    return PieChartSectionData(
                      value: (d['count'] ?? 0).toDouble(),
                      title: '${d['count']}',
                      color: color,
                      radius: 50,
                      titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: byType.asMap().entries.map((e) {
                final d = e.value;
                final color = colors[e.key % colors.length];
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text('${d['attack_type']}', style: const TextStyle(fontSize: 11)),
                  ],
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyChart(ColorScheme cs) {
    final byDay = (_overview!['by_day'] as List?) ?? [];
    if (byDay.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tan cong theo ngay', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (val, _) {
                          final idx = val.toInt();
                          if (idx < 0 || idx >= byDay.length) return const SizedBox.shrink();
                          final dateStr = byDay[idx]['date']?.toString() ?? '';
                          final parts = dateStr.split('-');
                          return Text(parts.length >= 3 ? '${parts[2]}/${parts[1]}' : dateStr,
                              style: const TextStyle(fontSize: 9));
                        },
                      ),
                    ),
                  ),
                  barGroups: byDay.asMap().entries.map((e) {
                    return BarChartGroupData(x: e.key, barRods: [
                      BarChartRodData(
                        toY: (e.value['count'] ?? 0).toDouble(),
                        color: cs.primary,
                        width: 12,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopSources(ColorScheme cs) {
    final sources = (_overview!['top_sources'] as List?) ?? [];
    if (sources.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Top nguon tan cong', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            ...sources.take(10).map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Text(s['source_country'] ?? '??',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(s['source_ip'] ?? '', style: TextStyle(fontSize: 12, color: Colors.grey[400]))),
                  Text('${s['count']}x', style: TextStyle(fontWeight: FontWeight.w600, color: cs.primary)),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  String _formatNumber(dynamic n) {
    final num val = n is num ? n : 0;
    if (val >= 1000000) return '${(val / 1000000).toStringAsFixed(1)}M';
    if (val >= 1000) return '${(val / 1000).toStringAsFixed(1)}K';
    return val.toString();
  }
}
