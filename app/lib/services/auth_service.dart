import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/config.dart';

class AuthService {
  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'user_data';
  
  final _client = http.Client();

  Uri _u(String path) {
    return Uri.parse('${AppConfig.baseUrl}$path');
  }

  Future<Map<String, dynamic>> register({
    required String email,
    required String username,
    required String password,
    String? fullName,
  }) async {
    try {
      final response = await _client.post(
        _u('/api/v1/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'username': username,
          'password': password,
          if (fullName != null && fullName.isNotEmpty) 'full_name': fullName,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final token = (data['access_token'] as String).trim();
        await _saveToken(token);
        await _saveUser(data['user'] as Map<String, dynamic>);
        print('[AuthService] Register successful, token saved (length: ${token.length})');
        return {'success': true, 'data': data};
      } else {
        final error = jsonDecode(response.body);
        return {
          'success': false,
          'error': error['detail'] ?? 'Kayıt başarısız',
        };
      }
    } catch (e) {
      return {'success': false, 'error': 'Bağlantı hatası: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await _client.post(
        _u('/api/v1/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final token = (data['access_token'] as String).trim();
        await _saveToken(token);
        await _saveUser(data['user'] as Map<String, dynamic>);
        print('[AuthService] Login successful, token saved (length: ${token.length})');
        return {'success': true, 'data': data};
      } else {
        final error = jsonDecode(response.body);
        return {
          'success': false,
          'error': error['detail'] ?? 'Giriş başarısız',
        };
      }
    } catch (e) {
      return {'success': false, 'error': 'Bağlantı hatası: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(_userKey);
    if (userJson != null) {
      return jsonDecode(userJson) as Map<String, dynamic>;
    }
    return null;
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  Future<void> _saveUser(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user));
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }

  Future<bool> isAuthenticated() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  Future<Map<String, dynamic>?> verifyToken() async {
    final token = await getToken();
    if (token == null) return null;

    try {
      // Token'ı temizle (başında/sonunda boşluk varsa)
      final cleanToken = token.trim();
      
      final response = await _client.get(
        _u('/api/v1/auth/me'),
        headers: {
          'Authorization': 'Bearer $cleanToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        // Token geçersiz, logout yap
        print('[AuthService] Token verification failed: ${response.statusCode} - ${response.body}');
        await logout();
        return null;
      }
    } catch (e) {
      print('[AuthService] Token verification error: $e');
      return null;
    }
  }
}

