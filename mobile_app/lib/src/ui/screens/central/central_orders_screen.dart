import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/driver_model.dart';
import '../../../models/order_model.dart';
import '../../../providers/central_provider.dart';
import '../../../providers/order_provider.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_empty_card.dart';

class CentralOrdersScreen extends StatefulWidget {
  const CentralOrdersScreen({super.key, required this.onCreateOrder});

  final VoidCallback onCreateOrder;

  @override
  State<CentralOrdersScreen> createState() => _CentralOrdersScreenState();
}

class _CentralOrdersScreenState extends State<CentralOrdersScreen> {
  final Map<String, String> _selectedDriverByOrder = <String, String>{};

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

  Future<void> _assignOrder(OrderModel order) async {
    final centralProv = context.read<CentralProvider>();
    final orderProv = context.read<OrderProvider>();
    final drivers = centralProv.drivers;

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
          backgroundColor: AppTheme.secondary,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al asignar: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final centralProv = context.watch<CentralProvider>();
    final orderProv = context.watch<OrderProvider>();

    final drivers = centralProv.drivers;
    final pendingOrders = orderProv.pendingOrders;
    final activeOrders = orderProv.activeOrders;
    final events = orderProv.events;
    final isLoading = orderProv.isLoading || centralProv.isLoading;

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gestión de Pedidos',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppTheme.secondary),
                  ),
                  SizedBox(height: 4),
                  Text('Control de recogida, entregas y despacho de última milla', style: TextStyle(color: Colors.grey)),
                ],
              ),
              Wrap(
                spacing: 12,
                children: [
                  AppButton(
                    onPressed: widget.onCreateOrder,
                    icon: Icons.add,
                    text: 'Crear Pedido',
                  ),
                  AppButton(
                    onPressed: () {
                      context.read<CentralProvider>().loadDrivers();
                      context.read<OrderProvider>().loadOrders();
                    },
                    icon: Icons.refresh,
                    text: 'Actualizar',
                    variant: AppButtonVariant.outlined,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left Column: Orders List
                Expanded(
                  flex: 3,
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      const Text(
                        'Pendientes por Asignar',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.secondary),
                      ),
                      const SizedBox(height: 12),
                      if (pendingOrders.isEmpty)
                        AppEmptyCard(message: 'No hay pedidos pendientes')
                      else
                        ...pendingOrders.map(
                          (order) => _buildPendingOrderCard(order, drivers, isLoading),
                        ),
                      const SizedBox(height: 24),
                      const Text(
                        'Pedidos en Ruta',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.secondary),
                      ),
                      const SizedBox(height: 12),
                      if (activeOrders.isEmpty)
                        AppEmptyCard(message: 'No hay pedidos en curso')
                      else
                        ...activeOrders.map((order) {
                          final assignedDriver = drivers.where((d) => d.id == order.assignedDriverId).firstOrNull;
                          return Card(
                            color: Colors.white,
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: Icon(
                                _orderTypeIcon(order.type),
                                color: AppTheme.secondary,
                              ),
                              title: Text(order.address, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                '${_orderTypeLabel(order.type)} - Estado: ${order.status} - Repartidor: ${assignedDriver != null ? assignedDriver.name : "sin asignar"}',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
                const SizedBox(width: 24),

                // Right Column: WebSocket Telemetry Events
                Expanded(
                  flex: 2,
                  child: Card(
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Eventos en Tiempo Real',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.secondary),
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: events.isEmpty
                                ? const Center(child: Text('Sin eventos recientes', style: TextStyle(color: Colors.grey)))
                                : ListView.separated(
                                    itemCount: events.length,
                                    separatorBuilder: (_, __) => const Divider(),
                                    itemBuilder: (context, index) {
                                      final event = events[index];
                                      final isError = event.toLowerCase().contains('desconectado') ||
                                          event.toLowerCase().contains('rechazó') ||
                                          event.toLowerCase().contains('error');
                                      return ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        dense: true,
                                        leading: Icon(
                                          isError ? Icons.warning_rounded : Icons.info_rounded,
                                          color: isError ? Colors.red : Colors.blue,
                                          size: 18,
                                        ),
                                        title: Text(
                                          event,
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingOrderCard(
    OrderModel order,
    List<DriverModel> drivers,
    bool isLoading,
  ) {
    final defaultDriver = drivers.isNotEmpty ? drivers.first.id : null;
    final selectedDriverId = _selectedDriverByOrder[order.id] ?? defaultDriver;
    if (selectedDriverId != null && !_selectedDriverByOrder.containsKey(order.id)) {
      _selectedDriverByOrder[order.id] = selectedDriverId;
    }

    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_orderTypeIcon(order.type), color: AppTheme.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    order.address,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${_orderTypeLabel(order.type)} ID: ${order.id}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: selectedDriverId,
                    decoration: const InputDecoration(
                      labelText: 'Asignar a',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: drivers
                        .map(
                          (driver) => DropdownMenuItem<String>(
                            value: driver.id,
                            child: Text(driver.name, style: const TextStyle(fontSize: 12)),
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
                ),
                const SizedBox(width: 12),
                AppButton(
                  onPressed: isLoading ? null : () => _assignOrder(order),
                  text: 'Asignar',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
