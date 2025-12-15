import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';
import '../../models/sensor_reading.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_container.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
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
            Text(state.error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => state.loadDashboard(),
              child: const Text('Yeniden dene'),
            )
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => state.loadDashboard(),
      backgroundColor: AppColors.glassSurface(0.3),
      color: AppColors.cyan,
      child: ListView(
        physics: const BouncingScrollPhysics(),
        children: [
          _ChartCard(
            title: 'Sıcaklık (Son 24 Saat)',
            subtitle: 'Eşik: 18–28°C',
            color: const Color(0xFF38D39F),
            sensor: 'temp',
            points: state.tempSeries,
          ),
          _ChartCard(
            title: 'Nem (Son 24 Saat)',
            subtitle: 'Eşik: 40–70%',
            color: const Color(0xFF38BDF8),
            sensor: 'humidity',
            points: state.humiditySeries,
          ),
          _ChartCard(
            title: 'CO₂ (Son 24 Saat)',
            subtitle: 'Eşik: 400–1000 ppm',
            color: const Color(0xFFF472B6),
            sensor: 'co2',
            points: state.co2Series,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.sensor,
    required this.points,
  });

  final String title;
  final String subtitle;
  final Color color;
  final String sensor;
  final List<SensorPoint> points;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = _unit(sensor);
    final spots = _toSpots(points);
    final values = points.map((p) => p.value).toList();
    final minValue = values.isEmpty ? 0.0 : values.reduce((a, b) => a < b ? a : b);
    final maxValue = values.isEmpty ? 0.0 : values.reduce((a, b) => a > b ? a : b);
    final avgValue = values.isEmpty ? 0.0 : values.reduce((a, b) => a + b) / values.length;
    final yTicks = _calculateYTicks(minValue, maxValue);
    final yInterval = yTicks.length >= 2 ? yTicks[1] - yTicks[0] : 1.0;
    final minChartY = yTicks.isNotEmpty ? yTicks.first : (minValue - 1);
    final maxChartY = yTicks.isNotEmpty ? yTicks.last : (maxValue + 1);
    final xTickIndexes = _calculateXTickIndexes(points.length);

    return GlassContainer(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54)),
                ],
              ),
              Text('${points.length} veri', style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _StatBadge(label: 'Ortalama', value: '${avgValue.toStringAsFixed(1)}$unit', color: color.withOpacity(0.32)),
              const SizedBox(width: 12),
              _StatBadge(label: 'Maksimum', value: '${maxValue.toStringAsFixed(1)}$unit', color: AppColors.success.withOpacity(0.25)),
              const SizedBox(width: 12),
              _StatBadge(label: 'Minimum', value: '${minValue.toStringAsFixed(1)}$unit', color: AppColors.amber.withOpacity(0.25)),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 240,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: yInterval,
                  getDrawingHorizontalLine: (value) => FlLine(color: Colors.white.withOpacity(0.06), strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 52,
                      interval: yInterval,
                      getTitlesWidget: (value, meta) {
                        final shouldShow = yTicks.any((tick) => (value - tick).abs() < (yInterval * 0.05));
                        if (!shouldShow) return const SizedBox.shrink();
                        final formatted = unit == 'ppm' && value.abs() >= 1000
                            ? '${(value / 1000).toStringAsFixed(1)}k'
                            : value.toStringAsFixed(value.abs() < 10 ? 1 : 0);
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text('$formatted$unit', style: theme.textTheme.labelSmall?.copyWith(color: Colors.white60)),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= points.length) return const SizedBox.shrink();
                        if (!xTickIndexes.contains(index)) return const SizedBox.shrink();
                        final time = points[index].time;
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            DateFormat.Hm().format(time),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.white54,
                              fontSize: 10,
                              height: 1.0,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: spots.isEmpty ? 0 : spots.length - 1,
                minY: minChartY,
                maxY: maxChartY,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    color: color,
                    isCurved: true,
                    barWidth: 3,
                    dotData: FlDotData(show: spots.length <= 12),
                    belowBarData: BarAreaData(show: true, color: color.withOpacity(0.12)),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touched) {
                      return touched.map((barSpot) {
                        final index = barSpot.x.toInt();
                        if (index < 0 || index >= points.length) return null;
                        final reading = points[index];
                        return LineTooltipItem(
                          '${reading.value.toStringAsFixed(1)}$unit\n${DateFormat.Hm().format(reading.time)}',
                          theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ) ??
                              const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                        );
                      }).whereType<LineTooltipItem>().toList();
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<FlSpot> _toSpots(List<SensorPoint> pts) {
    if (pts.isEmpty) return [];
    return List.generate(pts.length, (i) => FlSpot(i.toDouble(), pts[i].value));
  }

  List<int> _calculateXTickIndexes(int count) {
    if (count <= 0) return const [];
    if (count == 1) return const [0];
    final maxTicks = math.min(4, count);
    final step = (count - 1) / (maxTicks - 1);
    final indexes = <int>{};
    for (int i = 0; i < maxTicks; i++) {
      indexes.add((i * step).round().clamp(0, count - 1));
    }
    final sorted = indexes.toList()..sort();
    return sorted;
  }

  List<double> _calculateYTicks(double min, double max) {
    if (min == max) {
      final base = min == 0 ? 1.0 : (min.abs() * 0.1).clamp(0.5, 5.0);
      return [min - base, min, min + base];
    }
    final range = max - min;
    final rawStep = range / 4;
    final step = _niceStep(rawStep);
    final start = (min / step).floor() * step;
    final end = (max / step).ceil() * step;
    final ticks = <double>[];
    for (double v = start; v <= end + step * 0.5; v += step) {
      final value = double.parse(v.toStringAsFixed(3));
      ticks.add(value);
      if (ticks.length > 8) break;
    }
    return ticks;
  }

  double _niceStep(double raw) {
    if (raw == 0 || raw.isNaN || raw.isInfinite) return 1;
    final exponent = raw <= 0 ? 0 : (math.log(raw) / math.ln10).floor();
    final base = math.pow(10, exponent).toDouble();
    final fraction = raw / base;
    double niceFraction;
    if (fraction <= 1) {
      niceFraction = 1;
    } else if (fraction <= 2) {
      niceFraction = 2;
    } else if (fraction <= 5) {
      niceFraction = 5;
    } else {
      niceFraction = 10;
    }
    return niceFraction * base;
  }

  String _unit(String sensor) {
    switch (sensor) {
      case 'temp':
        return '°C';
      case 'humidity':
        return '%';
      case 'co2':
        return 'ppm';
      default:
        return '';
    }
  }
}

class _StatBadge extends StatelessWidget {
  const _StatBadge({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: GlassContainer(
        colorOpacity: 0.12,
        borderRadius: 14,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelSmall?.copyWith(color: Colors.white60)),
            const SizedBox(height: 6),
            Text(value, style: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
