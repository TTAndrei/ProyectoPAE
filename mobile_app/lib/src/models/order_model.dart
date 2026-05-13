double _asDouble(dynamic value, {double fallback = 0.0}) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value) ?? fallback;
  }
  return fallback;
}

class OrderModel {
  const OrderModel({
    required this.id,
    required this.type,
    required this.address,
    required this.lat,
    required this.lng,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.name,
    this.assignedDriverId,
    this.estimatedExtraMinutes,
  });

  final String id;
  final String type;
  final String? name;
  final String address;
  final double lat;
  final double lng;
  final String status;
  final String createdAt;
  final String updatedAt;
  final String? assignedDriverId;
  final double? estimatedExtraMinutes;

  bool get isPending => status == 'pending';
  bool get isAssigned => status == 'assigned';
  bool get isInProgress => status == 'in_progress';
  bool get isCompleted => status == 'completed';

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    return OrderModel(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      name: json['name']?.toString(),
      address: json['address']?.toString() ?? '',
      lat: _asDouble(json['lat']),
      lng: _asDouble(json['lng']),
      status: json['status']?.toString() ?? '',
      assignedDriverId: json['assigned_driver_id']?.toString(),
      estimatedExtraMinutes: json['estimated_extra_minutes'] == null
          ? null
          : _asDouble(json['estimated_extra_minutes']),
      createdAt: json['created_at']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString() ?? '',
    );
  }
}

class CreateOrderInput {
  const CreateOrderInput({
    required this.type,
    required this.address,
    required this.lat,
    required this.lng,
    this.name,
  });

  final String type;
  final String? name;
  final String address;
  final double lat;
  final double lng;

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      if (name != null && name!.isNotEmpty) 'name': name,
      'address': address,
      'lat': lat,
      'lng': lng,
    };
  }
}

class AssignOrderResult {
  const AssignOrderResult({
    required this.order,
    required this.extraMinutes,
  });

  final OrderModel order;
  final double extraMinutes;

  factory AssignOrderResult.fromJson(Map<String, dynamic> json) {
    final rawOrder = json['order'];
    if (rawOrder is! Map) {
      throw const FormatException('Invalid order payload in assign response');
    }
    return AssignOrderResult(
      order: OrderModel.fromJson(Map<String, dynamic>.from(rawOrder)),
      extraMinutes: _asDouble(json['extra_minutes']),
    );
  }
}

class RespondOrderResult {
  const RespondOrderResult({
    required this.order,
    this.extraMinutes,
    this.totalMinutes,
    this.totalDistanceKm,
  });

  final OrderModel order;
  final double? extraMinutes;
  final double? totalMinutes;
  final double? totalDistanceKm;

  factory RespondOrderResult.fromJson(Map<String, dynamic> json) {
    final rawOrder = json['order'];
    if (rawOrder is! Map) {
      throw const FormatException('Invalid order payload in respond response');
    }

    return RespondOrderResult(
      order: OrderModel.fromJson(Map<String, dynamic>.from(rawOrder)),
      extraMinutes: json['extra_minutes'] == null
          ? null
          : _asDouble(json['extra_minutes']),
      totalMinutes: json['total_minutes'] == null
          ? null
          : _asDouble(json['total_minutes']),
      totalDistanceKm: json['total_distance_km'] == null
          ? null
          : _asDouble(json['total_distance_km']),
    );
  }
}

class DriverRoutePlan {
  const DriverRoutePlan({
    required this.orders,
    required this.totalMinutes,
    required this.totalDistanceKm,
    required this.routeGeometry,
    required this.legMinutes,
  });

  final List<OrderModel> orders;
  final double totalMinutes;
  final double totalDistanceKm;
  final List<RoutePoint> routeGeometry;
  final List<double> legMinutes;

  factory DriverRoutePlan.fromJson(Map<String, dynamic> json) {
    final rawOrders = json['orders'];
    final orders = rawOrders is! List
        ? const <OrderModel>[]
        : rawOrders
            .map((raw) =>
                OrderModel.fromJson(Map<String, dynamic>.from(raw as Map)))
            .toList();

    final rawGeometry = json['route_geometry'];
    final geometry = rawGeometry is! List
        ? const <RoutePoint>[]
        : rawGeometry
            .whereType<Map>()
            .map((raw) => RoutePoint.fromJson(Map<String, dynamic>.from(raw)))
            .toList();

    final rawLegs = json['leg_minutes'];
    final legs = rawLegs is! List
        ? const <double>[]
        : rawLegs.map((value) => _asDouble(value)).toList();

    return DriverRoutePlan(
      orders: orders,
      totalMinutes: _asDouble(json['total_minutes']),
      totalDistanceKm: _asDouble(json['total_distance_km']),
      routeGeometry: geometry,
      legMinutes: legs,
    );
  }
}

class RoutePoint {
  const RoutePoint({
    required this.lat,
    required this.lng,
  });

  final double lat;
  final double lng;

  factory RoutePoint.fromJson(Map<String, dynamic> json) {
    return RoutePoint(
      lat: _asDouble(json['lat']),
      lng: _asDouble(json['lng']),
    );
  }
}
