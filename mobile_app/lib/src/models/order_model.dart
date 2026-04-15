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
    this.assignedDriverId,
    this.estimatedExtraMinutes,
  });

  final String id;
  final String type;
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
  });

  final String type;
  final String address;
  final double lat;
  final double lng;

  Map<String, dynamic> toJson() {
    return {
      'type': type,
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
