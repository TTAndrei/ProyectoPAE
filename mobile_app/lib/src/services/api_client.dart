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
        .map((raw) =>
            DriverModel.fromJson(Map<String, dynamic>.from(raw as Map)))
        .toList();
  }

  Future<DriverLocation?> getDriverLocation({
    required String token,
    required String driverId,
  }) async {
    final response = await _httpClient.get(
      _buildUri('/drivers/${Uri.encodeComponent(driverId)}/location'),
      headers: _headers(token: token),
    );

    if (response.statusCode == 404) {
      return null;
    }

    _ensureSuccess(response);
    final decoded = _decodeBody(response);
    if (decoded is! Map) {
      throw const ApiException('Invalid driver location response format');
    }

    return DriverLocation.fromJson(Map<String, dynamic>.from(decoded));
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
        .map(
            (raw) => OrderModel.fromJson(Map<String, dynamic>.from(raw as Map)))
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

  Future<List<GeocodeCandidate>> geocodeAddressCandidates({
    required String address,
    int maxResults = 5,
  }) async {
    final limit = maxResults.clamp(1, 10);
    final uri = Uri.https(
      'nominatim.openstreetmap.org',
      '/search',
      {
        'q': address,
        'format': 'jsonv2',
        'limit': '$limit',
      },
    );

    final response = await _httpClient.get(
      uri,
      headers: const {
        'Accept': 'application/json',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        'No se pudo geocodificar la direccion',
        statusCode: response.statusCode,
      );
    }

    final decoded = _decodeBody(response);
    if (decoded is! List || decoded.isEmpty) {
      throw const ApiException('No se encontro la direccion indicada');
    }

    final candidates = decoded
        .whereType<Map>()
        .map((raw) {
          final lat = double.tryParse(raw['lat']?.toString() ?? '');
          final lng = double.tryParse(raw['lon']?.toString() ?? '');
          if (lat == null || lng == null) {
            return null;
          }

          final displayName = raw['display_name']?.toString().trim() ?? '';
          return GeocodeCandidate(
            lat: lat,
            lng: lng,
            label: displayName.isEmpty
                ? '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}'
                : displayName,
          );
        })
        .whereType<GeocodeCandidate>()
        .toList();

    if (candidates.isEmpty) {
      throw const ApiException('Coordenadas de geocodificacion invalidas');
    }

    return candidates;
  }

  Future<({double lat, double lng})> geocodeAddress({
    required String address,
  }) async {
    final candidates = await geocodeAddressCandidates(
      address: address,
      maxResults: 1,
    );
    final selected = candidates.first;
    return (lat: selected.lat, lng: selected.lng);
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

  Future<RespondOrderResult> respondOrder({
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
    return RespondOrderResult.fromJson(Map<String, dynamic>.from(decoded));
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

  Future<DriverRoutePlan> getRoutePlan({
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

    return DriverRoutePlan.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<List<OrderModel>> getRouteOrders({
    required String token,
    required String driverId,
  }) async {
    final plan = await getRoutePlan(token: token, driverId: driverId);
    return plan.orders;
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

class GeocodeCandidate {
  const GeocodeCandidate({
    required this.lat,
    required this.lng,
    required this.label,
  });

  final double lat;
  final double lng;
  final String label;
}
