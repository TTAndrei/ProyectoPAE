import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../providers/driver_provider.dart';
import '../../providers/order_provider.dart';
import '../../providers/route_provider.dart';
import '../../services/driver_service.dart';
import '../../services/order_service.dart';
import '../../services/route_service.dart';
import '../../state/session_controller.dart';
import '../../theme/app_theme.dart';
import 'central_page.dart';
import '../widgets/driver_nav_bar.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final user = session.user;
    final token = session.token;

    if (user == null || token == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final orderService = context.read<OrderService>();
    final driverService = context.read<DriverService>();
    final routeService = context.read<RouteService>();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.secondary,
        foregroundColor: Colors.white,
        title: Text(
          'PAE Mobile - ${user.name} (${user.role})',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesion',
            onPressed: () => context.read<SessionController>().logout(),
            icon: const Icon(Icons.logout),
            color: Colors.white,
          ),
        ],
      ),
      body: user.role == 'central'
          ? MultiProvider(
              providers: [
                ChangeNotifierProvider<OrderProvider>(
                  create: (_) => OrderProvider(
                    orderService: orderService,
                    routeService: routeService,
                    token: token,
                    apiBaseUrl: AppConfig.apiBaseUrl,
                  ),
                ),
                ChangeNotifierProvider<DriverProvider>(
                  create: (_) => DriverProvider(
                    driverService: driverService,
                    routeService: routeService,
                    token: token,
                    apiBaseUrl: AppConfig.apiBaseUrl,
                    user: user,
                  ),
                ),
                ChangeNotifierProvider<RouteProvider>(
                  create: (_) => RouteProvider(routeService: routeService),
                ),
              ],
              child: const CentralPage(),
            )
          : MultiProvider(
              providers: [
                ChangeNotifierProvider<OrderProvider>(
                  create: (_) => OrderProvider(
                    orderService: orderService,
                    routeService: routeService,
                    token: token,
                    apiBaseUrl: AppConfig.apiBaseUrl,
                  ),
                ),
                ChangeNotifierProvider<DriverProvider>(
                  create: (_) => DriverProvider(
                    driverService: driverService,
                    routeService: routeService,
                    token: token,
                    apiBaseUrl: AppConfig.apiBaseUrl,
                    user: user,
                  ),
                ),
                ChangeNotifierProvider<RouteProvider>(
                  create: (_) => RouteProvider(routeService: routeService),
                ),
              ],
              child: const DriverNavBar(),
            ),
    );
  }
}
