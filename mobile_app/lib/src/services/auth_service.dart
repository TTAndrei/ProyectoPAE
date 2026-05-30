import '../models/app_user.dart';
import 'api_client.dart';
import 'auth_store.dart';

/// Wraps authentication-related API calls and local session persistence.
class AuthService {
  AuthService({
    required ApiClient apiClient,
    required AuthStore authStore,
  })  : _apiClient = apiClient,
        _authStore = authStore;

  final ApiClient _apiClient;
  final AuthStore _authStore;

  /// Attempts to restore a previously saved session.
  /// Returns the [AuthSession] if valid, or `null` if none / expired.
  Future<AuthSession?> restoreSession() async {
    final stored = await _authStore.readSession();
    if (stored == null) return null;

    try {
      final freshUser = await _apiClient.getCurrentUser(token: stored.token);
      final updated = AuthSession(token: stored.token, user: freshUser);
      await _authStore.saveSession(updated);
      return updated;
    } catch (_) {
      await _authStore.clearSession();
      return null;
    }
  }

  /// Logs in with credentials. Returns the [AuthSession] on success.
  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    final session = await _apiClient.login(
      username: username,
      password: password,
    );
    await _authStore.saveSession(session);
    return session;
  }

  /// Clears the persisted session.
  Future<void> logout() async {
    await _authStore.clearSession();
  }

  /// Updates user profile details and updates the local storage/session.
  Future<AppUser> updateProfile({
    required String token,
    String? name,
    String? username,
    String? password,
  }) async {
    final updatedUser = await _apiClient.updateProfile(
      token: token,
      name: name,
      username: username,
      password: password,
    );
    final stored = await _authStore.readSession();
    if (stored != null) {
      final newSession = AuthSession(token: stored.token, user: updatedUser);
      await _authStore.saveSession(newSession);
    }
    return updatedUser;
  }
}
