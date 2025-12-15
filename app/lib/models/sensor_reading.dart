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
        // "2025-11-03 11:00:00" formatını parse et (local time olarak)
        // Eğer UTC formatında geliyorsa parse edip local'e çevir
        if (bucketStr.contains('T') && bucketStr.contains('Z')) {
          // ISO 8601 UTC formatı
          time = DateTime.parse(bucketStr).toLocal();
        } else {
          // "2025-11-03 11:00:00" formatı - local time olarak varsay
          time = DateTime.parse(bucketStr);
          // Eğer UTC ise local'e çevir
          if (time.isUtc) {
            time = time.toLocal();
          }
        }
      } catch (e) {
        // Parse edilemezse şu anki zamanı kullan
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
