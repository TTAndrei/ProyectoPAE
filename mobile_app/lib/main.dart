import 'package:flutter/widgets.dart';

import 'src/app.dart';
import 'src/config/app_config.dart';
import 'src/services/api_client.dart';
import 'src/services/auth_store.dart';
import 'src/state/session_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final apiClient = ApiClient(baseUrl: AppConfig.apiBaseUrl);
  final authStore = AuthStore();
  final sessionController = SessionController(
    apiClient: apiClient,
    authStore: authStore,
  );

  await sessionController.restoreSession();

  runApp(
    PaeMobileApp(
      apiClient: apiClient,
      sessionController: sessionController,
    ),
  );
}
