import 'dart:async';

import 'package:flutter/material.dart';
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
    final formKey = GlobalKey<FormState>();
    final addressController = TextEditingController();
    final latController = TextEditingController(text: '40.4168');
    final lngController = TextEditingController(text: '-3.7038');
    String selectedType = 'pickup';

    final input = await showDialog<CreateOrderInput>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Crear pedido'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        value: selectedType,
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
                          setDialogState(() {
                            selectedType = value;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: addressController,
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
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: latController,
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Latitud',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || double.tryParse(value.trim()) == null) {
                            return 'Latitud invalida';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: lngController,
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Longitud',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || double.tryParse(value.trim()) == null) {
                            return 'Longitud invalida';
                          }
                          return null;
                        },
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
                    if (!formKey.currentState!.validate()) {
                      return;
                    }
                    Navigator.of(context).pop(
                      CreateOrderInput(
                        type: selectedType,
                        address: addressController.text.trim(),
                        lat: double.parse(latController.text.trim()),
                        lng: double.parse(lngController.text.trim()),
                      ),
                    );
                  },
                  child: const Text('Crear'),
                ),
              ],
            );
          },
        );
      },
    );

    addressController.dispose();
    latController.dispose();
    lngController.dispose();

    if (input == null) {
      return;
    }

    setState(() {
      _isLoading = true;
    });
    try {
      final order = await _api.createOrder(token: widget.token, input: input);
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
                  title: Text(order.address),
                  subtitle: Text(
                    '${order.type} - ${order.status} - Driver: ${order.assignedDriverId ?? 'sin asignar'}',
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

  Widget _buildPendingOrderCard(OrderModel order) {
    final defaultDriver = _drivers.isNotEmpty ? _drivers.first.id : null;
    final selectedDriverId = _selectedDriverByOrder[order.id] ?? defaultDriver;
    if (selectedDriverId != null && !_selectedDriverByOrder.containsKey(order.id)) {
      _selectedDriverByOrder[order.id] = selectedDriverId;
    }

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
            Text('${order.type} - ${order.id}'),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: selectedDriverId,
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
