import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';

class AuthState extends ChangeNotifier {
  final AuthService _authService = AuthService();
  bool _isAuthenticated = false;
  bool _isLoading = true;
  Map<String, dynamic>? _currentUser;

  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  Map<String, dynamic>? get currentUser => _currentUser;

  AuthState() {
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    _isLoading = true;
    notifyListeners();

    final isAuth = await _authService.isAuthenticated();
    if (isAuth) {
      final user = await _authService.verifyToken();
      if (user != null) {
        _isAuthenticated = true;
        _currentUser = await _authService.getCurrentUser();
      } else {
        _isAuthenticated = false;
        _currentUser = null;
      }
    } else {
      _isAuthenticated = false;
      _currentUser = null;
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> login(String username, String password) async {
    _isLoading = true;
    notifyListeners();

    final result = await _authService.login(
      username: username,
      password: password,
    );

    if (result['success'] == true) {
      _isAuthenticated = true;
      _currentUser = await _authService.getCurrentUser();
      _isLoading = false;
      notifyListeners();
      return true;
    } else {
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register({
    required String email,
    required String username,
    required String password,
    String? fullName,
  }) async {
    _isLoading = true;
    notifyListeners();

    final result = await _authService.register(
      email: email,
      username: username,
      password: password,
      fullName: fullName,
    );

    if (result['success'] == true) {
      _isAuthenticated = true;
      _currentUser = await _authService.getCurrentUser();
      _isLoading = false;
      notifyListeners();
      return true;
    } else {
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await _authService.logout();
    _isAuthenticated = false;
    _currentUser = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    await _checkAuthStatus();
  }
}

