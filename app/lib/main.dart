import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
import 'services/notification_service.dart';

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
  
  // Bildirim servisi lazy initialization ile başlatılacak
  // (ilk bildirim planlanırken initialize edilecek)
  
  runApp(const PlantApp());
}

class PlantApp extends StatefulWidget {
  const PlantApp({super.key});
  @override
  State<PlantApp> createState() => _PlantAppState();
}

class _PlantAppState extends State<PlantApp> with WidgetsBindingObserver {
  int _index = 0;
  bool _showRegister = false;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Uygulama foreground'a geldiğinde (açıldığında veya arka plandan döndüğünde)
    if (state == AppLifecycleState.resumed) {
      // AppState'i yeniden yükle (backend'e yeniden bağlan)
      // Context kullanılabilir olduğunda yeniden yükle
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final authState = Provider.of<AuthState>(context, listen: false);
        final appState = Provider.of<AppState>(context, listen: false);
        if (authState.isAuthenticated) {
          appState.loadDashboard();
        }
      });
    }
  }

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
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('tr', 'TR'),
          Locale('en', 'US'),
        ],
        locale: const Locale('tr', 'TR'),
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

            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: const SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.light,
                statusBarBrightness: Brightness.dark,
              ),
              child: Scaffold(
                backgroundColor: AppColors.background,
                body: SafeArea(
                  top: false,
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
    final topPadding = MediaQuery.of(context).padding.top;
    const headerHeight = 70.0;
    
    return Container(
      height: headerHeight + topPadding,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF10B981), // emerald-500
            Color(0xFF22C55E), // green-500
            Color(0xFF0D9488), // teal-600
          ],
          stops: [0.0, 0.5, 1.0],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Repeating leaf pattern overlay - covers entire area including status bar
          Positioned.fill(
            child: CustomPaint(
              painter: _LeafPatternPainter(),
            ),
          ),
          // Large left leaf silhouette
          Positioned(
            left: -64,
            top: topPadding / 2 - 20,
            bottom: -20,
            child: CustomPaint(
              size: const Size(160, 192),
              painter: _LargeLeafPainter(),
            ),
          ),
          // Large right leaf silhouette (mirrored)
          Positioned(
            right: -64,
            top: topPadding / 2 - 20,
            bottom: -20,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()..scale(-1.0, 1.0),
              child: CustomPaint(
                size: const Size(160, 192),
                painter: _LargeLeafPainter(),
              ),
            ),
          ),
          // Main content area
          Positioned(
            top: topPadding,
            left: 0,
            right: 0,
            bottom: 0,
            child: Center(
              child: Text(
                'LeafSense',
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: -0.3,
                  shadows: [
                    Shadow(
                      color: Colors.black.withOpacity(0.15),
                      offset: const Offset(0, 2),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Notification button
          Positioned(
            left: 16,
            top: topPadding,
            bottom: 0,
            child: Center(
              child: Consumer<AppState>(
                builder: (context, appState, _) {
                  final unreadCount = _getUnreadAlertsCount(appState);
                  return GestureDetector(
                    onTap: () {
                      _showNotifications(context, appState);
                      appState.markAlertsAsRead();
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Center(
                            child: Icon(
                              Icons.notifications_none_rounded,
                              size: 18,
                              color: Colors.white,
                            ),
                          ),
                          if (unreadCount > 0)
                            Positioned(
                              right: 4,
                              top: 4,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFFF4444),
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
            ),
          ),
        ],
        ),
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

// Repeating leaf pattern painter (opacity 0.08)
class _LeafPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..style = PaintingStyle.fill;

    // Pattern repeats every 100x100
    const patternSize = 100.0;
    final cols = (size.width / patternSize).ceil() + 1;
    final rows = (size.height / patternSize).ceil() + 1;

    for (int col = 0; col < cols; col++) {
      for (int row = 0; row < rows; row++) {
        final offsetX = col * patternSize;
        final offsetY = row * patternSize;
        
        canvas.save();
        canvas.translate(offsetX, offsetY);

        // Leaf shape 1
        final path1 = Path()
          ..moveTo(20, 30)
          ..quadraticBezierTo(25, 20, 30, 30)
          ..quadraticBezierTo(25, 40, 20, 30)
          ..close();
        canvas.drawPath(path1, paint);

        // Leaf shape 2
        final path2 = Path()
          ..moveTo(70, 65)
          ..quadraticBezierTo(75, 55, 80, 65)
          ..quadraticBezierTo(75, 75, 70, 65)
          ..close();
        canvas.drawPath(path2, paint);

        // Leaf shape 3
        final path3 = Path()
          ..moveTo(45, 80)
          ..quadraticBezierTo(48, 73, 51, 80)
          ..quadraticBezierTo(48, 87, 45, 80)
          ..close();
        canvas.drawPath(path3, paint);

        // Diamond shape 1
        final path4 = Path()
          ..moveTo(15, 75)
          ..lineTo(18, 78)
          ..lineTo(15, 81)
          ..lineTo(12, 78)
          ..close();
        canvas.drawPath(path4, paint);

        // Diamond shape 2
        final path5 = Path()
          ..moveTo(85, 20)
          ..lineTo(88, 23)
          ..lineTo(85, 26)
          ..lineTo(82, 23)
          ..close();
        canvas.drawPath(path5, paint);

        // Circles
        canvas.drawCircle(const Offset(55, 25), 3, paint);
        canvas.drawCircle(const Offset(30, 60), 2, paint);

        // Line
        final linePaint = Paint()
          ..color = Colors.white.withOpacity(0.08)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        final path6 = Path()
          ..moveTo(60, 50)
          ..quadraticBezierTo(62, 48, 64, 50);
        canvas.drawPath(path6, linePaint);

        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Large leaf silhouette painter (opacity 0.2)
class _LargeLeafPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    // Main leaf body
    final mainLeaf = Path()
      ..moveTo(15, 96)
      ..quadraticBezierTo(15, 35, 65, 10)
      ..quadraticBezierTo(78, 25, 72, 96)
      ..quadraticBezierTo(65, 150, 50, 165)
      ..quadraticBezierTo(25, 165, 15, 125)
      ..quadraticBezierTo(12, 110, 15, 96)
      ..close();
    canvas.drawPath(mainLeaf, paint);

    // Secondary leaflet 1
    final secondary1 = Paint()
      ..color = Colors.white.withOpacity(0.12) // 0.6 * 0.2
      ..style = PaintingStyle.fill;
    final path1 = Path()
      ..moveTo(72, 96)
      ..quadraticBezierTo(77, 45, 105, 25)
      ..quadraticBezierTo(118, 40, 112, 96)
      ..quadraticBezierTo(108, 125, 98, 140)
      ..close();
    canvas.drawPath(path1, secondary1);

    // Secondary leaflet 2
    final secondary2 = Paint()
      ..color = Colors.white.withOpacity(0.07) // 0.35 * 0.2
      ..style = PaintingStyle.fill;
    final path2 = Path()
      ..moveTo(72, 96)
      ..quadraticBezierTo(85, 55, 120, 40)
      ..quadraticBezierTo(133, 55, 127, 100)
      ..quadraticBezierTo(125, 120, 118, 135)
      ..close();
    canvas.drawPath(path2, secondary2);

    // Leaf veins
    final veinPaint = Paint()
      ..color = Colors.white.withOpacity(0.05) // 0.25 * 0.2
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    
    final vein1 = Path()
      ..moveTo(35, 55)
      ..quadraticBezierTo(50, 52, 65, 55);
    canvas.drawPath(vein1, veinPaint);

    final vein2 = Path()
      ..moveTo(32, 75)
      ..quadraticBezierTo(50, 72, 68, 75);
    canvas.drawPath(vein2, veinPaint);

    final vein3 = Path()
      ..moveTo(30, 95)
      ..quadraticBezierTo(50, 92, 70, 95);
    canvas.drawPath(vein3, veinPaint);

    final vein4 = Path()
      ..moveTo(28, 115)
      ..quadraticBezierTo(48, 112, 68, 115);
    canvas.drawPath(vein4, veinPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: SafeArea(
        top: false,
        child: Container(
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
