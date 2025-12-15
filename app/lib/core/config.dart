import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  static const _keyBaseUrl = 'base_url';
  static String _baseUrl = 'http://127.0.0.1:8000'; // Ayarlar’dan değişir

  static String get baseUrl => _baseUrl;

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _baseUrl = p.getString(_keyBaseUrl) ?? _baseUrl;
  }

  static Future<void> setBaseUrl(String url) async {
    _baseUrl = url;
    final p = await SharedPreferences.getInstance();
    await p.setString(_keyBaseUrl, url);
  }
}
