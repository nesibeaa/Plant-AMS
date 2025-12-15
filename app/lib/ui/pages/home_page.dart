import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';
import '../../core/config.dart';
import '../../models/sensor_reading.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_container.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().loadDashboard();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 60, color: AppColors.danger),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                state.error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white70),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => state.loadDashboard(),
              icon: const Icon(Icons.refresh),
              label: const Text('Yeniden dene'),
            ),
          ],
        ),
      );
    }

    final latest = state.latest;

    return RefreshIndicator(
      onRefresh: () => state.loadDashboard(),
      backgroundColor: AppColors.glassSurface(0.3),
      color: AppColors.cyan,
      child: ListView(
        physics: const BouncingScrollPhysics(),
        children: [
          if (latest != null) ...[
            _SensorSection(latest: latest),
            const SizedBox(height: 20),
          ],
          _AlertsSection(
            alerts: state.alerts,
            onSeeAll: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AlertsPage(alerts: state.alerts),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          const _AnalysisHistorySection(),
          const SizedBox(height: 20),
          _ModelStatusCard(baseUrl: AppConfig.baseUrl),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SensorSection extends StatelessWidget {
  const _SensorSection({required this.latest});

  final LatestReadings latest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Son Sensör Verileri', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 520;
            return GridView.count(
              crossAxisCount: isWide ? 3 : 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: isWide ? 1.08 : 0.9,
              children: [
                _SensorCard(
                  icon: Icons.thermostat,
                  label: 'Sıcaklık',
                  value: '${latest.temp.toStringAsFixed(1)}°C',
                  status: _statusForValue('temp', latest.temp),
                  description: 'Eşik 16–26°C',
                ),
                _SensorCard(
                  icon: Icons.water_drop,
                  label: 'Nem',
                  value: '${latest.humidity.toStringAsFixed(1)}%',
                  status: _statusForValue('humidity', latest.humidity),
                  description: 'Eşik 45–80%',
                ),
                _SensorCard(
                  icon: Icons.cloud,
                  label: 'CO₂',
                  value: '${latest.co2.toStringAsFixed(0)} ppm',
                  status: _statusForValue('co2', latest.co2),
                  description: 'Eşik ≤ 1200 ppm',
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  _SensorStatus _statusForValue(String sensor, double value) {
    switch (sensor) {
      case 'temp':
        if (value < 16) return const _SensorStatus('Düşük', AppColors.amber);
        if (value > 26) return const _SensorStatus('Yüksek', AppColors.danger);
        return const _SensorStatus('Normal', AppColors.cyan);
      case 'humidity':
        if (value < 45) return const _SensorStatus('Düşük', AppColors.amber);
        if (value > 80) return const _SensorStatus('Yüksek', AppColors.danger);
        return const _SensorStatus('Normal', AppColors.cyan);
      case 'co2':
        if (value > 1200) return const _SensorStatus('Yüksek', AppColors.danger);
        if (value < 400) return const _SensorStatus('Düşük', AppColors.amber);
        return const _SensorStatus('Normal', AppColors.cyan);
      default:
        return const _SensorStatus('—', Colors.white54);
    }
  }
}

class _SensorStatus {
  const _SensorStatus(this.label, this.color);
  final String label;
  final Color color;
}

class _SensorCard extends StatelessWidget {
  const _SensorCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.status,
    required this.description,
  });

  final IconData icon;
  final String label;
  final String value;
  final _SensorStatus status;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassContainer(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                height: 42,
                width: 42,
                decoration: BoxDecoration(
                  color: status.color.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: status.color.withOpacity(0.35)),
                ),
                child: Icon(icon, color: status.color, size: 22),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: status.color.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: status.color.withOpacity(0.45)),
                ),
                child: Text(
                  status.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                        color: status.color,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            label,
            style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: theme.textTheme.labelSmall?.copyWith(color: Colors.white54),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
          ),
        ],
      ),
    );
  }
}

Color _alertColor(String level) {
  switch (level) {
    case 'warn':
      return AppColors.amber;
    case 'error':
    case 'crit':
      return AppColors.danger;
    case 'info':
    default:
      return AppColors.success;
  }
}

