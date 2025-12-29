import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'core/config.dart';
import 'state/app_state.dart';
import 'state/auth_state.dart';
import 'ui/pages/home_page.dart';
import 'ui/pages/stats_page.dart';
import 'ui/pages/control_page.dart';
import 'ui/pages/settings_page.dart';
import 'ui/pages/plant_scan_page.dart';
import 'ui/pages/plants_page.dart';
import 'ui/pages/login_page.dart';
import 'ui/pages/register_page.dart';
import 'ui/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // .env dosyasını yükle (eğer varsa)
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    // .env dosyası yoksa devam et (opsiyonel)
  }
  await AppConfig.load();
  await initializeDateFormatting('tr_TR', null);
  runApp(const PlantApp());
}

class PlantApp extends StatefulWidget {
  const PlantApp({super.key});
  @override
  State<PlantApp> createState() => _PlantAppState();
}

class _PlantAppState extends State<PlantApp> {
  int _index = 0;
  bool _showRegister = false;

  final _pages = const [
    HomePage(),
    StatsPage(),
    ControlPage(),
    PlantScanPage(),
    PlantsPage(), // Bitkilerim
    SettingsPage(),
  ];

  void _setIndex(int value) {
    if (value >= 0 && value < _pages.length) {
      setState(() => _index = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthState()),
        ChangeNotifierProxyProvider<AuthState, AppState>(
          create: (_) => AppState()..loadDashboard(),
          update: (_, authState, previous) {
            final appState = previous ?? AppState()..loadDashboard();
            appState.setAuthState(authState);
            return appState;
          },
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Plant AMS',
        theme: AppTheme.light,
        home: Consumer<AuthState>(
          builder: (context, authState, _) {
            if (authState.isLoading) {
              return Scaffold(
                backgroundColor: AppColors.background,
                body: const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ),
              );
            }

            if (!authState.isAuthenticated) {
              return _showRegister
                  ? RegisterPage(
                      onNavigateToLogin: () {
                        setState(() => _showRegister = false);
                      },
                    )
                  : LoginPage(
                      onNavigateToRegister: () {
                        setState(() => _showRegister = true);
                      },
                    );
            }

            return Scaffold(
              backgroundColor: AppColors.background,
              body: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    _TopAppBar(),
                    Expanded(
                      child: _pages[_index],
                    ),
                  ],
                ),
              ),
              bottomNavigationBar: _BottomNav(
                currentIndex: _index,
                onSelected: _setIndex,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TopAppBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.background.withOpacity(0.9),
        border: Border(
          bottom: BorderSide(color: AppColors.border.withOpacity(0.7)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Consumer<AppState>(
            builder: (context, appState, _) {
              final unreadCount = _getUnreadAlertsCount(appState);
              return InkWell(
                onTap: () {
                  _showNotifications(context, appState);
                  // Bildirimlere girildiğinde okundu olarak işaretle
                  appState.markAlertsAsRead();
                },
                borderRadius: BorderRadius.circular(100),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.cardBackground,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Center(
                        child: Icon(
                          Icons.notifications_none,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (unreadCount > 0)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Color(0xFFEF4444), // red-500
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          Text(
            'Plant Scan',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
          ),
          const SizedBox(width: 36), // Balance the layout
        ],
      ),
    );
  }

  int _getUnreadAlertsCount(AppState appState) {
    // Okunmamış bildirimleri say (readAlertIds'de olmayanlar)
    // ID yoksa timestamp kullan
    return appState.alerts.where((alert) {
      final id = alert['id']?.toString() ?? alert['ts']?.toString() ?? '';
      if (id.isEmpty) return false;
      return !appState.readAlertIds.contains(id);
    }).length;
  }

  void _showNotifications(BuildContext context, AppState appState) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Uyarılar',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.textSecondary),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Alerts list
              Expanded(
                child: appState.alerts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.notifications_off_outlined,
                              size: 64,
                              color: AppColors.textTertiary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Henüz uyarı yok',
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: appState.alerts.length,
                        itemBuilder: (context, index) {
                          final alert = appState.alerts[index];
                          return _NotificationItem(alert: alert);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationItem extends StatelessWidget {
  const _NotificationItem({required this.alert});

  final Map<String, dynamic> alert;

  Color _getStatusColor(String? severity) {
    switch (severity?.toLowerCase()) {
      case 'critical':
        return const Color(0xFFEF4444); // red
      case 'warning':
        return const Color(0xFFF59E0B); // amber
      case 'info':
        return const Color(0xFF10B981); // green
      default:
        return AppColors.textSecondary;
    }
  }

  String _formatTime(String? ts) {
    if (ts == null) return '';
    try {
      final time = DateTime.parse(ts);
      final now = DateTime.now();
      final diff = now.difference(time);

      if (diff.inMinutes < 1) return 'Az önce';
      if (diff.inMinutes < 60) return '${diff.inMinutes}dk önce';
      if (diff.inHours < 24) return '${diff.inHours}s önce';
      if (diff.inDays < 7) return '${diff.inDays}g önce';
      return '${time.day}/${time.month}/${time.year}';
    } catch (e) {
      return ts;
    }
  }

  @override
  Widget build(BuildContext context) {
    final severity = alert['severity'] as String?;
    final message = alert['message'] as String? ?? '';
    final ts = alert['ts'] as String?;
    final statusColor = _getStatusColor(severity);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 6, right: 12),
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTime(ts),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 11,
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

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.currentIndex, required this.onSelected});

  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _NavItem(
                    icon: Icons.dashboard_outlined,
                    label: 'Sizin İçin',
                    index: 0,
                    currentIndex: currentIndex,
                    onTap: () => onSelected(0),
                  ),
                  _NavItem(
                    icon: Icons.show_chart,
                    label: 'Grafikler',
                    index: 1,
                    currentIndex: currentIndex,
                    onTap: () => onSelected(1),
                  ),
                  _CenterFloatingButton(
                    onTap: () => onSelected(3),
                    isActive: currentIndex == 3,
                  ),
                  _NavItem(
                    icon: Icons.local_florist_outlined,
                    label: 'Bitkilerim',
                    index: 4,
                    currentIndex: currentIndex,
                    onTap: () => onSelected(4),
                  ),
                  _NavItem(
                    icon: Icons.settings_outlined,
                    label: 'Ayarlar',
                    index: 5,
                    currentIndex: currentIndex,
                    onTap: () => onSelected(5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.currentIndex,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int index;
  final int currentIndex;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isActive = currentIndex == index;
    final color = isActive ? AppColors.primary : AppColors.textSecondary;
    
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: color,
                    fontSize: 11,
                    fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenterFloatingButton extends StatelessWidget {
  const _CenterFloatingButton({required this.onTap, required this.isActive});

  final VoidCallback onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryLight.withOpacity(0.4),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(
          Icons.qr_code_scanner,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }
}
