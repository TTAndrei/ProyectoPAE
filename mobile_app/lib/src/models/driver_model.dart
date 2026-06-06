import 'app_user.dart';

double? _asNullableDouble(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

class DriverModel {
  const DriverModel({
    required this.id,
    required this.username,
    required this.name,
    this.lat,
    this.lng,
    this.heading,
    this.locationUpdatedAt,
    this.isAvailable = true,
    this.company,
    this.kpis,
  });

  final String id;
  final String username;
  final String name;
  final double? lat;
  final double? lng;
  final double? heading;
  final String? locationUpdatedAt;
  final bool isAvailable;
  final CompanyModel? company;
  final DriverKpiModel? kpis;

  String get shortLocation {
    if (lat == null || lng == null) {
      return 'No location';
    }
    return '${lat!.toStringAsFixed(5)}, ${lng!.toStringAsFixed(5)}';
  }

  factory DriverModel.fromJson(Map<String, dynamic> json) {
    return DriverModel(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      lat: _asNullableDouble(json['lat']),
      lng: _asNullableDouble(json['lng']),
      heading: _asNullableDouble(json['heading']),
      locationUpdatedAt: json['location_updated_at']?.toString(),
      isAvailable:
          json['is_available'] == null ? true : (json['is_available'] as bool),
      company: json['company'] != null
          ? CompanyModel.fromJson(Map<String, dynamic>.from(json['company'] as Map))
          : null,
      kpis: DriverKpiModel.fromJson(json),
    );
  }
}

class DriverKpiModel {
  const DriverKpiModel({
    required this.driverId,
    required this.loadEfficiencyRatio,
    required this.loadEfficiencyPercent,
    required this.loadedDistanceKm,
    required this.totalDistanceKm,
    required this.activeOrderCount,
    required this.pendingConfirmationCount,
    required this.completedOrderCount,
    required this.targetLoadEfficiencyRatio,
    required this.meetsLoadEfficiencyTarget,
    required this.measurementNote,
  });

  final String driverId;
  final double loadEfficiencyRatio;
  final double loadEfficiencyPercent;
  final double loadedDistanceKm;
  final double totalDistanceKm;
  final int activeOrderCount;
  final int pendingConfirmationCount;
  final int completedOrderCount;
  final double targetLoadEfficiencyRatio;
  final bool meetsLoadEfficiencyTarget;
  final String measurementNote;

  String get loadEfficiencyLabel =>
      '${loadEfficiencyPercent.toStringAsFixed(1)}%';

  String get loadDistanceLabel =>
      '${loadedDistanceKm.toStringAsFixed(2)} / ${totalDistanceKm.toStringAsFixed(2)} km';

  factory DriverKpiModel.fromJson(Map<String, dynamic> json) {
    return DriverKpiModel(
      driverId: json['driver_id']?.toString() ?? json['id']?.toString() ?? '',
      loadEfficiencyRatio:
          _asNullableDouble(json['load_efficiency_ratio']) ?? 0.0,
      loadEfficiencyPercent:
          _asNullableDouble(json['load_efficiency_percent']) ?? 0.0,
      loadedDistanceKm: _asNullableDouble(json['loaded_distance_km']) ?? 0.0,
      totalDistanceKm: _asNullableDouble(json['total_distance_km']) ?? 0.0,
      activeOrderCount: (json['active_order_count'] as num?)?.toInt() ?? 0,
      pendingConfirmationCount:
          (json['pending_confirmation_count'] as num?)?.toInt() ?? 0,
      completedOrderCount:
          (json['completed_order_count'] as num?)?.toInt() ?? 0,
      targetLoadEfficiencyRatio:
          _asNullableDouble(json['target_load_efficiency_ratio']) ?? 0.75,
      meetsLoadEfficiencyTarget: json['meets_load_efficiency_target'] == true,
      measurementNote: json['measurement_note']?.toString() ?? '',
    );
  }
}

class DriverLocation {
  const DriverLocation({
    required this.driverId,
    required this.lat,
    required this.lng,
    required this.heading,
    this.updatedAt,
    this.isAvailable = true,
  });

  final String driverId;
  final double lat;
  final double lng;
  final double heading;
  final String? updatedAt;
  final bool isAvailable;

  factory DriverLocation.fromJson(Map<String, dynamic> json) {
    return DriverLocation(
      driverId: json['driver_id']?.toString() ?? '',
      lat: _asNullableDouble(json['lat']) ?? 0,
      lng: _asNullableDouble(json['lng']) ?? 0,
      heading: _asNullableDouble(json['heading']) ?? 0,
      updatedAt: json['updated_at']?.toString(),
      isAvailable:
          json['is_available'] == null ? true : (json['is_available'] as bool),
    );
  }
}
