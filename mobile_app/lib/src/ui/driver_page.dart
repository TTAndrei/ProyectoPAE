import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/driver_model.dart';
import '../models/order_model.dart';
import '../providers/driver_provider.dart';
import '../providers/order_provider.dart';
import '../providers/route_provider.dart';
import '../theme/app_theme.dart';
import 'widgets/app_button.dart';
import 'widgets/app_section_title.dart';
import 'widgets/app_empty_card.dart';
import 'widgets/app_map_pin_icon.dart';
import 'widgets/app_legend_items.dart';
import 'widgets/app_status_chip.dart';
import 'widgets/app_metric_pill.dart';

class DriverPage extends StatefulWidget {
  const DriverPage({super.key});

  @override
  State<DriverPage> createState() => _DriverPageState();
}

class _DriverPageState extends State<DriverPage> {
  static const Color _driverColor = AppTheme.secondary;
  static const Color _assignedColor = AppTheme.tertiary;
  static const Color _possibleColor = AppTheme.primary;

  final MapController _mapController = MapController();

  double? _lastAcceptedExtraMinutes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _getCurrentLocation();
    });
  }

  // ── Helpers (pure UI) ────────────────────────────────────────────

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

  String _orderTypeLabel(String type) {
    switch (type) {
      case 'pickup':
        return 'Pickup';
      case 'delivery':
        return 'Delivery';
      default:
        return type;
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
    if (points.length <= 1) return 13;

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

  // ── Actions ──────────────────────────────────────────────────────

  Future<void> _respondToPickup(OrderModel order, bool accepted) async {
    final orderProv = context.read<OrderProvider>();

    try {
      final result = await orderProv.respondToPickup(
        orderId: order.id,
        accepted: accepted,
      );

      if (accepted) {
        setState(() {
          _lastAcceptedExtraMinutes = result.extraMinutes;
        });
      }

      if (!mounted) return;

      final extraText = result.extraMinutes == null
          ? ''
          : ' Extra: ${result.extraMinutes!.toStringAsFixed(1)} min.';
      final totalText = result.totalMinutes == null
          ? ''
          : ' Ruta total: ${result.totalMinutes!.toStringAsFixed(1)} min.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accepted
                ? 'Pedido aceptado.$extraText$totalText'
                : 'Pedido rechazado.$totalText',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al responder: $error')),
      );
    }
  }

  Future<void> _completeOrder(OrderModel order) async {
    final orderProv = context.read<OrderProvider>();
    try {
      await orderProv.updateOrderStatus(
        orderId: order.id,
        status: 'completed',
        actionLabel: 'completado',
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al actualizar pedido: $error')),
      );
    }
  }

  Future<void> _getCurrentLocation() async {
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

  // ── Computed lists from providers ────────────────────────────────

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

  // ── Map card ─────────────────────────────────────────────────────

  Widget _buildDriverMapCard({
    required DriverLocation? driverLocation,
    required DriverRoutePlan? routePlan,
    required List<OrderModel> pendingOrders,
    required List<OrderModel> activeOrders,
    required RouteProvider routeProv,
  }) {
    final LatLng? driverPoint = driverLocation == null
        ? null
        : LatLng(driverLocation.lat, driverLocation.lng);

    final allPoints = <LatLng>[
      if (driverPoint != null) driverPoint,
      ...activeOrders.map((o) => LatLng(o.lat, o.lng)),
      ...pendingOrders.map((o) => LatLng(o.lat, o.lng)),
    ];

    if (allPoints.isEmpty) {
      return const AppEmptyCard(
        message: 'No hay ubicaciones para mostrar en mapa todavia.',
      );
    }

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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 320,
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: zoom,
                    minZoom: 3,
                    maxZoom: 18,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.pae.mobile',
                    ),
                    if (polylines.isNotEmpty)
                      PolylineLayer(polylines: polylines),
                    MarkerLayer(markers: markers),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 8,
              children: const [
                AppLegendItem(label: 'Mi ubicacion', color: _driverColor),
                AppLegendItem(
                    label: 'Pedidos asignados', color: _assignedColor),
                AppLegendItem(
                    label: 'Pedidos posibles', color: _possibleColor),
                AppOrderTypeLegendItem(
                  icon: Icons.inventory_2_rounded,
                  label: 'Pickup',
                ),
                AppOrderTypeLegendItem(
                  icon: Icons.subdirectory_arrow_right_rounded,
                  label: 'Delivery',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteMetricsCard(DriverRoutePlan? routePlan) {
    final totalMinutes = routePlan?.totalMinutes ?? 0.0;
    final totalDistance = routePlan?.totalDistanceKm ?? 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            AppMetricPill(
              icon: Icons.schedule,
              label: 'Tiempo total estimado',
              value: '${totalMinutes.toStringAsFixed(1)} min',
            ),
            AppMetricPill(
              icon: Icons.route,
              label: 'Distancia estimada',
              value: '${totalDistance.toStringAsFixed(2)} km',
            ),
            if (_lastAcceptedExtraMinutes != null)
              AppMetricPill(
                icon: Icons.add_road,
                label: 'Ultimo pedido aceptado añadió',
                value:
                    '${_lastAcceptedExtraMinutes!.toStringAsFixed(1)} min',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersColumns({
    required List<OrderModel> pendingOrders,
    required List<OrderModel> activeOrders,
    required bool isLoading,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final targetWidth =
              constraints.maxWidth < 820 ? 820.0 : constraints.maxWidth;

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: targetWidth,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _OrderColumn(
                      title: 'Por confirmar',
                      count: pendingOrders.length,
                      children: pendingOrders.isEmpty
                          ? const [
                              AppEmptyCard(
                                message:
                                    'No hay pedidos asignados pendientes de confirmacion',
                              ),
                            ]
                          : pendingOrders
                              .asMap()
                              .entries
                              .map((entry) => _buildAssignedOrderCard(
                                  entry.key + 1, entry.value, isLoading))
                              .toList(),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _OrderColumn(
                      title: 'En curso',
                      count: activeOrders.length,
                      children: activeOrders.isEmpty
                          ? const [
                              AppEmptyCard(
                                  message: 'No hay pedidos en curso'),
                            ]
                          : activeOrders
                              .asMap()
                              .entries
                              .map((entry) => _buildAssignedOrderCard(
                                  entry.key + 1, entry.value, isLoading))
                              .toList(),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAssignedOrderCard(int index, OrderModel order, bool isLoading) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: AppTheme.secondary.withValues(alpha: 0.1),
                  child: Text(
                    index.toString(),
                    style: const TextStyle(
                      color: AppTheme.secondary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (order.name != null)
                        Text(
                          order.name!,
                          style:
                              const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      Text(
                        order.address,
                        style: TextStyle(
                          fontWeight: order.name != null
                              ? FontWeight.w400
                              : FontWeight.w600,
                          fontSize: order.name != null ? 12 : 14,
                        ),
                      ),
                    ],
                  ),
                ),
                AppStatusChip(status: order.status),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(_orderTypeIcon(order.type), size: 18, color: AppTheme.tertiary),
                const SizedBox(width: 6),
                Text('${_orderTypeLabel(order.type)} - ${order.id}'),
              ],
            ),
            if (order.estimatedExtraMinutes != null) ...[
              const SizedBox(height: 6),
              Text(
                'Extra estimado: ${order.estimatedExtraMinutes!.toStringAsFixed(1)} min',
              ),
            ],
            const SizedBox(height: 12),
            if (order.status == 'assigned')
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      onPressed: isLoading
                          ? null
                          : () => _respondToPickup(order, false),
                      icon: Icons.close,
                      text: 'Rechazar',
                      variant: AppButtonVariant.outlined,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppButton(
                      onPressed: isLoading
                          ? null
                          : () => _respondToPickup(order, true),
                      icon: Icons.check,
                      text: 'Aceptar',
                    ),
                  ),
                ],
              ),
            if (order.status == 'in_progress')
              SizedBox(
                width: double.infinity,
                child: AppButton(
                  onPressed:
                      isLoading ? null : () => _completeOrder(order),
                  text: 'Completar parada',
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────

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
    final events = driverProv.events;
    final isLoading = orderProv.isLoading || driverProv.isLoading;
    final error = driverProv.error ?? orderProv.error;

    final pendingOrders = _pendingConfirmationOrders(orders, user.id);
    final activeOrders = _activeRoute(orders, routeOrders, user.id);

    if (isLoading && orders.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null && orders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('No se pudo cargar la informacion\n$error'),
              const SizedBox(height: 12),
              AppButton(
                onPressed: () {
                  driverProv.loadData();
                  orderProv.loadOrders();
                },
                text: 'Reintentar',
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          driverProv.loadData(),
          orderProv.loadOrders(),
        ]);
      },
      child: ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        children: [
          const AppSectionTitle(title: 'Mapa operativo', trailing: ''),
          _buildDriverMapCard(
            driverLocation: driverLocation,
            routePlan: routePlan,
            pendingOrders: pendingOrders,
            activeOrders: activeOrders,
            routeProv: routeProv,
          ),
          const AppSectionTitle(
              title: 'Estimacion de ruta', trailing: ''),
          _buildRouteMetricsCard(routePlan),
          const AppSectionTitle(title: 'Ubicación real', trailing: ''),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.place, color: _assignedColor),
                      const SizedBox(width: 8),
                      Text(
                        driverLocation != null
                            ? 'Última ubicación: ${driverLocation.lat.toStringAsFixed(6)}, ${driverLocation.lng.toStringAsFixed(6)}'
                            : 'Ubicación no obtenida todavía',
                        style:
                            const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  if (driverLocation != null &&
                      driverLocation.updatedAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Actualizado: ${driverLocation.updatedAt!.length >= 19 ? driverLocation.updatedAt!.substring(11, 19) : driverLocation.updatedAt}',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const AppSectionTitle(
            title: 'Pedidos en columnas',
            trailing: '',
          ),
          _buildOrdersColumns(
            pendingOrders: pendingOrders,
            activeOrders: activeOrders,
            isLoading: isLoading,
          ),
          AppSectionTitle(
            title: 'Eventos tiempo real',
            trailing: '${events.length}',
          ),
          if (events.isEmpty)
            const AppEmptyCard(message: 'Sin eventos recientes')
          else
            ...events.map(
              (event) => Card(
                child: ListTile(
                  dense: true,
                  title: Text(event),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OrderColumn extends StatelessWidget {
  const _OrderColumn({
    required this.title,
    required this.count,
    required this.children,
  });

  final String title;
  final int count;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('$count'),
              ),
            ],
          ),
        ),
        ...children,
      ],
    );
  }
}
