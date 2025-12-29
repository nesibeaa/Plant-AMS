import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';
import '../../models/sensor_reading.dart';
import '../../services/api_service.dart';
import '../theme/app_theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ApiService _apiService = ApiService();
  Map<String, dynamic>? _weatherData;
  bool _weatherLoading = false;

  Future<void> _loadWeather() async {
    setState(() => _weatherLoading = true);
    try {
      // Şimdilik Istanbul kullan, ileride kullanıcı konumunu ekleyebiliriz
      final data = await _apiService.getWeather();
      setState(() {
        _weatherData = data;
        _weatherLoading = false;
      });
    } catch (e) {
      setState(() => _weatherLoading = false);
      // Hata durumunda sessizce devam et, mock data gösterilecek
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().loadDashboard();
      _loadWeather();
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
                style: Theme.of(context).textTheme.bodyLarge,
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
      onRefresh: () async {
        await state.loadDashboard();
        await _loadWeather();
      },
      backgroundColor: AppColors.cardBackground,
      color: AppColors.primary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          // Hava Durumu Kartı
          _WeatherCard(
            weatherData: _weatherData, 
            loading: _weatherLoading,
            forecast: _weatherData?['forecast'] as List<dynamic>?,
          ),
          const SizedBox(height: 20),
          
          // Sensör Verileri
          if (latest != null) ...[
            _SensorSection(latest: latest),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }
}

class _WeatherCard extends StatelessWidget {
  const _WeatherCard({
    this.weatherData, 
    this.loading = false,
    this.forecast,
  });

  final Map<String, dynamic>? weatherData;
  final bool loading;
  final List<dynamic>? forecast;

  @override
  Widget build(BuildContext context) {
    // Veri yoksa ve yüklenmiyorsa, kartı gösterme (default değerler gösterilmeyecek)
    if (weatherData == null) {
      // Yükleniyorsa loading göster
      if (loading) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.all(16),
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        );
      }
      // Veri yoksa ve yüklenmiyorsa kartı gizle
      return const SizedBox.shrink();
    }
    
    // Weather data varsa gerçek verileri kullan
    final temp = weatherData!['temp'] as num? ?? 0.0;
    final feelsLike = weatherData!['feels_like'] as num? ?? 0.0;
    final humidity = weatherData!['humidity'] as int? ?? 0;
    final windSpeed = weatherData!['wind_speed'] as num? ?? 0.0;
    final description = weatherData!['description'] as String? ?? '';
    final city = weatherData!['city'] as String? ?? '';
    final weatherCode = weatherData!['weather_code'] as int? ?? 2;
    final iconType = weatherData!['icon'] as String? ?? 'clouds';
    
    // Weather code'a göre ikon seç
    IconData weatherIcon;
    Color iconColor;
    Color iconBg;
    Color iconBorder;
    
    // Gece/gündüz kontrolü (sadece açık hava için)
    final now = DateTime.now();
    final hour = now.hour;
    final isNight = hour < 6 || hour >= 18;
    
    if (weatherCode == 0 || iconType == 'clear') {
      // Açık hava - gece ise ay, gündüz ise güneş
      if (isNight) {
        weatherIcon = Icons.nightlight_round;
        iconColor = const Color(0xFF6366F1); // indigo-500
        iconBg = const Color(0xFFEEF2FF); // indigo-100
        iconBorder = const Color(0xFFC7D2FE); // indigo-200
      } else {
        weatherIcon = Icons.wb_sunny;
        iconColor = const Color(0xFFF59E0B); // amber-500
        iconBg = const Color(0xFFFEF3C7); // amber-100
        iconBorder = const Color(0xFFFDE68A); // amber-200
      }
    } else if ([1, 2, 3].contains(weatherCode) || iconType == 'clouds') {
      // Bulutlu
      weatherIcon = Icons.wb_cloudy_outlined;
      iconColor = const Color(0xFF94A3B8); // slate-400
      iconBg = const Color(0xFFE0F2FE); // sky-100
      iconBorder = const Color(0xFFBAE6FD); // sky-200
    } else if ((weatherCode >= 51 && weatherCode <= 68) || iconType == 'rain') {
      // Yağmurlu
      weatherIcon = Icons.grain;
      iconColor = const Color(0xFF3B82F6); // blue-500
      iconBg = const Color(0xFFDBEAFE); // blue-100
      iconBorder = const Color(0xFFBFDBFE); // blue-200
    } else if ((weatherCode >= 71 && weatherCode <= 78) || iconType == 'snow') {
      // Karlı
      weatherIcon = Icons.ac_unit;
      iconColor = const Color(0xFF60A5FA); // blue-400
      iconBg = const Color(0xFFE0F2FE); // sky-100
      iconBorder = const Color(0xFFBAE6FD); // sky-200
    } else if ((weatherCode >= 95 && weatherCode <= 99) || iconType == 'thunderstorm') {
      // Fırtınalı
      weatherIcon = Icons.flash_on;
      iconColor = const Color(0xFFF59E0B); // amber-500
      iconBg = const Color(0xFFFEF3C7); // amber-100
      iconBorder = const Color(0xFFFDE68A); // amber-200
    } else if ([45, 48].contains(weatherCode) || iconType == 'mist') {
      // Sisli
      weatherIcon = Icons.blur_on;
      iconColor = const Color(0xFF94A3B8); // slate-400
      iconBg = const Color(0xFFF1F5F9); // slate-100
      iconBorder = const Color(0xFFCBD5E1); // slate-200
    } else {
      // Varsayılan: bulutlu
      weatherIcon = Icons.wb_cloudy_outlined;
      iconColor = const Color(0xFF94A3B8);
      iconBg = const Color(0xFFE0F2FE);
      iconBorder = const Color(0xFFBAE6FD);
    }
    
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
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bugünkü Hava Durumu',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
          ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${(temp as num).toStringAsFixed(0)}°C',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                                color: AppColors.textPrimary,
                                letterSpacing: -0.5,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Weather icon (dinamik)
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: iconBorder),
                ),
                child: Icon(
                  weatherIcon,
                  color: iconColor,
                  size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Açıklama - tam genişlikte
          Text(
            description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
          ),
          const SizedBox(height: 12),
          // Detaylar - yan yana
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Hissedilen: ${(feelsLike as num).toStringAsFixed(0)}°C',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
              ),
              Text(
                'Nem: %${humidity.toStringAsFixed(0)} • Rüzgar: ${(windSpeed as num).toStringAsFixed(0)} km/s',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Konum: $city',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
          ),
          
          // Bitki Bakım Önerileri
          _PlantCareRecommendations(weatherData: weatherData),
          
          // Haftalık Tahmin - Expandable
          if (forecast != null && forecast!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Divider(height: 1, color: AppColors.border.withOpacity(0.5)),
            _ExpandableForecast(forecast: forecast!),
          ],
        ],
      ),
    );
  }
}

