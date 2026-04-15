import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/app_user.dart';
import '../models/driver_model.dart';
import '../models/order_model.dart';
import 'api_exception.dart';

class ApiClient {
  ApiClient({
    required this.baseUrl,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _httpClient;

  Uri _buildUri(String path) {
    final base = Uri.parse(baseUrl);
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    final combinedPath = '${basePath.isEmpty ? '' : basePath}$normalizedPath';

    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: combinedPath,
    );
  }

  Map<String, String> _headers({String? token}) {
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  dynamic _decodeBody(http.Response response) {
    if (response.bodyBytes.isEmpty) {
      return null;
    }
    final text = utf8.decode(response.bodyBytes);
    if (text.trim().isEmpty) {
      return null;
    }
    return jsonDecode(text);
  }

  String _extractErrorMessage(http.Response response) {
    try {
      final decoded = _decodeBody(response);
      if (decoded is Map && decoded['detail'] != null) {
        return decoded['detail'].toString();
      }
    } catch (_) {
      // Ignore parsing errors and fallback to generic text.
    }
    return 'Request failed';
  }

  void _ensureSuccess(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    throw ApiException(
      _extractErrorMessage(response),
      statusCode: response.statusCode,
    );
  }

  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    final response = await _httpClient.post(
      _buildUri('/auth/login'),
      headers: _headers(),
      body: jsonEncode({'username': username, 'password': password}),
    );
    _ensureSuccess(response);
    final decoded = _decodeBody(response);
    if (decoded is! Map) {
      throw const ApiException('Invalid login response format');
    }
    return AuthSession.fromLoginResponse(Map<String, dynamic>.from(decoded));
  }

  Future<AppUser> getCurrentUser({required String token}) async {
    final response = await _httpClient.get(
      _buildUri('/auth/me'),
      headers: _headers(token: token),
    );
    _ensureSuccess(response);
    final decoded = _decodeBody(response);
    if (decoded is! Map) {
      throw const ApiException('Invalid user response format');
    }
    return AppUser.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<List<DriverModel>> getDrivers({required String token}) async {
    final response = await _httpClient.get(
      _buildUri('/drivers/'),
      headers: _headers(token: token),
    );
    _ensureSuccess(response);
    final decoded = _decodeBody(response);
    if (decoded is! List) {
      throw const ApiException('Invalid drivers response format');
    }

    return decoded
        .map((raw) => DriverModel.fromJson(Map<String, dynamic>.from(raw as Map)))
        .toList();
  }

  Future<List<OrderModel>> getOrders({required String token}) async {
    final response = await _httpClient.get(
      _buildUri('/orders/'),
      headers: _headers(token: token),
    );
    _ensureSuccess(response);
    final decoded = _decodeBody(response);
    if (decoded is! List) {
      throw const ApiException('Invalid orders response format');
    }

    return decoded
        .map((raw) => OrderModel.fromJson(Map<String, dynamic>.from(raw as Map)))
        .toList();
  }

  Future<OrderModel> createOrder({
    required String token,
    required CreateOrderInput input,
  }) async {
    final response = await _httpClient.post(
      _buildUri('/orders/'),
      headers: _headers(token: token),
      body: jsonEncode(input.toJson()),
    );
    _ensureSuccess(response);
    final decoded = _decodeBody(response);
    if (decoded is! Map) {
      throw const ApiException('Invalid create order response format');
    }
    return OrderModel.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<AssignOrderResult> assignOrder({
    required String token,
    required String orderId,
    required String driverId,
  }) async {
    final response = await _httpClient.post(
      _buildUri('/orders/${Uri.encodeComponent(orderId)}/assign'),
      headers: _headers(token: token),
      body: jsonEncode({'driver_id': driverId}),
    );
    _ensureSuccess(response);
    final decoded = _decodeBody(response);
    if (decoded is! Map) {
      throw const ApiException('Invalid assign response format');
    }
    return AssignOrderResult.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<OrderModel> respondOrder({
    required String token,
    required String orderId,
    required bool accepted,
  }) async {
    final response = await _httpClient.post(
      _buildUri('/orders/${Uri.encodeComponent(orderId)}/respond'),
      headers: _headers(token: token),
      body: jsonEncode({'accepted': accepted}),
    );
    _ensureSuccess(response);
    final decoded = _decodeBody(response);
    if (decoded is! Map || decoded['order'] is! Map) {
      throw const ApiException('Invalid respond response format');
    }
    return OrderModel.fromJson(
      Map<String, dynamic>.from(decoded['order'] as Map),
    );
  }

  Future<OrderModel> updateOrderStatus({
    required String token,
    required String orderId,
    required String status,
  }) async {
    final response = await _httpClient.patch(
      _buildUri('/orders/${Uri.encodeComponent(orderId)}/status'),
      headers: _headers(token: token),
      body: jsonEncode({'status': status}),
    );
    _ensureSuccess(response);
    final decoded = _decodeBody(response);
    if (decoded is! Map || decoded['order'] is! Map) {
      throw const ApiException('Invalid update status response format');
    }
    return OrderModel.fromJson(
      Map<String, dynamic>.from(decoded['order'] as Map),
    );
  }

  Future<List<OrderModel>> getRouteOrders({
    required String token,
    required String driverId,
  }) async {
    final response = await _httpClient.get(
      _buildUri('/orders/route/${Uri.encodeComponent(driverId)}'),
      headers: _headers(token: token),
    );
    _ensureSuccess(response);
    final decoded = _decodeBody(response);
    if (decoded is! Map) {
      throw const ApiException('Invalid route response format');
    }

    final rawOrders = decoded['orders'];
    if (rawOrders is! List) {
      return const [];
    }

    return rawOrders
        .map((raw) => OrderModel.fromJson(Map<String, dynamic>.from(raw as Map)))
        .toList();
  }

  Future<void> updateDriverLocation({
    required String token,
    required String driverId,
    required double lat,
    required double lng,
    double heading = 0.0,
  }) async {
    final response = await _httpClient.put(
      _buildUri('/drivers/${Uri.encodeComponent(driverId)}/location'),
      headers: _headers(token: token),
      body: jsonEncode({'lat': lat, 'lng': lng, 'heading': heading}),
    );
    _ensureSuccess(response);
  }
}
