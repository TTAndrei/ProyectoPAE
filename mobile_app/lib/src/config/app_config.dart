import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static const _apiBaseUrlFromEnvironment = String.fromEnvironment('API_BASE_URL');

  static String get apiBaseUrl {
    if (_apiBaseUrlFromEnvironment.trim().isNotEmpty) {
      return _apiBaseUrlFromEnvironment;
    }

    final apiBaseUrlFromDotenv = dotenv.env['API_BASE_URL']?.trim();
    if (apiBaseUrlFromDotenv != null && apiBaseUrlFromDotenv.isNotEmpty) {
      return apiBaseUrlFromDotenv;
    }

    return 'http://localhost:8000';
  }
}
