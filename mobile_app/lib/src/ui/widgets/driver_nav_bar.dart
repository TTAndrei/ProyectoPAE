import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/order_model.dart';
import '../../providers/driver_provider.dart';
import '../../providers/order_provider.dart';
import '../../theme/app_theme.dart';
import '../screens/driver/driver_map_screen.dart';
import '../screens/driver/driver_profile_screen.dart';
import '../screens/driver/driver_tasks_screen.dart';
import 'app_button.dart';

import 'order_details_dialog.dart';

class DriverNavBar extends StatefulWidget {
  const DriverNavBar({super.key});

  @override
  State<DriverNavBar> createState() => _DriverNavBarState();
}

class _DriverNavBarState extends State<DriverNavBar> {
  int _selectedIndex = 0;
  double? _lastAcceptedExtraMinutes;
  StreamSubscription<AssignOrderResult>? _subscription;
  DriverProvider? _driverProv;
  final Set<String> _shownDialogOrderIds = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final driverProv = Provider.of<DriverProvider>(context, listen: false);
    if (_driverProv != driverProv) {
      _driverProv = driverProv;
      _subscription?.cancel();
      _subscription = driverProv.incomingOrderNotifications.listen((event) {
        _showIncomingOrderDialog(event);
      });
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _showIncomingOrderDialog(AssignOrderResult event) {
    if (!mounted) return;
    if (event.order.status == 'in_progress') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Central ha asignado un pedido directamente a tu ruta: ${event.order.address}'),
          backgroundColor: AppTheme.secondary,
        ),
      );
      return;
    }
    if (_shownDialogOrderIds.contains(event.order.id)) return;

    _shownDialogOrderIds.add(event.order.id);

    showDialog(
      context: context,
      barrierDismissible: false, // Force driver to select Accept or Reject
      builder: (dialogCtx) {
        return OrderDetailsDialog(
          order: event.order,
          onAccept: () {
            _shownDialogOrderIds.remove(event.order.id);
            _respondToPickup(event.order, true);
          },
          onReject: () {
            _shownDialogOrderIds.remove(event.order.id);
            _respondToPickup(event.order, false);
          },
        );
      },
    );
  }

  Future<void> _respondToPickup(
    OrderModel order,
    bool accepted,
  ) async {
    if (!mounted) return;
    final orderProv = context.read<OrderProvider>();
    final driverProv = context.read<DriverProvider>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      final result = await orderProv.respondToPickup(
        orderId: order.id,
        accepted: accepted,
      );

      if (accepted && result.extraMinutes != null) {
        setState(() {
          _lastAcceptedExtraMinutes = result.extraMinutes;
        });
      }

      // Refresh driver's own route plan and shift data immediately
      await driverProv.loadData();

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

  @override
  Widget build(BuildContext context) {
    final driverProv = context.watch<DriverProvider>();
    final orderProv = context.watch<OrderProvider>();

    final orders = orderProv.orders;
    final isLoading = orderProv.isLoading || driverProv.isLoading;
    final error = driverProv.error ?? orderProv.error;

    if (isLoading && orders.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (error != null && orders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'No se pudo cargar la información\n$error',
                textAlign: TextAlign.center,
              ),
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

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          DriverMapScreen(
            lastAcceptedExtraMinutes: _lastAcceptedExtraMinutes,
            onOrderAccepted: (minutes) {
              setState(() {
                _lastAcceptedExtraMinutes = minutes;
              });
            },
          ),
          DriverTasksScreen(
            onOrderAccepted: (minutes) {
              setState(() {
                _lastAcceptedExtraMinutes = minutes;
              });
            },
          ),
          const DriverProfileScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        selectedItemColor: AppTheme.tertiary,
        unselectedItemColor: Colors.grey,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'Mapa',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list),
            label: 'Tareas',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}
