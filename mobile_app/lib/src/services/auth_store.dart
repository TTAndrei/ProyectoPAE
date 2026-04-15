import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_user.dart';

class AuthStore {
  static const _tokenKey = 'auth_token';
  static const _userKey = 'auth_user';

  Future<void> saveSession(AuthSession session) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_tokenKey, session.token);
    await preferences.setString(_userKey, jsonEncode(session.user.toJson()));
  }

  Future<AuthSession?> readSession() async {
    final preferences = await SharedPreferences.getInstance();
    final token = preferences.getString(_tokenKey);
    final rawUser = preferences.getString(_userKey);
    if (token == null || rawUser == null) {
      return null;
    }

    try {
      final decoded = jsonDecode(rawUser);
      if (decoded is! Map) {
        return null;
      }
      final user = AppUser.fromJson(Map<String, dynamic>.from(decoded));
      return AuthSession(token: token, user: user);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearSession() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_tokenKey);
    await preferences.remove(_userKey);
  }
}
