import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'src/app.dart';
import 'src/config/app_config.dart';
import 'src/services/api_client.dart';
import 'src/services/auth_service.dart';
import 'src/services/auth_store.dart';
import 'src/services/driver_service.dart';
import 'src/services/order_service.dart';
import 'src/services/route_service.dart';
import 'src/state/session_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  // ── Services ───────────────────────────────────────────────────
  final apiClient = ApiClient(baseUrl: AppConfig.apiBaseUrl);
  final authStore = AuthStore();

  final authService = AuthService(
    apiClient: apiClient,
    authStore: authStore,
  );
  final orderService = OrderService(apiClient: apiClient);
  final driverService = DriverService(apiClient: apiClient);
  final routeService = RouteService(apiClient: apiClient);

  // ── Session ────────────────────────────────────────────────────
  final sessionController = SessionController(authService: authService);
  await sessionController.restoreSession();

  // ── Run ────────────────────────────────────────────────────────
  runApp(
    PaeMobileApp(
      apiClient: apiClient,
      sessionController: sessionController,
      orderService: orderService,
      driverService: driverService,
      routeService: routeService,
    ),
  );
}
