import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_user.dart';
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
  final WsService _wsService = WsService();
  final List<String> _events = <String>[];
  final _latController = TextEditingController(text: '40.4168');
  final _lngController = TextEditingController(text: '-3.7038');

  Timer? _refreshTimer;

  bool _isLoading = false;
  String? _error;

  List<OrderModel> _orders = const [];
  List<OrderModel> _routeOrders = const [];

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

  List<OrderModel> get _assignedForResponse {
    return _orders
        .where(
          (order) => order.status == 'assigned' && order.assignedDriverId == widget.user.id,
        )
        .toList();
  }

  List<OrderModel> get _activeRoute {
    final fromRoute = _routeOrders
        .where((order) => order.status != 'completed' && order.status != 'rejected')
        .toList();
    if (fromRoute.isNotEmpty) {
      return fromRoute;
    }

    return _orders
        .where(
          (order) =>
              order.assignedDriverId == widget.user.id &&
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

        if (type == 'pickup:notification') {
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
        _api.getOrders(token: widget.token),
        _api.getRouteOrders(token: widget.token, driverId: widget.user.id),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _orders = results[0] as List<OrderModel>;
        _routeOrders = results[1] as List<OrderModel>;
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
      await _api.respondOrder(
        token: widget.token,
        orderId: order.id,
        accepted: accepted,
      );

      _wsService.send({
        'type': 'driver:pickup:response',
        'order_id': order.id,
        'accepted': accepted,
      });

      _pushEvent('Pedido ${order.id}: ${accepted ? 'aceptado' : 'rechazado'}');
      await _loadData(showLoader: false);
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

  Future<void> _startOrder(OrderModel order) async {
    await _updateOrderStatus(order: order, status: 'in_progress', actionLabel: 'iniciado');
  }

  Future<void> _completeOrder(OrderModel order) async {
    await _updateOrderStatus(order: order, status: 'completed', actionLabel: 'completado');
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

      _pushEvent('Ubicacion enviada: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}');
      if (!mounted) {
        return;
      }
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
          _SectionTitle(
            title: 'Recogidas pendientes de respuesta',
            trailing: '${_assignedForResponse.length}',
          ),
          if (_assignedForResponse.isEmpty)
            const _EmptyCard(message: 'Sin recogidas por responder')
          else
            ..._assignedForResponse.map(_buildPendingResponseCard),
          _SectionTitle(title: 'Ruta activa', trailing: '${_activeRoute.length}'),
          if (_activeRoute.isEmpty)
            const _EmptyCard(message: 'Sin paradas activas')
          else
            ..._activeRoute.asMap().entries.map(
              (entry) => _buildRouteOrderCard(entry.key + 1, entry.value),
            ),
          _SectionTitle(title: 'Eventos tiempo real', trailing: '${_events.length}'),
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

  Widget _buildPendingResponseCard(OrderModel order) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              order.address,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text('Extra: ${order.estimatedExtraMinutes?.toStringAsFixed(1) ?? '-'} min'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : () => _respondToPickup(order, false),
                    icon: const Icon(Icons.close),
                    label: const Text('Rechazar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isLoading ? null : () => _respondToPickup(order, true),
                    icon: const Icon(Icons.check),
                    label: const Text('Aceptar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteOrderCard(int index, OrderModel order) {
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
                  backgroundColor: Colors.black.withOpacity(0.08),
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
            Text('${order.type} - ${order.id}'),
            const SizedBox(height: 12),
            if (order.status == 'assigned')
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _isLoading ? null : () => _startOrder(order),
                  child: const Text('Marcar en curso'),
                ),
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _colorForStatus(status).withOpacity(0.15),
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
                color: Colors.black.withOpacity(0.06),
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
