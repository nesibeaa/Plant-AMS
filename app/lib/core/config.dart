import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static const _keyBaseUrl = 'base_url';
  static const _keyGroqApiKey = 'groq_api_key';
  static String _baseUrl = 'http://127.0.0.1:8000'; // Ayarlar'dan değişir
  static String _groqApiKey = ''; // .env'den veya SharedPreferences'tan yüklenecek

  static String get baseUrl => _baseUrl;
  static String get groqApiKey => _groqApiKey;

  static Future<void> load() async {
    // Önce .env dosyasını yükle (eğer varsa)
    try {
      await dotenv.load(fileName: ".env");
      // .env'den API key'i oku
      final envKey = dotenv.env['GROQ_API_KEY'];
      if (envKey != null && envKey.isNotEmpty) {
        _groqApiKey = envKey;
      }
    } catch (e) {
      // .env dosyası yoksa veya yüklenemezse devam et
    }
    
    // SharedPreferences'tan oku (kullanıcı ayarlardan değiştirmişse)
    final p = await SharedPreferences.getInstance();
    _baseUrl = p.getString(_keyBaseUrl) ?? _baseUrl;
    final savedKey = p.getString(_keyGroqApiKey);
    // SharedPreferences'ta varsa onu kullan (kullanıcı ayarlardan değiştirmişse)
    if (savedKey != null && savedKey.isNotEmpty) {
      _groqApiKey = savedKey;
    }
    
    // Eğer hala boşsa, default değer kullan (fallback)
    if (_groqApiKey.isEmpty) {
      _groqApiKey = 'BURAYA_API_KEY_INIZI_YAZIN'; // .env dosyasına eklenmesi gereken
    }
  }

  static Future<void> setBaseUrl(String url) async {
    _baseUrl = url;
    final p = await SharedPreferences.getInstance();
    await p.setString(_keyBaseUrl, url);
  }

  static Future<void> setGroqApiKey(String key) async {
    _groqApiKey = key;
    final p = await SharedPreferences.getInstance();
    await p.setString(_keyGroqApiKey, key);
  }
}
