import 'driver_model.dart';
import 'order_model.dart';

class SimulationStatus {
  const SimulationStatus({
    required this.id,
    required this.status,
    required this.currentIndex,
    required this.totalStops,
    required this.driverId,
    this.currentStop,
    this.startedAt,
    this.finishedAt,
    this.error,
    this.comparison,
    this.events = const [],
    required this.kpis,
  });

  final String id;
  final String status;
  final int currentIndex;
  final int totalStops;
  final String driverId;
  final OrderModel? currentStop;
  final String? startedAt;
  final String? finishedAt;
  final String? error;
  final SimulationComparison? comparison;
  final List<SimulationEvent> events;
  final DriverKpiModel kpis;

  bool get isRunning => status == 'running';
  bool get isCompleted => status == 'completed';
  bool get isIdle => status == 'idle';
  bool get isFailed => status == 'failed';

  double get progressValue {
    if (totalStops <= 0) return 0.0;
    return (currentIndex / totalStops).clamp(0.0, 1.0).toDouble();
  }

  String get progressLabel => '$currentIndex/$totalStops';

  String get statusLabel {
    switch (status) {
      case 'running':
        return 'En curso';
      case 'completed':
        return 'Completada';
      case 'failed':
        return 'Fallida';
      default:
        return 'Inactiva';
    }
  }

  factory SimulationStatus.fromJson(Map<String, dynamic> json) {
    final currentStopRaw = json['current_stop'];
    return SimulationStatus(
      id: json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'idle',
      currentIndex: (json['current_index'] as num?)?.toInt() ?? 0,
      totalStops: (json['total_stops'] as num?)?.toInt() ?? 20,
      driverId: json['driver_id']?.toString() ?? 'driver-demo',
      currentStop: currentStopRaw is Map
          ? OrderModel.fromJson(Map<String, dynamic>.from(currentStopRaw))
          : null,
      startedAt: json['started_at']?.toString(),
      finishedAt: json['finished_at']?.toString(),
      error: json['error']?.toString(),
      comparison: json['comparison'] is Map
          ? SimulationComparison.fromJson(
              Map<String, dynamic>.from(json['comparison'] as Map),
            )
          : null,
      events: (json['events'] as List? ?? const [])
          .whereType<Map>()
          .map((raw) => SimulationEvent.fromJson(
                Map<String, dynamic>.from(raw),
              ))
          .toList(),
      kpis: DriverKpiModel.fromJson(
        Map<String, dynamic>.from((json['kpis'] as Map?) ?? const {}),
      ),
    );
  }
}

class SimulationComparison {
  const SimulationComparison({
    required this.dynamicDistanceKm,
    required this.fifoDistanceKm,
    required this.savingsKm,
    required this.savingsPercent,
    required this.dynamicOrderIds,
    required this.fifoOrderIds,
    required this.completedOrderCount,
    required this.activeOrderCount,
  });

  final double dynamicDistanceKm;
  final double fifoDistanceKm;
  final double savingsKm;
  final double savingsPercent;
  final List<String> dynamicOrderIds;
  final List<String> fifoOrderIds;
  final int completedOrderCount;
  final int activeOrderCount;

  factory SimulationComparison.fromJson(Map<String, dynamic> json) {
    double asDouble(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    return SimulationComparison(
      dynamicDistanceKm: asDouble(json['dynamic_distance_km']),
      fifoDistanceKm: asDouble(json['fifo_distance_km']),
      savingsKm: asDouble(json['savings_km']),
      savingsPercent: asDouble(json['savings_percent']),
      dynamicOrderIds: (json['dynamic_order_ids'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(),
      fifoOrderIds: (json['fifo_order_ids'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(),
      completedOrderCount:
          (json['completed_order_count'] as num?)?.toInt() ?? 0,
      activeOrderCount: (json['active_order_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class SimulationEvent {
  const SimulationEvent({
    required this.type,
    required this.orderId,
    required this.message,
    this.previousOrderIds = const [],
    this.newOrderIds = const [],
    this.createdAt,
  });

  final String type;
  final String orderId;
  final String message;
  final List<String> previousOrderIds;
  final List<String> newOrderIds;
  final String? createdAt;

  factory SimulationEvent.fromJson(Map<String, dynamic> json) {
    return SimulationEvent(
      type: json['type']?.toString() ?? '',
      orderId: json['order_id']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      previousOrderIds: (json['previous_order_ids'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(),
      newOrderIds: (json['new_order_ids'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(),
      createdAt: json['created_at']?.toString(),
    );
  }
}
