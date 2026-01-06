class SensorPoint {
  final DateTime time;
  final double value;
  SensorPoint({required this.time, required this.value});
  factory SensorPoint.fromJson(Map<String,dynamic> j) {
    // Backend formatı: {"bucket": "...", "count": ..., "min": ..., "max": ..., "avg": ...}
    // bucket string formatında (örn. "2025-11-03 11:00:00")
    try {
      final bucketStr = j['bucket'] as String? ?? '';
      final avgValue = j['avg'] as num?;
      
      if (bucketStr.isEmpty || avgValue == null) {
        // Null veya geçersiz veri - skip et, null döndür
        throw FormatException('Invalid data');
      }
      
      // Bucket formatını parse et - "2025-11-03 11:00:00" formatını handle et
      DateTime time;
      try {
        // Backend'den gelen bucket string'i parse et
        if (bucketStr.contains('T') && bucketStr.contains('Z')) {
          // ISO 8601 UTC formatı: "2026-01-02T01:00:00Z"
          final utcTime = DateTime.parse(bucketStr).toUtc();
          // UTC'den Türkiye saatine çevir (+3 saat)
          time = utcTime.add(const Duration(hours: 3));
        } else {
          // "2025-11-03 11:00:00" formatı - backend bu formatı kullanmıyor ama yine de handle et
          // Eğer bu format gelirse, UTC olduğunu varsayıp Türkiye saatine çevir
          try {
            final utcTime = DateTime.parse(bucketStr + 'Z').toUtc();
            time = utcTime.add(const Duration(hours: 3));
          } catch (_) {
            // Parse edilemezse normal parse dene
            time = DateTime.parse(bucketStr);
          }
        }
      } catch (e) {
        // Parse edilemezse şu anki zamanı kullan
        print('⚠️ SensorPoint.fromJson: Parse hatası: $e, bucket: $bucketStr');
        time = DateTime.now();
      }
      
      return SensorPoint(
        time: time,
        value: avgValue.toDouble()
      );
    } catch (e) {
      // Hata durumunda exception fırlat - liste filtrelenebilir
      rethrow;
    }
  }
}

class LatestReadings {
  final double temp, humidity, co2;
  LatestReadings({required this.temp, required this.humidity, required this.co2});
  factory LatestReadings.fromJson(Map<String,dynamic> j) => LatestReadings(
    temp: (j['temp'] as num).toDouble(),
    humidity: (j['humidity'] as num).toDouble(),
    co2: (j['co2'] as num).toDouble(),
  );
}
