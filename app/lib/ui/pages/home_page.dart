import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import '../../state/app_state.dart';
import '../../models/sensor_reading.dart';
import '../../models/plant_thresholds.dart';
import '../../services/api_service.dart';
import '../../services/notification_service.dart';
import '../theme/app_theme.dart';
import 'plant_detail_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ApiService _apiService = ApiService();
  final NotificationService _notificationService = NotificationService();
  Map<String, dynamic>? _weatherData;
  bool _weatherLoading = false;
  int _totalPlantsWithNotifications = 0; // Sadece bildirim ayarlı bitkiler
  int _plantsNeedingCare = 0;
  List<Map<String, dynamic>> _plantsWithNotifications = []; // Bildirim ayarlı bitkiler listesi
  List<Map<String, dynamic>> _plantsNeedingCareList = []; // Bakıma ihtiyaç duyan bitkiler

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
      _loadRemindersData();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Sayfa her göründüğünde verileri yenile
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRemindersData();
    });
  }

  Future<void> _loadRemindersData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final plantsJson = prefs.getString('saved_plants') ?? '[]';
      final plants = List<Map<String, dynamic>>.from(
        jsonDecode(plantsJson) as List
      );
      
      List<Map<String, dynamic>> plantsWithNotifications = [];
      List<Map<String, dynamic>> plantsNeedingCareList = [];
      final now = DateTime.now();
      final nowDate = DateTime(now.year, now.month, now.day);
      
      for (var plant in plants) {
        final plantId = plant['id'] as String?;
        if (plantId == null) continue;
        
        bool hasNotification = false;
        bool needsWatering = false;
        bool needsFertilization = false;
        DateTime? careDueDate;
        
        // Sulama ayarlarını kontrol et
        final wateringSettings = await _notificationService.getNotificationSettings(plantId, 'watering');
        if (wateringSettings != null && wateringSettings['enabled'] == true) {
          hasNotification = true;
          
          final lastWateringStr = prefs.getString('last_watering_$plantId');
          final repeatValue = wateringSettings['repeatValue'] as int? ?? 13;
          final repeatUnit = wateringSettings['repeatUnit'] as String? ?? 'days';
          final reminderTimeStr = wateringSettings['reminderTime'] as String?;
          
          DateTime nextDate;
          if (lastWateringStr != null) {
            final lastWatering = DateTime.parse(lastWateringStr);
            final lastWateringDate = DateTime(lastWatering.year, lastWatering.month, lastWatering.day);
            
            // Bugün yapıldıysa bakım ihtiyacı yok
            if (lastWateringDate.isAtSameMomentAs(nowDate)) {
              // Bakım ihtiyacı yok
            } else {
              if (repeatUnit == 'weeks') {
                nextDate = lastWatering.add(Duration(days: repeatValue * 7));
              } else if (repeatUnit == 'months') {
                nextDate = DateTime(lastWatering.year, lastWatering.month + repeatValue, lastWatering.day);
              } else {
                nextDate = lastWatering.add(Duration(days: repeatValue));
              }
              
              // Bildirim zamanını ekle
              if (reminderTimeStr != null) {
                final parts = reminderTimeStr.split(':');
                final reminderHour = int.parse(parts[0]);
                final reminderMinute = int.parse(parts[1]);
                nextDate = DateTime(nextDate.year, nextDate.month, nextDate.day, reminderHour, reminderMinute);
              }
              
              final nextDateOnly = DateTime(nextDate.year, nextDate.month, nextDate.day);
              
              // Bakım zamanı geldi mi kontrol et
              if (nextDateOnly.isBefore(nowDate) || nextDateOnly.isAtSameMomentAs(nowDate)) {
                if (reminderTimeStr != null) {
                  final parts = reminderTimeStr.split(':');
                  final reminderHour = int.parse(parts[0]);
                  final reminderMinute = int.parse(parts[1]);
                  
                  if (nextDateOnly.isAtSameMomentAs(nowDate)) {
                    // Bugünse bildirim zamanını kontrol et
                    if (now.hour > reminderHour || (now.hour == reminderHour && now.minute >= reminderMinute)) {
                      needsWatering = true;
                      if (careDueDate == null || nextDateOnly.isBefore(careDueDate)) {
                        careDueDate = nextDateOnly;
                      }
                    }
                  } else {
                    // Geçmişteyse kesinlikle bakım ihtiyacı var
                    needsWatering = true;
                    if (careDueDate == null || nextDateOnly.isBefore(careDueDate)) {
                      careDueDate = nextDateOnly;
                    }
                  }
                } else {
                  // Bildirim zamanı yoksa tarih kontrolü yeterli
                  needsWatering = true;
                  if (careDueDate == null || nextDateOnly.isBefore(careDueDate)) {
                    careDueDate = nextDateOnly;
                  }
                }
              }
            }
          } else {
            // Henüz sulama yapılmamışsa, bildirim zamanı geldiyse bakım ihtiyacı var
            if (reminderTimeStr != null) {
              final parts = reminderTimeStr.split(':');
              final reminderHour = int.parse(parts[0]);
              final reminderMinute = int.parse(parts[1]);
              
              if (now.hour > reminderHour || (now.hour == reminderHour && now.minute >= reminderMinute)) {
                needsWatering = true;
                if (careDueDate == null) {
                  careDueDate = nowDate;
                }
              }
            }
          }
        }
        
        // Gübreleme ayarlarını kontrol et
        final fertilizationSettings = await _notificationService.getNotificationSettings(plantId, 'fertilization');
        if (fertilizationSettings != null && fertilizationSettings['enabled'] == true) {
          hasNotification = true;
          
          final lastFertilizationStr = prefs.getString('last_fertilization_$plantId');
          final repeatValue = fertilizationSettings['repeatValue'] as int? ?? 13;
          final repeatUnit = fertilizationSettings['repeatUnit'] as String? ?? 'days';
          final reminderTimeStr = fertilizationSettings['reminderTime'] as String?;
          
          DateTime nextDate;
          if (lastFertilizationStr != null) {
            final lastFertilization = DateTime.parse(lastFertilizationStr);
            final lastFertilizationDate = DateTime(lastFertilization.year, lastFertilization.month, lastFertilization.day);
            
            // Bugün yapıldıysa bakım ihtiyacı yok
            if (lastFertilizationDate.isAtSameMomentAs(nowDate)) {
              // Bakım ihtiyacı yok
            } else {
              if (repeatUnit == 'weeks') {
                nextDate = lastFertilization.add(Duration(days: repeatValue * 7));
              } else if (repeatUnit == 'months') {
                nextDate = DateTime(lastFertilization.year, lastFertilization.month + repeatValue, lastFertilization.day);
              } else {
                nextDate = lastFertilization.add(Duration(days: repeatValue));
              }
              
              // Bildirim zamanını ekle
              if (reminderTimeStr != null) {
                final parts = reminderTimeStr.split(':');
                final reminderHour = int.parse(parts[0]);
                final reminderMinute = int.parse(parts[1]);
                nextDate = DateTime(nextDate.year, nextDate.month, nextDate.day, reminderHour, reminderMinute);
              }
              
              final nextDateOnly = DateTime(nextDate.year, nextDate.month, nextDate.day);
              
              // Bakım zamanı geldi mi kontrol et
              if (nextDateOnly.isBefore(nowDate) || nextDateOnly.isAtSameMomentAs(nowDate)) {
                if (reminderTimeStr != null) {
                  final parts = reminderTimeStr.split(':');
                  final reminderHour = int.parse(parts[0]);
                  final reminderMinute = int.parse(parts[1]);
                  
                  if (nextDateOnly.isAtSameMomentAs(nowDate)) {
                    // Bugünse bildirim zamanını kontrol et
                    if (now.hour > reminderHour || (now.hour == reminderHour && now.minute >= reminderMinute)) {
                      needsFertilization = true;
                      if (careDueDate == null || nextDateOnly.isBefore(careDueDate)) {
                        careDueDate = nextDateOnly;
                      }
                    }
                  } else {
                    // Geçmişteyse kesinlikle bakım ihtiyacı var
                    needsFertilization = true;
                    if (careDueDate == null || nextDateOnly.isBefore(careDueDate)) {
                      careDueDate = nextDateOnly;
                    }
                  }
                } else {
                  // Bildirim zamanı yoksa tarih kontrolü yeterli
                  needsFertilization = true;
                  if (careDueDate == null || nextDateOnly.isBefore(careDueDate)) {
                    careDueDate = nextDateOnly;
                  }
                }
              }
            }
          } else {
            // Henüz gübreleme yapılmamışsa, bildirim zamanı geldiyse bakım ihtiyacı var
            if (reminderTimeStr != null) {
              final parts = reminderTimeStr.split(':');
              final reminderHour = int.parse(parts[0]);
              final reminderMinute = int.parse(parts[1]);
              
              if (now.hour > reminderHour || (now.hour == reminderHour && now.minute >= reminderMinute)) {
                needsFertilization = true;
                if (careDueDate == null) {
                  careDueDate = nowDate;
                }
              }
            }
          }
        }
        
        // Bildirim ayarlı bitkileri ekle
        if (hasNotification) {
          plantsWithNotifications.add(plant);
          
          // Bakıma ihtiyaç duyan bitkileri ekle
          if (needsWatering || needsFertilization) {
            plantsNeedingCareList.add({
              ...plant,
              'careDueDate': careDueDate,
              'needsWatering': needsWatering,
              'needsFertilization': needsFertilization,
            });
          }
        }
      }
      
      // Bakıma ihtiyaç duyan bitkileri tarihe göre sırala (en eski önce)
      plantsNeedingCareList.sort((a, b) {
        final dateA = a['careDueDate'] as DateTime?;
        final dateB = b['careDueDate'] as DateTime?;
        if (dateA == null && dateB == null) return 0;
        if (dateA == null) return 1;
        if (dateB == null) return -1;
        return dateA.compareTo(dateB);
      });
      
      setState(() {
        _totalPlantsWithNotifications = plantsWithNotifications.length;
        _plantsNeedingCare = plantsNeedingCareList.length;
        _plantsWithNotifications = plantsWithNotifications;
        _plantsNeedingCareList = plantsNeedingCareList;
      });
    } catch (e) {
      print('❌ Anımsatmalar verisi yükleme hatası: $e');
    }
  }

  Future<void> _showRemindersModal(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final plantsJson = prefs.getString('saved_plants') ?? '[]';
      final allPlants = List<Map<String, dynamic>>.from(
        jsonDecode(plantsJson) as List
      );
      
      // Bildirim ayarlı bitkileri bul ve bakım ihtiyacı kontrolü yap (_loadRemindersData ile aynı mantık)
      List<Map<String, dynamic>> plantsWithNotifications = [];
      final now = DateTime.now();
      final nowDate = DateTime(now.year, now.month, now.day);
      
      for (var plant in allPlants) {
        final plantId = plant['id'] as String?;
        if (plantId == null) continue;
        
        bool hasNotification = false;
        bool needsWatering = false;
        bool needsFertilization = false;
        
        // Sulama ayarlarını kontrol et
        final wateringSettings = await _notificationService.getNotificationSettings(plantId, 'watering');
        if (wateringSettings != null && wateringSettings['enabled'] == true) {
          hasNotification = true;
          
          final lastWateringStr = prefs.getString('last_watering_$plantId');
          final repeatValue = wateringSettings['repeatValue'] as int? ?? 13;
          final repeatUnit = wateringSettings['repeatUnit'] as String? ?? 'days';
          final reminderTimeStr = wateringSettings['reminderTime'] as String?;
          
          if (lastWateringStr != null) {
            final lastWatering = DateTime.parse(lastWateringStr);
            final lastWateringDate = DateTime(lastWatering.year, lastWatering.month, lastWatering.day);
            
            if (!lastWateringDate.isAtSameMomentAs(nowDate)) {
              DateTime nextDate;
              if (repeatUnit == 'weeks') {
                nextDate = lastWatering.add(Duration(days: repeatValue * 7));
              } else if (repeatUnit == 'months') {
                nextDate = DateTime(lastWatering.year, lastWatering.month + repeatValue, lastWatering.day);
              } else {
                nextDate = lastWatering.add(Duration(days: repeatValue));
              }
              
              if (reminderTimeStr != null) {
                final parts = reminderTimeStr.split(':');
                final reminderHour = int.parse(parts[0]);
                final reminderMinute = int.parse(parts[1]);
                nextDate = DateTime(nextDate.year, nextDate.month, nextDate.day, reminderHour, reminderMinute);
              }
              
              final nextDateOnly = DateTime(nextDate.year, nextDate.month, nextDate.day);
              
              if (nextDateOnly.isBefore(nowDate) || nextDateOnly.isAtSameMomentAs(nowDate)) {
                if (reminderTimeStr != null) {
                  final parts = reminderTimeStr.split(':');
                  final reminderHour = int.parse(parts[0]);
                  final reminderMinute = int.parse(parts[1]);
                  
                  if (nextDateOnly.isAtSameMomentAs(nowDate)) {
                    if (now.hour > reminderHour || (now.hour == reminderHour && now.minute >= reminderMinute)) {
                      needsWatering = true;
                    }
                  } else {
                    needsWatering = true;
                  }
                } else {
                  needsWatering = true;
                }
              }
            }
          } else {
            if (reminderTimeStr != null) {
              final parts = reminderTimeStr.split(':');
              final reminderHour = int.parse(parts[0]);
              final reminderMinute = int.parse(parts[1]);
              
              if (now.hour > reminderHour || (now.hour == reminderHour && now.minute >= reminderMinute)) {
                needsWatering = true;
              }
            }
          }
        }
        
        // Gübreleme ayarlarını kontrol et
        final fertilizationSettings = await _notificationService.getNotificationSettings(plantId, 'fertilization');
        if (fertilizationSettings != null && fertilizationSettings['enabled'] == true) {
          hasNotification = true;
          
          final lastFertilizationStr = prefs.getString('last_fertilization_$plantId');
          final repeatValue = fertilizationSettings['repeatValue'] as int? ?? 13;
          final repeatUnit = fertilizationSettings['repeatUnit'] as String? ?? 'days';
          final reminderTimeStr = fertilizationSettings['reminderTime'] as String?;
          
          if (lastFertilizationStr != null) {
            final lastFertilization = DateTime.parse(lastFertilizationStr);
            final lastFertilizationDate = DateTime(lastFertilization.year, lastFertilization.month, lastFertilization.day);
            
            if (!lastFertilizationDate.isAtSameMomentAs(nowDate)) {
              DateTime nextDate;
              if (repeatUnit == 'weeks') {
                nextDate = lastFertilization.add(Duration(days: repeatValue * 7));
              } else if (repeatUnit == 'months') {
                nextDate = DateTime(lastFertilization.year, lastFertilization.month + repeatValue, lastFertilization.day);
              } else {
                nextDate = lastFertilization.add(Duration(days: repeatValue));
              }
              
              if (reminderTimeStr != null) {
                final parts = reminderTimeStr.split(':');
                final reminderHour = int.parse(parts[0]);
                final reminderMinute = int.parse(parts[1]);
                nextDate = DateTime(nextDate.year, nextDate.month, nextDate.day, reminderHour, reminderMinute);
              }
              
              final nextDateOnly = DateTime(nextDate.year, nextDate.month, nextDate.day);
              
              if (nextDateOnly.isBefore(nowDate) || nextDateOnly.isAtSameMomentAs(nowDate)) {
                if (reminderTimeStr != null) {
                  final parts = reminderTimeStr.split(':');
                  final reminderHour = int.parse(parts[0]);
                  final reminderMinute = int.parse(parts[1]);
                  
                  if (nextDateOnly.isAtSameMomentAs(nowDate)) {
                    if (now.hour > reminderHour || (now.hour == reminderHour && now.minute >= reminderMinute)) {
                      needsFertilization = true;
                    }
                  } else {
                    needsFertilization = true;
                  }
                } else {
                  needsFertilization = true;
                }
              }
            }
          } else {
            if (reminderTimeStr != null) {
              final parts = reminderTimeStr.split(':');
              final reminderHour = int.parse(parts[0]);
              final reminderMinute = int.parse(parts[1]);
              
              if (now.hour > reminderHour || (now.hour == reminderHour && now.minute >= reminderMinute)) {
                needsFertilization = true;
              }
            }
          }
        }
        
        if (hasNotification) {
          plantsWithNotifications.add({
            ...plant,
            'needsWatering': needsWatering,
            'needsFertilization': needsFertilization,
          });
        }
      }
      
      if (!context.mounted) return;
      
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AppColors.border, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Anımsatmalar',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: AppColors.textSecondary),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              // Bitki listesi
              Expanded(
                child: plantsWithNotifications.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.notifications_off,
                              size: 64,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Bildirim ayarlı bitki yok',
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: plantsWithNotifications.length,
                        itemBuilder: (context, index) {
                          final plant = plantsWithNotifications[index];
                          final imagePath = plant['imagePath'] as String?;
                          final needsWatering = plant['needsWatering'] == true;
                          final needsFertilization = plant['needsFertilization'] == true;
                          final needsCare = needsWatering || needsFertilization;
                          
                          // Debug için
                          if (needsCare) {
                            print('🔴 Bakıma ihtiyaç duyan bitki: ${plant['name']} - Sulama: $needsWatering, Gübreleme: $needsFertilization');
                          }
                          
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: AppColors.cardBackground,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: needsCare ? AppColors.danger : AppColors.border,
                                width: needsCare ? 2.5 : 1,
                              ),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(12),
                              leading: imagePath != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.file(
                                        File(imagePath),
                                        width: 60,
                                        height: 60,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) {
                                          return Container(
                                            width: 60,
                                            height: 60,
                                            decoration: BoxDecoration(
                                              color: AppColors.primary.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Icon(
                                              Icons.eco,
                                              color: AppColors.primary,
                                            ),
                                          );
                                        },
                                      ),
                                    )
                                  : Container(
                                      width: 60,
                                      height: 60,
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        Icons.eco,
                                        color: AppColors.primary,
                                      ),
                                    ),
                              title: Text(
                                plant['name'] as String? ?? 'Bitki',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              trailing: Icon(
                                Icons.chevron_right,
                                color: AppColors.textSecondary,
                              ),
                              onTap: () async {
                                Navigator.of(context).pop();
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => PlantDetailPage(
                                      plant: plant,
                                      initialTab: 1, // Bakım sekmesi
                                    ),
                                  ),
                                );
                                // Bitki detay sayfasından dönünce verileri yenile
                                if (mounted) {
                                  _loadRemindersData();
                                }
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      print('❌ Anımsatmalar modal hatası: $e');
    }
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
        await _loadRemindersData();
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
          
          // Anımsatmalar Kartı
          if (_totalPlantsWithNotifications > 0)
            _RemindersCard(
              totalPlants: _totalPlantsWithNotifications,
              plantsNeedingCare: _plantsNeedingCare,
              plantsNeedingCareList: _plantsNeedingCareList,
              plantsWithNotifications: _plantsWithNotifications,
              onTap: () => _showRemindersModal(context),
            ),
          if (_totalPlantsWithNotifications > 0)
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
    final windSpeed = (weatherData!['wind_speed'] as num?)?.toDouble() ?? 0.0;
    final description = (weatherData!['description'] as String?) ?? '';
    final icon = (weatherData!['icon'] as String?) ?? 'clouds';
    final descLower = description.toLowerCase();
    
    // Öncelik sırası: Aşırı soğuk/kar > Aşırı sıcak > Yağmur > Rüzgar > Sıcaklık > Nem
    
    // 1. Aşırı soğuk ve kar durumu
    if (temp < 5 || icon == 'snow' || descLower.contains('kar') || descLower.contains('kar yağışı')) {
      return 'Don riski var! Hassas bitkileri koruyucu örtü ile örtün veya sıcak alana taşıyın. '
          'Sulamayı durdurun, donmuş toprak kökleri zarar verir. Toprak donmadan önce malçlama yapın.';
    }
    
    // 2. Aşırı sıcak durumu
    if (temp > 32) {
      return 'Aşırı sıcak! Sabah 06:00-08:00 veya akşam 18:00-20:00 saatlerinde sulayın. '
          'Öğle saatlerinde sulamayın, su buharlaşır ve yaprakları yakar. '
          'Gölge sağlayın, toprak nemini günlük kontrol edin. Yapraklara su püskürtün.';
    }
    
    // 3. Yağmurlu hava
    if (icon == 'rain' || descLower.contains('yağmur') || descLower.contains('yağış')) {
      if (temp < 15) {
        return 'Yağmurlu ve serin. Sulama gerekmez, ancak saksı altındaki su birikintilerini boşaltın. '
            'Drenajı kontrol edin, kök çürümesini önleyin. Yapraklarda mantar riski artar.';
      } else {
        return 'Yağmurlu hava. Sulama yapmanıza gerek yok. '
            'Saksı bitkilerinde su birikimine dikkat edin, fazla suyu boşaltın. '
            'Yağmur sonrası toprak nemini kontrol edin.';
      }
    }
    
    // 4. Güçlü rüzgar
    if (windSpeed > 20) {
      return 'Güçlü rüzgar var. Saksıları sabitleyin, yüksek bitkileri destekleyin. '
          'Rüzgar toprak nemini hızla buharlaştırır, sulama ihtiyacını kontrol edin. '
          'Hassas bitkileri korumalı alana alın.';
    }
    
    // 5. Soğuk hava (5-15°C)
    if (temp >= 5 && temp < 15) {
      return 'Serin hava. Sulama sıklığını azaltın, toprak yavaş kurur. '
          'Soğuğa hassas bitkileri koruyucu örtü ile örtün. '
          'Don riski varsa öğleden sonra sulayın, sabah erken saatlerden kaçının.';
    }
    
    // 6. Ilıman hava (15-22°C)
    if (temp >= 15 && temp <= 22) {
      if (humidity < 40) {
        return 'Ilıman ama kuru hava. Yapraklara su püskürtün, bitkilerin yanına su dolu kap koyun. '
            'Normal sulama programınıza devam edin. Bu koşullar bitki büyümesi için ideal.';
      } else if (humidity > 70) {
        return 'Ilıman ama nemli hava. Havalandırmayı artırın, bitkiler arasında boşluk bırakın. '
            'Aşırı sulamadan kaçının, mantar hastalığı riski var. Yaprakları kuru tutun.';
      } else {
        return 'Mükemmel hava koşulları! Sıcaklık ve nem ideal. '
            'Düzenli sulama yapın, toprak nemini kontrol edin. '
            'Aktif büyüme dönemi, hafif gübreleme yapabilirsiniz.';
      }
    }
    
    // 7. Sıcak hava (22-30°C)
    if (temp > 22 && temp <= 30) {
      if (humidity < 40) {
        return 'Sıcak ve kuru hava. Toprak nemini günlük kontrol edin, daha sık sulayın. '
            'Sabah erken veya akşam geç saatlerde sulayın. Yapraklara su püskürtün. '
            'Direkt güneş alan bitkileri gölgeye taşıyın.';
      } else {
        return 'Sıcak hava. Sabah 07:00-09:00 saatlerinde sulayın. '
            'Toprak hızlı kurur, günlük kontrol edin. '
            'Öğle sıcağında gölge sağlayın, yaprak yanığı riski var.';
      }
    }
    
    // 8. Bulutlu hava
    if (icon == 'clouds' || descLower.contains('bulutlu')) {
      return 'Bulutlu hava. Işık azaldığı için sulama sıklığını azaltın. '
          'Toprak daha yavaş kurur. Işık seven bitkileri güneşli alana taşıyın. '
          'Havalandırmayı unutmayın.';
    }
    
    // 9. Güneşli hava
    if (icon == 'clear' || descLower.contains('açık') || descLower.contains('güneşli')) {
      if (temp > 25) {
        return 'Güneşli ve sıcak. Sabah erken sulayın, öğle saatlerinde gölge sağlayın. '
            'Toprak nemini günlük kontrol edin, sıcakta hızlı kurur. '
            'Yaprakları temiz tutun, toz güneş ışığını engeller.';
      } else {
        return 'Güneşli ve ılıman hava. Bitkileriniz için ideal koşullar! '
            'Bol ışık büyümeyi destekler. Normal sulama yapın, toprak nemini kontrol edin. '
            'Aktif büyüme dönemi, hafif gübreleme yapabilirsiniz.';
      }
    }
    
    // Varsayılan öneri
    return 'Hava durumu normal. Düzenli bakım yapın, toprak nemini kontrol edin. '
        'Hava koşullarına göre sulama sıklığını ayarlayın.';
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

