import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../models/order_model.dart';
import '../../../providers/driver_provider.dart';
import '../../../providers/order_provider.dart';
import '../../../providers/route_provider.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_empty_card.dart';
import '../../widgets/app_map_pin_icon.dart';
import '../../widgets/app_metric_pill.dart';
import '../../widgets/order_details_dialog.dart';

class DriverMapScreen extends StatefulWidget {
  const DriverMapScreen({
    super.key,
    this.lastAcceptedExtraMinutes,
    this.onOrderAccepted,
  });

  final double? lastAcceptedExtraMinutes;
  final ValueChanged<double>? onOrderAccepted;

  @override
  State<DriverMapScreen> createState() => _DriverMapScreenState();
}

class _DriverMapScreenState extends State<DriverMapScreen> {
  static const Color _driverColor = AppTheme.secondary;
  static const Color _assignedColor = AppTheme.tertiary;
  static const Color _possibleColor = AppTheme.primary;

  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerOnDriver();
    });
  }

  Future<void> _centerOnDriver() async {
    final driverProv = context.read<DriverProvider>();
    try {
      final position = await driverProv.getCurrentLocation();
      if (position != null && mounted) {
        _mapController.move(
          LatLng(position.latitude, position.longitude),
          14.5,
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error de ubicación: $error')),
      );
    }
  }

  Future<void> _respondToPickup(
    BuildContext context,
    OrderModel order,
    bool accepted,
  ) async {
    final orderProv = context.read<OrderProvider>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      final result = await orderProv.respondToPickup(
        orderId: order.id,
        accepted: accepted,
      );

      if (accepted && result.extraMinutes != null) {
        widget.onOrderAccepted?.call(result.extraMinutes!);
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            accepted
                ? 'Ruta aceptada y planificada.'
                : 'Nueva parada rechazada.',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Error al responder: $error')),
      );
    }
  }

  void _mockCallAction(String orderId) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Llamando al cliente/remitente del pedido #$orderId...')),
    );
  }

  IconData _orderTypeIcon(String type) {
    switch (type) {
      case 'pickup':
        return Icons.inventory_2_rounded;
      case 'delivery':
        return Icons.subdirectory_arrow_right_rounded;
      default:
        return Icons.location_on;
    }
  }

  LatLng _mapCenter(List<LatLng> points) {
    if (points.isEmpty) return const LatLng(40.4168, -3.7038);

    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;

    for (final point in points.skip(1)) {
      minLat = point.latitude < minLat ? point.latitude : minLat;
      maxLat = point.latitude > maxLat ? point.latitude : maxLat;
      minLng = point.longitude < minLng ? point.longitude : minLng;
      maxLng = point.longitude > maxLng ? point.longitude : maxLng;
    }
    return LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
  }

  double _zoomForPoints(List<LatLng> points) {
    if (points.length <= 1) return 13.5;

    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;

    for (final point in points.skip(1)) {
      minLat = point.latitude < minLat ? point.latitude : minLat;
      maxLat = point.latitude > maxLat ? point.latitude : maxLat;
      minLng = point.longitude < minLng ? point.longitude : minLng;
      maxLng = point.longitude > maxLng ? point.longitude : maxLng;
    }

    final span = (maxLat - minLat) > (maxLng - minLng)
        ? (maxLat - minLat)
        : (maxLng - minLng);

    if (span > 15) return 5;
    if (span > 8) return 6;
    if (span > 4) return 7;
    if (span > 2) return 8;
    if (span > 1) return 9;
    if (span > 0.4) return 10;
    if (span > 0.15) return 11;
    return 12.5;
  }

  List<OrderModel> _pendingConfirmationOrders(
    List<OrderModel> orders,
    String userId,
  ) {
    return orders
        .where((o) => o.assignedDriverId == userId && o.status == 'assigned')
        .toList();
  }

  List<OrderModel> _activeRoute(
    List<OrderModel> orders,
    List<OrderModel> routeOrders,
    String userId,
  ) {
    final fromRoute = routeOrders
        .where((o) => o.assignedDriverId == userId && o.status == 'in_progress')
        .toList();

    final activeOutsideRoute = orders
        .where(
          (o) =>
              o.assignedDriverId == userId &&
              o.status == 'in_progress' &&
              !fromRoute.any((r) => r.id == o.id),
        )
        .toList();

    return [...fromRoute, ...activeOutsideRoute];
  }

  @override
  Widget build(BuildContext context) {
    final driverProv = context.watch<DriverProvider>();
    final orderProv = context.watch<OrderProvider>();
    final routeProv = context.watch<RouteProvider>();

    final user = driverProv.user;
    final driverLocation = driverProv.driverLocation;
    final routePlan = driverProv.routePlan;
    final orders = orderProv.orders;
    final routeOrders = driverProv.routeOrders;
    final isLoading = orderProv.isLoading || driverProv.isLoading;

    final pendingOrders = _pendingConfirmationOrders(orders, user.id);
    final activeOrders = _activeRoute(orders, routeOrders, user.id);

    final LatLng? driverPoint = driverLocation == null
        ? null
        : LatLng(driverLocation.lat, driverLocation.lng);

    final allPoints = <LatLng>[
      if (driverPoint != null) driverPoint,
      ...activeOrders.map((o) => LatLng(o.lat, o.lng)),
      ...pendingOrders.map((o) => LatLng(o.lat, o.lng)),
    ];

    final center = _mapCenter(allPoints);
    final zoom = _zoomForPoints(allPoints);

    final routePoints = routePlan == null
        ? const <LatLng>[]
        : routeProv.isSparseRouteGeometry(routePlan)
            ? const <LatLng>[]
            : routePlan.routeGeometry
                .map((p) => LatLng(p.lat, p.lng))
                .toList();

    final polylines = <Polyline>[
      if (routePoints.length >= 2)
        Polyline(
          points: routePoints,
          color: _assignedColor.withValues(alpha: 1.0),
          strokeWidth: 5.0,
        ),
    ];

    final markers = <Marker>[
      if (driverPoint != null)
        Marker(
          point: driverPoint,
          width: 48,
          height: 48,
          child: const AppMapPinIcon(
            icon: Icons.local_shipping,
            color: _driverColor,
          ),
        ),
      for (final entry in activeOrders.asMap().entries)
        Marker(
          point: LatLng(entry.value.lat, entry.value.lng),
          width: 40,
          height: 40,
          child: AppMapPinIcon(
            icon: _orderTypeIcon(entry.value.type),
            color: _assignedColor,
            stopNumber: entry.key + 1,
          ),
        ),
      for (final order in pendingOrders)
        Marker(
          point: LatLng(order.lat, order.lng),
          width: 40,
          height: 40,
          child: AppMapPinIcon(
            icon: _orderTypeIcon(order.type),
            color: _possibleColor.withValues(alpha: 0.55),
          ),
        ),
    ];

    // Determine overlay panel state
    final hasPending = pendingOrders.isNotEmpty;
    final hasActive = activeOrders.isNotEmpty;
    final OrderModel? currentPanelOrder = hasPending
        ? pendingOrders.first
        : (hasActive ? activeOrders.first : null);

    final double bottomOffset = (currentPanelOrder != null) ? 224 : 16;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: zoom,
              maxZoom: 18.0,
              minZoom: 5.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
              ),
              PolylineLayer(polylines: polylines),
              MarkerLayer(markers: markers),
            ],
          ),
          
          // Standard Top summary card (Only show if there are no pending orders, to avoid clutter)
          if (!hasPending && routePlan != null && (routePlan.totalMinutes > 0 || routePlan.totalDistanceKm > 0))
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Card(
                  margin: EdgeInsets.zero,
                  color: Colors.white.withValues(alpha: 0.9),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      alignment: WrapAlignment.spaceEvenly,
                      children: [
                        AppMetricPill(
                          icon: Icons.schedule,
                          label: 'Tiempo est.',
                          value: '${routePlan.totalMinutes.toStringAsFixed(1)} min',
                        ),
                        AppMetricPill(
                          icon: Icons.route,
                          label: 'Distancia',
                          value: '${routePlan.totalDistanceKm.toStringAsFixed(2)} km',
                        ),
                        if (widget.lastAcceptedExtraMinutes != null)
                          AppMetricPill(
                            icon: Icons.add_road,
                            label: 'Último extra',
                            value: '${widget.lastAcceptedExtraMinutes!.toStringAsFixed(1)} min',
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Bottom Floating Overlay Panels
          if (currentPanelOrder != null)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Container(
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Card(
                  margin: EdgeInsets.zero,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: hasPending
                        ? _buildNotificationPanel(context, currentPanelOrder)
                        : _buildActiveDeliveryPanel(context, currentPanelOrder, routePlan, isLoading),
                  ),
                ),
              ),
            ),

          if (allPoints.isEmpty)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.3),
                child: Center(
                  child: AppEmptyCard(
                    message: 'No hay ubicaciones para mostrar en mapa todavía.',
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _centerOnDriver,
        backgroundColor: AppTheme.secondary,
        foregroundColor: Colors.white,
        tooltip: 'Centrar ubicación',
        // Move FAB up dynamically if bottom panel is showing
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          margin: EdgeInsets.only(bottom: bottomOffset > 16 ? 0 : 0),
          child: const Icon(Icons.my_location),
        ),
      ),
      // Set the FAB location based on whether panel is showing
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  // Left Panel Mockup: New Stop Notification
  Widget _buildNotificationPanel(BuildContext context, OrderModel order) {
    final isPickup = order.type == 'pickup';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            showDialog(
              context: context,
              builder: (dialogCtx) => OrderDetailsDialog(
                order: order,
                onNavigate: () => _mapController.move(LatLng(order.lat, order.lng), 15.5),
                onComplete: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await context.read<OrderProvider>().updateOrderStatus(
                      orderId: order.id,
                      status: 'completed',
                      actionLabel: order.type == 'pickup' ? 'recogido' : 'entregado',
                    );
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          order.type == 'pickup'
                              ? '¡Pedido marcado como recogido!'
                              : '¡Pedido marcado como entregado!',
                        ),
                      ),
                    );
                  } catch (e) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('Error al actualizar el pedido: $e')),
                    );
                  }
                },
              ),
            );
          },
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  color: AppTheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPickup ? '¡Nueva Recogida Asignada!' : '¡Nueva Entrega Asignada!',
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2F2E2E),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Se ha añadido una ${isPickup ? "recogida" : "entrega"} de paquete a tu ruta. Acepta para ver los detalles del nuevo punto de parada.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        
        // Accept / Ignore buttons
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 40,
                child: FilledButton(
                  onPressed: () => _respondToPickup(context, order, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF9E3100), // Solid brown-orange
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Aceptar Nueva Ruta',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 40,
              child: FilledButton(
                onPressed: () => _respondToPickup(context, order, false),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFEAE7E7),
                  foregroundColor: const Color(0xFF2F2E2E),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Ignorar',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
        const Divider(height: 24, color: Color(0xFFEAE7E7)),
        
        // Package Info & Distance
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ID DE PAQUETE',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade500,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '#${order.id.substring(0, order.id.length > 8 ? 8 : order.id.length).toUpperCase()}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2F2E2E),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TIEMPO EXTRA',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade500,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    order.estimatedExtraMinutes != null
                        ? '+${order.estimatedExtraMinutes!.toStringAsFixed(1)} Minutos'
                        : 'Calculando...',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2F2E2E),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Navigation and Phone buttons
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: () => _mapController.move(LatLng(order.lat, order.lng), 15.5),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.navigation, size: 18),
                  label: const Text(
                    'Navegar',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => _mockCallAction(order.id),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBCEFF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.phone,
                  color: Color(0xFF343D96),
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Right Panel Mockup: Route progress state
  Widget _buildActiveDeliveryPanel(
    BuildContext context,
    OrderModel order,
    DriverRoutePlan? routePlan,
    bool isLoading,
  ) {
    final isPickup = order.type == 'pickup';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top status row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Status pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF9E3100),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Icon(
                    isLoading ? Icons.sync : Icons.directions_run,
                    color: Colors.white,
                    size: 12,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isLoading ? 'RECALCULANDO RUTA...' : 'EN RUTA',
                    style: const TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            // Time remaining segment pill
            if (routePlan != null && routePlan.totalMinutes > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${routePlan.totalMinutes.round()} MIN',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),

        GestureDetector(
          onTap: () {
            showDialog(
              context: context,
              builder: (dialogCtx) => OrderDetailsDialog(
                order: order,
                onNavigate: () => _mapController.move(LatLng(order.lat, order.lng), 15.5),
                onComplete: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await context.read<OrderProvider>().updateOrderStatus(
                      orderId: order.id,
                      status: 'completed',
                      actionLabel: order.type == 'pickup' ? 'recogido' : 'entregado',
                    );
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          order.type == 'pickup'
                              ? '¡Pedido marcado como recogido!'
                              : '¡Pedido marcado como entregado!',
                        ),
                      ),
                    );
                  } catch (e) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('Error al actualizar el pedido: $e')),
                    );
                  }
                },
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Delivery focus text
              Text(
                isPickup ? 'RECOGIDA ACTUAL' : 'ENTREGA ACTUAL',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                isPickup ? 'Recoger de ${order.name ?? "Proveedor"}' : 'Entregar a ${order.name ?? "Cliente"}',
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2F2E2E),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              
              // Location row
              Row(
                children: [
                  Icon(Icons.place_outlined, size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      order.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 20, color: Color(0xFFEAE7E7)),

        // Package Info & Distance
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ID DE PAQUETE',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade500,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '#${order.id.substring(0, order.id.length > 8 ? 8 : order.id.length).toUpperCase()}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2F2E2E),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DISTANCIA TOTAL',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade500,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    routePlan != null ? '${routePlan.totalDistanceKm.toStringAsFixed(2)} Km' : 'Calculando...',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2F2E2E),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Navigation and Phone buttons
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: () => _mapController.move(LatLng(order.lat, order.lng), 15.5),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.navigation, size: 18),
                  label: const Text(
                    'Navegar',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => _mockCallAction(order.id),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBCEFF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.phone,
                  color: Color(0xFF343D96),
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
