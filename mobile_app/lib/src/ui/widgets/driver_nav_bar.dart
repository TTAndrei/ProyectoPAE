import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/driver_provider.dart';
import '../../providers/order_provider.dart';
import '../../theme/app_theme.dart';
import '../screens/driver/driver_map_screen.dart';
import '../screens/driver/driver_profile_screen.dart';
import '../screens/driver/driver_tasks_screen.dart';
import 'app_button.dart';

class DriverNavBar extends StatefulWidget {
  const DriverNavBar({super.key});

  @override
  State<DriverNavBar> createState() => _DriverNavBarState();
}

class _DriverNavBarState extends State<DriverNavBar> {
  int _selectedIndex = 0;
  double? _lastAcceptedExtraMinutes;

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
