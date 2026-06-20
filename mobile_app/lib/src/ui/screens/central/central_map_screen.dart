import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../../models/driver_model.dart';
import '../../../providers/central_provider.dart';
import '../../../providers/order_provider.dart';
import '../../../providers/route_provider.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/app_empty_card.dart';
import '../../widgets/app_map_pin_icon.dart';
import '../../widgets/app_legend_items.dart';

class CentralMapScreen extends StatefulWidget {
  const CentralMapScreen({super.key});

  @override
  State<CentralMapScreen> createState() => _CentralMapScreenState();
}

class _CentralMapScreenState extends State<CentralMapScreen> {
  String? _selectedDriverId;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _centerMapOnVisiblePoints();
  }

  void _centerMapOnVisiblePoints() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final centralProv = context.read<CentralProvider>();
      final orderProv = context.read<OrderProvider>();
      final routeProv = context.read<RouteProvider>();

      final drivers = centralProv.drivers;
      final activeAssignedOrders = orderProv.activeAssignedOrders;
      final routePlansByDriver = orderProv.routePlansByDriver;
      final selectedDriverId = drivers.any((d) => d.id == _selectedDriverId) ? _selectedDriverId : null;

      final driversWithLocation = drivers.where((d) => d.lat != null && d.lng != null).toList();
      final visibleDrivers = selectedDriverId == null
          ? driversWithLocation
          : driversWithLocation.where((d) => d.id == selectedDriverId).toList();
      final visibleOrders = selectedDriverId == null
          ? activeAssignedOrders
          : activeAssignedOrders.where((order) => order.assignedDriverId == selectedDriverId).toList();
      final visibleRoutePlans = selectedDriverId == null
          ? routePlansByDriver
          : Map.fromEntries(
              routePlansByDriver.entries.where((entry) => entry.key == selectedDriverId),
            );

      final pts = <LatLng>[
        for (final driver in visibleDrivers) LatLng(driver.lat!, driver.lng!),
        for (final order in visibleOrders) LatLng(order.lat, order.lng),
        for (final plan in visibleRoutePlans.values)
          if (!routeProv.isSparseRouteGeometry(plan))
            ...plan.routeGeometry.map((point) => LatLng(point.lat, point.lng)),
      ];

      if (pts.isNotEmpty) {
        final center = _mapCenter(pts);
        final zoom = _zoomForPoints(pts);
        _mapController.move(center, zoom);
      }
    });
  }

  static const List<Color> _driverPalette = [
    AppTheme.secondary,
    AppTheme.tertiary,
    Color(0xFF0D9488),
    Color(0xFF2563EB),
    Color(0xFFD97706),
    Color(0xFFE11D48),
    Color(0xFF4F46E5),
    Color(0xFF16A34A),
  ];

  Map<String, Color> _driverColors(List<DriverModel> drivers) {
    final ids = drivers.map((d) => d.id).toList()..sort();
    final map = <String, Color>{};
    for (var i = 0; i < ids.length; i++) {
      map[ids[i]] = _driverPalette[i % _driverPalette.length];
    }
    return map;
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
    if (points.isEmpty) {
      return const LatLng(41.6260, 2.6900); // Centered in Pineda de Mar
    }

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
    return 13.5;
  }

  void _selectDriver(String driverId) {
    setState(() {
      _selectedDriverId = _selectedDriverId == driverId ? null : driverId;
    });
    _centerMapOnVisiblePoints();
  }

  void _showAllDrivers() {
    setState(() {
      _selectedDriverId = null;
    });
    _centerMapOnVisiblePoints();
  }

  @override
  Widget build(BuildContext context) {
    final centralProv = context.watch<CentralProvider>();
    final orderProv = context.watch<OrderProvider>();
    final routeProv = context.watch<RouteProvider>();

    final drivers = centralProv.drivers;
    final activeAssignedOrders = orderProv.activeAssignedOrders;
    final routePlansByDriver = orderProv.routePlansByDriver;
    final driverColors = _driverColors(drivers);
    final selectedDriverId =
        drivers.any((driver) => driver.id == _selectedDriverId)
            ? _selectedDriverId
            : null;

    final driversWithLocation =
        drivers.where((d) => d.lat != null && d.lng != null).toList();
    final visibleDrivers = selectedDriverId == null
        ? driversWithLocation
        : driversWithLocation.where((d) => d.id == selectedDriverId).toList();
    final visibleOrders = selectedDriverId == null
        ? activeAssignedOrders
        : activeAssignedOrders
            .where((order) => order.assignedDriverId == selectedDriverId)
            .toList();
    final visibleRoutePlans = selectedDriverId == null
        ? routePlansByDriver
        : Map.fromEntries(
            routePlansByDriver.entries
                .where((entry) => entry.key == selectedDriverId),
          );

    final points = <LatLng>[
      for (final driver in visibleDrivers) LatLng(driver.lat!, driver.lng!),
      for (final order in visibleOrders) LatLng(order.lat, order.lng),
      for (final plan in visibleRoutePlans.values)
        if (!routeProv.isSparseRouteGeometry(plan))
          ...plan.routeGeometry.map((point) => LatLng(point.lat, point.lng)),
    ];

    final polylines = <Polyline>[];
    for (final driver in visibleDrivers) {
      final color = driverColors[driver.id] ?? _driverPalette.first;
      final plan = routePlansByDriver[driver.id];
      if (plan == null || routeProv.isSparseRouteGeometry(plan)) continue;

      final routePoints =
          plan.routeGeometry.map((p) => LatLng(p.lat, p.lng)).toList();
      if (routePoints.length < 2) continue;

      polylines.add(
        Polyline(
          points: routePoints,
          color: color.withValues(alpha: 1.0),
          strokeWidth: 4.5,
        ),
      );
    }

    final markers = <Marker>[
      for (final driver in visibleDrivers)
        Marker(
          point: LatLng(driver.lat!, driver.lng!),
          width: 48,
          height: 48,
          child: AppMapPinIcon(
            icon: Icons.local_shipping,
            color: driverColors[driver.id] ?? _driverPalette.first,
          ),
        ),
      for (final order in visibleOrders)
        Marker(
          point: LatLng(order.lat, order.lng),
          width: 40,
          height: 40,
          child: AppMapPinIcon(
            icon: _orderTypeIcon(order.type),
            color:
                (driverColors[order.assignedDriverId] ?? _driverPalette.first)
                    .withValues(alpha: 0.8),
          ),
        ),
    ];

    final center = _mapCenter(points);
    final zoom = _zoomForPoints(points);

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Monitorización de Flota',
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.secondary),
              ),
              SizedBox(height: 4),
              Text('Posicionamiento GPS y rutas activas en tiempo real',
                  style: TextStyle(color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Card(
              color: Colors.white,
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  if (points.isEmpty)
                    AppEmptyCard(
                      message:
                          'No hay ubicaciones de conductores/pedidos para mostrar en mapa.',
                    )
                  else
                    FlutterMap(
                      mapController: _mapController,
                      key: const ValueKey('central-map'),
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

                  // Map Legend overlay
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: Card(
                      color: Colors.white.withValues(alpha: 0.92),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Wrap(
                          spacing: 16,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: selectedDriverId == null
                                  ? null
                                  : _showAllDrivers,
                              icon: const Icon(Icons.public_rounded, size: 18),
                              label: const Text('Vista general'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.secondary,
                                disabledForegroundColor: AppTheme.secondary,
                                backgroundColor: selectedDriverId == null
                                    ? AppTheme.secondary.withValues(alpha: 0.08)
                                    : Colors.white,
                                side: BorderSide(
                                  color: selectedDriverId == null
                                      ? AppTheme.secondary
                                      : AppTheme.secondary
                                          .withValues(alpha: 0.28),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 15),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                            ...drivers.map((driver) {
                              final count = activeAssignedOrders
                                  .where((o) => o.assignedDriverId == driver.id)
                                  .length;
                              final color = driverColors[driver.id] ??
                                  _driverPalette.first;
                              return AppDriverLegendItem(
                                color: color,
                                label: driver.name,
                                detail: '$count pedidos',
                                isSelected: selectedDriverId == driver.id,
                                onTap: () => _selectDriver(driver.id),
                              );
                            }),
                            const AppOrderTypeLegendItem(
                              icon: Icons.inventory_2_rounded,
                              label: 'Pickup',
                            ),
                            const AppOrderTypeLegendItem(
                              icon: Icons.subdirectory_arrow_right_rounded,
                              label: 'Delivery',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
