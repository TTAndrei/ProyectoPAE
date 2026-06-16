import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/central_provider.dart';
import '../../../providers/order_provider.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/app_button.dart';

class CentralDashboardScreen extends StatelessWidget {
  const CentralDashboardScreen({super.key, required this.onCreateOrder});

  final VoidCallback onCreateOrder;

  @override
  Widget build(BuildContext context) {
    final centralProv = context.watch<CentralProvider>();
    final orderProv = context.watch<OrderProvider>();

    final drivers = centralProv.drivers;
    final orders = orderProv.orders;
    final pendingOrders = orderProv.pendingOrders;
    final activeDriversCount =
        drivers.where((d) => d.lat != null && d.lng != null).length;
    final completedOrdersCount =
        orders.where((o) => o.status == 'completed').length;

    return Padding(
      padding: const EdgeInsets.all(32),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool isWide = constraints.maxWidth > 768;

          // Header
          final headerWidget = isWide
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Dashboard de Operaciones',
                          style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.secondary),
                        ),
                        SizedBox(height: 4),
                        Text('Resumen operativo de la flota en tiempo real',
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                    Wrap(
                      spacing: 12,
                      children: [
                        AppButton(
                          onPressed: onCreateOrder,
                          icon: Icons.add,
                          text: 'Crear Pedido',
                        ),
                        AppButton(
                          onPressed: () {
                            context.read<CentralProvider>().loadDrivers();
                            context.read<OrderProvider>().loadOrders();
                          },
                          icon: Icons.refresh,
                          text: 'Actualizar',
                          variant: AppButtonVariant.outlined,
                        ),
                      ],
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Dashboard de Operaciones',
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.secondary),
                    ),
                    const SizedBox(height: 4),
                    const Text('Resumen operativo de la flota en tiempo real',
                        style: TextStyle(color: Colors.grey, fontSize: 13)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: AppButton(
                            onPressed: onCreateOrder,
                            icon: Icons.add,
                            text: 'Crear Pedido',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppButton(
                            onPressed: () {
                              context.read<CentralProvider>().loadDrivers();
                              context.read<OrderProvider>().loadOrders();
                            },
                            icon: Icons.refresh,
                            text: 'Actualizar',
                            variant: AppButtonVariant.outlined,
                          ),
                        ),
                      ],
                    ),
                  ],
                );

          // Grid of metrics
          final metricsGrid = _GridWidget(
            childCount: 4,
            itemBuilder: (context, index) {
              switch (index) {
                case 0:
                  return _buildMetricCard(
                    icon: Icons.local_shipping_rounded,
                    color: AppTheme.secondary,
                    label: 'Flota Total',
                    value: '${drivers.length}',
                  );
                case 1:
                  return _buildMetricCard(
                    icon: Icons.explore_rounded,
                    color: Colors.green,
                    label: 'Conductores en Ruta',
                    value: '$activeDriversCount',
                  );
                case 2:
                  return _buildMetricCard(
                    icon: Icons.pending_actions_rounded,
                    color: Colors.orange,
                    label: 'Pedidos Pendientes',
                    value: '${pendingOrders.length}',
                  );
                case 3:
                  return _buildMetricCard(
                    icon: Icons.check_circle_rounded,
                    color: Colors.blue,
                    label: 'Pedidos Completados',
                    value: '$completedOrdersCount',
                  );
                default:
                  return const SizedBox();
              }
            },
          );

          // Fleet Status content
          final fleetStatusCard = Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Estado General de la Flota',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.secondary),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildStatusIndicator(
                        label: 'Disponible',
                        value: drivers.where((d) => d.isAvailable).length,
                        total: drivers.isEmpty ? 1 : drivers.length,
                        color: Colors.green,
                      ),
                      _buildStatusIndicator(
                        label: 'En Ruta',
                        value: activeDriversCount,
                        total: drivers.isEmpty ? 1 : drivers.length,
                        color: Colors.blue,
                      ),
                      _buildStatusIndicator(
                        label: 'No Disponible',
                        value: drivers.where((d) => !d.isAvailable).length,
                        total: drivers.isEmpty ? 1 : drivers.length,
                        color: Colors.grey,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );

          // Performance highlight content
          final performanceCard = Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Rendimiento Semanal',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.secondary),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: Column(
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 100,
                              height: 100,
                              child: CircularProgressIndicator(
                                value: 0.94,
                                strokeWidth: 10,
                                backgroundColor:
                                    Colors.grey.withValues(alpha: 0.15),
                                color: AppTheme.primary,
                              ),
                            ),
                            const Text(
                              '94%',
                              style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.secondary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Eficiencia de Entregas',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Excelente nivel de cumplimiento en las entregas urbanas durante los últimos 14 días.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          );

          if (isWide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                headerWidget,
                const SizedBox(height: 32),
                metricsGrid,
                const SizedBox(height: 32),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 3,
                        child: fleetStatusCard,
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        flex: 2,
                        child: performanceCard,
                      ),
                    ],
                  ),
                ),
              ],
            );
          } else {
            // Mobile portrait or narrow views: everything scrollable in a single ListView
            return ListView(
              padding: EdgeInsets.zero,
              children: [
                headerWidget,
                const SizedBox(height: 24),
                metricsGrid,
                const SizedBox(height: 24),
                fleetStatusCard,
                const SizedBox(height: 24),
                performanceCard,
              ],
            );
          }
        },
      ),
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                      fontSize: 13,
                      color: Colors.grey,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.secondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicator({
    required String label,
    required int value,
    required int total,
    required Color color,
  }) {
    final pct = value / total;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 70,
              height: 70,
              child: CircularProgressIndicator(
                value: pct,
                strokeWidth: 6,
                backgroundColor: Colors.grey.withValues(alpha: 0.1),
                color: color,
              ),
            ),
            Text(
              '$value',
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.secondary),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _GridWidget extends StatelessWidget {
  const _GridWidget({
    required this.childCount,
    required this.itemBuilder,
  });

  final int childCount;
  final Widget Function(BuildContext, int) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        int crossAxisCount = 4;
        if (width < 600) {
          crossAxisCount = 1;
        } else if (width < 960) {
          crossAxisCount = 2;
        }

        if (crossAxisCount == 4) {
          return Row(
            children: List.generate(childCount, (index) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: index == 0 ? 0 : 12,
                    right: index == childCount - 1 ? 0 : 12,
                  ),
                  child: itemBuilder(context, index),
                ),
              );
            }),
          );
        } else if (crossAxisCount == 2) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: itemBuilder(context, 0)),
                  const SizedBox(width: 24),
                  Expanded(child: itemBuilder(context, 1)),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: itemBuilder(context, 2)),
                  const SizedBox(width: 24),
                  Expanded(child: itemBuilder(context, 3)),
                ],
              ),
            ],
          );
        } else {
          return Column(
            children: List.generate(childCount, (index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: itemBuilder(context, index),
              );
            }),
          );
        }
      },
    );
  }
}
