import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/sensor_reading.dart';
import '../models/plant_thresholds.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import 'auth_state.dart';

class AppState extends ChangeNotifier {
  final api = ApiService();
  final _notificationService = NotificationService();
  Timer? _refreshTimer;
  Timer? _quickRefreshTimer;
  
  // AuthState inject 
  AuthState? _authState;
  
  
  final Map<String, DateTime> _lastNotificationTime = {};
  
  void setAuthState(AuthState authState) {
    _authState = authState;
    
    api.onUnauthorized = () {
      _authState?.logout();
    };
  }

  LatestReadings? latest;
  List<SensorPoint> tempSeries = [], humiditySeries = [], co2Series = [];
  List<Map<String, dynamic>> alerts = [];
  Set<String> readAlertIds = {}; // Okunmuş bildirim ID'leri
  Map<String, Map<String, dynamic>> actuators = {
    'fan': {'mode': 'auto', 'state': 'off', 'last_change': null},
    'heater': {'mode': 'auto', 'state': 'off', 'last_change': null},
    'humidifier': {'mode': 'auto', 'state': 'off', 'last_change': null},
  };
  bool loading = false;
  String? error;
  
  void markAlertsAsRead() {
    
    for (final alert in alerts) {
      final id = alert['id']?.toString() ?? alert['ts']?.toString() ?? '';
      if (id.isNotEmpty) {
        readAlertIds.add(id);
      }
    }
    notifyListeners();
  }

