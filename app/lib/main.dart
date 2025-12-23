import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/config.dart';
import 'state/app_state.dart';
import 'state/auth_state.dart';
import 'ui/pages/home_page.dart';
import 'ui/pages/stats_page.dart';
import 'ui/pages/control_page.dart';
import 'ui/pages/settings_page.dart';
import 'ui/pages/plant_scan_page.dart';
import 'ui/pages/login_page.dart';
import 'ui/pages/register_page.dart';
import 'ui/theme/app_theme.dart';
import 'ui/widgets/glass_container.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.load();
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
    SettingsPage(),
  ];

  void _setIndex(int value) => setState(() => _index = value);

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
        theme: AppTheme.dark,
        home: Consumer<AuthState>(
          builder: (context, authState, _) {
            if (authState.isLoading) {
              return Scaffold(
                backgroundColor: AppColors.background,
                body: const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.cyan),
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
                child: Column(
                  children: [
                    if (_index == 0) ...[
                      _Header(
                        onNewAnalysis: () => _setIndex(3),
                        currentUser: authState.currentUser,
                      ),
                      const SizedBox(height: 12),
                    ],
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        switchInCurve: Curves.easeInOut,
                        switchOutCurve: Curves.easeInOut,
                        child: Padding(
                          key: ValueKey(_index),
                          padding: EdgeInsets.only(
                            left: 16,
                            right: 16,
                            top: _index == 3 ? 0 : 8,
                            bottom: 8,
                          ),
                          child: _pages[_index],
                        ),
                      ),
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

class _Header extends StatelessWidget {
  const _Header({
    required this.onNewAnalysis,
    this.currentUser,
  });

  final VoidCallback onNewAnalysis;
  final Map<String, dynamic>? currentUser;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompact = MediaQuery.of(context).size.width < 720;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: GlassContainer(
        borderRadius: 16,
        padding: EdgeInsets.symmetric(horizontal: isCompact ? 14 : 18, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  height: 34,
                  width: 34,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: LinearGradient(
                      colors: [
                        AppColors.cyan,
                        AppColors.cyan.withOpacity(0.7),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      'PA',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Colors.black.withOpacity(0.85),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Plant AMS',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: const [
                          _StatusChip(
                            label: 'Indoor model aktif',
                            color: AppColors.cyan,
                          ),
                          _StatusChip(
                            label: 'FastAPI bağlı',
                            color: AppColors.success,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.center,
              child: _NewAnalysisButton(
                onTap: onNewAnalysis,
                dense: isCompact,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewAnalysisButton extends StatelessWidget {
  const _NewAnalysisButton({required this.onTap, this.dense = false});

  final VoidCallback onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 12, vertical: dense ? 5 : 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cyan.withOpacity(0.5)),
          boxShadow: [
            BoxShadow(
              color: AppColors.cyan.withOpacity(0.22),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.camera_alt_outlined, size: dense ? 14 : 16, color: Colors.white),
            const SizedBox(width: 5),
            Text(
              'Yeni Analiz',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.5)),
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.28),
            color.withOpacity(0.14),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 6,
            width: 6,
            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
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
    final items = const [
      _NavItemData(Icons.home_outlined, 'Ana'),
      _NavItemData(Icons.show_chart, 'Grafikler'),
      _NavItemData(Icons.tune, 'Kontrol'),
      _NavItemData(Icons.camera_alt, 'Analiz'),
      _NavItemData(Icons.settings, 'Ayarlar'),
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: GlassContainer(
          padding: const EdgeInsets.symmetric(vertical: 6),
          borderRadius: 22,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var i = 0; i < items.length; i++)
                _BottomNavItem(
                  data: items[i],
                  active: currentIndex == i,
                  onTap: () => onSelected(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({required this.data, required this.active, required this.onTap});

  final _NavItemData data;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.cyan : Colors.white54;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.cyan.withOpacity(0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(data.icon, size: 22, color: color),
            const SizedBox(height: 4),
            Text(
              data.label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: active ? FontWeight.w600 : FontWeight.w400),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItemData {
  const _NavItemData(this.icon, this.label);
  final IconData icon;
  final String label;
}
