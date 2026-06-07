import 'dart:async';

import 'package:flutter/material.dart';
import '../models/driver_model.dart';
import '../models/analytics_models.dart';
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
  bool _disposed = false;
  bool _isLoading = false;
  String? _error;
  List<DriverModel> _drivers = const [];
  FleetSummaryModel? _fleetSummary;
  List<DriverPerformanceModel> _driverPerformance = const [];
  List<RouteHistoryModel> _routesHistory = const [];
  final Map<String, List<AuditLogModel>> _orderAudits = {};

  // ── Getters ──────────────────────────────────────────────────────
  bool get isLoading => _isLoading;
  String? get error => _error;
  List<DriverModel> get drivers => _drivers;
  FleetSummaryModel? get fleetSummary => _fleetSummary;
  List<DriverPerformanceModel> get driverPerformance => _driverPerformance;
  List<RouteHistoryModel> get routesHistory => _routesHistory;
  Map<String, List<AuditLogModel>> get orderAudits => _orderAudits;

  // ── Lifecycle ────────────────────────────────────────────────────
  @override
  void dispose() {
    _disposed = true;
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
    if (_disposed) return;
    if (showLoader) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      _drivers = await _driverService.fetchDrivers(token: _token);
      _error = null;
    } catch (e) {
      _error = e.toString();
    }

    // Analytics fetched separately so a failure doesn't block driver data
    try {
      final analytics = await Future.wait([
        _driverService.fetchFleetSummary(token: _token),
        _driverService.fetchDriverPerformance(token: _token),
        _driverService.fetchRoutesHistory(token: _token),
      ]);
      _fleetSummary = analytics[0] as FleetSummaryModel;
      _driverPerformance = analytics[1] as List<DriverPerformanceModel>;
      _routesHistory = analytics[2] as List<RouteHistoryModel>;
    } catch (_) {
      // Analytics failure is non-critical; keep last known values
    }

    if (!_disposed) {
      if (showLoader) _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<AuditLogModel>> loadOrderAudit(String orderId) async {
    try {
      final logs = await _driverService.fetchAuditLogs(token: _token, orderId: orderId);
      _orderAudits[orderId] = logs;
      if (!_disposed) notifyListeners();
      return logs;
    } catch (e) {
      _error = e.toString();
      if (!_disposed) notifyListeners();
      rethrow;
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
