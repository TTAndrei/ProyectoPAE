import 'dart:async';

import 'package:flutter/material.dart';
import '../models/driver_model.dart';
import '../models/analytics_models.dart';
import '../models/simulation_model.dart';
import '../services/driver_service.dart';
import '../services/simulation_service.dart';
import '../services/ws_service.dart';

/// Manages central-specific state: listing all drivers and receiving real-time GPS updates.
class CentralProvider extends ChangeNotifier {
  CentralProvider({
    required DriverService driverService,
    required SimulationService simulationService,
    required String token,
    required String apiBaseUrl,
  })  : _driverService = driverService,
        _simulationService = simulationService,
        _token = token,
        _apiBaseUrl = apiBaseUrl {
    _loadDrivers();
    _loadSimulationStatus(showLoader: false);
    _connectWs();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _loadDrivers(showLoader: false),
    );
  }

  final DriverService _driverService;
  final SimulationService _simulationService;
  final String _token;
  final String _apiBaseUrl;
  final WsService _wsService = WsService();
  final StreamController<void> _wsRefreshController =
      StreamController<void>.broadcast();

  Timer? _refreshTimer;
  Timer? _simulationPollTimer;
  bool _disposed = false;
  bool _isLoading = false;
  bool _isSimulationLoading = false;
  String? _error;
  List<DriverModel> _drivers = const [];
  FleetSummaryModel? _fleetSummary;
  List<DriverPerformanceModel> _driverPerformance = const [];
  List<RouteHistoryModel> _routesHistory = const [];
  final Map<String, List<AuditLogModel>> _orderAudits = {};
  SimulationStatus? _simulationStatus;
  DriverKpiModel? _simulationKpis;
  String _selectedSimulation = 'route-20';

  // ── Getters ──────────────────────────────────────────────────────
  bool get isLoading => _isLoading;
  String? get error => _error;
  List<DriverModel> get drivers => _drivers;
  FleetSummaryModel? get fleetSummary => _fleetSummary;
  List<DriverPerformanceModel> get driverPerformance => _driverPerformance;
  List<RouteHistoryModel> get routesHistory => _routesHistory;
  Map<String, List<AuditLogModel>> get orderAudits => _orderAudits;
  SimulationStatus? get simulationStatus => _simulationStatus;
  DriverKpiModel? get simulationKpis => _simulationKpis;
  bool get isSimulationLoading => _isSimulationLoading;
  String get selectedSimulation => _selectedSimulation;
  Stream<void> get wsRefreshStream => _wsRefreshController.stream;

  // ── Lifecycle ────────────────────────────────────────────────────
  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    _simulationPollTimer?.cancel();
    _wsService.disconnect();
    _wsRefreshController.close();
    super.dispose();
  }

  // ── WebSocket ────────────────────────────────────────────────────
  void _connectWs() {
    _wsService.connect(
      apiBaseUrl: _apiBaseUrl,
      token: _token,
      onMessage: (payload) {
        final type = payload['type']?.toString() ?? 'event';
        if (type == 'driver:location:update') {
          _applyDriverLocationUpdate(payload);
          return;
        }

        if (type == 'pickup:response' ||
            type == 'driver:offline') {
          _loadDrivers(showLoader: false);
          _emitRefresh();
        }

        if (type == 'simulation:tick' ||
            type == 'simulation:reroute' ||
            type == 'simulation:completed') {
          _loadSimulationStatus(showLoader: false);
          _loadDrivers(showLoader: false);
          _emitRefresh();
        }
      },
      onError: (_) {},
      onDone: () {},
    );
  }

  void _applyDriverLocationUpdate(Map<String, dynamic> payload) {
    final driverId = payload['driver_id']?.toString();
    final lat = _asDouble(payload['lat']);
    final lng = _asDouble(payload['lng']);
    if (driverId == null || lat == null || lng == null) {
      return;
    }

    final heading = _asDouble(payload['heading']);
    final updatedAt =
        payload['updated_at']?.toString() ?? DateTime.now().toIso8601String();
    var changed = false;
    _drivers = _drivers.map((driver) {
      if (driver.id != driverId) return driver;
      changed = true;
      return driver.copyWith(
        lat: lat,
        lng: lng,
        heading: heading,
        locationUpdatedAt: updatedAt,
      );
    }).toList();

    if (changed && !_disposed) {
      notifyListeners();
      _emitRefresh();
    }
  }

  double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  void _emitRefresh() {
    if (!_disposed && !_wsRefreshController.isClosed) {
      _wsRefreshController.add(null);
    }
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

  Future<void> loadSimulationStatus() => _loadSimulationStatus();

  Future<void> selectSimulation(String simulation) async {
    if (simulation != 'route-20' && simulation != 'rerouting') {
      return;
    }
    _selectedSimulation = simulation;
    await _loadSimulationStatus(showLoader: true);
  }

  Future<void> _loadSimulationStatus({bool showLoader = true}) async {
    if (_disposed) return;
    if (showLoader) {
      _isSimulationLoading = true;
      notifyListeners();
    }

    try {
      final status = _selectedSimulation == 'rerouting'
          ? await _simulationService.fetchReroutingStatus(token: _token)
          : await _simulationService.fetchRoute20Status(token: _token);
      _simulationStatus = status;
      _simulationKpis = status.kpis;
      _error = null;
      _syncSimulationPolling();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (!_disposed) {
        if (showLoader) _isSimulationLoading = false;
        notifyListeners();
      }
    }
  }

  void _syncSimulationPolling() {
    if (_simulationStatus?.isRunning == true) {
      _simulationPollTimer ??= Timer.periodic(
          const Duration(seconds: 2),
          (_) async {
            await _loadSimulationStatus(showLoader: false);
            _emitRefresh();
          },
      );
    } else {
      _simulationPollTimer?.cancel();
      _simulationPollTimer = null;
    }
  }

  Future<void> startRoute20Simulation() async {
    _selectedSimulation = 'route-20';
    _isSimulationLoading = true;
    _error = null;
    notifyListeners();

    try {
      final status = await _simulationService.startRoute20(token: _token);
      _simulationStatus = status;
      _simulationKpis = status.kpis;
      _syncSimulationPolling();
      await _loadDrivers(showLoader: false);
      _emitRefresh();
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isSimulationLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> resetRoute20Simulation() async {
    _selectedSimulation = 'route-20';
    _isSimulationLoading = true;
    _error = null;
    notifyListeners();

    try {
      final status = await _simulationService.resetRoute20(token: _token);
      _simulationStatus = status;
      _simulationKpis = status.kpis;
      _syncSimulationPolling();
      await _loadDrivers(showLoader: false);
      _emitRefresh();
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isSimulationLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<DriverKpiModel> loadSimulationKpis() async {
    _isSimulationLoading = true;
    _error = null;
    notifyListeners();

    try {
      final kpis = _selectedSimulation == 'rerouting'
          ? await _simulationService.fetchReroutingKpis(token: _token)
          : await _simulationService.fetchRoute20Kpis(token: _token);
      _simulationKpis = kpis;
      return kpis;
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isSimulationLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> startReroutingSimulation() async {
    _selectedSimulation = 'rerouting';
    _isSimulationLoading = true;
    _error = null;
    notifyListeners();

    try {
      final status = await _simulationService.startRerouting(token: _token);
      _simulationStatus = status;
      _simulationKpis = status.kpis;
      _syncSimulationPolling();
      await _loadDrivers(showLoader: false);
      _emitRefresh();
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isSimulationLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> resetReroutingSimulation() async {
    _selectedSimulation = 'rerouting';
    _isSimulationLoading = true;
    _error = null;
    notifyListeners();

    try {
      final status = await _simulationService.resetRerouting(token: _token);
      _simulationStatus = status;
      _simulationKpis = status.kpis;
      _syncSimulationPolling();
      await _loadDrivers(showLoader: false);
      _emitRefresh();
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isSimulationLoading = false;
      if (!_disposed) notifyListeners();
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

  Future<void> updateDriverLocation({
    required String driverId,
    required double lat,
    required double lng,
    double heading = 0.0,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _driverService.updateDriverLocation(
        token: _token,
        driverId: driverId,
        lat: lat,
        lng: lng,
        heading: heading,
      );
      await _loadDrivers(showLoader: false);
      _emitRefresh();
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> deleteDriver(String driverId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _driverService.deleteDriver(token: _token, driverId: driverId);
      await _loadDrivers(showLoader: false);
      _emitRefresh();
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      if (!_disposed) notifyListeners();
    }
  }
}
