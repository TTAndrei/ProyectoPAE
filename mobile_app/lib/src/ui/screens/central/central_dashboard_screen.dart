import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/driver_model.dart';
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
    final simulationCard = _buildSimulationCard(context, centralProv);

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
                simulationCard,
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
                simulationCard,
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

  Widget _buildSimulationCard(
    BuildContext context,
    CentralProvider centralProv,
  ) {
    final status = centralProv.simulationStatus;
    final kpis = centralProv.simulationKpis ?? status?.kpis;
    final isLoading = centralProv.isSimulationLoading;
    final isRunning = status?.isRunning == true;
    final currentStop = status?.currentStop;
    final selected = centralProv.selectedSimulation;
    final isRerouting = selected == 'rerouting';
    final totalFallback = isRerouting ? 3 : 20;
    final driverLabel = status?.driverId ?? 'driver-demo';

    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.route_rounded,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Simulaciones de ruta',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.secondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isRerouting
                            ? '$driverLabel · rerouting dinámico · ${status?.statusLabel ?? 'Inactiva'}'
                            : '$driverLabel · 20 recogidas demo · ${status?.statusLabel ?? 'Inactiva'}',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  status?.progressLabel ?? '0/$totalFallback',
                  style: const TextStyle(
                    color: AppTheme.secondary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  selected: selected == 'route-20',
                  label: const Text('Ruta 20'),
                  onSelected: isLoading
                      ? null
                      : (_) => _runSimulationAction(
                            context,
                            () => context
                                .read<CentralProvider>()
                                .selectSimulation('route-20'),
                            'Estado de Ruta 20 cargado',
                            reloadOrders: false,
                          ),
                ),
                ChoiceChip(
                  selected: selected == 'rerouting',
                  label: const Text('Rerouting demo'),
                  onSelected: isLoading
                      ? null
                      : (_) => _runSimulationAction(
                            context,
                            () => context
                                .read<CentralProvider>()
                                .selectSimulation('rerouting'),
                            'Estado de rerouting cargado',
                            reloadOrders: false,
                          ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: status?.progressValue ?? 0.0,
                minHeight: 8,
                backgroundColor: Colors.grey.withValues(alpha: 0.14),
                color: isRunning ? Colors.green : AppTheme.primary,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              currentStop == null
                  ? 'Parada actual: sin parada activa'
                  : 'Parada actual: ${currentStop.name ?? currentStop.address}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (status?.error != null) ...[
              const SizedBox(height: 8),
              Text(
                status!.error!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                AppButton(
                  onPressed: isRunning || isLoading
                      ? null
                      : () => _runSimulationAction(
                            context,
                            () => isRerouting
                                ? context
                                    .read<CentralProvider>()
                                    .startReroutingSimulation()
                                : context
                                    .read<CentralProvider>()
                                    .startRoute20Simulation(),
                            'Simulación iniciada',
                          ),
                  icon: Icons.play_arrow_rounded,
                  text: isRerouting ? 'Iniciar rerouting' : 'Iniciar Ruta 20',
                  isLoading: isLoading && !isRunning,
                ),
                AppButton(
                  onPressed: isLoading
                      ? null
                      : () => _runSimulationAction(
                            context,
                            () async {
                              await context
                                  .read<CentralProvider>()
                                  .loadSimulationKpis();
                            },
                            'KPIs actualizados',
                          ),
                  icon: Icons.analytics_rounded,
                  text: 'Consultar KPIs',
                  variant: AppButtonVariant.outlined,
                ),
                AppButton(
                  onPressed: isLoading
                      ? null
                      : () => _runSimulationAction(
                            context,
                            () => isRerouting
                                ? context
                                    .read<CentralProvider>()
                                    .resetReroutingSimulation()
                                : context
                                    .read<CentralProvider>()
                                    .resetRoute20Simulation(),
                            'Simulación reseteada',
                          ),
                  icon: Icons.restart_alt_rounded,
                  text: 'Reset',
                  variant: AppButtonVariant.outlined,
                ),
              ],
            ),
            const SizedBox(height: 18),
            _buildSimulationKpis(kpis),
            if (status?.comparison != null) ...[
              const SizedBox(height: 18),
              _buildComparison(status!.comparison!),
            ],
            if (status?.events.isNotEmpty == true) ...[
              const SizedBox(height: 18),
              _buildRerouteEvents(status!.events),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _runSimulationAction(
    BuildContext context,
    Future<void> Function() action,
    String successMessage,
    {bool reloadOrders = true}
  ) async {
    try {
      await action();
      if (!context.mounted) return;
      if (reloadOrders) {
        await context.read<OrderProvider>().loadOrders();
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error de simulación: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildComparison(comparison) {
    final savings = comparison.savingsKm.toStringAsFixed(2);
    final savingsPercent = comparison.savingsPercent.toStringAsFixed(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Comparativa rerouting vs FIFO',
          style: TextStyle(
            color: AppTheme.secondary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _buildKpiPill(
              'Ruta dinámica',
              '${comparison.dynamicDistanceKm.toStringAsFixed(2)} km',
            ),
            _buildKpiPill(
              'FIFO estimada',
              '${comparison.fifoDistanceKm.toStringAsFixed(2)} km',
            ),
            _buildKpiPill('Ahorro', '$savings km · $savingsPercent%'),
            _buildKpiPill(
              'Activos/completados',
              '${comparison.activeOrderCount}/${comparison.completedOrderCount}',
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Orden dinámico: ${comparison.dynamicOrderIds.join(' → ')}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 4),
        Text(
          'Orden FIFO: ${comparison.fifoOrderIds.join(' → ')}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildRerouteEvents(List events) {
    final visibleEvents = events.length > 3 ? events.sublist(events.length - 3) : events;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Inserciones dinámicas',
          style: TextStyle(
            color: AppTheme.secondary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...visibleEvents.map(
          (event) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.alt_route_rounded,
                  size: 16,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.message.isEmpty
                            ? 'Pedido ${event.orderId} insertado'
                            : event.message,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (event.previousOrderIds.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Antes: ${event.previousOrderIds.join(' → ')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                      if (event.newOrderIds.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Ahora: ${event.newOrderIds.join(' → ')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSimulationKpis(DriverKpiModel? kpis) {
    if (kpis == null) {
      return const Text(
        'KPIs no cargados',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _buildKpiPill('Eficiencia carga', kpis.loadEfficiencyLabel),
        _buildKpiPill('Km cargados/total', kpis.loadDistanceLabel),
        _buildKpiPill(
          'Activos/completados',
          '${kpis.activeOrderCount}/${kpis.completedOrderCount}',
        ),
        _buildKpiPill(
          'Aceptación inserciones',
          '${(kpis.insertionAcceptanceRate * 100).toStringAsFixed(0)}%',
        ),
      ],
    );
  }

  Widget _buildKpiPill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6F8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              color: AppTheme.secondary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
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
