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
import 'src/services/simulation_service.dart';
import 'src/state/session_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // .env is optional; --dart-define=API_BASE_URL is preferred for builds.
  }
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
  final simulationService = SimulationService(apiClient: apiClient);

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
      simulationService: simulationService,
    ),
  );
}
