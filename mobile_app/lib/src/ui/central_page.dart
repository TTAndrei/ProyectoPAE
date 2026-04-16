import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/driver_model.dart';
import '../models/order_model.dart';
import '../services/api_client.dart';
import '../services/ws_service.dart';

class CentralPage extends StatefulWidget {
  const CentralPage({
    super.key,
    required this.token,
  });

  final String token;

  @override
  State<CentralPage> createState() => _CentralPageState();
}

class _CentralPageState extends State<CentralPage> {
  static const List<Color> _driverPalette = [
    Color(0xFF1D4ED8),
    Color(0xFF0F766E),
    Color(0xFFB45309),
    Color(0xFF9333EA),
    Color(0xFFDC2626),
    Color(0xFF0E7490),
    Color(0xFF7C3AED),
    Color(0xFF15803D),
  ];

  final WsService _wsService = WsService();
  final Map<String, String> _selectedDriverByOrder = <String, String>{};
  final List<String> _events = <String>[];

  Timer? _refreshTimer;
  bool _isLoading = false;
  String? _error;

  List<DriverModel> _drivers = const [];
  List<OrderModel> _orders = const [];

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
    super.dispose();
  }

  List<OrderModel> get _pendingOrders {
    return _orders.where((order) => order.status == 'pending').toList();
  }

  List<OrderModel> get _activeOrders {
    return _orders.where((order) => order.status != 'pending').toList();
  }

  List<OrderModel> get _activeAssignedOrders {
    return _orders
        .where(
          (order) =>
              order.assignedDriverId != null &&
              order.status != 'completed' &&
              order.status != 'rejected',
        )
        .toList();
  }

  void _connectWs() {
    _wsService.connect(
      apiBaseUrl: _api.baseUrl,
      token: widget.token,
      onMessage: (payload) {
        final type = payload['type']?.toString() ?? 'event';
        _pushEvent('WS: $type');

        if (type == 'driver:location:update' || type == 'pickup:response') {
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

  Future<void> _loadData({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final results = await Future.wait<dynamic>([
        _api.getDrivers(token: widget.token),
        _api.getOrders(token: widget.token),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _drivers = results[0] as List<DriverModel>;
        _orders = results[1] as List<OrderModel>;
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

  Future<void> _assignOrder(OrderModel order) async {
    if (_drivers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay repartidores disponibles')),
      );
      return;
    }

    final driverId = _selectedDriverByOrder[order.id] ?? _drivers.first.id;
    setState(() {
      _isLoading = true;
    });

    try {
      final result = await _api.assignOrder(
        token: widget.token,
        orderId: order.id,
        driverId: driverId,
      );

      _wsService.send({
        'type': 'central:pickup:notify',
        'order_id': order.id,
        'driver_id': driverId,
      });

      _pushEvent(
        'Asignado ${result.order.id} a $driverId (+${result.extraMinutes.toStringAsFixed(1)} min)',
      );

      await _loadData(showLoader: false);

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pedido asignado. Tiempo extra: ${result.extraMinutes.toStringAsFixed(1)} min',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al asignar: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openCreateOrderDialog() async {
    final draft = await showDialog<_CreateOrderDraft>(
      context: context,
      builder: (_) => const _CreateOrderDialog(),
    );

    if (draft == null) {
      return;
    }

    setState(() {
      _isLoading = true;
    });
    try {
      final candidates = await _api.geocodeAddressCandidates(
        address: draft.address,
        maxResults: 5,
      );

      if (!mounted) {
        return;
      }

      GeocodeCandidate selectedCandidate;
      if (candidates.length == 1) {
        selectedCandidate = candidates.first;
      } else {
        setState(() {
          _isLoading = false;
        });

        final selected = await _openGeocodeCandidateDialog(
          address: draft.address,
          candidates: candidates,
        );
        if (!mounted) {
          return;
        }
        if (selected == null) {
          return;
        }

        selectedCandidate = selected;
        setState(() {
          _isLoading = true;
        });
      }

      final order = await _api.createOrder(
        token: widget.token,
        input: CreateOrderInput(
          type: draft.type,
          address: draft.address,
          lat: selectedCandidate.lat,
          lng: selectedCandidate.lng,
        ),
      );

      _pushEvent('Nuevo pedido ${order.id} (${order.type})');
      await _loadData(showLoader: false);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pedido creado correctamente')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al crear pedido: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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

  Map<String, Color> _driverColors() {
    final ids = _drivers.map((driver) => driver.id).toList()..sort();
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
      return 12;
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

  Widget _buildCentralMapCard() {
    final driverColors = _driverColors();
    final activeAssignedOrders = _activeAssignedOrders;

    final driversWithLocation = _drivers
        .where((driver) => driver.lat != null && driver.lng != null)
        .toList();

    final points = <LatLng>[
      for (final driver in driversWithLocation)
        LatLng(driver.lat!, driver.lng!),
      for (final order in activeAssignedOrders) LatLng(order.lat, order.lng),
    ];

    if (points.isEmpty) {
      return const _EmptyCard(
        message:
            'No hay ubicaciones de conductores/pedidos para mostrar en mapa.',
      );
    }

    final center = _mapCenter(points);
    final zoom = _zoomForPoints(points);

    final polylines = <Polyline>[];
    for (final driver in driversWithLocation) {
      final color = driverColors[driver.id] ?? _driverPalette.first;
      final driverPoint = LatLng(driver.lat!, driver.lng!);
      final ordersForDriver = activeAssignedOrders
          .where((order) => order.assignedDriverId == driver.id)
          .toList();

      for (final order in ordersForDriver) {
        polylines.add(
          Polyline(
            points: [driverPoint, LatLng(order.lat, order.lng)],
            color: color.withValues(alpha: 0.35),
            strokeWidth: 2.3,
          ),
        );
      }
    }

    final markers = <Marker>[
      for (final driver in driversWithLocation)
        Marker(
          point: LatLng(driver.lat!, driver.lng!),
          width: 50,
          height: 50,
          child: _MapPinIcon(
            icon: Icons.local_shipping,
            color: driverColors[driver.id] ?? _driverPalette.first,
          ),
        ),
      for (final order in activeAssignedOrders)
        Marker(
          point: LatLng(order.lat, order.lng),
          width: 42,
          height: 42,
          child: _MapPinIcon(
            icon: _orderTypeIcon(order.type),
            color:
                (driverColors[order.assignedDriverId] ?? _driverPalette.first)
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
                ..._drivers.map((driver) {
                  final count = activeAssignedOrders
                      .where((order) => order.assignedDriverId == driver.id)
                      .length;
                  final color = driverColors[driver.id] ?? _driverPalette.first;

                  return _DriverLegendItem(
                    color: color,
                    label: driver.name,
                    detail: '$count pedidos activos',
                  );
                }),
                const _OrderTypeLegendItem(
                  icon: Icons.inventory_2_rounded,
                  label: 'Pickup',
                ),
                const _OrderTypeLegendItem(
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _orders.isEmpty && _drivers.isEmpty) {
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: _isLoading ? null : _openCreateOrderDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('Crear pedido'),
                ),
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : () => _loadData(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Actualizar'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          _SectionTitle(
            title: 'Mapa global conductores + pedidos asignados',
            trailing: '${_activeAssignedOrders.length}',
          ),
          _buildCentralMapCard(),
          _SectionTitle(
            title: 'Pendientes por asignar',
            trailing: '${_pendingOrders.length}',
          ),
          if (_pendingOrders.isEmpty)
            const _EmptyCard(message: 'No hay pedidos pendientes')
          else
            ..._pendingOrders.map(_buildPendingOrderCard),
          _SectionTitle(
            title: 'Pedidos activos',
            trailing: '${_activeOrders.length}',
          ),
          if (_activeOrders.isEmpty)
            const _EmptyCard(message: 'No hay pedidos activos')
          else
            ..._activeOrders.map(
              (order) => Card(
                child: ListTile(
                  leading: Icon(_orderTypeIcon(order.type)),
                  title: Text(order.address),
                  subtitle: Text(
                    '${_orderTypeLabel(order.type)} - ${order.status} - Driver: ${order.assignedDriverId ?? 'sin asignar'}',
                  ),
                ),
              ),
            ),
          _SectionTitle(title: 'Repartidores', trailing: '${_drivers.length}'),
          if (_drivers.isEmpty)
            const _EmptyCard(message: 'No hay repartidores')
          else
            ..._drivers.map(
              (driver) => Card(
                child: ListTile(
                  leading: const Icon(Icons.local_shipping_outlined),
                  title: Text(driver.name),
                  subtitle: Text(driver.shortLocation),
                ),
              ),
            ),
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

  Widget _buildPendingOrderCard(OrderModel order) {
    final defaultDriver = _drivers.isNotEmpty ? _drivers.first.id : null;
    final selectedDriverId = _selectedDriverByOrder[order.id] ?? defaultDriver;
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
                Icon(_orderTypeIcon(order.type)),
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
              items: _drivers
                  .map(
                    (driver) => DropdownMenuItem<String>(
                      value: driver.id,
                      child: Text(driver.name),
                    ),
                  )
                  .toList(),
              onChanged: _drivers.isEmpty
                  ? null
                  : (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _selectedDriverByOrder[order.id] = value;
                      });
                    },
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isLoading ? null : () => _assignOrder(order),
                child: const Text('Asignar pedido'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateOrderDialog extends StatefulWidget {
  const _CreateOrderDialog();

  @override
  State<_CreateOrderDialog> createState() => _CreateOrderDialogState();
}

class _CreateOrderDialogState extends State<_CreateOrderDialog> {
  final _formKey = GlobalKey<FormState>();
  final _addressController = TextEditingController();

  String _selectedType = 'pickup';

  @override
  void dispose() {
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
                  DropdownMenuItem(value: 'delivery', child: Text('Delivery')),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _selectedType = value;
                  });
                },
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
            if (!_formKey.currentState!.validate()) {
              return;
            }
            Navigator.of(context).pop(
              _CreateOrderDraft(
                type: _selectedType,
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
  });

  final String type;
  final String address;
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}

class _MapPinIcon extends StatelessWidget {
  const _MapPinIcon({
    required this.icon,
    required this.color,
  });

  final IconData icon;
  final Color color;

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
      child: Icon(icon, size: 23, color: color),
    );
  }
}

class _DriverLegendItem extends StatelessWidget {
  const _DriverLegendItem({
    required this.color,
    required this.label,
    required this.detail,
  });

  final Color color;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
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
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                detail,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.black.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
        ],
      ),
    );
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
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
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
