import 'dart:async';

import 'package:flutter/material.dart';
import '../models/driver_model.dart';
import '../services/driver_service.dart';
import '../services/ws_service.dart';

/// Manages central-specific state: listing all drivers and receiving real-time GPS updates.
class CentralProvider extends ChangeNotifier {
  CentralProvider({
    required DriverService driverService,
    required String token,
    required String apiBaseUrl,
  })  : _driverService = driverService,
        _token = token,
        _apiBaseUrl = apiBaseUrl {
    _loadDrivers();
    _connectWs();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _loadDrivers(showLoader: false),
    );
  }

  final DriverService _driverService;
  final String _token;
  final String _apiBaseUrl;
  final WsService _wsService = WsService();

  Timer? _refreshTimer;
  bool _isLoading = false;
  String? _error;
  List<DriverModel> _drivers = const [];

  // ── Getters ──────────────────────────────────────────────────────
  bool get isLoading => _isLoading;
  String? get error => _error;
  List<DriverModel> get drivers => _drivers;

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
        if (type == 'driver:location:update' ||
            type == 'pickup:response' ||
            type == 'driver:offline') {
          _loadDrivers(showLoader: false);
        }
      },
      onError: (_) {},
      onDone: () {},
    );
  }

  // ── Data loading ─────────────────────────────────────────────────
  Future<void> loadDrivers() => _loadDrivers(showLoader: true);

  Future<void> _loadDrivers({bool showLoader = true}) async {
    if (showLoader) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      _drivers = await _driverService.fetchDrivers(token: _token);
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (showLoader) _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> registerDriver({
    required String username,
    required String password,
    required String name,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _driverService.registerDriver(
        token: _token,
        username: username,
        password: password,
        name: name,
      );
      await _loadDrivers(showLoader: false);
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
