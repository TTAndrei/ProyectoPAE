import 'dart:convert';

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
    this.incoterm,
    this.origen,
    this.destino,
    this.tipoBulto,
    this.dimensiones,
    this.peso,
    this.esAdr = false,
    this.adrTipo,
    this.adrCodigoUn,
    this.clienteNombre,
    this.clienteContacto,
    this.destinatarioNombre,
    this.destinatarioContacto,
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
  final String? incoterm;
  final String? origen;
  final String? destino;
  final String? tipoBulto;
  final String? dimensiones;
  final double? peso;
  final bool esAdr;
  final String? adrTipo;
  final String? adrCodigoUn;
  final String? clienteNombre;
  final String? clienteContacto;
  final String? destinatarioNombre;
  final String? destinatarioContacto;

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
      incoterm: json['incoterm']?.toString(),
      origen: json['origen']?.toString(),
      destino: json['destino']?.toString(),
      tipoBulto: json['tipo_bulto']?.toString(),
      dimensiones: json['dimensiones']?.toString(),
      peso: json['peso'] == null ? null : _asDouble(json['peso']),
      esAdr: json['es_adr'] == true,
      adrTipo: json['adr_tipo']?.toString(),
      adrCodigoUn: json['adr_codigo_un']?.toString(),
      clienteNombre: json['cliente_nombre']?.toString(),
      clienteContacto: json['cliente_contacto']?.toString(),
      destinatarioNombre: json['destinatario_nombre']?.toString(),
      destinatarioContacto: json['destinatario_contacto']?.toString(),
    );
  }
}

class CreateOrderInput {
  const CreateOrderInput({
    required this.type,
    required this.address,
    required this.lat,
    required this.lng,
    this.driverId,
    this.name,
    this.incoterm,
    this.origen,
    this.destino,
    this.tipoBulto,
    this.dimensiones,
    this.peso,
    this.esAdr = false,
    this.adrTipo,
    this.adrCodigoUn,
    this.clienteNombre,
    this.clienteContacto,
    this.destinatarioNombre,
    this.destinatarioContacto,
  });

  final String type;
  final String? name;
  final String? driverId;
  final String address;
  final double lat;
  final double lng;
  final String? incoterm;
  final String? origen;
  final String? destino;
  final String? tipoBulto;
  final String? dimensiones;
  final double? peso;
  final bool esAdr;
  final String? adrTipo;
  final String? adrCodigoUn;
  final String? clienteNombre;
  final String? clienteContacto;
  final String? destinatarioNombre;
  final String? destinatarioContacto;

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      if (name != null && name!.isNotEmpty) 'name': name,
      if (driverId != null && driverId!.isNotEmpty) 'driver_id': driverId,
      'address': address,
      'lat': lat,
      'lng': lng,
      if (incoterm != null && incoterm!.isNotEmpty) 'incoterm': incoterm,
      if (origen != null && origen!.isNotEmpty) 'origen': origen,
      if (destino != null && destino!.isNotEmpty) 'destino': destino,
      if (tipoBulto != null && tipoBulto!.isNotEmpty) 'tipo_bulto': tipoBulto,
      if (dimensiones != null && dimensiones!.isNotEmpty)
        'dimensiones': dimensiones,
      if (peso != null) 'peso': peso,
      'es_adr': esAdr,
      if (adrTipo != null && adrTipo!.isNotEmpty) 'adr_tipo': adrTipo,
      if (adrCodigoUn != null && adrCodigoUn!.isNotEmpty)
        'adr_codigo_un': adrCodigoUn,
      if (clienteNombre != null && clienteNombre!.isNotEmpty)
        'cliente_nombre': clienteNombre,
      if (clienteContacto != null && clienteContacto!.isNotEmpty)
        'cliente_contacto': clienteContacto,
      if (destinatarioNombre != null && destinatarioNombre!.isNotEmpty)
        'destinatario_nombre': destinatarioNombre,
      if (destinatarioContacto != null && destinatarioContacto!.isNotEmpty)
        'destinatario_contacto': destinatarioContacto,
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
    List<RoutePoint> geometry;
    if (rawGeometry is String) {
      // Backend persists geometry as json.dumps() string in Neo4j;
      // parse it back to a list on the Flutter side.
      try {
        final decoded = jsonDecode(rawGeometry);
        geometry = decoded is List
            ? decoded
                .whereType<Map>()
                .map((raw) =>
                    RoutePoint.fromJson(Map<String, dynamic>.from(raw)))
                .toList()
            : const <RoutePoint>[];
      } catch (_) {
        geometry = const <RoutePoint>[];
      }
    } else if (rawGeometry is List) {
      geometry = rawGeometry
          .whereType<Map>()
          .map((raw) => RoutePoint.fromJson(Map<String, dynamic>.from(raw)))
          .toList();
    } else {
      geometry = const <RoutePoint>[];
    }

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
