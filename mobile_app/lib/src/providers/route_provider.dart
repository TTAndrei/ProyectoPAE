import 'package:flutter/material.dart';
import '../models/order_model.dart';
import '../services/route_service.dart';

/// Exposes route-geometry utilities and map helpers to the UI.
class RouteProvider extends ChangeNotifier {
  RouteProvider({required RouteService routeService})
      : _routeService = routeService;

  final RouteService _routeService;

  /// Whether a plan has sparse (non-street-level) geometry.
  bool isSparseRouteGeometry(DriverRoutePlan plan) {
    return _routeService.isSparseRouteGeometry(plan);
  }
}
