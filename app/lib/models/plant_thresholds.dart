/// Bitki türlerine özel optimal sensör aralıkları
class PlantThresholds {
  final String plantType;
  final double tempMin;
  final double tempMax;
  final double humidityMin;
  final double humidityMax;
  final double co2Min;
  final double co2Max;

  const PlantThresholds({
    required this.plantType,
    required this.tempMin,
    required this.tempMax,
    required this.humidityMin,
    required this.humidityMax,
    required this.co2Min,
    required this.co2Max,
  });

  /// Bitki türüne göre optimal aralıkları döndürür
  /// Genel sera koşulları için makul aralıklar kullanılır
  /// Hem İngilizce hem Türkçe isimleri destekler
  static PlantThresholds forPlantType(String plantType) {
    // Bitki türünü normalize et (büyük/küçük harf duyarsız)
    var normalized = plantType.toLowerCase().trim();
    
    // Class name formatından bitki türünü çıkar (örn: "Strawberry_Healthy" -> "strawberry")
    if (normalized.contains('_')) {
      normalized = normalized.split('_')[0];
    }
    
    // Türkçe isimleri İngilizce'ye çevir
    final englishName = _turkishToEnglish(normalized);
    
    // Bitki türlerine göre özel aralıklar
    switch (englishName) {
      // Meyve ağaçları - biraz daha düşük nem, orta sıcaklık
      case 'apple':
        return const PlantThresholds(
          plantType: 'Apple',
          tempMin: 16.0,
          tempMax: 25.0,
          humidityMin: 50.0,
          humidityMax: 70.0,
          co2Min: 400.0,
          co2Max: 600.0,
        );
      case 'blueberry':
        return const PlantThresholds(
          plantType: 'Blueberry',
          tempMin: 15.0,
          tempMax: 25.0,
          humidityMin: 60.0,
          humidityMax: 80.0,
          co2Min: 400.0,
          co2Max: 600.0,
        );
      case 'cherry':
      case 'sour cherry':
        return const PlantThresholds(
          plantType: 'Cherry',
          tempMin: 16.0,
          tempMax: 25.0,
          humidityMin: 45.0,
          humidityMax: 70.0,
          co2Min: 400.0,
          co2Max: 1000.0,
        );
      case 'orange':
        return const PlantThresholds(
          plantType: 'Orange',
          tempMin: 15.0,
          tempMax: 30.0,
          humidityMin: 50.0,
          humidityMax: 70.0,
          co2Min: 400.0,
          co2Max: 600.0,
        );
      case 'peach':
        return const PlantThresholds(
          plantType: 'Peach',
          tempMin: 17.0,
          tempMax: 26.0,
          humidityMin: 45.0,
          humidityMax: 70.0,
          co2Min: 400.0,
          co2Max: 1000.0,
        );
      case 'grape':
        return const PlantThresholds(
          plantType: 'Grape',
          tempMin: 15.0,
          tempMax: 30.0,
          humidityMin: 50.0,
          humidityMax: 70.0,
          co2Min: 400.0,
          co2Max: 600.0,
        );
      case 'raspberry':
        return const PlantThresholds(
          plantType: 'Raspberry',
          tempMin: 15.0,
          tempMax: 25.0,
          humidityMin: 60.0,
          humidityMax: 80.0,
          co2Min: 400.0,
          co2Max: 600.0,
        );
      case 'strawberry':
        return const PlantThresholds(
          plantType: 'Strawberry',
          tempMin: 15.0,
          tempMax: 25.0,
          humidityMin: 60.0,
          humidityMax: 80.0,
          co2Min: 400.0,
          co2Max: 800.0,
        );
      
      // Sebzeler - genelde daha yüksek nem ve sıcaklık
      case 'tomato':
        return const PlantThresholds(
          plantType: 'Tomato',
          tempMin: 18.0,
          tempMax: 25.0,
          humidityMin: 60.0,
          humidityMax: 80.0,
          co2Min: 400.0,
          co2Max: 800.0,
        );
      case 'pepper':
      case 'bell pepper':
      case 'pepper, bell':
        return const PlantThresholds(
          plantType: 'Pepper, bell',
          tempMin: 20.0,
          tempMax: 30.0,
          humidityMin: 60.0,
          humidityMax: 80.0,
          co2Min: 400.0,
          co2Max: 800.0,
        );
      case 'potato':
        return const PlantThresholds(
          plantType: 'Potato',
          tempMin: 15.0,
          tempMax: 20.0,
          humidityMin: 60.0,
          humidityMax: 80.0,
          co2Min: 400.0,
          co2Max: 800.0,
        );
      case 'corn':
      case 'maize':
        return const PlantThresholds(
          plantType: 'Corn (maize)',
          tempMin: 15.0,
          tempMax: 30.0,
          humidityMin: 50.0,
          humidityMax: 70.0,
          co2Min: 400.0,
          co2Max: 1000.0,
        );
      case 'squash':
        return const PlantThresholds(
          plantType: 'Squash',
          tempMin: 18.0,
          tempMax: 25.0,
          humidityMin: 60.0,
          humidityMax: 80.0,
          co2Min: 400.0,
          co2Max: 800.0,
        );
      case 'soybean':
        return const PlantThresholds(
          plantType: 'Soybean',
          tempMin: 18.0,
          tempMax: 28.0,
          humidityMin: 50.0,
          humidityMax: 75.0,
          co2Min: 400.0,
          co2Max: 1000.0,
        );
      
      // Bilinmeyen bitki türü için varsayılan aralıklar
      default:
        return const PlantThresholds(
          plantType: 'Unknown',
          tempMin: 18.0,
          tempMax: 26.0,
          humidityMin: 50.0,
          humidityMax: 70.0,
          co2Min: 400.0,
          co2Max: 1000.0,
        );
    }
  }

