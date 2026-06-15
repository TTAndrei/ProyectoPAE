import '../models/order_model.dart';
import 'api_client.dart';

/// Wraps route-plan API calls and route geometry utilities.
class RouteService {
  RouteService({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  /// Fetches the optimised route plan for a driver.
  Future<DriverRoutePlan> getRoutePlan({
    required String token,
    required String driverId,
  }) {
    return _apiClient.getRoutePlan(token: token, driverId: driverId);
  }

  /// Returns `true` when the geometry has too few points to be a real street-level route.
  ///
  /// Uses strict `<` (not `<=`) so that a fallback straight-line with exactly
  /// [orders.length + 1] points is still considered drawable.
  bool isSparseRouteGeometry(DriverRoutePlan plan) {
    if (plan.routeGeometry.length < 2) return true;
    final minimumWaypointCount =
        plan.orders.isEmpty ? 0 : plan.orders.length + 1;
    return plan.routeGeometry.length < minimumWaypointCount;
  }

  /// Keeps the richer geometry when the incoming one is sparse but
  /// the existing one already has street-level detail.
  ///
  /// Exception: if the order list changed (driver accepted a new order or
  /// completed one), the old geometry is stale and the incoming plan is
  /// always preferred so the map updates immediately.
  DriverRoutePlan preferStreetGeometry({
    required DriverRoutePlan incoming,
    DriverRoutePlan? current,
  }) {
    if (current == null) return incoming;

    // If the set of orders changed, old geometry is stale — always use incoming.
    final incomingIds = incoming.orders.map((o) => o.id).toSet();
    final currentIds = current.orders.map((o) => o.id).toSet();
    if (incomingIds.length != currentIds.length ||
        !incomingIds.containsAll(currentIds)) {
      return incoming;
    }

    final incomingSparse = isSparseRouteGeometry(incoming);
    final currentLooksStreet = !isSparseRouteGeometry(current);

    if (incomingSparse && currentLooksStreet) {
      return DriverRoutePlan(
        orders: incoming.orders,
        totalMinutes: incoming.totalMinutes,
        totalDistanceKm: incoming.totalDistanceKm,
        routeGeometry: current.routeGeometry,
        legMinutes: incoming.legMinutes.isNotEmpty
            ? incoming.legMinutes
            : current.legMinutes,
      );
    }
    return incoming;
  }

  /// Merges incoming route plans with the existing ones, preserving
  /// richer geometry when possible.
  Map<String, DriverRoutePlan> mergeRoutePlans(
    Map<String, DriverRoutePlan> current,
    Map<String, DriverRoutePlan> incoming,
  ) {
    final merged = <String, DriverRoutePlan>{};
    for (final entry in incoming.entries) {
      merged[entry.key] = preferStreetGeometry(
        incoming: entry.value,
        current: current[entry.key],
      );
    }
    return merged;
  }
}
