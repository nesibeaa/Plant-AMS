import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:io' show Platform;

class AppConfig {
  static const _keyBaseUrl = 'base_url';
  static const _keyGroqApiKey = 'groq_api_key';
  
  
  static String get _defaultBaseUrl {
    if (Platform.isIOS) {
      
      return 'http://10.2.51.211:8000'; 
    } else {
      
      return 'http://127.0.0.1:8000';
    }
  }
  
  static String _baseUrl = ''; 
  static String _groqApiKey = ''; 

  static String get baseUrl => _baseUrl;
  static String get groqApiKey => _groqApiKey;

  static Future<void> load() async {
    
    try {
      await dotenv.load(fileName: ".env");
      
      final envKey = dotenv.env['GROQ_API_KEY'];
      if (envKey != null && envKey.isNotEmpty) {
        _groqApiKey = envKey;
      }
    } catch (e) {
      
    }
    
    
    final p = await SharedPreferences.getInstance();
    final savedUrl = p.getString(_keyBaseUrl);
    
    
    if (savedUrl != null && savedUrl.isNotEmpty) {
      _baseUrl = savedUrl; 
    } else {
      
      try {
        final envBaseUrl = dotenv.env['BASE_URL'];
        if (envBaseUrl != null && envBaseUrl.isNotEmpty) {
          _baseUrl = envBaseUrl; // .env'den
        } else {
          _baseUrl = _defaultBaseUrl; // Platform'a göre varsayılan
        }
      } catch (e) {
        _baseUrl = _defaultBaseUrl; // Platform'a göre varsayılan
      }
    }
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
