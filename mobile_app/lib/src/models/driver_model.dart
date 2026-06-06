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
      isAvailable: json['is_available'] == null ? true : (json['is_available'] as bool),
      company: json['company'] != null
          ? CompanyModel.fromJson(Map<String, dynamic>.from(json['company'] as Map))
          : null,
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
      isAvailable: json['is_available'] == null ? true : (json['is_available'] as bool),
    );
  }
}
