import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_container.dart';

class ControlPage extends StatefulWidget {
  const ControlPage({super.key});
  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> {
  bool? fanPending, heaterPending, humidifierPending;

  Future<void> _toggle(BuildContext context, String device, bool value) async {
    final state = context.read<AppState>();
    final status = state.actuators[device] ?? const <String, dynamic>{};
    final mode = (status['mode'] ?? 'auto') as String;
    final action = _resolveAction(mode, value);

    setState(() => _setPending(device, value));
    try {
      await state.setActuator(device, action);
      if (!mounted) return;
      String message;
      if (action == 'on') {
        message = '${device.toUpperCase()} manuel açıldı';
      } else if (action == 'off') {
        message = '${device.toUpperCase()} manuel kapandı';
      } else if (action == 'auto') {
        message = '${device.toUpperCase()} otomatik moda alındı';
      } else {
        message = '${device.toUpperCase()} güncellendi';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _setPending(device, null));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
      return;
    }
    if (!mounted) return;
    setState(() => _setPending(device, null));
  }

  String _resolveAction(String mode, bool value) {
    if (mode == 'manual') {
      return value ? 'on' : 'auto';
    }
    // Otomatik modda: true -> manuel aç, false -> otomatikte kal
    return value ? 'on' : 'auto';
  }

  void _setPending(String device, bool? value) {
    switch (device) {
      case 'fan':
        fanPending = value;
        break;
      case 'heater':
        heaterPending = value;
        break;
      case 'humidifier':
        humidifierPending = value;
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<AppState>();
    final latest = state.latest;
    final actuators = state.actuators;

    final fanStatus = actuators['fan'] ?? const <String, dynamic>{};
    final heaterStatus = actuators['heater'] ?? const <String, dynamic>{};
    final humidifierStatus = actuators['humidifier'] ?? const <String, dynamic>{};

    final fanMode = (fanStatus['mode'] ?? 'auto') as String;
    final heaterMode = (heaterStatus['mode'] ?? 'auto') as String;
    final humidifierMode = (humidifierStatus['mode'] ?? 'auto') as String;

    final fanActual = (fanStatus['state'] ?? 'off') == 'on';
    final heaterActual = (heaterStatus['state'] ?? 'off') == 'on';
    final humidifierActual = (humidifierStatus['state'] ?? 'off') == 'on';

    final fanValue = fanPending ?? fanActual;
    final heaterValue = heaterPending ?? heaterActual;
    final humidifierValue = humidifierPending ?? humidifierActual;

    final fanIsPending = fanPending != null;
    final heaterIsPending = heaterPending != null;
    final humidifierIsPending = humidifierPending != null;

    return RefreshIndicator(
      onRefresh: () => context.read<AppState>().loadDashboard(),
      backgroundColor: AppColors.glassSurface(0.3),
      color: AppColors.cyan,
      child: ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text('Kontrol Paneli', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          _ActuatorCard(
            icon: Icons.air,
            label: 'Fan',
            description: 'CO₂ > 1200 ppm → Aç',
            value: fanValue,
            isManual: fanMode == 'manual',
            isPending: fanIsPending,
            autoInfo: latest != null ? 'Anlık CO₂: ${latest.co2.toStringAsFixed(0)} ppm' : null,
            onChanged: (v) => _toggle(context, 'fan', v),
          ),
          _ActuatorCard(
            icon: Icons.local_fire_department,
            label: 'Isıtıcı',
            description: 'Sıcaklık < 18°C → Aç',
            value: heaterValue,
            isManual: heaterMode == 'manual',
            isPending: heaterIsPending,
            autoInfo: latest != null ? 'Anlık Sıcaklık: ${latest.temp.toStringAsFixed(1)}°C' : null,
            onChanged: (v) => _toggle(context, 'heater', v),
          ),
          _ActuatorCard(
            icon: Icons.grain,
            label: 'Nemlendirici',
            description: 'Nem < 45% → Aç',
            value: humidifierValue,
            isManual: humidifierMode == 'manual',
            isPending: humidifierIsPending,
            autoInfo: latest != null ? 'Anlık Nem: ${latest.humidity.toStringAsFixed(1)}%' : null,
            onChanged: (v) => _toggle(context, 'humidifier', v),
          ),
          const SizedBox(height: 20),
          GlassContainer(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.white60),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Son değişiklikler anlık olarak kaydedilir. Aktüatör durumları backend üzerinden senkronize edilir.',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActuatorCard extends StatelessWidget {
  const _ActuatorCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.value,
    required this.isManual,
    this.isPending = false,
    this.autoInfo,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String description;
  final bool value;
  final bool isManual;
  final bool isPending;
  final String? autoInfo;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GlassContainer(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  height: 40,
                  width: 40,
                  decoration: BoxDecoration(
                    color: AppColors.glassSurface(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.glassSurface(0.16)),
                  ),
                  child: Icon(icon, color: Colors.white70),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(description, style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54)),
                      if (autoInfo != null) ...[
                        const SizedBox(height: 4),
                        Text(autoInfo!, style: theme.textTheme.labelSmall?.copyWith(color: Colors.white38)),
                      ],
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: (isManual ? AppColors.amber : AppColors.cyan).withOpacity(0.16),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: (isManual ? AppColors.amber : AppColors.cyan).withOpacity(0.45),
                          ),
                        ),
                        child: Text(
                          isManual ? 'Manuel Mod' : 'Otomatik',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: isManual ? AppColors.amber : AppColors.cyan,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Opacity(
                      opacity: isPending ? 0.35 : 1,
                      child: IgnorePointer(
                        ignoring: isPending,
                        child: Switch(
                          value: value,
                          onChanged: onChanged,
                          activeColor: AppColors.cyan,
                          activeTrackColor: AppColors.cyan.withOpacity(0.3),
                        ),
                      ),
                    ),
                    if (isPending)
                      const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
