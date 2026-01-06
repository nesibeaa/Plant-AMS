import 'dart:math' as math;
import 'dart:io';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../../state/app_state.dart';
import '../../models/sensor_reading.dart';
import '../../services/api_service.dart';
import '../theme/app_theme.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  int _selectedSensorIndex = 0; // 0: Temp, 1: Humidity, 2: CO2

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
    final theme = Theme.of(context);

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

    List<SensorPoint> currentPoints;
    Color chartColor;
    Color chartAreaColor;
    String chartUnit;
    String chartTitle;
    String chartSubtitle;
    double minThreshold;
    double maxThreshold;

    switch (_selectedSensorIndex) {
      case 0: // Temperature
        currentPoints = state.tempSeries;
        chartColor = AppColors.tempColor;
        chartAreaColor = AppColors.tempColor.withOpacity(0.14);
        chartUnit = '°C';
        chartTitle = 'Sıcaklık';
        chartSubtitle = '';
        minThreshold = 18;
        maxThreshold = 28;
        break;
      case 1: // Humidity
        currentPoints = state.humiditySeries;
        chartColor = AppColors.humidityColor;
        chartAreaColor = AppColors.humidityColor.withOpacity(0.16);
        chartUnit = '%';
        chartTitle = 'Nem';
        chartSubtitle = '';
        minThreshold = 40;
        maxThreshold = 70;
        break;
      case 2: // CO2
        currentPoints = state.co2Series;
        chartColor = AppColors.co2Color;
        chartAreaColor = AppColors.co2Color.withOpacity(0.16);
        chartUnit = 'ppm';
        chartTitle = 'CO₂';
        chartSubtitle = '';
        minThreshold = 400;
        maxThreshold = 1000;
        break;
      default:
        currentPoints = [];
        chartColor = AppColors.primary;
        chartAreaColor = AppColors.primary.withOpacity(0.1);
        chartUnit = '';
        chartTitle = '';
        chartSubtitle = '';
        minThreshold = 0;
        maxThreshold = 0;
    }

    // Filter by range (24 saat)
    final now = DateTime.now();
    final filteredPoints = currentPoints.where((p) => now.difference(p.time).inHours <= 24).toList();

    // Verileri grafik için optimize et (çok fazla nokta varsa örnekle)
    final displayPoints = _downsampleData(filteredPoints, true);

    final values = filteredPoints.map((p) => p.value).toList();
    final minValue = values.isEmpty ? 0.0 : values.reduce((a, b) => a < b ? a : b);
    final maxValue = values.isEmpty ? 0.0 : values.reduce((a, b) => a > b ? a : b);
    final avgValue = values.isEmpty ? 0.0 : values.reduce((a, b) => a + b) / values.length;

    return RefreshIndicator(
      onRefresh: () => context.read<AppState>().loadDashboard(),
      backgroundColor: AppColors.cardBackground,
      color: AppColors.primary,
      child: ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          Text('Grafikler', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500)),
          const SizedBox(height: 16),
          // Sensor Tabs
          Row(
            children: [
              _SensorTab(
                label: 'Sıcaklık',
                icon: Icons.thermostat_outlined,
                isActive: _selectedSensorIndex == 0,
                onTap: () => setState(() => _selectedSensorIndex = 0),
                activeColor: AppColors.tempColor,
              ),
              const SizedBox(width: 8),
              _SensorTab(
                label: 'Nem',
                icon: Icons.water_drop_outlined,
                isActive: _selectedSensorIndex == 1,
                onTap: () => setState(() => _selectedSensorIndex = 1),
                activeColor: AppColors.humidityColor,
              ),
              const SizedBox(width: 8),
              _SensorTab(
                label: 'CO₂',
                icon: Icons.cloud_outlined,
                isActive: _selectedSensorIndex == 2,
                onTap: () => setState(() => _selectedSensorIndex = 2),
                activeColor: AppColors.co2Color,
              ),
            ],
          ),
          const SizedBox(height: 20),
          _ChartCard(
            title: chartTitle,
            subtitle: chartSubtitle,
            color: chartColor,
            areaColor: chartAreaColor,
            points: displayPoints,
            unit: chartUnit,
            minThreshold: minThreshold,
            maxThreshold: maxThreshold,
            minValue: minValue,
            maxValue: maxValue,
            avgValue: avgValue,
            is24Hour: true,
          ),
          const SizedBox(height: 24),
          // Rapor Al Butonu
          _ExportReportButton(
            onPressed: () => _exportToCSV(context),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _exportToCSV(BuildContext context) async {
    // Loading dialog'u göster
    if (!context.mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: Center(
          child: Card(
            color: AppColors.cardBackground,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Rapor oluşturuluyor...',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      final apiService = ApiService();
      
      // Tüm sensör verilerini çek
      final allReadings = await apiService.getAllReadingsForExport();
      
      // Dialog'u kapat
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      
      if (allReadings.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Export edilecek veri bulunamadı')),
          );
        }
        return;
      }

      // CSV formatına çevir
      final csvContent = _generateCSV(allReadings);
      
      // Geçici dosya oluştur
      final directory = await getTemporaryDirectory();
      final timestamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
      final file = File('${directory.path}/sensor_raporu_$timestamp.csv');
      await file.writeAsString(csvContent);
      
      // Share sheet'i göster
      if (context.mounted) {
        await Share.shareXFiles(
          [XFile(file.path)],
          text: 'Sensör Verileri Raporu',
          subject: 'Sensor Raporu',
        );
      }
    } catch (e) {
      // Dialog'u kapat
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rapor oluşturulurken hata oluştu: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  String _generateCSV(List<Map<String, dynamic>> readings) {
    final buffer = StringBuffer();
    
    // CSV Header
    buffer.writeln('Tarih, Saat, Sensör ID, Tip, Değer');
    
    // Verileri sırala (zaman sırasına göre)
    final sortedReadings = List<Map<String, dynamic>>.from(readings);
    sortedReadings.sort((a, b) {
      final aTs = DateTime.parse(a['ts'] as String);
      final bTs = DateTime.parse(b['ts'] as String);
      return aTs.compareTo(bTs);
    });
    
    // CSV satırları
    for (final reading in sortedReadings) {
      try {
        final tsStr = reading['ts'] as String;
        DateTime ts;
        if (tsStr.endsWith('Z')) {
          ts = DateTime.parse(tsStr).toUtc();
        } else {
          ts = DateTime.parse(tsStr + 'Z').toUtc();
        }
        // UTC'den Türkiye saatine çevir
        final turkeyTime = ts.add(const Duration(hours: 3));
        
        final date = DateFormat('yyyy-MM-dd').format(turkeyTime);
        final time = DateFormat('HH:mm:ss').format(turkeyTime);
        final sensorId = reading['sensor_id'] as String? ?? '';
        final type = reading['type'] as String? ?? '';
        final value = reading['value']?.toString() ?? '';
        
        buffer.writeln('$date,$time,$sensorId,$type,$value');
      } catch (e) {
        // Hatalı veriyi atla
        continue;
      }
    }
    
    return buffer.toString();
  }

  /// Verileri grafik için optimize eder - çok fazla nokta varsa örnekler
  /// 24 saat için: maksimum 48 nokta (her 30 dakikada bir)
  /// 7 gün için: maksimum 28 nokta (her 6 saatte bir)
  List<SensorPoint> _downsampleData(List<SensorPoint> points, bool is24Hour) {
    if (points.isEmpty) return points;
    
    final targetCount = is24Hour ? 48 : 28;
    
    // Eğer veri sayısı hedeften az ise, olduğu gibi döndür
    if (points.length <= targetCount) return points;
    
    // Zaman sırasına göre sıralı olduğundan emin ol
    final sorted = List<SensorPoint>.from(points)..sort((a, b) => a.time.compareTo(b.time));
    
    // İlk ve son noktayı her zaman dahil et
    final result = <SensorPoint>[sorted.first];
    
    // Aralıkları hesapla
    final step = (sorted.length - 1) / (targetCount - 1);
    
    for (int i = 1; i < targetCount - 1; i++) {
      final index = (i * step).round().clamp(1, sorted.length - 2);
      result.add(sorted[index]);
    }
    
    // Son noktayı ekle (eğer ilk noktadan farklıysa)
    if (sorted.last.time != sorted.first.time) {
      result.add(sorted.last);
    }
    
    return result;
  }
}

class _SensorTab extends StatelessWidget {
  const _SensorTab({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
    required this.activeColor,
  });

  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? activeColor.withOpacity(0.1) : AppColors.cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive ? activeColor.withOpacity(0.4) : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: isActive ? activeColor : AppColors.textSecondary),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isActive ? activeColor : AppColors.textSecondary,
                  fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.areaColor,
    required this.points,
    required this.unit,
    required this.minThreshold,
    required this.maxThreshold,
    required this.minValue,
    required this.maxValue,
    required this.avgValue,
    required this.is24Hour,
  });

  final String title;
  final String subtitle;
  final Color color;
  final Color areaColor;
  final List<SensorPoint> points;
  final String unit;
  final double minThreshold;
  final double maxThreshold;
  final double minValue;
  final double maxValue;
  final double avgValue;
  final bool is24Hour;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spots = _toSpots(points);
    final yTicks = _calculateYTicks(minValue, maxValue, minThreshold, maxThreshold);
    final yInterval = yTicks.length >= 2 ? yTicks[1] - yTicks[0] : 1.0;
    final minChartY = yTicks.isNotEmpty ? yTicks.first : (minValue - 1);
    final maxChartY = yTicks.isNotEmpty ? yTicks.last : (maxValue + 1);
    final xTickIndexes = _calculateXTickIndexes(points.length, is24Hour);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500)),
          const SizedBox(height: 16),
          Row(
            children: [
              _StatBadge(label: 'Ortalama', value: '${avgValue.toStringAsFixed(1)}$unit', color: color),
              const SizedBox(width: 8),
              _StatBadge(label: 'Maksimum', value: '${maxValue.toStringAsFixed(1)}$unit', color: color),
              const SizedBox(width: 8),
              _StatBadge(label: 'Minimum', value: '${minValue.toStringAsFixed(1)}$unit', color: color),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 240,
            child: points.isEmpty
                ? Center(
                    child: Text(
                      'Veri bulunamadı',
                      style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                    ),
                  )
                : LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: yInterval > 0 ? yInterval : null,
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: AppColors.border.withOpacity(0.5),
                          strokeWidth: 1,
                        ),
                      ),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            interval: yInterval > 0 ? yInterval : null,
                            getTitlesWidget: (value, meta) {
                              final shouldShow = yTicks.any((tick) => (value - tick).abs() < (yInterval * 0.05));
                              if (!shouldShow) return const SizedBox.shrink();
                              final formatted = unit == 'ppm' && value.abs() >= 1000
                                  ? '${(value / 1000).toStringAsFixed(1)}k'
                                  : value.toStringAsFixed(value.abs() < 10 ? 1 : 0);
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Text(
                                  '$formatted$unit',
                                  style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textSecondary),
                                ),
                              );
                            },
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            interval: 1,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (index < 0 || index >= points.length) return const SizedBox.shrink();
                              if (!xTickIndexes.contains(index)) return const SizedBox.shrink();
                              final time = points[index].time;
                              String formatted;
                              if (is24Hour) {
                                formatted = DateFormat.Hm().format(time);
                              } else {
                                // 7 gün için: Sadece gün adı (kısa ve temiz)
                                final weekdayNames = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
                                formatted = weekdayNames[time.weekday - 1];
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  formatted,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: AppColors.textTertiary,
                                    fontSize: is24Hour ? 10 : 11,
                                    height: 1.0,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
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
                      maxX: spots.isEmpty ? 0 : math.max(0, spots.length - 1).toDouble(),
                      minY: minChartY,
                      maxY: maxChartY,
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          color: color,
                          isCurved: true,
                          barWidth: 2,
                          dotData: FlDotData(show: spots.length <= 12),
                          belowBarData: BarAreaData(
                            show: true,
                            color: areaColor,
                            cutOffY: minThreshold,
                            applyCutOffY: true,
                          ),
                          aboveBarData: BarAreaData(
                            show: true,
                            color: AppColors.danger.withOpacity(0.16),
                            cutOffY: maxThreshold,
                            applyCutOffY: true,
                          ),
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
                                '${reading.value.toStringAsFixed(1)}$unit\n${is24Hour ? DateFormat.Hm().format(reading.time) : DateFormat.yMd().add_Hm().format(reading.time)}',
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

  List<int> _calculateXTickIndexes(int count, bool is24Hour) {
    if (count <= 0) return const [];
    if (count == 1) return const [0];
    
    if (is24Hour) {
      // 24 saat için: 6-7 tick göster (daha fazla ama çakışmasın)
      final maxTicks = math.min(7, count);
      final step = (count - 1) / (maxTicks - 1);
      final indexes = <int>{};
      for (int i = 0; i < maxTicks; i++) {
        indexes.add((i * step).round().clamp(0, count - 1));
      }
      final sorted = indexes.toList()..sort();
      return sorted;
    } else {
      // 7 gün için: Sadece hafta içi günler göster (5 tick: Pzt, Çar, Cum, Pazar + başlangıç)
      // Veya daha az tick ile çakışmayı önle
      final maxTicks = math.min(5, count); // 5 tick yeterli (daha az çakışma)
      if (maxTicks <= 1) return [0];
      final step = (count - 1) / (maxTicks - 1);
      final indexes = <int>{};
      for (int i = 0; i < maxTicks; i++) {
        indexes.add((i * step).round().clamp(0, count - 1));
      }
      final sorted = indexes.toList()..sort();
      return sorted;
    }
  }

  List<double> _calculateYTicks(double min, double max, double minThreshold, double maxThreshold) {
    double effectiveMin = math.min(min, minThreshold);
    double effectiveMax = math.max(max, maxThreshold);

    if (effectiveMin == effectiveMax) {
      final base = effectiveMin == 0 ? 1.0 : (effectiveMin.abs() * 0.1).clamp(0.5, 5.0);
      return [effectiveMin - base, effectiveMin, effectiveMin + base];
    }
    final range = effectiveMax - effectiveMin;
    final rawStep = range / 4;
    final step = _niceStep(rawStep);
    final start = (effectiveMin / step).floor() * step;
    final end = (effectiveMax / step).ceil() * step;
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text(value, style: theme.textTheme.titleSmall?.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _ExportReportButton extends StatelessWidget {
  const _ExportReportButton({required this.onPressed});
  
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.download, size: 20),
        label: const Text('Rapor Al (CSV)'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 2,
        ),
      ),
    );
  }
}