  AppState() {
    // Otomatik yenileme başlat (her 1 dakikada bir)
    _startAutoRefresh();
    _startQuickRefresh();
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      // Yükleme sırasında yeni istek yapma
      if (!loading) {
        loadDashboard();
      }
    });
  }

  void stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _quickRefreshTimer?.cancel();
    _quickRefreshTimer = null;
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _quickRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> loadDashboard() async {
    loading = true; error = null; notifyListeners();
    try {
      final latestFuture = api.getLatest();
      final tempFuture = api.getSeries(sensor:'temp', bucket:'hourly', hours:24);
      final humidityFuture = api.getSeries(sensor:'humidity', bucket:'hourly', hours:24);
      final co2Future = api.getSeries(sensor:'co2', bucket:'hourly', hours:24);
      final actuatorsFuture = api.getActuators();

      latest = await latestFuture;
      tempSeries = await tempFuture;
      humiditySeries = await humidityFuture;
      co2Series = await co2Future;
      try {
        actuators = await actuatorsFuture;
      } catch (e) {
        // Actuator endpoint başarısız olsa bile dashboard verileri güncellensin
        debugPrint('Actuator fetch error: $e');
      }
      
      // Bitki eşik kontrollerini yap ve bildirim gönder
      if (latest != null) {
        await _checkPlantThresholds(latest!);
      }
      
      final newAlerts = await _buildAlerts();
      // Yeni gelen bildirimlerin ID'lerini kontrol et, okunmamış olanları koru
      final existingIds = readAlertIds.toSet();
      alerts = newAlerts;
      // Mevcut ID'leri koru (yeni bildirimler otomatik okunmamış olur)
      readAlertIds = existingIds;
      
      // Debug: veri sayısını kontrol et
      print('Loaded series - temp: ${tempSeries.length}, humidity: ${humiditySeries.length}, co2: ${co2Series.length}');
    } catch (e) {
      error = e.toString();
      print('Error loading dashboard: $e');
    } finally {
      loading = false; notifyListeners();
    }
  }

  Future<void> setActuator(String device, String action) async {
    await api.setActuator(device: device, action: action);
    try {
      final status = await api.getActuatorStatus(device);
      actuators = {
        ...actuators,
        device: status,
      };
      // Aktüatör komutundan sonra dashboard'u hemen yenile
      await loadDashboard();
      return;
    } catch (e) {
      // API başarısız olsa bile üst katmana ilet
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _buildAlerts() async {
    final alertsList = (await api.getAlerts(limit: 20)).map(_localizeAlert).toList();
    final actuatorHistory = await api.getActuatorHistory(limit: 20);
    final actuatorAlerts = actuatorHistory.map(_mapActuatorEventToAlert).toList();
    
    // Local alert'leri oku (bitki bakım ve optimal değer bildirimleri)
    final localAlerts = await _loadLocalAlerts();

    final allAlerts = [...alertsList, ...actuatorAlerts, ...localAlerts];
    allAlerts.sort((a, b) {
      final aTime = DateTime.parse(a['ts'] as String);
      final bTime = DateTime.parse(b['ts'] as String);
      return bTime.compareTo(aTime);
    });

    return allAlerts.take(20).toList(); // 20'ye çıkardık çünkü local alert'ler de var
  }

  // Local alert'leri SharedPreferences'tan yükle
  Future<List<Map<String, dynamic>>> _loadLocalAlerts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alertsJson = prefs.getString('local_alerts') ?? '[]';
      return List<Map<String, dynamic>>.from(
        jsonDecode(alertsJson) as List,
      ).map((alert) {
        // Localize et (eğer gerekirse)
        return _localizeAlert(alert);
      }).toList();
    } catch (e) {
      debugPrint('Local alert yükleme hatası: $e');
      return [];
    }
  }

  Map<String, dynamic> _mapActuatorEventToAlert(Map<String, dynamic> event) {
    final device = (event['device'] ?? 'fan').toString();
    final action = (event['action'] ?? '').toString();
    final reason = (event['reason'] ?? '').toString();
    String message;

    if (device == 'fan') {
      if (action == 'on') {
        message = reason == 'automation'
            ? 'Fan otomatik açıldı (CO₂ eşiği aşıldı)'
            : 'Fan manuel açıldı';
      } else if (action == 'off') {
        message = reason == 'automation'
            ? 'Fan otomatik kapandı'
            : 'Fan manuel kapandı';
      } else {
        message = 'Fan otomatik moda alındı';
      }
    } else if (device == 'heater') {
      if (action == 'on') {
        message = reason == 'automation'
            ? 'Isıtıcı otomatik açıldı (Sıcaklık eşiği altında)'
            : 'Isıtıcı manuel açıldı';
      } else if (action == 'off') {
        message = reason == 'automation'
            ? 'Isıtıcı otomatik kapandı'
            : 'Isıtıcı manuel kapandı';
      } else {
        message = 'Isıtıcı otomatik moda alındı';
      }
    } else if (device == 'humidifier') {
      if (action == 'on') {
        message = reason == 'automation'
            ? 'Nemlendirici otomatik açıldı (Nem eşiği altında)'
            : 'Nemlendirici manuel açıldı';
      } else if (action == 'off') {
        message = reason == 'automation'
            ? 'Nemlendirici otomatik kapandı'
            : 'Nemlendirici manuel kapandı';
      } else {
        message = 'Nemlendirici otomatik moda alındı';
      }
    } else {
      // Bilinmeyen device için genel mesaj
      if (action == 'on') {
        message = reason == 'automation'
            ? '$device otomatik açıldı'
            : '$device manuel açıldı';
      } else if (action == 'off') {
        message = reason == 'automation'
            ? '$device otomatik kapandı'
            : '$device manuel kapandı';
      } else {
        message = '$device otomatik moda alındı';
      }
    }

    return {
      'id': 'actuator_${event['id']}',
      'level': 'info',
      'source': 'actuator',
      'message': message,
      'ts': event['ts'],
    };
  }

  Map<String, dynamic> _localizeAlert(Map<String, dynamic> raw) {
    final message = (raw['message'] ?? '').toString();
    String localized = message;
    final lower = message.toLowerCase();

    if (lower.contains('humidity out of range')) {
      final match = RegExp(r'([0-9]+(?:\.[0-9]+)?)').firstMatch(message);
      final value = match != null ? match.group(1) : null;
      localized = value != null ? 'Nem eşiği dışında: ${double.parse(value).toStringAsFixed(1)}%' : 'Nem eşiği dışında';
    } else if (lower.contains('temp out of range')) {
      final match = RegExp(r'([0-9]+(?:\.[0-9]+)?)').firstMatch(message);
      final value = match != null ? match.group(1) : null;
      localized = value != null ? 'Sıcaklık eşiği dışında: ${double.parse(value).toStringAsFixed(1)}°C' : 'Sıcaklık eşiği dışında';
    } else if (lower.contains('co2 out of range')) {
      final match = RegExp(r'([0-9]+(?:\.[0-9]+)?)').firstMatch(message);
      final value = match != null ? match.group(1) : null;
      localized = value != null ? 'CO₂ eşiği dışında: ${double.parse(value).toStringAsFixed(0)} ppm' : 'CO₂ eşiği dışında';
    } else if (lower.contains('fan auto-off')) {
      localized = 'Fan otomatik kapandı (normal değerler)';
    } else if (lower.contains('heater auto-off')) {
      localized = 'Isıtıcı otomatik kapandı (normal değerler)';
    } else if (lower.contains('humidifier auto-off')) {
      localized = 'Nemlendirici otomatik kapandı (normal değerler)';
    }

    return {
      ...raw,
      'level': raw['level'] ?? 'info',
      'message': localized,
      'ts': raw['ts'] ?? DateTime.now().toIso8601String(),
    };
  }

  void _startQuickRefresh() {
    _quickRefreshTimer?.cancel();
    _quickRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (loading) return;
      try {
        final latestFuture = api.getLatest();
        final actuatorsFuture = api.getActuators();
        final alertsFuture = _buildAlerts();

        final newLatest = await latestFuture;
        final newActuators = await actuatorsFuture;
        final newAlerts = await alertsFuture;

        bool changed = false;
        if (latest == null ||
            latest!.temp != newLatest.temp ||
            latest!.humidity != newLatest.humidity ||
            latest!.co2 != newLatest.co2) {
          changed = true;
        }

        for (final device in ['fan', 'heater', 'humidifier']) {
          final current = actuators[device] ?? const <String, dynamic>{};
          final updated = newActuators[device] ?? const <String, dynamic>{};
          if (current['mode'] != updated['mode'] || current['state'] != updated['state']) {
            changed = true;
            break;
          }
        }

        if (!changed) {
          if (alerts.length != newAlerts.length) {
            changed = true;
          } else {
            for (var i = 0; i < alerts.length; i++) {
              if (alerts[i]['id'] != newAlerts[i]['id'] || alerts[i]['ts'] != newAlerts[i]['ts']) {
                changed = true;
                break;
              }
            }
          }
        }

        if (changed) {
          latest = newLatest;
          actuators = newActuators;
          alerts = newAlerts;
          notifyListeners();
        }
      } catch (e) {
        debugPrint('Quick refresh error: $e');
      }
    });
  }

  // Bitki eşik aralıklarını kontrol et ve bildirim gönder
  Future<void> _checkPlantThresholds(LatestReadings readings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final plantsJson = prefs.getString('saved_plants') ?? '[]';
      final plants = List<Map<String, dynamic>>.from(
        jsonDecode(plantsJson) as List,
      );

      final now = DateTime.now();
      const notificationCooldown = Duration(minutes: 5); // 5 dakika içinde aynı bildirimi tekrar gönderme

      for (final plant in plants) {
        final plantId = plant['id']?.toString() ?? '';
        final plantName = plant['name']?.toString() ?? plant['plantType']?.toString() ?? 'Bilinmeyen Bitki';
        // Bitki türünü plantType veya originalPlantType'dan al (species değil)
        final plantType = plant['plantType']?.toString() ?? plant['originalPlantType']?.toString() ?? 'Unknown';

        if (plantId.isEmpty) continue;

        final thresholds = PlantThresholds.forPlantType(plantType);

        // Sıcaklık kontrolü
        if (thresholds.isTempOutOfRange(readings.temp)) {
          final key = '${plantId}_temp';
          final lastTime = _lastNotificationTime[key];
          if (lastTime == null || now.difference(lastTime) > notificationCooldown) {
            await _notificationService.sendThresholdAlertNotification(
              plantName: plantName,
              sensorType: 'temp',
              value: readings.temp,
              unit: '°C',
            );
            _lastNotificationTime[key] = now;
          }
        }

        // Nem kontrolü
        if (thresholds.isHumidityOutOfRange(readings.humidity)) {
          final key = '${plantId}_humidity';
          final lastTime = _lastNotificationTime[key];
          if (lastTime == null || now.difference(lastTime) > notificationCooldown) {
            await _notificationService.sendThresholdAlertNotification(
              plantName: plantName,
              sensorType: 'humidity',
              value: readings.humidity,
              unit: '%',
            );
            _lastNotificationTime[key] = now;
          }
        }

        // CO2 kontrolü
        if (thresholds.isCo2OutOfRange(readings.co2)) {
          final key = '${plantId}_co2';
          final lastTime = _lastNotificationTime[key];
          if (lastTime == null || now.difference(lastTime) > notificationCooldown) {
            await _notificationService.sendThresholdAlertNotification(
              plantName: plantName,
              sensorType: 'co2',
              value: readings.co2,
              unit: ' ppm',
            );
            _lastNotificationTime[key] = now;
          }
        }
      }
    } catch (e) {
      debugPrint('Bitki eşik kontrolü hatası: $e');
    }
  }
}
