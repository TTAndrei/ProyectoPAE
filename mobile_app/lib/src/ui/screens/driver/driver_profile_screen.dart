import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/driver_model.dart';
import '../../../models/order_model.dart';
import '../../../providers/driver_provider.dart';
import '../../../providers/order_provider.dart';
import '../../../state/session_controller.dart';
import '../../../theme/app_theme.dart';

class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  String _formatDuration(Duration duration) {
    if (duration == Duration.zero) return '00:00:00';
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }

  void _showEditProfileDialog(BuildContext context) {
    final session = context.read<SessionController>();
    final user = session.user;
    if (user == null) return;

    final nameController = TextEditingController(text: user.name);
    final usernameController = TextEditingController(text: user.username);
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Editar Perfil'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Ingresa tu nombre';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de usuario',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Ingresa tu usuario';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Nueva Contraseña (opcional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;

                final success = await session.updateProfile(
                  name: nameController.text.trim(),
                  username: usernameController.text.trim(),
                  password: passwordController.text.isNotEmpty
                      ? passwordController.text
                      : null,
                );

                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? 'Perfil actualizado correctamente'
                          : 'Error al actualizar',
                    ),
                  ),
                );
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );
  }

  List<OrderModel> _pendingConfirmationOrders(
    List<OrderModel> orders,
    String userId,
  ) {
    return orders
        .where((o) => o.assignedDriverId == userId && o.status == 'assigned')
        .toList();
  }

  List<OrderModel> _activeRoute(
    List<OrderModel> orders,
    List<OrderModel> routeOrders,
    String userId,
  ) {
    final fromRoute = routeOrders
        .where((o) => o.assignedDriverId == userId && o.status == 'in_progress')
        .toList();

    final activeOutsideRoute = orders
        .where(
          (o) =>
              o.assignedDriverId == userId &&
              o.status == 'in_progress' &&
              !fromRoute.any((r) => r.id == o.id),
        )
        .toList();

    return [...fromRoute, ...activeOutsideRoute];
  }

  List<OrderModel> _completedRoute(List<OrderModel> orders, String userId) {
    return orders
        .where((o) => o.assignedDriverId == userId && o.status == 'completed')
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final driverProv = context.watch<DriverProvider>();
    final orderProv = context.watch<OrderProvider>();

    final user = driverProv.user;
    final kpis = driverProv.kpis;
    final orders = orderProv.orders;
    final routeOrders = driverProv.routeOrders;

    final pendingCount = _pendingConfirmationOrders(orders, user.id).length;
    final activeCount = _activeRoute(orders, routeOrders, user.id).length;
    final completedCount = _completedRoute(orders, user.id).length;
    final totalStops = completedCount + pendingCount + activeCount;

    final nameInitials = user.name.isNotEmpty
        ? user.name
            .trim()
            .split(' ')
            .map((e) => e[0])
            .take(2)
            .join()
            .toUpperCase()
        : '?';

    return Scaffold(
      backgroundColor: const Color(0xFFF9F6F5),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Hero Section
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F0EF), // bg-surface-container-low
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  // Avatar with Online Indicator
                  Stack(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.secondary.withValues(alpha: 0.1),
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            nameInitials,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.secondary,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  // Name and Vehicle Pills
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name,
                          style: const TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF2F2E2E),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'EN SERVICIO',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primary,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    AppTheme.secondary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'VAN #${user.id.substring(0, user.id.length > 3 ? 3 : user.id.length).toUpperCase()}',
                                style: const TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.secondary,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Edit Action
                  IconButton(
                    onPressed: () => _showEditProfileDialog(context),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.all(10),
                    ),
                    icon: const Icon(
                      Icons.edit,
                      color: AppTheme.secondary,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Stats Cards (2 Columns)
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: const Border(
                        left: BorderSide(color: AppTheme.primary, width: 4),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'HORAS DE TURNO',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade500,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatDuration(driverProv.shiftDuration),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2F2E2E),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: const Border(
                        left: BorderSide(color: AppTheme.secondary, width: 4),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ENTREGAS',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade500,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$completedCount / $totalStops',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2F2E2E),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Shift start/end section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    driverProv.activeJornada != null
                        ? Icons.timer
                        : Icons.timer_outlined,
                    color: driverProv.activeJornada != null
                        ? AppTheme.primary
                        : Colors.grey,
                    size: 28,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          driverProv.activeJornada != null
                              ? 'TURNO ACTIVO'
                              : 'SIN TURNO',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: driverProv.activeJornada != null
                                ? AppTheme.primary
                                : Colors.grey,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          driverProv.activeJornada != null
                              ? 'Registrando tiempo de ruta'
                              : 'Inicia turno para recibir pedidos',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: driverProv.isLoading
                        ? null
                        : () {
                            if (driverProv.activeJornada != null) {
                              driverProv.endShift();
                            } else {
                              driverProv.startShift();
                            }
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: driverProv.activeJornada != null
                          ? const Color(0xFFFDE8E8)
                          : AppTheme.primary,
                      foregroundColor: driverProv.activeJornada != null
                          ? const Color(0xFFB31B25)
                          : Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      driverProv.activeJornada != null
                          ? 'Finalizar'
                          : 'Iniciar',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Settings Group ("Ajustes Operativos")
            const Padding(
              padding: EdgeInsets.only(left: 8, bottom: 8),
              child: Text(
                'AJUSTES OPERATIVOS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF3F0EF),
                borderRadius: BorderRadius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  // Availability Toggle
                  InkWell(
                    onTap: () =>
                        driverProv.toggleAvailability(!driverProv.isAvailable),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.event_available,
                              color: AppTheme.primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Disponibilidad',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2F2E2E),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Aceptando nuevas solicitudes de despacho',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Custom Toggle Switch
                          Switch.adaptive(
                            value: driverProv.isAvailable,
                            activeThumbColor: AppTheme.primary,
                            onChanged: (val) =>
                                driverProv.toggleAvailability(val),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(
                      height: 1, indent: 66, color: Color(0xFFEAE7E7)),

                  _buildKpiSettingsRow(kpis),
                  const Divider(
                      height: 1, indent: 66, color: Color(0xFFEAE7E7)),

                  // Notification Preferences
                  _buildSettingsRow(
                    icon: Icons.notifications_active,
                    iconBg: AppTheme.secondary.withValues(alpha: 0.1),
                    iconColor: AppTheme.secondary,
                    title: 'Notificaciones',
                    subtitle: 'Alertas Push, SMS y Urgentes',
                    onTap: () {},
                  ),
                  const Divider(
                      height: 1, indent: 66, color: Color(0xFFEAE7E7)),

                  // Navigation App Choice
                  _buildSettingsRow(
                    icon: Icons.near_me,
                    iconBg: Colors.grey.shade300.withValues(alpha: 0.5),
                    iconColor: const Color(0xFF2F2E2E),
                    title: 'App de Navegación',
                    subtitle: 'Google Maps (Predeterminado)',
                    onTap: () {},
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Preference Group (General)
            const Padding(
              padding: EdgeInsets.only(left: 8, bottom: 8),
              child: Text(
                'GENERAL',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF3F0EF),
                borderRadius: BorderRadius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _buildSettingsRow(
                    icon: Icons.language,
                    iconBg: Colors.grey.shade300.withValues(alpha: 0.5),
                    iconColor: const Color(0xFF2F2E2E),
                    title: 'Idioma de la App',
                    subtitle: 'Español (Estados Unidos)',
                    onTap: () {},
                  ),
                  const Divider(
                      height: 1, indent: 66, color: Color(0xFFEAE7E7)),
                  _buildSettingsRow(
                    icon: Icons.support_agent,
                    iconBg: Colors.grey.shade300.withValues(alpha: 0.5),
                    iconColor: const Color(0xFF2F2E2E),
                    title: 'Soporte',
                    subtitle: 'Asistencia de Despacho 24/7',
                    onTap: () {},
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Logout Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: () => session.logout(),
                style: FilledButton.styleFrom(
                  backgroundColor:
                      const Color(0xFFFDE8E8), // Light red background
                  foregroundColor:
                      const Color(0xFFB31B25), // On-error-container text
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.logout, size: 18),
                label: const Text(
                  'Cerrar sesión',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Center(
              child: Text(
                'KINETIC PULSE v4.2.1-STABLE',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  letterSpacing: 2.0,
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsRow({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2F2E2E),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.grey.shade400,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiSettingsRow(DriverKpiModel? kpis) {
    final target = kpis == null
        ? '75'
        : (kpis.targetLoadEfficiencyRatio * 100).toStringAsFixed(0);
    final subtitle = kpis == null
        ? 'Calculando ratio de eficiencia de carga'
        : '${kpis.loadDistanceLabel} cargados, objetivo $target%';

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.secondary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.show_chart,
              color: AppTheme.secondary,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ratio eficiencia de carga',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2F2E2E),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          if (kpis == null)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Chip(
              avatar: Icon(
                kpis.meetsLoadEfficiencyTarget
                    ? Icons.check_circle
                    : Icons.trending_down,
                size: 16,
              ),
              label: Text(kpis.loadEfficiencyLabel),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}
