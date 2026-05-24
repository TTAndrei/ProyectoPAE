import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../models/driver_model.dart';
import '../../models/order_model.dart';
import '../../providers/driver_provider.dart';
import '../../providers/order_provider.dart';
import '../../providers/route_provider.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import '../widgets/app_button.dart';
import '../widgets/app_section_title.dart';
import '../widgets/app_empty_card.dart';
import '../widgets/app_map_pin_icon.dart';
import '../widgets/app_legend_items.dart';

class CentralPage extends StatefulWidget {
  const CentralPage({super.key});

  @override
  State<CentralPage> createState() => _CentralPageState();
}

class _CentralPageState extends State<CentralPage> {
  static const List<Color> _driverPalette = [
    AppTheme.secondary, // Brand deep indigo
    AppTheme.tertiary,  // Brand purple/lavender
    Color(0xFF0D9488),  // Modern teal
    Color(0xFF2563EB),  // Vibrant blue
    Color(0xFFD97706),  // Amber
    Color(0xFFE11D48),  // Rose
    Color(0xFF4F46E5),  // Indigo purple
    Color(0xFF16A34A),  // Green
  ];

  final Map<String, String> _selectedDriverByOrder = <String, String>{};

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

  Map<String, Color> _driverColors(List<DriverModel> drivers) {
    final ids = drivers.map((d) => d.id).toList()..sort();
    final map = <String, Color>{};
    for (var i = 0; i < ids.length; i++) {
      map[ids[i]] = _driverPalette[i % _driverPalette.length];
    }
    return map;
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
    if (points.length <= 1) return 12;

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

  Future<void> _assignOrder(OrderModel order) async {
    final driverProv = context.read<DriverProvider>();
    final orderProv = context.read<OrderProvider>();
    final drivers = driverProv.drivers;

    if (drivers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay repartidores disponibles')),
      );
      return;
    }

    final driverId = _selectedDriverByOrder[order.id] ?? drivers.first.id;

    try {
      final result = await orderProv.assignOrder(
        orderId: order.id,
        driverId: driverId,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pedido asignado. Tiempo extra: ${result.extraMinutes.toStringAsFixed(1)} min',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al asignar: $error')),
      );
    }
  }

  Future<void> _openCreateOrderDialog() async {
    final orderProv = context.read<OrderProvider>();

    final draft = await showDialog<_CreateOrderDraft>(
      context: context,
      builder: (_) => const _CreateOrderDialog(),
    );
    if (draft == null) return;

    try {
      final candidates = await orderProv.geocodeAddressCandidates(
        address: draft.address,
      );

      if (!mounted) return;

      GeocodeCandidate selectedCandidate;
      if (candidates.length == 1) {
        selectedCandidate = candidates.first;
      } else {
        final selected = await _openGeocodeCandidateDialog(
          address: draft.address,
          candidates: candidates,
        );
        if (!mounted || selected == null) return;
        selectedCandidate = selected;
      }

      await orderProv.createOrder(
        type: draft.type,
        name: draft.name,
        address: draft.address,
        lat: selectedCandidate.lat,
        lng: selectedCandidate.lng,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pedido creado correctamente')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al crear pedido: $error')),
      );
    }
  }

  Future<GeocodeCandidate?> _openGeocodeCandidateDialog({
    required String address,
    required List<GeocodeCandidate> candidates,
  }) async {
    return showDialog<GeocodeCandidate>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Direccion ambigua'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Se encontraron varias coincidencias para:',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.black.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  address,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                const Text('Toca la ubicacion correcta:'),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: candidates.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, index) {
                      final candidate = candidates[index];
                      return Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: const Icon(Icons.place_outlined),
                          title: Text(candidate.label),
                          subtitle: Text(
                            '${candidate.lat.toStringAsFixed(5)}, ${candidate.lng.toStringAsFixed(5)}',
                          ),
                          onTap: () {
                            Navigator.of(dialogContext).pop(candidate);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );
  }

  // ── Map card ─────────────────────────────────────────────────────

  Widget _buildCentralMapCard({
    required List<DriverModel> drivers,
    required List<OrderModel> activeAssignedOrders,
    required Map<String, DriverRoutePlan> routePlansByDriver,
    required Map<String, Color> driverColors,
    required RouteProvider routeProv,
  }) {
    final driversWithLocation =
        drivers.where((d) => d.lat != null && d.lng != null).toList();

    final points = <LatLng>[
      for (final driver in driversWithLocation)
        LatLng(driver.lat!, driver.lng!),
      for (final order in activeAssignedOrders) LatLng(order.lat, order.lng),
      for (final plan in routePlansByDriver.values)
        if (!routeProv.isSparseRouteGeometry(plan))
          ...plan.routeGeometry
              .map((point) => LatLng(point.lat, point.lng)),
    ];

    if (points.isEmpty) {
      return AppEmptyCard(
        message:
            'No hay ubicaciones de conductores/pedidos para mostrar en mapa.',
      );
    }

    final center = _mapCenter(points);
    final zoom = _zoomForPoints(points);

    final polylines = <Polyline>[];
    for (final driver in driversWithLocation) {
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
          strokeWidth: 5.0,
        ),
      );
    }

    final markers = <Marker>[
      for (final driver in driversWithLocation)
        Marker(
          point: LatLng(driver.lat!, driver.lng!),
          width: 50,
          height: 50,
          child: AppMapPinIcon(
            icon: Icons.local_shipping,
            color: driverColors[driver.id] ?? _driverPalette.first,
          ),
        ),
      for (final order in activeAssignedOrders)
        Marker(
          point: LatLng(order.lat, order.lng),
          width: 42,
          height: 42,
          child: AppMapPinIcon(
            icon: _orderTypeIcon(order.type),
            color: (driverColors[order.assignedDriverId] ??
                    _driverPalette.first)
                .withValues(alpha: 0.7),
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
                height: 360,
                child: FlutterMap(
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
              children: [
                ...drivers.map((driver) {
                  final count = activeAssignedOrders
                      .where((o) => o.assignedDriverId == driver.id)
                      .length;
                  final color =
                      driverColors[driver.id] ?? _driverPalette.first;
                  return AppDriverLegendItem(
                    color: color,
                    label: driver.name,
                    detail: '$count pedidos activos',
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
          ],
        ),
      ),
    );
  }

  // ── Pending order card ───────────────────────────────────────────

  Widget _buildPendingOrderCard(
    OrderModel order,
    List<DriverModel> drivers,
    bool isLoading,
  ) {
    final defaultDriver = drivers.isNotEmpty ? drivers.first.id : null;
    final selectedDriverId =
        _selectedDriverByOrder[order.id] ?? defaultDriver;
    if (selectedDriverId != null &&
        !_selectedDriverByOrder.containsKey(order.id)) {
      _selectedDriverByOrder[order.id] = selectedDriverId;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_orderTypeIcon(order.type), color: AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    order.address,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('${_orderTypeLabel(order.type)} - ${order.id}'),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedDriverId,
              decoration: const InputDecoration(
                labelText: 'Asignar a',
                border: OutlineInputBorder(),
              ),
              items: drivers
                  .map(
                    (driver) => DropdownMenuItem<String>(
                      value: driver.id,
                      child: Text(driver.name),
                    ),
                  )
                  .toList(),
              onChanged: drivers.isEmpty
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() {
                        _selectedDriverByOrder[order.id] = value;
                      });
                    },
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: AppButton(
                onPressed:
                    isLoading ? null : () => _assignOrder(order),
                text: 'Asignar pedido',
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
    final orderProv = context.watch<OrderProvider>();
    final driverProv = context.watch<DriverProvider>();
    final routeProv = context.watch<RouteProvider>();

    final drivers = driverProv.drivers;
    final orders = orderProv.orders;
    final pendingOrders = orderProv.pendingOrders;
    final activeOrders = orderProv.activeOrders;
    final activeAssignedOrders = orderProv.activeAssignedOrders;
    final routePlansByDriver = orderProv.routePlansByDriver;
    final events = orderProv.events;
    final isLoading = orderProv.isLoading;
    final error = orderProv.error;
    final driverColors = _driverColors(drivers);

    if (isLoading && orders.isEmpty && drivers.isEmpty) {
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
                onPressed: () => orderProv.loadOrders(),
                text: 'Reintentar',
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => orderProv.loadOrders(),
      child: ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                AppButton(
                  onPressed: isLoading ? null : _openCreateOrderDialog,
                  icon: Icons.add,
                  text: 'Crear pedido',
                ),
                AppButton(
                  onPressed: isLoading ? null : () => orderProv.loadOrders(),
                  icon: Icons.refresh,
                  text: 'Actualizar',
                  variant: AppButtonVariant.outlined,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          AppSectionTitle(
            title: 'Mapa global conductores + pedidos asignados',
            trailing: '${activeAssignedOrders.length}',
          ),
          _buildCentralMapCard(
            drivers: drivers,
            activeAssignedOrders: activeAssignedOrders,
            routePlansByDriver: routePlansByDriver,
            driverColors: driverColors,
            routeProv: routeProv,
          ),
          AppSectionTitle(
            title: 'Pendientes por asignar',
            trailing: '${pendingOrders.length}',
          ),
          if (pendingOrders.isEmpty)
            AppEmptyCard(message: 'No hay pedidos pendientes')
          else
            ...pendingOrders.map(
              (order) => _buildPendingOrderCard(order, drivers, isLoading),
            ),
          AppSectionTitle(
            title: 'Pedidos activos',
            trailing: '${activeOrders.length}',
          ),
          if (activeOrders.isEmpty)
            AppEmptyCard(message: 'No hay pedidos activos')
          else
            ...activeOrders.map(
              (order) => Card(
                child: ListTile(
                  leading: Icon(
                    _orderTypeIcon(order.type),
                    color: order.assignedDriverId != null
                        ? (driverColors[order.assignedDriverId] ?? AppTheme.primary)
                        : AppTheme.primary,
                  ),
                  title: Text(order.address),
                  subtitle: Text(
                    '${_orderTypeLabel(order.type)} - ${order.status} - Driver: ${order.assignedDriverId ?? 'sin asignar'}',
                  ),
                ),
              ),
            ),
          AppSectionTitle(
            title: 'Repartidores',
            trailing: '${drivers.length}',
          ),
          if (drivers.isEmpty)
            AppEmptyCard(message: 'No hay repartidores')
          else
            ...drivers.map(
              (driver) => Card(
                child: ListTile(
                  leading: Icon(
                    Icons.local_shipping_outlined,
                    color: driverColors[driver.id] ?? AppTheme.secondary,
                  ),
                  title: Text(driver.name),
                  subtitle: Text(driver.shortLocation),
                ),
              ),
            ),
          AppSectionTitle(
            title: 'Eventos tiempo real',
            trailing: '${events.length}',
          ),
          if (events.isEmpty)
            AppEmptyCard(message: 'Sin eventos recientes')
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

// ── Create Order Dialog ──────────────────────────────────────────────

class _CreateOrderDialog extends StatefulWidget {
  const _CreateOrderDialog();

  @override
  State<_CreateOrderDialog> createState() => _CreateOrderDialogState();
}

class _CreateOrderDialogState extends State<_CreateOrderDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();

  String _selectedType = 'pickup';

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Crear pedido'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _selectedType,
                decoration: const InputDecoration(
                  labelText: 'Tipo',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'pickup', child: Text('Pickup')),
                  DropdownMenuItem(
                      value: 'delivery', child: Text('Delivery')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedType = value;
                  });
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre empresa / cliente (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Direccion',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Ingresa una direccion';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.place_outlined, size: 17),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Las coordenadas se calculan automaticamente desde la direccion.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context).pop(
              _CreateOrderDraft(
                type: _selectedType,
                name: _nameController.text.trim().isEmpty
                    ? null
                    : _nameController.text.trim(),
                address: _addressController.text.trim(),
              ),
            );
          },
          child: const Text('Crear'),
        ),
      ],
    );
  }
}

class _CreateOrderDraft {
  const _CreateOrderDraft({
    required this.type,
    required this.address,
    this.name,
  });

  final String type;
  final String? name;
  final String address;
}