class _RemindersCard extends StatelessWidget {
  const _RemindersCard({
    required this.totalPlants,
    required this.plantsNeedingCare,
    required this.plantsNeedingCareList,
    required this.plantsWithNotifications,
    required this.onTap,
  });

  final int totalPlants;
  final int plantsNeedingCare;
  final List<Map<String, dynamic>> plantsNeedingCareList;
  final List<Map<String, dynamic>> plantsWithNotifications;
  final VoidCallback onTap;

  Widget _buildPlantImage(String? imagePath, {double offset = 0}) {
    return Positioned(
      left: offset,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.cardBackground,
            width: 2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: imagePath != null && File(imagePath).existsSync()
              ? Image.file(
                  File(imagePath),
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                      ),
                      child: Icon(
                        Icons.eco,
                        color: AppColors.primary,
                        size: 30,
                      ),
                    );
                  },
                )
              : Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                  ),
                  child: Icon(
                    Icons.eco,
                    color: AppColors.primary,
                    size: 30,
                  ),
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Bakıma ihtiyaç duyan bitkilerden maksimum 3 tanesini al (en eski önce)
    // Eğer bakıma ihtiyaç duyan bitki yoksa, bildirim ayarlı bitkilerden ilk 3'ünü göster
    final plantsToShow = plantsNeedingCareList.isNotEmpty 
        ? plantsNeedingCareList.take(3).toList()
        : plantsWithNotifications.take(3).toList();
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Bitki fotoğrafları (sol) - maksimum 3 tane, stacked görünüm
            SizedBox(
              width: 80,
              height: 80,
              child: Stack(
                children: [
                  if (plantsToShow.isNotEmpty)
                    _buildPlantImage(
                      plantsToShow[0]['imagePath'] as String?,
                      offset: 0,
                    ),
                  if (plantsToShow.length > 1)
                    _buildPlantImage(
                      plantsToShow[1]['imagePath'] as String?,
                      offset: 15,
                    ),
                  if (plantsToShow.length > 2)
                    _buildPlantImage(
                      plantsToShow[2]['imagePath'] as String?,
                      offset: 30,
                    ),
                  // Eğer hiç bitki yoksa placeholder göster
                  if (plantsToShow.isEmpty)
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.eco,
                        color: AppColors.primary,
                        size: 30,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // Sağ taraf - bilgiler
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Genel',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$totalPlants bitki ($plantsNeedingCare bakıma ihtiyaç duyuyor)',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      // Sulama ikonu - bakıma ihtiyaç varsa kırmızı çerçeve
                      Builder(
                        builder: (context) {
                          final needsWatering = plantsNeedingCareList.any((p) => p['needsWatering'] == true);
                          return Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: needsWatering 
                                  ? AppColors.danger.withOpacity(0.1)
                                  : AppColors.primary.withOpacity(0.1),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: needsWatering ? AppColors.danger : AppColors.primary,
                                width: 2,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Image.asset(
                                'assets/images/Sulamak.png',
                                errorBuilder: (context, error, stackTrace) {
                                  return Icon(
                                    Icons.water_drop,
                                    color: needsWatering ? AppColors.danger : AppColors.primary,
                                    size: 24,
                                  );
                                },
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 12),
                      // Gübreleme ikonu - bakıma ihtiyaç varsa kırmızı çerçeve
                      Builder(
                        builder: (context) {
                          final needsFertilization = plantsNeedingCareList.any((p) => p['needsFertilization'] == true);
                          return Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: needsFertilization 
                                  ? AppColors.danger.withOpacity(0.1)
                                  : AppColors.primary.withOpacity(0.1),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: needsFertilization ? AppColors.danger : AppColors.primary,
                                width: 2,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Image.asset(
                                'assets/images/Gübrelemek.png',
                                errorBuilder: (context, error, stackTrace) {
                                  return Icon(
                                    Icons.eco,
                                    color: needsFertilization ? AppColors.danger : AppColors.primary,
                                    size: 24,
                                  );
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
        Text(
          'Sensör Verileri',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
                letterSpacing: -0.5,
              ),
        ),
        const SizedBox(height: 12),
        Column(
              children: [
                _SensorCard(
                  icon: Icons.thermostat,
                  label: 'Sıcaklık',
                  value: '${latest.temp.toStringAsFixed(1)}°C',
              iconColor: const Color(0xFF10B981), // emerald-500
              iconBg: const Color(0xFFD1FAE5), // emerald-400/10
              iconBorder: const Color(0xFFA7F3D0), // emerald-300/70
              ringColor: const Color(0xFFD1FAE5), // emerald-200
              sensorType: 'temp',
                ),
            const SizedBox(height: 12),
                _SensorCard(
                  icon: Icons.water_drop,
                  label: 'Nem',
              value: '${latest.humidity.toStringAsFixed(0)}%',
              iconColor: const Color(0xFFF59E0B), // amber-500
              iconBg: const Color(0xFFFEF3C7), // amber-400/10
              iconBorder: const Color(0xFFFDE68A), // amber-300/70
              ringColor: const Color(0xFFFEF3C7), // amber-200
              sensorType: 'humidity',
                ),
            const SizedBox(height: 12),
                _SensorCard(
                  icon: Icons.cloud,
                  label: 'CO₂',
                  value: '${latest.co2.toStringAsFixed(0)} ppm',
              iconColor: const Color(0xFFEF4444), // red-500
              iconBg: const Color(0xFFFEE2E2), // red-400/10
              iconBorder: const Color(0xFFFECACA), // red-400/70
              ringColor: const Color(0xFFDBEAFE), // sky-200 (HTML'de sky-200 kullanılmış)
              sensorType: 'co2',
                ),
              ],
        ),
      ],
    );
  }

}

class _SensorCard extends StatelessWidget {
  const _SensorCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.iconColor,
    required this.iconBg,
    required this.iconBorder,
    required this.ringColor,
    required this.sensorType,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color iconColor;
  final Color iconBg;
  final Color iconBorder;
  final Color ringColor;
  final String sensorType;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Bitki listesini alttan modal olarak göster
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (modalContext) => _PlantListBottomSheet(
            sensorType: sensorType,
          ),
        );
      },
      child: Container(
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
              child: Row(
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
                  Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Bitki listesi bottom sheet widget'ı
class _PlantListBottomSheet extends StatefulWidget {
  final String sensorType;
  
  const _PlantListBottomSheet({
    required this.sensorType,
  });

  @override
  State<_PlantListBottomSheet> createState() => _PlantListBottomSheetState();
}

class _PlantListBottomSheetState extends State<_PlantListBottomSheet> {
  String? _tooltipMessage;

  void _showTooltip(String message) {
    setState(() {
      _tooltipMessage = message;
    });
    
    // 3 saniye sonra gizle
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _tooltipMessage = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Mevcut sensör değerlerini al
    final state = context.watch<AppState>();
    final latest = state.latest;
    
    return Stack(
      children: [
        Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textSecondary.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Bahçemdeki Bitkiler',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 16),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _loadPlants(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(),
                      );
                    }
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'Henüz bitki eklenmemiş',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                        ),
                      );
                    }
                    final plants = snapshot.data!;
                    return ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.6,
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: plants.length,
                        itemBuilder: (context, index) {
                          final plant = plants[index];
                          return _PlantListItem(
                            plant: plant,
                            sensorType: widget.sensorType,
                            latest: latest,
                            onWarningTap: (message) => _showTooltip(message),
                          );
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
          ),
        ),
        // Tooltip overlay - modal'ın üstünde göster
        if (_tooltipMessage != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(12),
                  color: const Color(0xFFEF4444),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _tooltipMessage!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white, size: 18),
                          onPressed: () {
                            setState(() {
                              _tooltipMessage = null;
                            });
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<List<Map<String, dynamic>>> _loadPlants() async {
    final prefs = await SharedPreferences.getInstance();
    final plantsJson = prefs.getString('saved_plants') ?? '[]';
    return List<Map<String, dynamic>>.from(
      jsonDecode(plantsJson) as List,
    );
  }
}

class _PlantListItem extends StatelessWidget {
  final Map<String, dynamic> plant;
  final String sensorType;
  final LatestReadings? latest;
  final Function(String message) onWarningTap;
  
  const _PlantListItem({
    required this.plant,
    required this.sensorType,
    required this.latest,
    required this.onWarningTap,
  });

  @override
  Widget build(BuildContext context) {
    // Bitki türünü plantType veya originalPlantType'dan al (species değil, çünkü o alan yok)
    final plantType = plant['plantType'] ?? plant['originalPlantType'] ?? 'Unknown';
    final thresholds = PlantThresholds.forPlantType(plantType);
    
    String rangeText;
    bool isOutOfRange = false;
    
    if (latest != null) {
      switch (sensorType) {
        case 'temp':
          rangeText = '${thresholds.tempMin.toStringAsFixed(0)}–${thresholds.tempMax.toStringAsFixed(0)}°C';
          isOutOfRange = thresholds.isTempOutOfRange(latest!.temp);
          break;
        case 'humidity':
          rangeText = '${thresholds.humidityMin.toStringAsFixed(0)}–${thresholds.humidityMax.toStringAsFixed(0)}%';
          isOutOfRange = thresholds.isHumidityOutOfRange(latest!.humidity);
          break;
        case 'co2':
          rangeText = '${thresholds.co2Min.toStringAsFixed(0)}–${thresholds.co2Max.toStringAsFixed(0)} ppm';
          isOutOfRange = thresholds.isCo2OutOfRange(latest!.co2);
          break;
        default:
          rangeText = '—';
      }
    } else {
      switch (sensorType) {
        case 'temp':
          rangeText = '${thresholds.tempMin.toStringAsFixed(0)}–${thresholds.tempMax.toStringAsFixed(0)}°C';
          break;
        case 'humidity':
          rangeText = '${thresholds.humidityMin.toStringAsFixed(0)}–${thresholds.humidityMax.toStringAsFixed(0)}%';
          break;
        case 'co2':
          rangeText = '${thresholds.co2Min.toStringAsFixed(0)}–${thresholds.co2Max.toStringAsFixed(0)} ppm';
          break;
        default:
          rangeText = '—';
      }
    }
    
    // Uyarı mesajını hazırla (eğer aralık dışındaysa)
    String? warningMessage;
    if (latest != null && isOutOfRange) {
      switch (sensorType) {
        case 'temp':
          if (latest!.temp > thresholds.tempMax) {
            warningMessage = 'Sıcaklık optimal değerinin üzerinde';
          } else if (latest!.temp < thresholds.tempMin) {
            warningMessage = 'Sıcaklık optimal değerinin altında';
          }
          break;
        case 'humidity':
          if (latest!.humidity > thresholds.humidityMax) {
            warningMessage = 'Nem optimal değerinin üzerinde';
          } else if (latest!.humidity < thresholds.humidityMin) {
            warningMessage = 'Nem optimal değerinin altında';
          }
          break;
        case 'co2':
          if (latest!.co2 > thresholds.co2Max) {
            warningMessage = 'CO₂ optimal değerinin üzerinde';
          } else if (latest!.co2 < thresholds.co2Min) {
            warningMessage = 'CO₂ optimal değerinin altında';
          }
          break;
      }
    }
    
    return ListTile(
      title: Row(
        children: [
          Expanded(
            child: Text(plant['name'] ?? plantType),
          ),
          if (latest != null)
            isOutOfRange
                ? GestureDetector(
                    onTap: () {
                      if (warningMessage != null) {
                        onWarningTap(warningMessage!);
                      }
                    },
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: Color(0xFFEF4444),
                      size: 20,
                    ),
                  )
                : const Icon(
                    Icons.check_circle,
                    color: Color(0xFF10B981),
                    size: 20,
                  ),
        ],
      ),
      subtitle: Text('Optimal: $rangeText'),
      leading: const Icon(Icons.eco, color: Color(0xFF10B981)),
    );
  }
}
