class AuditLogModel {
  const AuditLogModel({
    required this.id,
    required this.orderId,
    required this.action,
    this.driverId,
    required this.timestamp,
    this.details,
  });

  final String id;
  final String orderId;
  final String action;
  final String? driverId;
  final String timestamp;
  final String? details;

  factory AuditLogModel.fromJson(Map<String, dynamic> json) {
    return AuditLogModel(
      id: json['id']?.toString() ?? '',
      orderId: json['order_id']?.toString() ?? '',
      action: json['action']?.toString() ?? '',
      driverId: json['driver_id']?.toString(),
      timestamp: json['timestamp']?.toString() ?? '',
      details: json['details']?.toString(),
    );
  }
}

class DriverPerformanceModel {
  const DriverPerformanceModel({
    required this.driverId,
    required this.name,
    required this.loadEfficiencyRatio,
    required this.loadEfficiencyPercent,
    required this.loadedDistanceKm,
    required this.totalDistanceKm,
    required this.activeOrderCount,
    required this.pendingConfirmationCount,
    required this.completedOrderCount,
    required this.averageLoadPackages,
    required this.averageInsertionDetourMinutes,
    required this.packagesPerKm,
    required this.insertionAcceptanceRate,
    required this.meetsLoadEfficiencyTarget,
  });

  final String driverId;
  final String name;
  final double loadEfficiencyRatio;
  final double loadEfficiencyPercent;
  final double loadedDistanceKm;
  final double totalDistanceKm;
  final int activeOrderCount;
  final int pendingConfirmationCount;
  final int completedOrderCount;
  final double averageLoadPackages;
  final double averageInsertionDetourMinutes;
  final double packagesPerKm;
  final double insertionAcceptanceRate;
  final bool meetsLoadEfficiencyTarget;

  factory DriverPerformanceModel.fromJson(Map<String, dynamic> json) {
    return DriverPerformanceModel(
      driverId: json['driver_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      loadEfficiencyRatio:
          (json['load_efficiency_ratio'] as num?)?.toDouble() ?? 0.0,
      loadEfficiencyPercent:
          (json['load_efficiency_percent'] as num?)?.toDouble() ?? 0.0,
      loadedDistanceKm: (json['loaded_distance_km'] as num?)?.toDouble() ?? 0.0,
      totalDistanceKm: (json['total_distance_km'] as num?)?.toDouble() ?? 0.0,
      activeOrderCount: (json['active_order_count'] as num?)?.toInt() ?? 0,
      pendingConfirmationCount:
          (json['pending_confirmation_count'] as num?)?.toInt() ?? 0,
      completedOrderCount:
          (json['completed_order_count'] as num?)?.toInt() ?? 0,
      averageLoadPackages:
          (json['average_load_packages'] as num?)?.toDouble() ?? 0.0,
      averageInsertionDetourMinutes:
          (json['average_insertion_detour_minutes'] as num?)?.toDouble() ?? 0.0,
      packagesPerKm: (json['packages_per_km'] as num?)?.toDouble() ?? 0.0,
      insertionAcceptanceRate:
          (json['insertion_acceptance_rate'] as num?)?.toDouble() ?? 0.0,
      meetsLoadEfficiencyTarget: json['meets_load_efficiency_target'] == true,
    );
  }
}

class FleetSummaryModel {
  const FleetSummaryModel({
    required this.totalDistanceKm,
    required this.loadedDistanceKm,
    required this.averageLoadEfficiencyPercent,
    required this.totalActiveOrders,
    required this.totalPendingConfirmations,
    required this.totalCompletedOrders,
    required this.averageLoadPackages,
    required this.averageInsertionDetourMinutes,
    required this.packagesPerKm,
    required this.insertionAcceptanceRate,
  });

  final double totalDistanceKm;
  final double loadedDistanceKm;
  final double averageLoadEfficiencyPercent;
  final int totalActiveOrders;
  final int totalPendingConfirmations;
  final int totalCompletedOrders;
  final double averageLoadPackages;
  final double averageInsertionDetourMinutes;
  final double packagesPerKm;
  final double insertionAcceptanceRate;

  factory FleetSummaryModel.fromJson(Map<String, dynamic> json) {
    return FleetSummaryModel(
      totalDistanceKm: (json['total_distance_km'] as num?)?.toDouble() ?? 0.0,
      loadedDistanceKm: (json['loaded_distance_km'] as num?)?.toDouble() ?? 0.0,
      averageLoadEfficiencyPercent:
          (json['average_load_efficiency_percent'] as num?)?.toDouble() ?? 0.0,
      totalActiveOrders: (json['total_active_orders'] as num?)?.toInt() ?? 0,
      totalPendingConfirmations:
          (json['total_pending_confirmations'] as num?)?.toInt() ?? 0,
      totalCompletedOrders:
          (json['total_completed_orders'] as num?)?.toInt() ?? 0,
      averageLoadPackages:
          (json['average_load_packages'] as num?)?.toDouble() ?? 0.0,
      averageInsertionDetourMinutes:
          (json['average_insertion_detour_minutes'] as num?)?.toDouble() ?? 0.0,
      packagesPerKm: (json['packages_per_km'] as num?)?.toDouble() ?? 0.0,
      insertionAcceptanceRate:
          (json['insertion_acceptance_rate'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class RouteHistoryModel {
  const RouteHistoryModel({
    required this.id,
    required this.driverId,
    required this.orderIds,
    required this.completedOrderIds,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.totalMinutes,
    required this.totalDistanceKm,
    required this.routeGeometry,
    required this.legMinutes,
  });

  final String id;
  final String driverId;
  final List<String> orderIds;
  final List<String> completedOrderIds;
  final String status;
  final String createdAt;
  final String updatedAt;
  final double totalMinutes;
  final double totalDistanceKm;
  final List<Map<String, double>> routeGeometry;
  final List<double> legMinutes;

  factory RouteHistoryModel.fromJson(Map<String, dynamic> json) {
    final rawOrderIds = json['order_ids'] as List?;
    final rawCompletedOrderIds = json['completed_order_ids'] as List?;
    final rawLegMinutes = json['leg_minutes'] as List?;
    final rawGeom = json['route_geometry'] as List?;

    List<Map<String, double>> parsedGeom = [];
    if (rawGeom != null) {
      for (final rawPoint in rawGeom) {
        if (rawPoint is Map) {
          final lat = (rawPoint['lat'] as num?)?.toDouble();
          final lng = (rawPoint['lng'] as num?)?.toDouble();
          if (lat != null && lng != null) {
            parsedGeom.add({'lat': lat, 'lng': lng});
          }
        }
      }
    }

    return RouteHistoryModel(
      id: json['id']?.toString() ?? '',
      driverId: json['driver_id']?.toString() ?? '',
      orderIds: rawOrderIds != null ? List<String>.from(rawOrderIds) : [],
      completedOrderIds: rawCompletedOrderIds != null
          ? List<String>.from(rawCompletedOrderIds)
          : [],
      status: json['status']?.toString() ?? '',
      createdAt: json['created_at']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString() ?? '',
      totalMinutes: (json['total_minutes'] as num?)?.toDouble() ?? 0.0,
      totalDistanceKm: (json['total_distance_km'] as num?)?.toDouble() ?? 0.0,
      routeGeometry: parsedGeom,
      legMinutes: rawLegMinutes != null
          ? rawLegMinutes.map((m) => (m as num).toDouble()).toList()
          : [],
    );
  }
}
