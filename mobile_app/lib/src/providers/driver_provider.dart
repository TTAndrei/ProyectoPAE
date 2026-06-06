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
    bool autoConnect = true,
    bool enablePolling = true,
    Duration refreshInterval = const Duration(seconds: 8),
  })  : _driverService = driverService,
        _routeService = routeService,
        _token = token,
        _apiBaseUrl = apiBaseUrl,
        _user = user {
    _loadData();
    if (autoConnect) {
      _connectWs();
    }
    if (enablePolling) {
      _refreshTimer = Timer.periodic(
        refreshInterval,
        (_) => _loadData(showLoader: false),
      );
    }
    _secondsTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (_activeJornada != null) {
          notifyListeners();
        }
      },
    );
  }

  final DriverService _driverService;
  final RouteService _routeService;
  final String _token;
  final String _apiBaseUrl;
  final AppUser _user;
  final WsService _wsService = WsService();

  Timer? _refreshTimer;
  Timer? _secondsTimer;
  bool _isLoading = false;
  String? _error;

  DriverLocation? _driverLocation;
  DriverKpiModel? _kpis;
  DriverRoutePlan? _routePlan;
  List<OrderModel> _routeOrders = const [];
  final List<String> _events = <String>[];
  bool _isAvailable = true;
  Map<String, dynamic>? _activeJornada;
  final Set<String> _notifiedAssignedOrderIds = <String>{};

  final _incomingOrderStreamController =
      StreamController<AssignOrderResult>.broadcast();
  final _wsRefreshController = StreamController<void>.broadcast();

  // ── Getters ──────────────────────────────────────────────────────
  Stream<AssignOrderResult> get incomingOrderNotifications =>
      _incomingOrderStreamController.stream;

  /// Stream that fires when WS events indicate orders should be refreshed.
  Stream<void> get wsRefreshStream => _wsRefreshController.stream;
  bool get isLoading => _isLoading;
  String? get error => _error;
  DriverLocation? get driverLocation => _driverLocation;
  DriverKpiModel? get kpis => _kpis;
  DriverRoutePlan? get routePlan => _routePlan;
  List<OrderModel> get routeOrders => _routeOrders;
  List<String> get events => _events;
  AppUser get user => _user;
  bool get isAvailable => _isAvailable;
  Map<String, dynamic>? get activeJornada => _activeJornada;

  Duration get shiftDuration {
    final active = _activeJornada;
    if (active == null) return Duration.zero;
    final startTimeStr = active['start_time']?.toString();
    if (startTimeStr == null) return Duration.zero;
    try {
      final startTime = DateTime.parse(startTimeStr);
      return DateTime.now().difference(startTime);
    } catch (_) {
      return Duration.zero;
    }
  }

  // ── Lifecycle ────────────────────────────────────────────────────
  @override
  void dispose() {
    _refreshTimer?.cancel();
    _secondsTimer?.cancel();
    _wsService.disconnect();
    _incomingOrderStreamController.close();
    _wsRefreshController.close();
    super.dispose();
  }

  // ── WebSocket ────────────────────────────────────────────────────
  void _connectWs() {
    debugPrint('[DriverProvider] Connecting WS for user ${_user.id}...');
    _wsService.connect(
      apiBaseUrl: _apiBaseUrl,
      token: _token,
      onMessage: (payload) {
        final type = payload['type']?.toString() ?? 'event';
        debugPrint('[DriverProvider] WS message received: type=$type');
        _pushEvent('WS: $type');

        if (type == 'pickup:auto_assigned' ||
            type == 'pickup:notification' ||
            type == 'driver:location:update' ||
            type == 'pickup:response') {
          _loadData(showLoader: false);
          _wsRefreshController.add(null); // notify OrderProvider
        }

        // Notification of newly assigned order needing confirmation: notify via stream
        if (type == 'pickup:notification' || type == 'pickup:auto_assigned') {
          debugPrint('[DriverProvider] Nuevo pedido asignado recibido');
          try {
            final assignment = AssignOrderResult.fromJson(payload);
            _emitAssignmentIfNew(assignment);
          } catch (e) {
            debugPrint('[DriverProvider] Error parsing notification: $e');
            _pushEvent('Error parseo asignacion: $e');
          }
        }
      },
      onError: (error) {
        debugPrint('[DriverProvider] WS error: $error');
        _pushEvent('WS error: $error');
      },
      onDone: () {
        debugPrint('[DriverProvider] WS disconnected');
        _pushEvent('WS disconnected');
      },
    );
    debugPrint('[DriverProvider] WS connect() called');
  }

  void sendWsMessage(Map<String, dynamic> payload) {
    _wsService.send(payload);
  }

  void _pushEvent(String value) {
    _events.insert(0, value);
    if (_events.length > 8) _events.removeLast();
    notifyListeners();
  }

  void _emitAssignmentIfNew(AssignOrderResult assignment) {
    if (!_notifiedAssignedOrderIds.add(assignment.order.id)) {
      return;
    }
    _incomingOrderStreamController.add(assignment);
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
        _routeService.getRoutePlan(token: _token, driverId: _user.id),
        _driverService.getDriverLocation(token: _token, driverId: _user.id),
        _driverService.getActiveJornada(token: _token),
        _driverService.getMyDriverKpis(token: _token),
      ]);

      final incomingPlan = results[0] as DriverRoutePlan;
      final newRoutePlan = _routeService.preferStreetGeometry(
        incoming: incomingPlan,
        current: _routePlan,
      );

      _routePlan = newRoutePlan;
      _routeOrders = newRoutePlan.orders;
      _driverLocation = results[1] as DriverLocation?;
      _activeJornada = results[2] as Map<String, dynamic>?;
      _kpis = results[3] as DriverKpiModel;

      if (_driverLocation != null) {
        _isAvailable = _driverLocation!.isAvailable;
      }

      // Check if there are any assigned orders needing acceptance and push them
      final assignedOrders =
          newRoutePlan.orders.where((o) => o.status == 'assigned').toList();
      final assignedOrderIds = assignedOrders.map((order) => order.id).toSet();
      _notifiedAssignedOrderIds
          .removeWhere((orderId) => !assignedOrderIds.contains(orderId));
      if (assignedOrders.isNotEmpty) {
        for (final order in assignedOrders) {
          final assignment = AssignOrderResult(
            order: order,
            extraMinutes: order.estimatedExtraMinutes ?? 0.0,
          );
          _emitAssignmentIfNew(assignment);
        }
      }

      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (showLoader) _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> toggleAvailability(bool available) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _driverService.updateDriverAvailability(
        token: _token,
        driverId: _user.id,
        isAvailable: available,
      );
      _isAvailable = available;
      _pushEvent('Disponibilidad: ${available ? "Activo" : "Pausado"}');
      await _loadData(showLoader: false);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> startShift() async {
    _isLoading = true;
    notifyListeners();
    try {
      final res = await _driverService.startJornada(token: _token);
      _activeJornada = res;
      _pushEvent('Jornada iniciada');
      await _loadData(showLoader: false);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> endShift() async {
    _isLoading = true;
    notifyListeners();
    try {
      await _driverService.endJornada(token: _token);
      _activeJornada = null;
      _pushEvent('Jornada finalizada');
      await _loadData(showLoader: false);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
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
      isAvailable: _isAvailable,
    );

    _pushEvent(
      'Ubicación real enviada: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
    );
    notifyListeners();
  }
}
