import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/order_model.dart';
import '../../../providers/driver_provider.dart';
import '../../../providers/order_provider.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_empty_card.dart';
import '../../widgets/order_details_dialog.dart';

class DriverTasksScreen extends StatefulWidget {
  const DriverTasksScreen({
    super.key,
    this.onOrderAccepted,
  });

  final ValueChanged<double>? onOrderAccepted;

  @override
  State<DriverTasksScreen> createState() => _DriverTasksScreenState();
}

class _DriverTasksScreenState extends State<DriverTasksScreen> {
  bool _showUpcoming = true;

  String _formatDuration(double totalMinutes) {
    if (totalMinutes <= 0) return '0 min';
    final hours = (totalMinutes / 60).floor();
    final minutes = (totalMinutes % 60).round();
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '$minutes min';
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

  Future<void> _respondToPickup(
    BuildContext context,
    OrderModel order,
    bool accepted,
  ) async {
    final orderProv = context.read<OrderProvider>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      final result = await orderProv.respondToPickup(
        orderId: order.id,
        accepted: accepted,
      );

      if (accepted && result.extraMinutes != null) {
        widget.onOrderAccepted?.call(result.extraMinutes!);
      }

      if (!mounted) return;

      final extraText = result.extraMinutes == null
          ? ''
          : ' Extra: ${result.extraMinutes!.toStringAsFixed(1)} min.';
      final totalText = result.totalMinutes == null
          ? ''
          : ' Ruta total: ${result.totalMinutes!.toStringAsFixed(1)} min.';

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            accepted
                ? 'Pedido aceptado.$extraText$totalText'
                : 'Pedido rechazado.$totalText',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Error al responder: $error')),
      );
    }
  }

  void _openOrderDetails(BuildContext context, OrderModel order) {
    final orderProv = context.read<OrderProvider>();
    showDialog(
      context: context,
      builder: (dialogCtx) => OrderDetailsDialog(
        order: order,
        onComplete: () async {
          final messenger = ScaffoldMessenger.of(context);
          try {
            await orderProv.updateOrderStatus(
              orderId: order.id,
              status: 'completed',
              actionLabel: order.type == 'pickup' ? 'recogido' : 'entregado',
            );
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  order.type == 'pickup'
                      ? '¡Pedido marcado como recogido!'
                      : '¡Pedido marcado como entregado!',
                ),
              ),
            );
          } catch (e) {
            messenger.showSnackBar(
              SnackBar(content: Text('Error al actualizar el pedido: $e')),
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final driverProv = context.watch<DriverProvider>();
    final orderProv = context.watch<OrderProvider>();

    final user = driverProv.user;
    final orders = orderProv.orders;
    final routeOrders = driverProv.routeOrders;
    final routePlan = driverProv.routePlan;
    final isLoading = orderProv.isLoading || driverProv.isLoading;

    final pendingOrders = _pendingConfirmationOrders(orders, user.id);
    final activeOrders = _activeRoute(orders, routeOrders, user.id);
    final completedOrders = _completedRoute(orders, user.id);

    final upcomingTasks = [...activeOrders, ...pendingOrders];

    final totalMinutes = routePlan?.totalMinutes ?? 0.0;
    final stopsRemaining = upcomingTasks.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F6F5),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            driverProv.loadData(),
            orderProv.loadOrders(),
          ]);
        },
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          children: [
            // Dashboard Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PANEL DEL CONDUCTOR',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2.0,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Horario de Ruta',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF2F2E2E),
                      ),
                    ),
                  ],
                ),
                // Toggle Button
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAE7E7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => setState(() => _showUpcoming = true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _showUpcoming
                                ? Colors.white
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: _showUpcoming
                                ? [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.05),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    )
                                  ]
                                : null,
                          ),
                          child: Text(
                            'Próximas',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: _showUpcoming
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              color: _showUpcoming
                                  ? AppTheme.primary
                                  : Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _showUpcoming = false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: !_showUpcoming
                                ? Colors.white
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: !_showUpcoming
                                ? [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.05),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    )
                                  ]
                                : null,
                          ),
                          child: Text(
                            'Completadas',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: !_showUpcoming
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              color: !_showUpcoming
                                  ? AppTheme.primary
                                  : Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Route Stats Bento Grid
            IntrinsicHeight(
              child: Row(
                children: [
                  // Stats Card 1 (Time Remaining)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.2),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.speed,
                            color: Colors.white,
                            size: 28,
                          ),
                          const SizedBox(height: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'TIEMPO RESTANTE',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withValues(alpha: 0.8),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatDuration(totalMinutes),
                                style: const TextStyle(
                                  fontFamily: 'Manrope',
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Stats Card 2 (Stops Remaining)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFFEAE7E7),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.route,
                            color: AppTheme.secondary,
                            size: 28,
                          ),
                          const SizedBox(height: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _showUpcoming
                                    ? 'PARADAS RESTANTES'
                                    : 'COMPLETADAS',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _showUpcoming
                                    ? '$stopsRemaining'
                                    : '${completedOrders.length}',
                                style: const TextStyle(
                                  fontFamily: 'Manrope',
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF2F2E2E),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Route List
            if (_showUpcoming) ...[
              if (upcomingTasks.isEmpty)
                AppEmptyCard(message: 'No tienes tareas pendientes.')
              else
                ...upcomingTasks.asMap().entries.map((entry) {
                  final index = entry.key;
                  final order = entry.value;
                  final isNext = index == 0;

                  return _buildTaskItem(
                    context: context,
                    index: index + 1,
                    order: order,
                    isNext: isNext,
                    isLoading: isLoading,
                  );
                }),
            ] else ...[
              if (completedOrders.isEmpty)
                AppEmptyCard(
                    message: 'No has completado ninguna tarea todavía.')
              else
                ...completedOrders.asMap().entries.map((entry) {
                  final index = entry.key;
                  final order = entry.value;

                  return _buildTaskItem(
                    context: context,
                    index: index + 1,
                    order: order,
                    isNext: false,
                    isLoading: isLoading,
                    isCompleted: true,
                  );
                }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTaskItem({
    required BuildContext context,
    required int index,
    required OrderModel order,
    required bool isNext,
    required bool isLoading,
    bool isCompleted = false,
  }) {
    final orderNumStr = index.toString().padLeft(2, '0');

    // Type Chip color coding
    Color chipBg;
    Color chipText;
    String typeLabel;
    if (order.type == 'pickup') {
      chipBg = AppTheme.secondary.withValues(alpha: 0.1);
      chipText = AppTheme.secondary;
      typeLabel = 'Recogida';
    } else if (order.type == 'delivery') {
      chipBg = AppTheme.primary.withValues(alpha: 0.1);
      chipText = AppTheme.primary;
      typeLabel = 'Entrega';
    } else {
      chipBg = AppTheme.tertiary.withValues(alpha: 0.1);
      chipText = AppTheme.tertiary;
      typeLabel = 'Soporte';
    }

    if (isCompleted) {
      chipBg = Colors.green.withValues(alpha: 0.1);
      chipText = Colors.green;
      typeLabel = 'Completado';
    }

    if (isNext) {
      // Siguiente Style (Highlighted with orange left border)
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left accent stripe
              Container(
                width: 6,
                color: AppTheme.primary,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Big number and 'Siguiente' label
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            orderNumStr,
                            style: const TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.primary,
                              letterSpacing: -1,
                            ),
                          ),
                          const Text(
                            'SIGUIENTE',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      // Core details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: chipBg,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    typeLabel.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: chipText,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (order.estimatedExtraMinutes != null)
                                  Text(
                                    'Extra: ${order.estimatedExtraMinutes!.toStringAsFixed(1)} min',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              order.address,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'Manrope',
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2F2E2E),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'ID Paquete: #${order.id} • ${order.name ?? 'Express'}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            // Confirmation Action Buttons if status is assigned
                            if (order.status == 'assigned') ...[
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: AppButton(
                                      onPressed: isLoading
                                          ? null
                                          : () => _respondToPickup(
                                              context, order, false),
                                      icon: Icons.close,
                                      text: 'Rechazar',
                                      variant: AppButtonVariant.outlined,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: AppButton(
                                      onPressed: isLoading
                                          ? null
                                          : () => _respondToPickup(
                                              context, order, true),
                                      icon: Icons.check,
                                      text: 'Aceptar',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      // Action button (navigation details)
                      if (order.status == 'in_progress') ...[
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () => _openOrderDetails(context, order),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppTheme.secondary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.navigation,
                              color: AppTheme.secondary,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      // Regular Style (Grey background container)
      return GestureDetector(
        onTap: () => _openOrderDetails(context, order),
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F0EF),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Index number
                    Text(
                      orderNumStr,
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade600,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: chipBg,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  typeLabel.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: chipText,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (order.estimatedExtraMinutes != null &&
                                  !isCompleted)
                                Text(
                                  'Extra: ${order.estimatedExtraMinutes!.toStringAsFixed(1)} min',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            order.address,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2F2E2E),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'ID Paquete: #${order.id} • ${order.name ?? 'Express'}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Right chevron or custom action
                    if (!isCompleted)
                      Icon(
                        Icons.chevron_right,
                        color: Colors.grey.shade400,
                        size: 24,
                      )
                    else
                      const Icon(
                        Icons.check_circle_outline,
                        color: Colors.green,
                        size: 24,
                      ),
                  ],
                ),
                // Confirmation Action Buttons if status is assigned (even in regular style)
                if (order.status == 'assigned') ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          onPressed: isLoading
                              ? null
                              : () => _respondToPickup(context, order, false),
                          icon: Icons.close,
                          text: 'Rechazar',
                          variant: AppButtonVariant.outlined,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: AppButton(
                          onPressed: isLoading
                              ? null
                              : () => _respondToPickup(context, order, true),
                          icon: Icons.check,
                          text: 'Aceptar',
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
  }
}
