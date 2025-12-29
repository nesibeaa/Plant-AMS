import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';
import '../theme/app_theme.dart';

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

  String _formatLastChange(dynamic lastChange) {
    if (lastChange == null) return '—';
    try {
      final time = DateTime.parse(lastChange.toString());
      final now = DateTime.now();
      final diff = now.difference(time);
      if (diff.inMinutes < 1) return 'Az önce';
      if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return lastChange.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
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
      backgroundColor: AppColors.cardBackground,
      color: AppColors.primary,
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Kontrol Paneli',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.5,
                    ),
              ),
              Text(
                'Aç/Kapa • Anlık',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          // Control Cards
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 600;
              if (isWide) {
                return Row(
                  children: [
                    Expanded(
                      child: _ControlCard(
                        icon: Icons.air,
                        label: 'Fan',
                        lastChange: _formatLastChange(fanStatus['last_change']),
                        value: fanValue,
                        isPending: fanIsPending,
                        threshold: 'CO₂ > 1000 ppm → Aç',
                        iconColor: const Color(0xFF10B981),
                        iconBg: const Color(0xFFD1FAE5),
                        iconBorder: const Color(0xFFA7F3D0),
                        onChanged: (v) => _toggle(context, 'fan', v),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _ControlCard(
                        icon: Icons.local_fire_department,
                        label: 'Isıtıcı',
                        lastChange: _formatLastChange(heaterStatus['last_change']),
                        value: heaterValue,
                        isPending: heaterIsPending,
                        threshold: 'Sıcaklık < 18°C → Aç',
                        iconColor: const Color(0xFFF59E0B),
                        iconBg: const Color(0xFFFEF3C7),
                        iconBorder: const Color(0xFFFDE68A),
                        onChanged: (v) => _toggle(context, 'heater', v),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _ControlCard(
                        icon: Icons.water_drop,
                        label: 'Nemlendirici',
                        lastChange: _formatLastChange(humidifierStatus['last_change']),
                        value: humidifierValue,
                        isPending: humidifierIsPending,
                        threshold: 'Nem < 40% → Aç',
                        iconColor: const Color(0xFF38BDF8),
                        iconBg: const Color(0xFFE0F2FE),
                        iconBorder: const Color(0xFFBAE6FD),
                        onChanged: (v) => _toggle(context, 'humidifier', v),
                      ),
                    ),
                  ],
                );
              } else {
                return Column(
                  children: [
                    _ControlCard(
                      icon: Icons.air,
                      label: 'Fan',
                      lastChange: _formatLastChange(fanStatus['last_change']),
                      value: fanValue,
                      isPending: fanIsPending,
                      threshold: 'CO₂ > 1000 ppm → Aç',
                      iconColor: const Color(0xFF10B981),
                      iconBg: const Color(0xFFD1FAE5),
                      iconBorder: const Color(0xFFA7F3D0),
                      onChanged: (v) => _toggle(context, 'fan', v),
                    ),
                    const SizedBox(height: 16),
                    _ControlCard(
                      icon: Icons.local_fire_department,
                      label: 'Isıtıcı',
                      lastChange: _formatLastChange(heaterStatus['last_change']),
                      value: heaterValue,
                      isPending: heaterIsPending,
                      threshold: 'Sıcaklık < 18°C → Aç',
                      iconColor: const Color(0xFFF59E0B),
                      iconBg: const Color(0xFFFEF3C7),
                      iconBorder: const Color(0xFFFDE68A),
                      onChanged: (v) => _toggle(context, 'heater', v),
                    ),
                    const SizedBox(height: 16),
                    _ControlCard(
                      icon: Icons.water_drop,
                      label: 'Nemlendirici',
                      lastChange: _formatLastChange(humidifierStatus['last_change']),
                      value: humidifierValue,
                      isPending: humidifierIsPending,
                      threshold: 'Nem < 40% → Aç',
                      iconColor: const Color(0xFF38BDF8),
                      iconBg: const Color(0xFFE0F2FE),
                      iconBorder: const Color(0xFFBAE6FD),
                      onChanged: (v) => _toggle(context, 'humidifier', v),
                    ),
                  ],
                );
              }
            },
          ),
          const SizedBox(height: 20),
          
          // Info Card
          Container(
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Son değişiklikler anlık olarak kaydedilir.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.check_circle,
                  color: AppColors.primary,
                  size: 20,
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _ControlCard extends StatelessWidget {
  const _ControlCard({
    required this.icon,
    required this.label,
    required this.lastChange,
    required this.value,
    required this.isPending,
    required this.threshold,
    required this.iconColor,
    required this.iconBg,
    required this.iconBorder,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String lastChange;
  final bool value;
  final bool isPending;
  final String threshold;
  final Color iconColor;
  final Color iconBg;
  final Color iconBorder;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(color: iconBorder),
                    ),
                    child: Icon(icon, color: iconColor, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textPrimary,
                            ),
                      ),
                      Text(
                        'Son: $lastChange',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                children: [
                  Text(
                    'Durum',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                  ),
                  const SizedBox(width: 12),
                  Switch(
                    value: value,
                    onChanged: isPending ? null : onChanged,
                    activeColor: AppColors.primaryLight,
                    activeTrackColor: AppColors.primaryLight.withOpacity(0.5),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Eşik: $threshold',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
          ),
        ],
      ),
    );
  }
}
