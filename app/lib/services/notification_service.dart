import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<bool> initialize() async {
    if (_initialized) return true;

    try {
      // Timezone'u başlat (idempotent - birden fazla kez çağrılabilir)
      tz.initializeTimeZones();
      try {
        tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));
      } catch (e) {
        // Eğer timezone bulunamazsa varsayılan kullan
        print('Timezone ayarlama hatası: $e');
      }

      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      // iOS'ta bildirim plugin'i initialize et
      // iOS'ta plugin bazen geç hazır olabilir, birkaç kez deneyelim
      for (int attempt = 0; attempt < 3; attempt++) {
        try {
          if (attempt > 0) {
            // İlk denemeden sonra bekle
            await Future.delayed(Duration(milliseconds: 200 * attempt));
          }
          
          final initialized = await _notifications.initialize(
            initSettings,
            onDidReceiveNotificationResponse: _onNotificationTapped,
          );

          if (initialized == true) {
            _initialized = true;
            print('✅ Bildirim servisi başarıyla başlatıldı (deneme ${attempt + 1})');
            return true;
          }
        } catch (initError) {
          print('⚠️ Bildirim initialize hatası (deneme ${attempt + 1}): $initError');
          if (attempt == 2) {
            // Son denemede başarısız olduysa, iOS simulator'da olabilir
            print('ℹ️ Bildirim servisi initialize edilemedi. Gerçek iOS cihazında test edin.');
            _initialized = true; // Ayarları kaydetmeye devam et
            return false;
          }
        }
      }
      
      _initialized = true;
      return false;
    } catch (e, stackTrace) {
      print('Bildirim servisi başlatma hatası: $e');
      print('Stack trace: $stackTrace');
      // Hata olsa bile ayarları kaydetmeye devam et
      _initialized = true;
      return false;
    }
  }


  void _onNotificationTapped(NotificationResponse response) {
    // Bildirim tıklandığında yapılacak işlemler
  }

  Future<bool> scheduleWateringNotification({
    required String plantId,
    required String plantName,
    required DateTime scheduledDate,
    required TimeOfDay reminderTime,
    required int repeatDays,
    String repeatUnit = 'days',
    int repeatValue = 13,
    String waterAmount = 'Orta',
    String howToWater = 'Topraktan',
  }) async {
    try {
      // Önce ayarları kaydet (bildirim servisi çalışmasa bile)
      await _saveNotificationSettings(plantId, 'watering', {
        'scheduledDate': scheduledDate.toIso8601String(),
        'reminderTime': '${reminderTime.hour}:${reminderTime.minute}',
        'repeatDays': repeatDays,
        'repeatUnit': repeatUnit,
        'repeatValue': repeatValue,
        'waterAmount': waterAmount,
        'howToWater': howToWater,
        'enabled': true,
      });

      // Bildirim servisini initialize etmeyi dene
      bool canScheduleNotifications = false;
      try {
        if (!_initialized) {
          final initResult = await initialize();
          canScheduleNotifications = initResult;
        } else {
          canScheduleNotifications = _initialized;
        }
      } catch (initError) {
        print('Bildirim servisi initialize edilemedi: $initError');
        canScheduleNotifications = false;
      }
      
      // Bildirimleri sadece servis çalışıyorsa planla
      if (canScheduleNotifications) {
        try {
          final scheduledDateTime = DateTime(
            scheduledDate.year,
            scheduledDate.month,
            scheduledDate.day,
            reminderTime.hour,
            reminderTime.minute,
          );

          final tzScheduledDate = tz.TZDateTime.from(scheduledDateTime, tz.local);

          const androidDetails = AndroidNotificationDetails(
            'watering_channel',
            'Sulama Bildirimleri',
            channelDescription: 'Bitki sulama hatırlatıcı bildirimleri',
            importance: Importance.high,
            priority: Priority.high,
            showWhen: true,
          );

          const iosDetails = DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          );

          const notificationDetails = NotificationDetails(
            android: androidDetails,
            iOS: iosDetails,
          );

          final notificationId = _getNotificationId(plantId, 'watering');

          // Önceki bildirimleri iptal et
          await _cancelPreviousNotifications(plantId, 'watering');

          // Tekrarlayan bildirimler için sadece bir bildirim planla (matchDateTimeComponents ile otomatik tekrarlanır)
          await _notifications.zonedSchedule(
            notificationId,
            '💧 $plantName için sulama zamanı',
            '$plantName bitkinizi sulamayı unutmayın!',
            tzScheduledDate,
            notificationDetails,
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
            matchDateTimeComponents: repeatDays > 0 
                ? DateTimeComponents.time 
                : DateTimeComponents.dateAndTime,
          );
          print('✅ Bildirimler başarıyla planlandı');
          
          // Planlanan bildirimleri kontrol et
          final pending = await _notifications.pendingNotificationRequests();
          print('📋 Toplam planlanan bildirim sayısı: ${pending.length}');
          final plantNotifications = pending.where((n) => 
            n.id >= notificationId && n.id <= notificationId + 10
          ).toList();
          print('📌 Bu bitki için planlanan bildirim sayısı: ${plantNotifications.length}');
          if (plantNotifications.isNotEmpty) {
            print('   İlk bildirim: ${plantNotifications.first.title} - ${plantNotifications.first.body}');
          }
        } catch (scheduleError) {
          print('❌ Bildirim planlama hatası: $scheduleError');
          // Ayarlar zaten kaydedildi, devam et
        }
      } else {
        print('⚠️ Bildirim servisi çalışmıyor, sadece ayarlar kaydedildi');
      }

      return true; // Ayarlar kaydedildi, başarılı
    } catch (e) {
      print('❌ Bildirim ayarlama hatası: $e');
      // Hata olsa bile ayarlar kaydedildi, true döndür
      return true;
    }
  }

  Future<bool> scheduleFertilizationNotification({
    required String plantId,
    required String plantName,
    required DateTime scheduledDate,
    required TimeOfDay reminderTime,
    required int repeatDays,
    String repeatUnit = 'days',
    int repeatValue = 13,
  }) async {
    try {
      // Önce ayarları kaydet (bildirim servisi çalışmasa bile)
      await _saveNotificationSettings(plantId, 'fertilization', {
        'scheduledDate': scheduledDate.toIso8601String(),
        'reminderTime': '${reminderTime.hour}:${reminderTime.minute}',
        'repeatDays': repeatDays,
        'repeatUnit': repeatUnit,
        'repeatValue': repeatValue,
        'enabled': true,
      });

      // Bildirim servisini initialize etmeyi dene
      bool canScheduleNotifications = false;
      try {
        if (!_initialized) {
          final initResult = await initialize();
          canScheduleNotifications = initResult;
        } else {
          canScheduleNotifications = _initialized;
        }
      } catch (initError) {
        print('Bildirim servisi initialize edilemedi: $initError');
        canScheduleNotifications = false;
      }
      
      // Bildirimleri sadece servis çalışıyorsa planla
      if (canScheduleNotifications) {
        try {
          final scheduledDateTime = DateTime(
            scheduledDate.year,
            scheduledDate.month,
            scheduledDate.day,
            reminderTime.hour,
            reminderTime.minute,
          );

          final tzScheduledDate = tz.TZDateTime.from(scheduledDateTime, tz.local);

          const androidDetails = AndroidNotificationDetails(
            'fertilization_channel',
            'Gübreleme Bildirimleri',
            channelDescription: 'Bitki gübreleme hatırlatıcı bildirimleri',
            importance: Importance.high,
            priority: Priority.high,
            showWhen: true,
          );

          const iosDetails = DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          );

          const notificationDetails = NotificationDetails(
            android: androidDetails,
            iOS: iosDetails,
          );

          final notificationId = _getNotificationId(plantId, 'fertilization');

          // Önceki bildirimleri iptal et
          await _cancelPreviousNotifications(plantId, 'fertilization');

          // Tekrarlayan bildirimler için sadece bir bildirim planla (matchDateTimeComponents ile otomatik tekrarlanır)
          await _notifications.zonedSchedule(
            notificationId,
            '🌱 $plantName için gübreleme zamanı',
            '$plantName bitkinizi gübrelemeyi unutmayın!',
            tzScheduledDate,
            notificationDetails,
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
            matchDateTimeComponents: repeatDays > 0 
                ? DateTimeComponents.time 
                : DateTimeComponents.dateAndTime,
          );
          print('Bildirimler başarıyla planlandı');
        } catch (scheduleError) {
          print('Bildirim planlama hatası: $scheduleError');
          // Ayarlar zaten kaydedildi, devam et
        }
      } else {
        print('Bildirim servisi çalışmıyor, sadece ayarlar kaydedildi');
      }

      return true; // Ayarlar kaydedildi, başarılı
    } catch (e) {
      print('Bildirim ayarlama hatası: $e');
      // Hata olsa bile ayarlar kaydedildi, true döndür
      return true;
    }
  }

  Future<Map<String, dynamic>?> getNotificationSettings(String plantId, String type) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'notification_${plantId}_$type';
      final jsonString = prefs.getString(key);
      if (jsonString == null) {
        print('ℹ️ Bildirim ayarları bulunamadı: $key');
        return null;
      }
      final settings = jsonDecode(jsonString) as Map<String, dynamic>;
      print('✅ Bildirim ayarları yüklendi: $key');
      print('   Ayarlar: $jsonString');
      return settings;
    } catch (e) {
      print('❌ Bildirim ayarları yüklenemedi: $e');
      return null;
    }
  }

  Future<void> _saveNotificationSettings(
    String plantId,
    String type,
    Map<String, dynamic> settings,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'notification_${plantId}_$type';
      final jsonString = jsonEncode(settings);
      await prefs.setString(key, jsonString);
      print('✅ Bildirim ayarları kaydedildi: $key');
      print('   Ayarlar: $jsonString');
    } catch (e) {
      print('❌ Bildirim ayarları kaydedilemedi: $e');
    }
  }

  int _getNotificationId(String plantId, String type) {
    final hash = plantId.hashCode + type.hashCode;
    return hash.abs() % 1000000;
  }

  // Önceki bildirimleri iptal et
  Future<void> _cancelPreviousNotifications(String plantId, String type) async {
    try {
      final notificationId = _getNotificationId(plantId, type);
      
      // Ana bildirimi iptal et
      await _notifications.cancel(notificationId);
      
      // Tekrarlanan bildirimleri de iptal et (1-10 arası)
      for (int i = 1; i <= 10; i++) {
        await _notifications.cancel(notificationId + i);
      }
      
      print('🗑️ Önceki bildirimler iptal edildi: $plantId - $type');
    } catch (e) {
      print('❌ Bildirim iptal etme hatası: $e');
    }
  }

  Future<void> cancelNotification(String plantId, String type) async {
    final notificationId = _getNotificationId(plantId, type);
    await _notifications.cancel(notificationId);
    
    // Tekrarlanan bildirimleri de iptal et
    for (int i = 1; i <= 10; i++) {
      await _notifications.cancel(notificationId + i);
    }

    // Ayarları temizle
    final prefs = await SharedPreferences.getInstance();
    final key = 'notification_${plantId}_$type';
    await prefs.remove(key);
  }

  // Bildirim izinlerini kontrol et
  Future<bool> checkPermissions() async {
    try {
      if (!_initialized) {
        await initialize();
      }
      
      // Android için izin kontrolü
      final androidInfo = await _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidInfo != null) {
        final granted = await androidInfo.requestNotificationsPermission();
        final isGranted = granted ?? false;
        print('📱 Android bildirim izni: ${isGranted ? "Verildi ✅" : "Reddedildi ❌"}');
        return isGranted;
      }
      
      // iOS için izin kontrolü
      final iosInfo = await _notifications.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (iosInfo != null) {
        final settings = await iosInfo.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        final granted = settings ?? false;
        print('📱 iOS bildirim izni: ${granted ? "Verildi ✅" : "Reddedildi ❌"}');
        return granted;
      }
      
      return false;
    } catch (e) {
      print('❌ Bildirim izni kontrolü hatası: $e');
      return false;
    }
  }

  // Planlanan bildirimleri listele (test için)
  Future<void> listPendingNotifications() async {
    try {
      if (!_initialized) {
        await initialize();
      }
      
      final pendingNotifications = await _notifications.pendingNotificationRequests();
      print('📋 Planlanan bildirim sayısı: ${pendingNotifications.length}');
      
      if (pendingNotifications.isEmpty) {
        print('⚠️ Planlanmış bildirim yok!');
      } else {
        for (var notification in pendingNotifications) {
          print('  📌 ID: ${notification.id}, Başlık: ${notification.title}, Tarih: ${notification.body}');
          if (notification.payload != null) {
            print('     Payload: ${notification.payload}');
          }
        }
      }
    } catch (e) {
      print('❌ Planlanan bildirimleri listeleme hatası: $e');
    }
  }

  // Test bildirimi gönder (hemen)
  Future<void> sendTestNotification() async {
    try {
      if (!_initialized) {
        await initialize();
      }
      
      const androidDetails = AndroidNotificationDetails(
        'watering_channel',
        'Sulama Bildirimleri',
        channelDescription: 'Bitki sulama hatırlatıcı bildirimleri',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notifications.show(
        999999,
        'Test Bildirimi',
        'Bildirimler çalışıyor! ✅',
        notificationDetails,
      );
      
      print('✅ Test bildirimi gönderildi!');
    } catch (e) {
      print('❌ Test bildirimi gönderme hatası: $e');
    }
  }

  // Bitki eşik aralığı dışında veri geldiğinde bildirim gönder
  Future<void> sendThresholdAlertNotification({
    required String plantName,
    required String sensorType,
    required double value,
    required String unit,
  }) async {
    try {
      if (!_initialized) {
        await initialize();
      }

      String title;
      String body;
      
      switch (sensorType) {
        case 'temp':
          title = '⚠️ Sıcaklık Uyarısı';
          body = '$plantName için sıcaklık değeri optimal aralığın dışında: ${value.toStringAsFixed(1)}$unit';
          break;
        case 'humidity':
          title = '⚠️ Nem Uyarısı';
          body = '$plantName için nem değeri optimal aralığın dışında: ${value.toStringAsFixed(0)}$unit';
          break;
        case 'co2':
          title = '⚠️ CO₂ Uyarısı';
          body = '$plantName için CO₂ değeri optimal aralığın dışında: ${value.toStringAsFixed(0)}$unit';
          break;
        default:
          title = '⚠️ Sensör Uyarısı';
          body = '$plantName için $sensorType değeri optimal aralığın dışında: ${value.toStringAsFixed(1)}$unit';
      }

      const androidDetails = AndroidNotificationDetails(
        'threshold_alerts_channel',
        'Eşik Uyarıları',
        channelDescription: 'Bitki eşik aralığı uyarı bildirimleri',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Bildirim ID'si: bitki adı + sensör tipi hash'i
      final notificationId = (plantName.hashCode + sensorType.hashCode).abs() % 1000000;

      await _notifications.show(
        notificationId,
        title,
        body,
        notificationDetails,
      );
      
      // Alert'i uygulama içi uyarılar sayfasına kaydet
      await _saveLocalAlert(
        level: 'warn',
        source: 'threshold',
        message: body,
      );
      
      print('✅ Eşik uyarı bildirimi gönderildi: $title - $body');
    } catch (e) {
      print('❌ Eşik uyarı bildirimi gönderme hatası: $e');
    }
  }

  // Local alert'i SharedPreferences'a kaydet
  Future<void> _saveLocalAlert({
    required String level,
    required String source,
    required String message,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alertsJson = prefs.getString('local_alerts') ?? '[]';
      final alerts = List<Map<String, dynamic>>.from(
        jsonDecode(alertsJson) as List,
      );
      
      // Yeni alert ekle
      final newAlert = {
        'id': 'local_${DateTime.now().millisecondsSinceEpoch}',
        'level': level,
        'source': source,
        'message': message,
        'ts': DateTime.now().toIso8601String(),
      };
      
      alerts.insert(0, newAlert);
      
      // En fazla 100 alert tut (eski alert'leri sil)
      if (alerts.length > 100) {
        alerts.removeRange(100, alerts.length);
      }
      
      await prefs.setString('local_alerts', jsonEncode(alerts));
      print('✅ Local alert kaydedildi: $message');
    } catch (e) {
      print('❌ Local alert kaydetme hatası: $e');
    }
  }
}

