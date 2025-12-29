import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/config.dart';
import '../../state/auth_state.dart';
import '../widgets/glass_container.dart';
import '../theme/app_theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _controller;
  late final TextEditingController _groqApiKeyController;
  bool _notificationsCritical = true;
  bool _notificationsWarnings = false;
  bool _notificationsAnalysis = true;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: AppConfig.baseUrl);
    _groqApiKeyController = TextEditingController();
    _loadGroqApiKey();
  }

  Future<void> _loadGroqApiKey() async {
    await AppConfig.load();
    setState(() {
      _groqApiKeyController.text = AppConfig.groqApiKey;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _groqApiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = context.watch<AuthState>();
    final currentUser = authState.currentUser;

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      children: [
        Text('Ayarlar', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        // Kullanıcı Bilgileri
        if (currentUser != null)
          GlassContainer(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      height: 48,
                      width: 48,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          colors: [
                            AppColors.cyan,
                            AppColors.cyan.withOpacity(0.7),
                          ],
                        ),
                      ),
                      child: Center(
                        child: Text(
                          (currentUser['username'] as String? ?? 'U')[0].toUpperCase(),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentUser['full_name'] as String? ?? 
                            currentUser['username'] as String? ?? 
                            'Kullanıcı',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            currentUser['email'] as String? ?? '',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: AppColors.background,
                        title: const Text('Çıkış Yap'),
                        content: const Text('Çıkış yapmak istediğinize emin misiniz?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('İptal'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: Text(
                              'Çıkış Yap',
                              style: TextStyle(color: AppColors.danger),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true && context.mounted) {
                      await authState.logout();
                    }
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Çıkış Yap'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: BorderSide(color: AppColors.danger.withOpacity(0.5)),
                  ),
                ),
              ],
            ),
          ),
        if (currentUser != null) const SizedBox(height: 16),
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
