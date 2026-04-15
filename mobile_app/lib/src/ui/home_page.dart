import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/session_controller.dart';
import 'central_page.dart';
import 'driver_page.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: Text('PAE Mobile - ${user.name} (${user.role})'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesion',
            onPressed: () => context.read<SessionController>().logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: user.role == 'central'
          ? CentralPage(token: token)
          : DriverPage(token: token, user: user),
    );
  }
}
