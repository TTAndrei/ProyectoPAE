import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/api_client.dart';
import 'services/driver_service.dart';
import 'services/order_service.dart';
import 'services/route_service.dart';
import 'services/simulation_service.dart';
import 'state/session_controller.dart';
import 'theme/app_theme.dart';
import 'ui/screens/home_page.dart';
import 'ui/screens/login_page.dart';

class PaeMobileApp extends StatelessWidget {
  const PaeMobileApp({
    super.key,
    required this.apiClient,
    required this.sessionController,
    required this.orderService,
    required this.driverService,
    required this.routeService,
    required this.simulationService,
  });

  final ApiClient apiClient;
  final SessionController sessionController;
  final OrderService orderService;
  final DriverService driverService;
  final RouteService routeService;
  final SimulationService simulationService;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: apiClient),
        Provider<OrderService>.value(value: orderService),
        Provider<DriverService>.value(value: driverService),
        Provider<RouteService>.value(value: routeService),
        Provider<SimulationService>.value(value: simulationService),
        ChangeNotifierProvider<SessionController>.value(
          value: sessionController,
        ),
      ],
      child: MaterialApp(
        title: 'PAE Mobile',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const RootPage(),
      ),
    );
  }
}

class RootPage extends StatelessWidget {
  const RootPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();

    if (session.isInitializing) {
      return const _SplashPage();
    }

    if (!session.isAuthenticated) {
      return const LoginPage();
    }

    return const HomePage();
  }
}

class _SplashPage extends StatelessWidget {
  const _SplashPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