  /// Türkçe bitki isimlerini İngilizce'ye çevir
  static String _turkishToEnglish(String turkishName) {
    const translations = {
      // Türkçe -> İngilizce
      'elma': 'apple',
      'yaban mersini': 'blueberry',
      'kiraz': 'cherry',
      'mısır': 'corn',
      'üzüm': 'grape',
      'portakal': 'orange',
      'şeftali': 'peach',
      'biber': 'pepper',
      'patates': 'potato',
      'ahududu': 'raspberry',
      'soya': 'soybean',
      'kabak': 'squash',
      'çilek': 'strawberry',
      'domates': 'tomato',
    };
    
    // Direkt eşleşme varsa döndür
    if (translations.containsKey(turkishName)) {
      return translations[turkishName]!;
    }
    
    // Kısmi eşleşme için kontrol et (örn: "çilek1" -> "çilek")
    // Önce en uzun eşleşmeyi bul
    String? bestMatch;
    int bestLength = 0;
    for (final entry in translations.entries) {
      if (turkishName.contains(entry.key) && entry.key.length > bestLength) {
        bestMatch = entry.value;
        bestLength = entry.key.length;
      }
    }
    if (bestMatch != null) {
      return bestMatch;
    }
    
    // Eşleşme yoksa orijinal değeri döndür (İngilizce olabilir)
    return turkishName;
  }

  /// Sıcaklık değeri aralık dışında mı?
  bool isTempOutOfRange(double temp) {
    return temp < tempMin || temp > tempMax;
  }

  /// Nem değeri aralık dışında mı?
  bool isHumidityOutOfRange(double humidity) {
    return humidity < humidityMin || humidity > humidityMax;
  }

  /// CO2 değeri aralık dışında mı?
  bool isCo2OutOfRange(double co2) {
    return co2 < co2Min || co2 > co2Max;
  }

  /// Hangi sensörler aralık dışında?
  List<String> getOutOfRangeSensors(double temp, double humidity, double co2) {
    final outOfRange = <String>[];
    if (isTempOutOfRange(temp)) outOfRange.add('temp');
    if (isHumidityOutOfRange(humidity)) outOfRange.add('humidity');
    if (isCo2OutOfRange(co2)) outOfRange.add('co2');
    return outOfRange;
  }
}