class _ExpandableForecast extends StatefulWidget {
  const _ExpandableForecast({required this.forecast});

  final List<dynamic> forecast;

  @override
  State<_ExpandableForecast> createState() => _ExpandableForecastState();
}

class _ExpandableForecastState extends State<_ExpandableForecast> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: () {
            setState(() {
              _isExpanded = !_isExpanded;
            });
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Haftalık Tahmin',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                ),
                Icon(
                  _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
        if (_isExpanded) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 82,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: widget.forecast.take(7).map((day) {
                final dayData = day as Map<String, dynamic>;
                return _ForecastDayItem(
                  date: dayData['date'] as String? ?? '',
                  maxTemp: (dayData['max_temp'] as num?)?.toDouble() ?? 0.0,
                  minTemp: (dayData['min_temp'] as num?)?.toDouble() ?? 0.0,
                  weatherCode: dayData['weather_code'] as int? ?? 2,
                  icon: dayData['icon'] as String? ?? 'clouds',
                  description: dayData['description'] as String? ?? 'Bulutlu',
                  isLast: false,
                  isCompact: true,
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }
}

class _ForecastDayItem extends StatelessWidget {
  const _ForecastDayItem({
    required this.date,
    required this.maxTemp,
    required this.minTemp,
    required this.weatherCode,
    required this.icon,
    required this.description,
    this.isLast = false,
    this.isCompact = false,
  });

  final String date;
  final double maxTemp;
  final double minTemp;
  final int weatherCode;
  final String icon;
  final String description;
  final bool isLast;
  final bool isCompact;

  IconData _getWeatherIcon() {
    if (weatherCode == 0 || icon == 'clear') {
      return Icons.wb_sunny;
    } else if ([1, 2, 3].contains(weatherCode) || icon == 'clouds') {
      return Icons.wb_cloudy_outlined;
    } else if ((weatherCode >= 51 && weatherCode <= 68) || icon == 'rain') {
      return Icons.grain;
    } else if ((weatherCode >= 71 && weatherCode <= 78) || icon == 'snow') {
      return Icons.ac_unit;
    } else if ((weatherCode >= 95 && weatherCode <= 99) || icon == 'thunderstorm') {
      return Icons.flash_on;
    } else if ([45, 48].contains(weatherCode) || icon == 'mist') {
      return Icons.blur_on;
    } else {
      return Icons.wb_cloudy_outlined;
    }
  }

  Color _getIconColor() {
    if (weatherCode == 0 || icon == 'clear') {
      return const Color(0xFFF59E0B);
    } else if ([1, 2, 3].contains(weatherCode) || icon == 'clouds') {
      return const Color(0xFF94A3B8);
    } else if ((weatherCode >= 51 && weatherCode <= 68) || icon == 'rain') {
      return const Color(0xFF3B82F6);
    } else if ((weatherCode >= 71 && weatherCode <= 78) || icon == 'snow') {
      return const Color(0xFF60A5FA);
    } else if ((weatherCode >= 95 && weatherCode <= 99) || icon == 'thunderstorm') {
      return const Color(0xFFF59E0B);
    } else {
      return const Color(0xFF94A3B8);
    }
  }

  String _formatDate(String dateStr, {bool compact = false}) {
    if (dateStr.isEmpty) return '';
    try {
      final date = DateTime.parse(dateStr);
      
      // Türkçe gün isimleri - Bugün/Yarın demeden direkt gün adı
      if (compact) {
        final weekdaysShort = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
        return weekdaysShort[date.weekday - 1];
      } else {
        final weekdays = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];
        return weekdays[date.weekday - 1];
      }
    } catch (e) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayName = _formatDate(date, compact: isCompact);
    final iconData = _getWeatherIcon();
    final iconColor = _getIconColor();

    // Compact (yatay) görünüm
    if (isCompact) {
      return SizedBox(
        width: 60,
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Gün adı
              Text(
                dayName,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                      fontSize: 10,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              // İkon
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: iconColor.withOpacity(0.3)),
                ),
                child: Icon(
                  iconData,
                  color: iconColor,
                  size: 13,
                ),
              ),
              const SizedBox(height: 3),
              // Sıcaklık
              Text(
                '${maxTemp.toStringAsFixed(0)}°',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                      fontSize: 10,
                    ),
              ),
              Text(
                '${minTemp.toStringAsFixed(0)}°',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 9,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    // Dikey (liste) görünüm
    return Column(
      children: [
        Row(
          children: [
            // Gün adı
            SizedBox(
              width: 70,
              child: Text(
                dayName,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                    ),
              ),
            ),
            const SizedBox(width: 12),
            // İkon
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: iconColor.withOpacity(0.3)),
              ),
              child: Icon(
                iconData,
                color: iconColor,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            // Açıklama
            Expanded(
              child: Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
              ),
            ),
            const SizedBox(width: 12),
            // Sıcaklık
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${maxTemp.toStringAsFixed(0)}°',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                ),
                Text(
                  ' / ${minTemp.toStringAsFixed(0)}°',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                ),
              ],
            ),
          ],
        ),
        if (!isLast) ...[
          const SizedBox(height: 12),
          Divider(height: 1, color: AppColors.border.withOpacity(0.5)),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _PlantCareRecommendations extends StatelessWidget {
  const _PlantCareRecommendations({this.weatherData});

  final Map<String, dynamic>? weatherData;

  String _getRecommendation() {
    if (weatherData == null) return 'Hava durumu verisi yükleniyor...';
    
    final temp = (weatherData!['temp'] as num?)?.toDouble() ?? 20.0;
    final humidity = (weatherData!['humidity'] as num?)?.toInt() ?? 50;
    final description = (weatherData!['description'] as String?) ?? '';
    final icon = (weatherData!['icon'] as String?) ?? 'clouds';
    
    // Sıcaklık bazlı öneriler
    if (temp < 10) {
      return 'Hava çok soğuk. Bitkilerinizi içeri alın veya don koruması sağlayın. Sıcak bir yere taşıyın.';
    } else if (temp < 18) {
      return 'Hava serin. Bitkilerinizi soğuktan koruyun. Sulamayı azaltın ve sıcak bir yerde tutun.';
    } else if (temp > 30) {
      return 'Hava çok sıcak! Bitkilerinize daha sık su verin. Direkt güneşten koruyun ve gölge sağlayın.';
    } else if (temp > 25) {
      return 'Hava sıcak. Bitkilerinizi daha sık sulayın. Sabah veya akşam saatlerinde sulama yapın.';
    }
    
    // Nem bazlı öneriler
    if (humidity < 30) {
      return 'Hava çok kuru. Bitkilerinize nem sağlayın. Yapraklara su püskürtün veya nemlendirici kullanın.';
    } else if (humidity < 40) {
      return 'Hava kuru. Bitkileriniz için ekstra nem gerekebilir. Sulama sıklığını kontrol edin.';
    } else if (humidity > 70) {
      return 'Hava nemli. Havalandırmayı artırın. Aşırı sulamadan kaçının ve bitkilerinizi havalandırın.';
    }
    
    // Hava durumu bazlı öneriler
    if (icon == 'rain' || description.toLowerCase().contains('yağmur')) {
      return 'Yağmurlu hava. Sulama yapmanıza gerek yok. Bitkilerinizi fazla sudan koruyun.';
    } else if (icon == 'clear') {
      return 'Güneşli hava. Bitkileriniz bol ışık alıyor. Sulamayı düzenli yapın ve yaprakları temiz tutun.';
    } else if (icon == 'snow' || description.toLowerCase().contains('kar')) {
      return 'Karlı hava! Bitkilerinizi içeri alın veya sıcak bir yerde tutun. Don riskine karşı koruyun.';
    }
    
    // Varsayılan öneri
    return 'Hava durumu normal. Düzenli bakım yapın, toprak nemini kontrol edin ve bitkilerinizi gözlemleyin.';
  }

  @override
  Widget build(BuildContext context) {
    final recommendation = _getRecommendation();

    return Column(
      children: [
        const SizedBox(height: 16),
        Divider(height: 1, color: AppColors.border.withOpacity(0.5)),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Bitki bakım ikonu - diğer ikonlarla aynı boyut (40x40)
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(100),
                child: Image.asset(
                  'assets/images/bakim.png',
                  width: 40,
                  height: 40,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(
                      Icons.emoji_nature,
                      color: AppColors.primary,
                      size: 20,
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Öneri metni
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bitki Bakım Önerisi',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    recommendation,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                          height: 1.4,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SensorSection extends StatelessWidget {
  const _SensorSection({required this.latest});

  final LatestReadings latest;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'Sensör Verileri',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.5,
                  ),
            ),
            Text(
              'Son Senkron: 2dk önce',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Column(
              children: [
                _SensorCard(
                  icon: Icons.thermostat,
                  label: 'Sıcaklık',
                  value: '${latest.temp.toStringAsFixed(1)}°C',
              status: _getStatus('temp', latest.temp),
              iconColor: const Color(0xFF10B981), // emerald-500
              iconBg: const Color(0xFFD1FAE5), // emerald-400/10
              iconBorder: const Color(0xFFA7F3D0), // emerald-300/70
              ringColor: const Color(0xFFD1FAE5), // emerald-200
              range: 'Eşik: 18–28°C',
                ),
            const SizedBox(height: 12),
                _SensorCard(
                  icon: Icons.water_drop,
                  label: 'Nem',
              value: '${latest.humidity.toStringAsFixed(0)}%',
              status: _getStatus('humidity', latest.humidity),
              iconColor: const Color(0xFFF59E0B), // amber-500
              iconBg: const Color(0xFFFEF3C7), // amber-400/10
              iconBorder: const Color(0xFFFDE68A), // amber-300/70
              ringColor: const Color(0xFFFEF3C7), // amber-200
              range: 'Eşik: 40–70%',
                ),
            const SizedBox(height: 12),
                _SensorCard(
                  icon: Icons.cloud,
                  label: 'CO₂',
                  value: '${latest.co2.toStringAsFixed(0)} ppm',
              status: _getStatus('co2', latest.co2),
              iconColor: const Color(0xFFEF4444), // red-500
              iconBg: const Color(0xFFFEE2E2), // red-400/10
              iconBorder: const Color(0xFFFECACA), // red-400/70
              ringColor: const Color(0xFFDBEAFE), // sky-200 (HTML'de sky-200 kullanılmış)
              range: 'Eşik: 400–1000 ppm',
                ),
              ],
        ),
      ],
    );
  }

  _SensorStatus _getStatus(String sensor, double value) {
    switch (sensor) {
      case 'temp':
        if (value < 18) return const _SensorStatus('Düşük', Color(0xFFF59E0B));
        if (value > 28) return const _SensorStatus('Yüksek', Color(0xFFEF4444));
        return const _SensorStatus('Normal', Color(0xFF10B981));
      case 'humidity':
        if (value < 40) return const _SensorStatus('Düşük', Color(0xFFF59E0B));
        if (value > 70) return const _SensorStatus('Yüksek', Color(0xFFEF4444));
        return const _SensorStatus('Normal', Color(0xFF10B981));
      case 'co2':
        if (value > 1000) return const _SensorStatus('Yüksek', Color(0xFFEF4444));
        if (value < 400) return const _SensorStatus('Düşük', Color(0xFFF59E0B));
        return const _SensorStatus('Normal', Color(0xFF10B981));
      default:
        return const _SensorStatus('—', AppColors.textSecondary);
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
    required this.iconColor,
    required this.iconBg,
    required this.iconBorder,
    required this.ringColor,
    required this.range,
  });

  final IconData icon;
  final String label;
  final String value;
  final _SensorStatus status;
  final Color iconColor;
  final Color iconBg;
  final Color iconBorder;
  final Color ringColor;
  final String range;

  Map<String, dynamic> _getBadgeStyle() {
    if (status.label == 'Normal') {
      return {
        'bg': const Color(0xFFECFDF5), // emerald-50
        'border': const Color(0xFFD1FAE5), // emerald-200
        'text': const Color(0xFF065F46), // emerald-700
      };
    } else if (status.label == 'Düşük') {
      return {
        'bg': const Color(0xFFFEF3C7), // amber-50
        'border': const Color(0xFFFEF3C7), // amber-200
        'text': const Color(0xFF92400E), // amber-700
      };
    } else {
      return {
        'bg': const Color(0xFFFEF2F2), // red-50
        'border': const Color(0xFFEF4444), // red-500
        'text': const Color(0xFFEF4444), // red-500
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    final badgeStyle = _getBadgeStyle();
    
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Stack(
        children: [
          // Ring border (absolute positioned)
          Positioned.fill(
            child: Container(
                decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: ringColor, width: 1),
                ),
          ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: iconBg,
                              borderRadius: BorderRadius.circular(100),
                              border: Border.all(color: iconBorder),
                            ),
                            child: Icon(icon, color: iconColor, size: 20),
        ),
                          const SizedBox(width: 10),
                          Flexible(
          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
            children: [
                                Text(
                                  label,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: AppColors.textSecondary,
                    ),
                  ),
                                Text(
                                  value,
                                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.textPrimary,
                                        letterSpacing: -0.5,
                  ),
                ),
            ],
          ),
        ),
      ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: badgeStyle['bg'] as Color,
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(color: badgeStyle['border'] as Color),
                ),
                      child: Text(
                        status.label,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: badgeStyle['text'] as Color,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
          ),
        ),
      ),
          ],
        ),
        const SizedBox(height: 12),
                Text(
                  range,
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
