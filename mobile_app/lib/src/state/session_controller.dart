import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../services/auth_service.dart';

/// Manages the user session: login, logout, session restore.
/// This replaces the old SessionController.
class SessionController extends ChangeNotifier {
  SessionController({
    required AuthService authService,
  }) : _authService = authService;

  final AuthService _authService;

  bool _isInitializing = true;
  bool _isLoading = false;
  String? _errorMessage;
  String? _token;
  AppUser? _user;

  bool get isInitializing => _isInitializing;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _token != null && _user != null;
  String? get errorMessage => _errorMessage;
  String? get token => _token;
  AppUser? get user => _user;

  Future<void> restoreSession() async {
    _isInitializing = true;
    _errorMessage = null;
    notifyListeners();

    final session = await _authService.restoreSession();
    if (session != null) {
      _token = session.token;
      _user = session.user;
    } else {
      _token = null;
      _user = null;
    }

    _isInitializing = false;
    notifyListeners();
  }

  Future<bool> login({
    required String username,
    required String password,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final session = await _authService.login(
        username: username,
        password: password,
      );
      _token = session.token;
      _user = session.user;
      return true;
    } catch (error) {
      _errorMessage = error.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _token = null;
    _user = null;
    _errorMessage = null;
    notifyListeners();
    await _authService.logout();
  }
}
