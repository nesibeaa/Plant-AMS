import 'package:flutter/material.dart';
import '../../core/config.dart';
import '../widgets/glass_container.dart';
import '../theme/app_theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _controller;
  bool _notificationsCritical = true;
  bool _notificationsWarnings = false;
  bool _notificationsAnalysis = true;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: AppConfig.baseUrl);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      children: [
        Text('Ayarlar', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        GlassContainer(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('API Sunucu Adresi', style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60)),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                decoration: const InputDecoration(hintText: 'http://127.0.0.1:8000'),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: () async {
                    await AppConfig.setBaseUrl(_controller.text.trim());
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('API adresi güncellendi')),
                    );
                  },
                  child: const Text('Kaydet'),
                ),
              )
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlassContainer(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bildirimler', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              _buildToggle(
                label: 'Kritik uyarılar',
                value: _notificationsCritical,
                onChanged: (v) => setState(() => _notificationsCritical = v),
              ),
              _buildToggle(
                label: 'Uyarı seviyesi',
                value: _notificationsWarnings,
                onChanged: (v) => setState(() => _notificationsWarnings = v),
              ),
              _buildToggle(
                label: 'Analiz sonuçları',
                value: _notificationsAnalysis,
                onChanged: (v) => setState(() => _notificationsAnalysis = v),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildToggle({required String label, required bool value, required ValueChanged<bool> onChanged}) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      value: value,
      onChanged: onChanged,
      activeColor: AppColors.cyan,
      activeTrackColor: AppColors.cyan.withOpacity(0.3),
    );
  }
}
