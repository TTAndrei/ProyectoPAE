import 'dart:async';

import 'package:flutter/material.dart';
import '../models/order_model.dart';
import '../services/order_service.dart';
import '../services/route_service.dart';

/// Manages order state: fetching, creating, assigning, and filtering orders.
///
/// NOTE: This provider does NOT open its own WebSocket connection.
/// Instead, it relies on an external refresh stream (from DriverProvider or
/// CentralProvider) to trigger order reloads. This avoids the bug where
/// multiple WS connections with the same token overwrite each other in the
/// backend's _repartidores dict.
class OrderProvider extends ChangeNotifier {
  OrderProvider({
    required OrderService orderService,
    required RouteService routeService,
    required String token,
    String? apiBaseUrl,
    Stream<void>? refreshStream,
  })  : _orderService = orderService,
        _routeService = routeService,
        _token = token {
    _loadOrders();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _loadOrders(showLoader: false),
    );
    if (refreshStream != null) {
      _wsRefreshSub = refreshStream.listen((_) {
        _loadOrders(showLoader: false);
      });
    }
  }

  final OrderService _orderService;
  final RouteService _routeService;
  final String _token;

  Timer? _refreshTimer;
  StreamSubscription<void>? _wsRefreshSub;
  bool _isLoading = false;
  String? _error;

  List<OrderModel> _orders = const [];
  Map<String, DriverRoutePlan> _routePlansByDriver = const {};
  final List<String> _events = <String>[];

  // ── Getters ──────────────────────────────────────────────────────
  bool get isLoading => _isLoading;
  String? get error => _error;
  List<OrderModel> get orders => _orders;
  Map<String, DriverRoutePlan> get routePlansByDriver => _routePlansByDriver;
  List<String> get events => _events;

  List<OrderModel> get pendingOrders =>
      _orders.where((o) => o.status == 'pending').toList();

  List<OrderModel> get activeOrders =>
      _orders.where((o) => o.status != 'pending').toList();

  List<OrderModel> get activeAssignedOrders => _orders
      .where((o) =>
          o.assignedDriverId != null &&
          o.status != 'completed' &&
          o.status != 'rejected')
      .toList();

  // ── Lifecycle ────────────────────────────────────────────────────
  @override
  void dispose() {
    _refreshTimer?.cancel();
    _wsRefreshSub?.cancel();
    super.dispose();
  }

  void _pushEvent(String value) {
    _events.insert(0, value);
    if (_events.length > 8) _events.removeLast();
    notifyListeners();
  }

  // ── Data loading ─────────────────────────────────────────────────
  Future<void> loadOrders() => _loadOrders(showLoader: true);

  Future<void> _loadOrders({bool showLoader = true}) async {
    if (showLoader) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      _orders = await _orderService.fetchOrders(token: _token);

      // Fetch route plans for active assigned drivers.
      final activeDriverIds = activeAssignedOrders
          .map((o) => o.assignedDriverId!)
          .toSet()
          .toList()
        ..sort();

      final incoming = <String, DriverRoutePlan>{};
      if (activeDriverIds.isNotEmpty) {
        final entries =
            await Future.wait<MapEntry<String, DriverRoutePlan>?>(
          activeDriverIds.map((driverId) async {
            try {
              final plan = await _routeService.getRoutePlan(
                token: _token,
                driverId: driverId,
              );
              return MapEntry(driverId, plan);
            } catch (_) {
              return null;
            }
          }),
        );
        for (final entry in entries) {
          if (entry != null) incoming[entry.key] = entry.value;
        }
      }

      _routePlansByDriver =
          _routeService.mergeRoutePlans(_routePlansByDriver, incoming);
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (showLoader) _isLoading = false;
      notifyListeners();
    }
  }

  // ── Mutations ────────────────────────────────────────────────────
  Future<OrderModel> createOrder({
    required String type,
    String? name,
    required String address,
    required double lat,
    required double lng,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final order = await _orderService.createOrder(
        token: _token,
        input: CreateOrderInput(
          type: type,
          name: name,
          address: address,
          lat: lat,
          lng: lng,
        ),
      );
      _pushEvent('Nuevo pedido ${order.id} (${order.type})');
      await _loadOrders(showLoader: false);
      return order;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<AssignOrderResult> assignOrder({
    required String orderId,
    required String driverId,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _orderService.assignOrder(
        token: _token,
        orderId: orderId,
        driverId: driverId,
      );

      // WS notification is already sent by the backend HTTP endpoint

      _pushEvent(
        'Asignado ${result.order.id} a $driverId '
        '(+${result.extraMinutes.toStringAsFixed(1)} min)',
      );
      await _loadOrders(showLoader: false);
      return result;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<RespondOrderResult> respondToPickup({
    required String orderId,
    required bool accepted,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _orderService.respondOrder(
        token: _token,
        orderId: orderId,
        accepted: accepted,
      );

      // WS notification is already sent by the backend HTTP endpoint

      _pushEvent('Pedido $orderId: ${accepted ? 'aceptado' : 'rechazado'}');
      await _loadOrders(showLoader: false);
      return result;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateOrderStatus({
    required String orderId,
    required String status,
    String? actionLabel,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      await _orderService.updateOrderStatus(
        token: _token,
        orderId: orderId,
        status: status,
      );
      _pushEvent('Pedido $orderId ${actionLabel ?? status}');
      await _loadOrders(showLoader: false);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Geocodes an address via the order service (which wraps Nominatim).
  Future<List<GeocodeCandidate>> geocodeAddressCandidates({
    required String address,
    int maxResults = 5,
  }) {
    return _orderService.geocodeAddressCandidates(
      address: address,
      maxResults: maxResults,
    );
  }
}
