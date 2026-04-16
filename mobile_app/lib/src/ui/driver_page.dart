import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/app_user.dart';
import '../models/driver_model.dart';
import '../models/order_model.dart';
import '../services/api_client.dart';
import '../services/ws_service.dart';

class DriverPage extends StatefulWidget {
  const DriverPage({
    super.key,
    required this.token,
    required this.user,
  });

  final String token;
  final AppUser user;

  @override
  State<DriverPage> createState() => _DriverPageState();
}

class _DriverPageState extends State<DriverPage> {
  static const Color _driverColor = Color(0xFF1D4ED8);
  static const Color _assignedColor = Color(0xFF0F766E);
  static const Color _possibleColor = Color(0xFFD97706);

  final WsService _wsService = WsService();
  final List<String> _events = <String>[];
  final _latController = TextEditingController(text: '40.4168');
  final _lngController = TextEditingController(text: '-3.7038');

  Timer? _refreshTimer;

  bool _isLoading = false;
  String? _error;

  List<OrderModel> _orders = const [];
  List<OrderModel> _routeOrders = const [];
  DriverLocation? _driverLocation;
  DriverRoutePlan? _routePlan;
  double? _lastAcceptedExtraMinutes;

  ApiClient get _api => context.read<ApiClient>();

  @override
  void initState() {
    super.initState();
    _loadData();
    _connectWs();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _loadData(showLoader: false),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _wsService.disconnect();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  List<OrderModel> get _possibleOrders {
    return _orders
        .where((order) =>
            order.status == 'pending' && order.assignedDriverId == null)
        .toList();
  }

  List<OrderModel> get _activeRoute {
    final fromRoute = _routeOrders
        .where((order) =>
            order.assignedDriverId == widget.user.id &&
            (order.status == 'assigned' || order.status == 'in_progress'))
        .toList();

    final assignedOutsideRoute = _orders
        .where(
          (order) =>
              order.assignedDriverId == widget.user.id &&
              (order.status == 'assigned' || order.status == 'in_progress') &&
              !fromRoute.any((routeOrder) => routeOrder.id == order.id),
        )
        .toList();

    return [...fromRoute, ...assignedOutsideRoute];
  }

  void _connectWs() {
    _wsService.connect(
      apiBaseUrl: _api.baseUrl,
      token: widget.token,
      onMessage: (payload) {
        final type = payload['type']?.toString() ?? 'event';
        _pushEvent('WS: $type');

        if (type == 'pickup:notification' ||
            type == 'driver:location:update' ||
            type == 'pickup:response') {
          _loadData(showLoader: false);
        }
      },
      onError: (error) => _pushEvent('WS error: $error'),
      onDone: () => _pushEvent('WS disconnected'),
    );
  }

  void _pushEvent(String value) {
    if (!mounted) {
      return;
    }
    setState(() {
      _events.insert(0, value);
      if (_events.length > 8) {
        _events.removeLast();
      }
    });
  }

  bool _isSparseRouteGeometry(DriverRoutePlan plan) {
    if (plan.routeGeometry.length < 2) {
      return true;
    }
    final minimumWaypointCount =
        plan.orders.isEmpty ? 0 : plan.orders.length + 1;
    return plan.routeGeometry.length <= minimumWaypointCount;
  }

  DriverRoutePlan _preferStreetGeometry({
    required DriverRoutePlan incoming,
    DriverRoutePlan? current,
  }) {
    if (current == null) {
      return incoming;
    }

    final incomingSparse = _isSparseRouteGeometry(incoming);
    final currentLooksStreet = !_isSparseRouteGeometry(current);

    if (incomingSparse && currentLooksStreet) {
      return DriverRoutePlan(
        orders: incoming.orders,
        totalMinutes: incoming.totalMinutes,
        totalDistanceKm: incoming.totalDistanceKm,
        routeGeometry: current.routeGeometry,
        legMinutes: incoming.legMinutes.isNotEmpty
            ? incoming.legMinutes
            : current.legMinutes,
      );
    }

    return incoming;
  }

  Future<void> _loadData({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final results = await Future.wait<dynamic>([
        _api.getOrders(token: widget.token),
        _api.getRoutePlan(token: widget.token, driverId: widget.user.id),
        _api.getDriverLocation(token: widget.token, driverId: widget.user.id),
      ]);

      if (!mounted) {
        return;
      }

      final incomingRoutePlan = results[1] as DriverRoutePlan;
      final routePlan = _preferStreetGeometry(
        incoming: incomingRoutePlan,
        current: _routePlan,
      );
      setState(() {
        _orders = results[0] as List<OrderModel>;
        _routePlan = routePlan;
        _routeOrders = routePlan.orders;
        _driverLocation = results[2] as DriverLocation?;
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (showLoader && mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _respondToPickup(OrderModel order, bool accepted) async {
    setState(() {
      _isLoading = true;
    });
    try {
      final result = await _api.respondOrder(
        token: widget.token,
        orderId: order.id,
        accepted: accepted,
      );

      _wsService.send({
        'type': 'driver:pickup:response',
        'order_id': order.id,
        'accepted': accepted,
      });

      if (accepted) {
        setState(() {
          _lastAcceptedExtraMinutes = result.extraMinutes;
        });
      }

      _pushEvent('Pedido ${order.id}: ${accepted ? 'aceptado' : 'rechazado'}');
      await _loadData(showLoader: false);

      if (!mounted) {
        return;
      }

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
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al responder: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _completeOrder(OrderModel order) async {
    await _updateOrderStatus(
        order: order, status: 'completed', actionLabel: 'completado');
  }

  Future<void> _updateOrderStatus({
    required OrderModel order,
    required String status,
    required String actionLabel,
  }) async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _api.updateOrderStatus(
        token: widget.token,
        orderId: order.id,
        status: status,
      );
      _pushEvent('Pedido ${order.id} $actionLabel');
      await _loadData(showLoader: false);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al actualizar pedido: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _sendLocation() async {
    final lat = double.tryParse(_latController.text.trim());
    final lng = double.tryParse(_lngController.text.trim());

    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Latitud/longitud invalidas')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });
    try {
      await _api.updateDriverLocation(
        token: widget.token,
        driverId: widget.user.id,
        lat: lat,
        lng: lng,
      );

      _wsService.send({
        'type': 'driver:location',
        'lat': lat,
        'lng': lng,
        'heading': 0.0,
      });

      if (!mounted) {
        return;
      }

      setState(() {
        _driverLocation = DriverLocation(
          driverId: widget.user.id,
          lat: lat,
          lng: lng,
          heading: 0,
          updatedAt: DateTime.now().toIso8601String(),
        );
      });

      _pushEvent(
          'Ubicacion enviada: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ubicacion actualizada')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al enviar ubicacion: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
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
    if (points.isEmpty) {
      return const LatLng(40.4168, -3.7038);
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
    if (points.length <= 1) {
      return 13;
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

    final span = (maxLat - minLat) > (maxLng - minLng)
        ? (maxLat - minLat)
        : (maxLng - minLng);

    if (span > 15) {
      return 5;
    }
    if (span > 8) {
      return 6;
    }
    if (span > 4) {
      return 7;
    }
    if (span > 2) {
      return 8;
    }
    if (span > 1) {
      return 9;
    }
    if (span > 0.4) {
      return 10;
    }
    if (span > 0.15) {
      return 11;
    }
    return 12.5;
  }

  Widget _buildDriverMapCard() {
    final possibleOrders = _possibleOrders;
    final assignedOrders = _activeRoute;

    final LatLng? driverPoint = _driverLocation == null
        ? null
        : LatLng(_driverLocation!.lat, _driverLocation!.lng);

    final allPoints = <LatLng>[
      if (driverPoint != null) driverPoint,
      ...assignedOrders.map((order) => LatLng(order.lat, order.lng)),
      ...possibleOrders.map((order) => LatLng(order.lat, order.lng)),
    ];

    if (allPoints.isEmpty) {
      return const _EmptyCard(
        message: 'No hay ubicaciones para mostrar en mapa todavia.',
      );
    }

    final center = _mapCenter(allPoints);
    final zoom = _zoomForPoints(allPoints);

    final routePoints = _routePlan == null
        ? const <LatLng>[]
        : _isSparseRouteGeometry(_routePlan!)
            ? const <LatLng>[]
            : _routePlan!.routeGeometry
                .map((point) => LatLng(point.lat, point.lng))
                .toList();

    final polylines = <Polyline>[
      if (routePoints.length >= 2)
        Polyline(
          points: routePoints,
          color: _assignedColor.withValues(alpha: 0.42),
          strokeWidth: 3.2,
        ),
    ];

    final markers = <Marker>[
      if (driverPoint != null)
        Marker(
          point: driverPoint,
          width: 48,
          height: 48,
          child: const _MapPinIcon(
            icon: Icons.local_shipping,
            color: _driverColor,
          ),
        ),
      for (final entry in assignedOrders.asMap().entries)
        Marker(
          point: LatLng(entry.value.lat, entry.value.lng),
          width: 40,
          height: 40,
          child: _MapPinIcon(
            icon: _orderTypeIcon(entry.value.type),
            color: _assignedColor,
            stopNumber: entry.key + 1,
          ),
        ),
      for (final order in possibleOrders)
        Marker(
          point: LatLng(order.lat, order.lng),
          width: 40,
          height: 40,
          child: _MapPinIcon(
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
                _LegendItem(label: 'Mi ubicacion', color: _driverColor),
                _LegendItem(label: 'Pedidos asignados', color: _assignedColor),
                _LegendItem(label: 'Pedidos posibles', color: _possibleColor),
                _OrderTypeLegendItem(
                  icon: Icons.inventory_2_rounded,
                  label: 'Pickup',
                ),
                _OrderTypeLegendItem(
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

  Widget _buildRouteMetricsCard() {
    final totalMinutes = _routePlan?.totalMinutes ?? 0.0;
    final totalDistance = _routePlan?.totalDistanceKm ?? 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            _MetricPill(
              icon: Icons.schedule,
              label: 'Tiempo total estimado',
              value: '${totalMinutes.toStringAsFixed(1)} min',
            ),
            _MetricPill(
              icon: Icons.route,
              label: 'Distancia estimada',
              value: '${totalDistance.toStringAsFixed(2)} km',
            ),
            if (_lastAcceptedExtraMinutes != null)
              _MetricPill(
                icon: Icons.add_road,
                label: 'Ultimo pedido aceptado añadió',
                value: '${_lastAcceptedExtraMinutes!.toStringAsFixed(1)} min',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersColumns() {
    final possibleOrders = _possibleOrders;
    final acceptedOrders = _activeRoute;

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
                      title: 'Pedidos posibles',
                      count: possibleOrders.length,
                      children: possibleOrders.isEmpty
                          ? const [
                              _EmptyCard(
                                  message:
                                      'No hay pedidos pendientes por asignar'),
                            ]
                          : possibleOrders
                              .map(_buildPossibleOrderCard)
                              .toList(),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _OrderColumn(
                      title: 'Pedidos aceptados / activos',
                      count: acceptedOrders.length,
                      children: acceptedOrders.isEmpty
                          ? const [
                              _EmptyCard(
                                  message:
                                      'No hay pedidos aceptados o activos'),
                            ]
                          : acceptedOrders
                              .asMap()
                              .entries
                              .map((entry) => _buildAssignedOrderCard(
                                  entry.key + 1, entry.value))
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _orders.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _orders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('No se pudo cargar la informacion\n$_error'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loadData,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadData(showLoader: false),
      child: ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        children: [
          _SectionTitle(title: 'Mapa operativo', trailing: ''),
          _buildDriverMapCard(),
          _SectionTitle(title: 'Estimacion de ruta', trailing: ''),
          _buildRouteMetricsCard(),
          _SectionTitle(title: 'Ubicacion manual', trailing: ''),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextFormField(
                    controller: _latController,
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Latitud',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _lngController,
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Longitud',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isLoading ? null : _sendLocation,
                      icon: const Icon(Icons.my_location),
                      label: const Text('Enviar ubicacion'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const _SectionTitle(
            title: 'Pedidos en columnas',
            trailing: '',
          ),
          _buildOrdersColumns(),
          _SectionTitle(
              title: 'Eventos tiempo real', trailing: '${_events.length}'),
          if (_events.isEmpty)
            const _EmptyCard(message: 'Sin eventos recientes')
          else
            ..._events.map(
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

  Widget _buildPossibleOrderCard(OrderModel order) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_orderTypeIcon(order.type), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    order.address,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('${_orderTypeLabel(order.type)} - ${order.id}'),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.info_outline, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Disponible para asignacion por Central',
                    style: TextStyle(
                      color: Colors.black.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssignedOrderCard(int index, OrderModel order) {
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
                  backgroundColor: Colors.black.withValues(alpha: 0.08),
                  child: Text(index.toString()),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    order.address,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                _StatusChip(status: order.status),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(_orderTypeIcon(order.type), size: 18),
                const SizedBox(width: 6),
                Text('${_orderTypeLabel(order.type)} - ${order.id}'),
              ],
            ),
            if (order.estimatedExtraMinutes != null) ...[
              const SizedBox(height: 6),
              Text(
                  'Extra estimado: ${order.estimatedExtraMinutes!.toStringAsFixed(1)} min'),
            ],
            const SizedBox(height: 12),
            if (order.status == 'assigned')
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () => _respondToPickup(order, false),
                      icon: const Icon(Icons.close),
                      label: const Text('Rechazar'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () => _respondToPickup(order, true),
                      icon: const Icon(Icons.check),
                      label: const Text('Aceptar'),
                    ),
                  ),
                ],
              ),
            if (order.status == 'in_progress')
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isLoading ? null : () => _completeOrder(order),
                  child: const Text('Completar parada'),
                ),
              ),
          ],
        ),
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
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
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

class _MapPinIcon extends StatelessWidget {
  const _MapPinIcon({
    required this.icon,
    required this.color,
    this.stopNumber,
  });

  final IconData icon;
  final Color color;
  final int? stopNumber;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color, width: 2.4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (stopNumber == null) Icon(icon, size: 23, color: color),
          if (stopNumber != null)
            Text(
              stopNumber.toString(),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          if (stopNumber != null)
            Positioned(
              right: 1,
              bottom: 1,
              child: Icon(
                icon,
                size: 11,
                color: color.withValues(alpha: 0.85),
              ),
            ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.black.withValues(alpha: 0.68),
                ),
              ),
              Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}

class _OrderTypeLegendItem extends StatelessWidget {
  const _OrderTypeLegendItem({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _colorForStatus(status).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        _labelForStatus(status),
        style: TextStyle(
          color: _colorForStatus(status),
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  Color _colorForStatus(String value) {
    switch (value) {
      case 'pending':
        return const Color(0xFFB45309);
      case 'assigned':
        return const Color(0xFF1D4ED8);
      case 'in_progress':
        return const Color(0xFF0F766E);
      case 'completed':
        return const Color(0xFF166534);
      case 'rejected':
        return const Color(0xFFB91C1C);
      default:
        return Colors.black54;
    }
  }

  String _labelForStatus(String value) {
    switch (value) {
      case 'pending':
        return 'Pendiente';
      case 'assigned':
        return 'Asignado';
      case 'in_progress':
        return 'En curso';
      case 'completed':
        return 'Completado';
      case 'rejected':
        return 'Rechazado';
      default:
        return value;
    }
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.trailing,
  });

  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          if (trailing.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(trailing),
            ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(message),
      ),
    );
  }
}
