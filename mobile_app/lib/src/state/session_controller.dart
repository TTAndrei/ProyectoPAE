import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../services/api_client.dart';
import '../services/auth_store.dart';

class SessionController extends ChangeNotifier {
  SessionController({
    required ApiClient apiClient,
    required AuthStore authStore,
  })  : _apiClient = apiClient,
        _authStore = authStore;

  final ApiClient _apiClient;
  final AuthStore _authStore;

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

    final storedSession = await _authStore.readSession();
    if (storedSession == null) {
      _token = null;
      _user = null;
      _isInitializing = false;
      notifyListeners();
      return;
    }

    _token = storedSession.token;
    _user = storedSession.user;

    try {
      final currentUser = await _apiClient.getCurrentUser(token: storedSession.token);
      _user = currentUser;
      await _authStore.saveSession(
        AuthSession(token: storedSession.token, user: currentUser),
      );
    } catch (_) {
      _token = null;
      _user = null;
      await _authStore.clearSession();
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
      final session = await _apiClient.login(username: username, password: password);
      _token = session.token;
      _user = session.user;
      await _authStore.saveSession(session);
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
    await _authStore.clearSession();
  }
}
