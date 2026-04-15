import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/api_client.dart';
import 'state/session_controller.dart';
import 'ui/home_page.dart';
import 'ui/login_page.dart';

class PaeMobileApp extends StatelessWidget {
  const PaeMobileApp({
    super.key,
    required this.apiClient,
    required this.sessionController,
  });

  final ApiClient apiClient;
  final SessionController sessionController;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: apiClient),
        ChangeNotifierProvider<SessionController>.value(value: sessionController),
      ],
      child: MaterialApp(
        title: 'PAE Mobile',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF0F766E),
          scaffoldBackgroundColor: const Color(0xFFF3F6F8),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF0F766E),
            foregroundColor: Colors.white,
          ),
          cardTheme: const CardTheme(
            margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        ),
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
