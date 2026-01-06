import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../core/config.dart';
import '../models/sensor_reading.dart';
import 'auth_service.dart';

const bool MOCK_MODE = false; // backend bağlayınca false yapacağız

class ApiService {
  final _client = http.Client();
  final _authService = AuthService();
  
  
  Map<String, String> get _headers => {
    'Connection': 'keep-alive',
    'Keep-Alive': 'timeout=5, max=1000',
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };
  
  
  Function()? onUnauthorized;

  Uri _u(String path, [Map<String,String>? q]) {
    final params = q ?? <String, String>{};
    
    params['_'] = DateTime.now().millisecondsSinceEpoch.toString();
    return Uri.parse('${AppConfig.baseUrl}$path').replace(queryParameters: params);
  }
  
  
  void _handleUnauthorized() {
    if (onUnauthorized != null) {
      onUnauthorized!();
    }
  }

  Future<LatestReadings> getLatest() async {
    if (MOCK_MODE) {
      return LatestReadings(temp: 22.7, humidity: 65.2, co2: 780);
    }
    try {
      final r = await _client.get(
        _u('/api/v1/latest'),
        headers: _headers,
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('Bağlantı zaman aşımına uğradı');
        },
      );
      if (r.statusCode != 200) throw Exception('getLatest ${r.statusCode}');
      return LatestReadings.fromJson(jsonDecode(r.body));
    } catch (e) {
      print('⚠️ getLatest hatası: $e');
      // Backend çalışmıyorsa mock data döndür
      return LatestReadings(temp: 22.7, humidity: 65.2, co2: 780);
    }
  }

  Future<Map<String, dynamic>> getWeather({String city = "Istanbul", String countryCode = "TR"}) async {
    try {
      final r = await _client.get(
        _u('/api/v1/weather', {'city': city, 'country_code': countryCode}),
        headers: _headers,
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('Bağlantı zaman aşımına uğradı');
        },
      );
      if (r.statusCode != 200) throw Exception('getWeather ${r.statusCode}');
      return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (e) {
      print('⚠️ getWeather hatası: $e');
      // Backend çalışmıyorsa boş map döndür
      return {};
    }
  }

  /// Tüm sensör okumalarını CSV export için al (limit yok)
  Future<List<Map<String, dynamic>>> getAllReadingsForExport({int limit = 10000}) async {
    if (MOCK_MODE) {
      return [];
    }
    try {
      final readingsR = await _client.get(
        _u('/api/v1/readings', {'limit': limit.toString()}),
        headers: _headers,
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Bağlantı zaman aşımına uğradı');
        },
      );
      if (readingsR.statusCode != 200) throw Exception('getAllReadings ${readingsR.statusCode}');
      final readingsData = jsonDecode(readingsR.body) as List;
      return readingsData.cast<Map<String, dynamic>>();
    } catch (e) {
      print('⚠️ getAllReadingsForExport hatası: $e');
      rethrow;
    }
  }

  Future<List<SensorPoint>> getSeries({
    required String sensor, String bucket='hourly', int hours=24, int days=7,
  }) async {
    if (MOCK_MODE) {
      // 24 saatlik sahte veri
      final now = DateTime.now();
      final rand = Random(sensor.hashCode);
      return List.generate(24, (i) {
        final t = now.subtract(Duration(hours: 23 - i));
        double v;
        if (sensor == 'temp') v = 20 + rand.nextDouble()*5;
        else if (sensor == 'humidity') v = 55 + rand.nextDouble()*20;
        else v = 600 + rand.nextDouble()*400;
        return SensorPoint(time: t, value: double.parse(v.toStringAsFixed(1)));
      });
    }
    
    // Son okumaları direkt al (daha fazla veri noktası için)
    // Önce son 100 okumayı al (cache-busting otomatik ekleniyor)
    try {
      final readingsR = await _client.get(
        _u('/api/v1/readings', {'limit': '100'}),
        headers: _headers,
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('Bağlantı zaman aşımına uğradı');
        },
      );
      if (readingsR.statusCode != 200) throw Exception('getReadings ${readingsR.statusCode}');
      final readingsData = jsonDecode(readingsR.body) as List;
    
    // İlgili sensör tipine göre filtrele
    final filtered = readingsData
        .where((r) => r['type'] == sensor)
        .map((r) {
          try {
            // UTC zamanı parse et ve Türkiye saatine (UTC+3) çevir
            final tsStr = r['ts'] as String;
            // ISO 8601 formatını parse et (UTC olarak)
            DateTime ts;
            if (tsStr.endsWith('Z')) {
              // UTC formatı: "2026-01-02T01:33:48.279875Z"
              ts = DateTime.parse(tsStr).toUtc();
            } else {
              // Z yoksa, UTC olduğunu varsay
              ts = DateTime.parse(tsStr + 'Z').toUtc();
            }
            // UTC'den Türkiye saatine çevir (+3 saat)
            final turkeyTime = ts.add(const Duration(hours: 3));
            return SensorPoint(time: turkeyTime, value: (r['value'] as num).toDouble());
          } catch (e) {
            print('⚠️ getSeries: Parse hatası: $e, ts: ${r['ts']}');
            return null;
          }
        })
        .whereType<SensorPoint>()
        .toList();
    
    // Zaman sırasına göre sırala (eski → yeni)
    filtered.sort((a, b) => a.time.compareTo(b.time));
    
      // Eğer yeterli veri yoksa, gruplandırılmış veriyi kullan
      if (filtered.length < 5) {
        final q = {
          'sensor': sensor, 'bucket': bucket,
          if (bucket=='hourly') 'hours':'$hours' else 'days':'$days',
        };
        final r = await _client.get(
          _u('/api/v1/stats/series', q),
          headers: _headers,
        ).timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            throw Exception('Bağlantı zaman aşımına uğradı');
          },
        );
        if (r.statusCode != 200) throw Exception('getSeries ${r.statusCode}');
        final data = jsonDecode(r.body) as List;
        final points = <SensorPoint>[];
        for (final item in data) {
          try {
            final point = SensorPoint.fromJson(item as Map<String, dynamic>);
            points.add(point);
          } catch (e) {
            print('Skipping invalid data point: $e');
          }
        }
        points.sort((a, b) => a.time.compareTo(b.time));
        return points;
      }
      
      return filtered;
    } catch (e) {
      print('⚠️ getSeries hatası: $e');
      // Backend çalışmıyorsa mock data döndür
      final now = DateTime.now();
      final rand = Random(sensor.hashCode);
      return List.generate(24, (i) {
        final t = now.subtract(Duration(hours: 23 - i));
        double v;
        if (sensor == 'temp') v = 20 + rand.nextDouble()*5;
        else if (sensor == 'humidity') v = 55 + rand.nextDouble()*20;
        else v = 600 + rand.nextDouble()*400;
        return SensorPoint(time: t, value: double.parse(v.toStringAsFixed(1)));
      });
    }
  }

  Future<void> setActuator({required String device, required String action}) async {
    if (MOCK_MODE) return; // şimdilik no-op
    try {
      final r = await _client.post(
        _u('/api/v1/control/$device'),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode({'action': action}),
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('Bağlantı zaman aşımına uğradı');
        },
      );
      if (r.statusCode != 200) throw Exception('setActuator ${r.statusCode}');
    } catch (e) {
      print('⚠️ setActuator hatası: $e');
      rethrow; // Bu metod için hata fırlatmaya devam et
    }
  }

  Future<Map<String, Map<String, dynamic>>> getActuators() async {
    if (MOCK_MODE) {
      return {
        'fan': {'mode': 'auto', 'state': 'off', 'last_change': null},
        'heater': {'mode': 'auto', 'state': 'off', 'last_change': null},
        'humidifier': {'mode': 'auto', 'state': 'off', 'last_change': null},
      };
    }
    try {
      final r = await _client.get(
        _u('/api/v1/actuators'),
        headers: _headers,
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('Bağlantı zaman aşımına uğradı');
        },
      );
      if (r.statusCode != 200) throw Exception('getActuators ${r.statusCode}');
      final raw = Map<String, dynamic>.from(jsonDecode(r.body) as Map);
      final result = <String, Map<String, dynamic>>{};
      raw.forEach((key, value) {
        result[key] = Map<String, dynamic>.from(value as Map);
      });
      return result;
    } catch (e) {
      print('⚠️ getActuators hatası: $e');
      // Backend çalışmıyorsa mock data döndür
      return {
        'fan': {'mode': 'auto', 'state': 'off', 'last_change': null},
        'heater': {'mode': 'auto', 'state': 'off', 'last_change': null},
        'humidifier': {'mode': 'auto', 'state': 'off', 'last_change': null},
      };
    }
  }

  Future<Map<String, dynamic>> getActuatorStatus(String device) async {
    if (MOCK_MODE) {
      return {'mode': 'auto', 'state': 'off', 'last_change': null};
    }
    try {
      final r = await _client.get(
        _u('/api/v1/actuator/$device'),
        headers: _headers,
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('Bağlantı zaman aşımına uğradı');
        },
      );
      if (r.statusCode != 200) throw Exception('getActuatorStatus ${r.statusCode}');
      return Map<String, dynamic>.from(jsonDecode(r.body) as Map);
    } catch (e) {
      print('⚠️ getActuatorStatus hatası: $e');
      // Backend çalışmıyorsa mock data döndür
      return {'mode': 'auto', 'state': 'off', 'last_change': null};
    }
  }

  Future<List<Map<String, dynamic>>> getAlerts({int limit = 20}) async {
    if (MOCK_MODE) return [];
    try {
      final r = await _client.get(
        _u('/api/v1/alerts', {'limit': limit.toString()}),
        headers: _headers,
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('Bağlantı zaman aşımına uğradı');
        },
      );
      if (r.statusCode != 200) throw Exception('getAlerts ${r.statusCode}');
      return List<Map<String, dynamic>>.from(jsonDecode(r.body));
    } catch (e) {
      print('⚠️ getAlerts hatası: $e');
      // Backend çalışmıyorsa boş liste döndür
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getActuatorHistory({int limit = 20}) async {
    if (MOCK_MODE) return [];
    try {
      // Tüm actuator'lar için genel endpoint kullan
      final r = await _client.get(
        _u('/api/v1/actuator/history', {'limit': limit.toString()}),
        headers: _headers,
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('Bağlantı zaman aşımına uğradı');
        },
      );
      if (r.statusCode != 200) throw Exception('getActuatorHistory ${r.statusCode}');
      return List<Map<String, dynamic>>.from(jsonDecode(r.body));
    } catch (e) {
      print('⚠️ getActuatorHistory hatası: $e');
      // Backend çalışmıyorsa boş liste döndür
      return [];
    }
  }

  Future<Map<String, dynamic>> analyzePlant({
    required Uint8List imageBytes,
    String model = 'auto',
  }) async {
    final token = await _authService.getToken();
    if (token == null) {
      throw Exception('Authentication required');
    }

    final uri = Uri.parse('${AppConfig.baseUrl}/api/v1/analyze-plant')
        .replace(queryParameters: {'model': model});
    
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(
      http.MultipartFile.fromBytes(
        'image',
        imageBytes,
        filename: 'plant.jpg',
      ),
    );

    try {
      final streamedResponse = await _client.send(request).timeout(
        const Duration(seconds: 30), // Analiz için daha uzun timeout
        onTimeout: () {
          throw Exception('Bağlantı zaman aşımına uğradı');
        },
      );
      final response = await http.Response.fromStream(streamedResponse);

      // Token geçersizse (401) otomatik logout
      if (response.statusCode == 401) {
        _handleUnauthorized();
        throw Exception('Oturum süreniz dolmuş. Lütfen tekrar giriş yapın.');
      }

      if (response.statusCode != 200) {
        final errorBody = response.body;
        throw Exception('Analyze plant failed: ${response.statusCode} - $errorBody');
      }

      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      print('⚠️ analyzePlant hatası: $e');
      rethrow; // Bu metod için hata fırlatmaya devam et
    }
  }
}