String _alertTime(String ts) {
  try {
    final time = DateTime.parse(ts);
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'Az önce';
    if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
    if (diff.inHours < 24) return '${diff.inHours} saat önce';
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  } catch (_) {
    return ts;
  }
}

class _AlertsSection extends StatelessWidget {
  const _AlertsSection({required this.alerts, required this.onSeeAll});

  final List<Map<String, dynamic>> alerts;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (alerts.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Son Uyarılar', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            GestureDetector(
              onTap: onSeeAll,
              child: Text(
                'Tümü',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54, decoration: TextDecoration.underline),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GlassContainer(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final alert in alerts.take(4))
                ListTile(
                  leading: Container(
                    height: 8,
                    width: 8,
                    decoration: BoxDecoration(
                      color: _alertColor(alert['level'] as String? ?? 'info'),
                      shape: BoxShape.circle,
                    ),
                  ),
                  title: Text(
                    alert['message'] as String? ?? 'Bilinmeyen uyarı',
                    style: theme.textTheme.bodyMedium,
                  ),
                  subtitle: Text(
                    _alertTime(alert['ts'] as String? ?? ''),
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54),
                  ),
                  trailing: Checkbox(
                    value: false,
                    onChanged: (_) {},
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    side: BorderSide(color: AppColors.glassSurface(0.2)),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class AlertsPage extends StatelessWidget {
  const AlertsPage({super.key, required this.alerts});

  final List<Map<String, dynamic>> alerts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Tüm Uyarılar'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: GlassContainer(
          padding: EdgeInsets.zero,
          child: ListView.separated(
            itemCount: alerts.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              color: AppColors.glassSurface(0.2),
            ),
            itemBuilder: (context, index) {
              final alert = alerts[index];
              final color = _alertColor(alert['level'] as String? ?? 'info');
              return ListTile(
                leading: Container(
                  height: 10,
                  width: 10,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                title: Text(
                  alert['message'] as String? ?? 'Bilinmeyen uyarı',
                  style: theme.textTheme.bodyMedium,
                ),
                subtitle: Text(
                  _alertTime(alert['ts'] as String? ?? ''),
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AnalysisHistorySection extends StatelessWidget {
  const _AnalysisHistorySection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final samples = [
      const _AnalysisHistoryCard('https://images.unsplash.com/photo-1525253086316-d0c936c814f8?q=80&w=600&auto=format&fit=crop', 'Sağlıklı • %92'),
      const _AnalysisHistoryCard('https://images.unsplash.com/photo-1438109491414-7198515b166b?q=80&w=600&auto=format&fit=crop', 'Mildiyö • %82'),
      const _AnalysisHistoryCard('https://images.unsplash.com/photo-1501004318641-b39e6451bec6?q=80&w=600&auto=format&fit=crop', 'Yaprak yanığı • %66'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Analiz Geçmişi', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            Text('Tümü', style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54)),
          ],
        ),
        const SizedBox(height: 12),
        GlassContainer(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: samples
                .map((sample) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: sample,
                      ),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _AnalysisHistoryCard extends StatelessWidget {
  const _AnalysisHistoryCard(this.imageUrl, this.caption);
  final String imageUrl;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: Image.network(imageUrl, fit: BoxFit.cover),
          ),
          Positioned(
            left: 6,
            right: 6,
            bottom: 6,
            child: GlassContainer(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              borderRadius: 10,
              colorOpacity: 0.22,
              child: Text(
                caption,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelStatusCard extends StatelessWidget {
  const _ModelStatusCard({required this.baseUrl});
  final String baseUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassContainer(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 8,
                width: 8,
                decoration: const BoxDecoration(color: AppColors.cyan, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text('Model Durumu', style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60)),
            ],
          ),
          const SizedBox(height: 8),
          Text('Indoor model aktif', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Veri kaynakları: sıcaklık, nem, CO₂ sensörleri • FastAPI backend • PyTorch modelleri',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54)),
          const SizedBox(height: 16),
          Text('API Sunucu Adresi', style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60)),
          const SizedBox(height: 6),
          GlassContainer(
            colorOpacity: 0.12,
            borderRadius: 12,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Text(baseUrl, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70)),
          ),
        ],
      ),
    );
  }
}
