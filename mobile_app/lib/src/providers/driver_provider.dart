import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/app_user.dart';
import '../models/driver_model.dart';
import '../models/order_model.dart';
import '../services/driver_service.dart';
import '../services/route_service.dart';
import '../services/ws_service.dart';

/// Manages driver-specific state: location tracking, route plans,
/// and real-time WebSocket updates.
class DriverProvider extends ChangeNotifier {
  DriverProvider({
    required DriverService driverService,
    required RouteService routeService,
    required String token,
    required String apiBaseUrl,
    required AppUser user,
  })  : _driverService = driverService,
        _routeService = routeService,
        _token = token,
        _apiBaseUrl = apiBaseUrl,
        _user = user {
    _loadData();
    _connectWs();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _loadData(showLoader: false),
    );
  }

  final DriverService _driverService;
  final RouteService _routeService;
  final String _token;
  final String _apiBaseUrl;
  final AppUser _user;
  final WsService _wsService = WsService();

  Timer? _refreshTimer;
  bool _isLoading = false;
  String? _error;

  List<DriverModel> _drivers = const [];
  DriverLocation? _driverLocation;
  DriverRoutePlan? _routePlan;
  List<OrderModel> _routeOrders = const [];
  final List<String> _events = <String>[];

  // ── Getters ──────────────────────────────────────────────────────
  bool get isLoading => _isLoading;
  String? get error => _error;
  List<DriverModel> get drivers => _drivers;
  DriverLocation? get driverLocation => _driverLocation;
  DriverRoutePlan? get routePlan => _routePlan;
  List<OrderModel> get routeOrders => _routeOrders;
  List<String> get events => _events;
  AppUser get user => _user;

  // ── Lifecycle ────────────────────────────────────────────────────
  @override
  void dispose() {
    _refreshTimer?.cancel();
    _wsService.disconnect();
    super.dispose();
  }

  // ── WebSocket ────────────────────────────────────────────────────
  void _connectWs() {
    _wsService.connect(
      apiBaseUrl: _apiBaseUrl,
      token: _token,
      onMessage: (payload) {
        final type = payload['type']?.toString() ?? 'event';
        _pushEvent('WS: $type');

        if (type == 'pickup:notification' ||
            type == 'driver:location:update' ||
            type == 'pickup:response') {
          _loadData(showLoader: false);
        }
      },
      onError: (error) => _pushEvent('WS error: $error'),
      onDone: () => _pushEvent('WS disconnected'),
    );
  }

  void sendWsMessage(Map<String, dynamic> payload) {
    _wsService.send(payload);
  }

  void _pushEvent(String value) {
    _events.insert(0, value);
    if (_events.length > 8) _events.removeLast();
    notifyListeners();
  }

  // ── Data loading ─────────────────────────────────────────────────
  Future<void> loadData() => _loadData(showLoader: true);

  Future<void> _loadData({bool showLoader = true}) async {
    if (showLoader) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      final results = await Future.wait<dynamic>([
        _driverService.fetchDrivers(token: _token),
        _routeService.getRoutePlan(token: _token, driverId: _user.id),
        _driverService.getDriverLocation(token: _token, driverId: _user.id),
      ]);

      final incomingPlan = results[1] as DriverRoutePlan;
      final newRoutePlan = _routeService.preferStreetGeometry(
        incoming: incomingPlan,
        current: _routePlan,
      );

      _drivers = results[0] as List<DriverModel>;
      _routePlan = newRoutePlan;
      _routeOrders = newRoutePlan.orders;
      _driverLocation = results[2] as DriverLocation?;
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (showLoader) _isLoading = false;
      notifyListeners();
    }
  }

  // ── Location ─────────────────────────────────────────────────────
  Future<Position?> getCurrentLocation() async {
    _isLoading = true;
    notifyListeners();

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Los servicios de ubicación están desactivados.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Los permisos de ubicación fueron denegados.');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception(
          'Los permisos de ubicación están denegados permanentemente.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      await sendLocationDirect(position.latitude, position.longitude);
      return position;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> sendLocationDirect(double lat, double lng) async {
    await _driverService.updateDriverLocation(
      token: _token,
      driverId: _user.id,
      lat: lat,
      lng: lng,
    );

    _wsService.send({
      'type': 'driver:location',
      'lat': lat,
      'lng': lng,
      'heading': 0.0,
    });

    _driverLocation = DriverLocation(
      driverId: _user.id,
      lat: lat,
      lng: lng,
      heading: 0,
      updatedAt: DateTime.now().toIso8601String(),
    );

    _pushEvent(
      'Ubicación real enviada: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
    );
    notifyListeners();
  }
}
