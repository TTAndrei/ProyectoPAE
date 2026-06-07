import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/analytics_models.dart';
import '../../../providers/central_provider.dart';
import '../../../theme/app_theme.dart';

class CentralAnalyticsScreen extends StatefulWidget {
  const CentralAnalyticsScreen({super.key});

  @override
  State<CentralAnalyticsScreen> createState() => _CentralAnalyticsScreenState();
}

class _CentralAnalyticsScreenState extends State<CentralAnalyticsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedOrderId = '';
  bool _isSearching = false;
  String? _searchError;
  List<AuditLogModel>? _currentAuditLogs;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatTimestamp(String isoString) {
    if (isoString.isEmpty) return '';
    final dt = DateTime.tryParse(isoString);
    if (dt == null) return isoString;
    final localDt = dt.toLocal();
    final hour = localDt.hour.toString().padLeft(2, '0');
    final minute = localDt.minute.toString().padLeft(2, '0');
    final day = localDt.day.toString().padLeft(2, '0');
    final month = localDt.month.toString().padLeft(2, '0');
    return '$day/$month $hour:$minute';
  }

  Future<void> _triggerSearch(String orderId) async {
    if (orderId.trim().isEmpty) return;
    setState(() {
      _selectedOrderId = orderId.trim();
      _searchController.text = orderId.trim();
      _isSearching = true;
      _searchError = null;
      _currentAuditLogs = null;
    });

    try {
      final logs = await context.read<CentralProvider>().loadOrderAudit(orderId.trim());
      setState(() {
        _currentAuditLogs = logs;
      });
    } catch (e) {
      setState(() {
        _searchError = 'Error al cargar auditoría: $e';
      });
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final centralProv = context.watch<CentralProvider>();
    final summary = centralProv.fleetSummary;
    final rankings = centralProv.driverPerformance;
    final routes = centralProv.routesHistory;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppTheme.appBackground,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Analíticas e Informes',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.neutral,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                'Visión global del rendimiento de flota, reparto y trazabilidad',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.neutral.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: centralProv.isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              onPressed: () => centralProv.loadDrivers(),
              tooltip: 'Refrescar datos',
            ),
            const SizedBox(width: 16),
          ],
          bottom: const TabBar(
            labelColor: AppTheme.primary,
            unselectedLabelColor: Colors.black54,
            indicatorColor: AppTheme.primary,
            indicatorSize: TabBarIndicatorSize.tab,
            tabs: [
              Tab(
                icon: Icon(Icons.analytics_outlined),
                text: 'Resumen Flota',
              ),
              Tab(
                icon: Icon(Icons.leaderboard_outlined),
                text: 'Rendimiento Repartidores',
              ),
              Tab(
                icon: Icon(Icons.history_outlined),
                text: 'Rutas e Inspección',
              ),
            ],
          ),
        ),
        body: centralProv.isLoading && summary == null
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildOverviewTab(summary),
                  _buildDriversRankingTab(rankings),
                  _buildRoutesAndLogsTab(routes),
                ],
              ),
      ),
    );
  }

  // ── Tab 1: Fleet Overview ──────────────────────────────────────────
  Widget _buildOverviewTab(FleetSummaryModel? summary) {
    if (summary == null) {
      return const Center(child: Text('No hay datos del resumen disponibles'));
    }

    final double efficiencyVal = summary.averageLoadEfficiencyPercent / 100.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Load Efficiency radial display & quick stats card
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 700;
              return Flex(
                direction: isWide ? Axis.horizontal : Axis.vertical,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Circular Load Efficiency Card
                  Flexible(
                    flex: isWide ? 1 : 0,
                    fit: isWide ? FlexFit.tight : FlexFit.loose,
                    child: Card(
                      color: Colors.white,
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'Eficiencia de Carga Media',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.secondary,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                SizedBox(
                                  width: 140,
                                  height: 140,
                                  child: CircularProgressIndicator(
                                    value: efficiencyVal.clamp(0.0, 1.0),
                                    strokeWidth: 14,
                                    backgroundColor: Colors.grey.shade100,
                                    color: AppTheme.primary,
                                  ),
                                ),
                                Column(
                                  children: [
                                    Text(
                                      '${summary.averageLoadEfficiencyPercent.toStringAsFixed(1)}%',
                                      style: const TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.neutral,
                                      ),
                                    ),
                                    const Text(
                                      'eficiencia',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Porcentaje de distancia recorrida con mercancía asignada frente a distancia total.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 20, height: 20),
                  // Distance breakdown and performance goals info card
                  Flexible(
                    flex: isWide ? 2 : 0,
                    fit: isWide ? FlexFit.tight : FlexFit.loose,
                    child: Card(
                      color: Colors.white,
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Análisis de Distancias de la Flota',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.secondary,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Row(
                              children: [
                                _buildDistanceIconCard(
                                  icon: Icons.alt_route_rounded,
                                  color: AppTheme.secondary,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Distancia Total Recorrida',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      Text(
                                        '${summary.totalDistanceKm.toStringAsFixed(2)} km',
                                        style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                _buildDistanceIconCard(
                                  icon: Icons.local_shipping_rounded,
                                  color: AppTheme.primary,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Distancia Recorrida con Carga',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      Text(
                                        '${summary.loadedDistanceKm.toStringAsFixed(2)} km',
                                        style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppTheme.appBackground,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.info_outline_rounded,
                                    color: AppTheme.secondary,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Mantener la eficiencia de carga por encima del 60% reduce costes logísticos y emisiones. Optimice la asignación de pedidos para minimizar trayectos en vacío.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade700,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          // Section header: Order statistics
          Text(
            'Estado de los Pedidos en Flota',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.neutral,
                ),
          ),
          const SizedBox(height: 16),
          // Order metrics row
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = (constraints.maxWidth - 32) / 3;
              final useVertical = constraints.maxWidth < 600;

              final widgets = [
                _buildOrderCountCard(
                  title: 'Pedidos Activos',
                  count: summary.totalActiveOrders,
                  color: AppTheme.secondary,
                  icon: Icons.pending_actions_rounded,
                ),
                _buildOrderCountCard(
                  title: 'Confirmaciones Pendientes',
                  count: summary.totalPendingConfirmations,
                  color: Colors.orange.shade700,
                  icon: Icons.flaky_rounded,
                ),
                _buildOrderCountCard(
                  title: 'Pedidos Completados',
                  count: summary.totalCompletedOrders,
                  color: Colors.green.shade700,
                  icon: Icons.check_circle_rounded,
                ),
              ];

              if (useVertical) {
                return Column(
                  children: widgets
                      .map((w) => Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: SizedBox(width: double.infinity, child: w),
                          ))
                      .toList(),
                );
              }

              return Row(
                children: [
                  SizedBox(width: itemWidth, child: widgets[0]),
                  const SizedBox(width: 16),
                  SizedBox(width: itemWidth, child: widgets[1]),
                  const SizedBox(width: 16),
                  SizedBox(width: itemWidth, child: widgets[2]),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDistanceIconCard({required IconData icon, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 28),
    );
  }

  Widget _buildOrderCountCard({
    required String title,
    required int count,
    required Color color,
    required IconData icon,
  }) {
    return Card(
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tab 2: Driver Performance ──────────────────────────────────────
  Widget _buildDriversRankingTab(List<DriverPerformanceModel> rankings) {
    if (rankings.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.people_outline_rounded, size: 48, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'No hay datos de conductores disponibles en este momento',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      );
    }

    // Sort descending by loadEfficiencyPercent
    final sortedRankings = List<DriverPerformanceModel>.from(rankings)
      ..sort((a, b) => b.loadEfficiencyPercent.compareTo(a.loadEfficiencyPercent));

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: sortedRankings.length,
      itemBuilder: (context, index) {
        final driver = sortedRankings[index];
        final rank = index + 1;
        final meetsTarget = driver.meetsLoadEfficiencyTarget;

        Color rankColor = Colors.grey.shade600;
        if (rank == 1) {
          rankColor = const Color(0xFFFFD700); // Gold
        } else if (rank == 2) {
          rankColor = const Color(0xFFC0C0C0); // Silver
        } else if (rank == 3) {
          rankColor = const Color(0xFFCD7F32); // Bronze
        }

        return Card(
          color: Colors.white,
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 600;

                final avatarAndName = Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: rank <= 3 ? rankColor : Colors.grey.shade200,
                      child: Text(
                        '$rank',
                        style: TextStyle(
                          color: rank <= 3 ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            driver.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'ID: ${driver.driverId.length > 8 ? driver.driverId.substring(0, 8) : driver.driverId}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );

                final efficiencyIndicator = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Eficiencia de Carga',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                        Text(
                          '${driver.loadEfficiencyPercent.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: meetsTarget ? Colors.green.shade700 : AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (driver.loadEfficiencyPercent / 100.0).clamp(0.0, 1.0),
                        minHeight: 8,
                        backgroundColor: Colors.grey.shade100,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          meetsTarget ? Colors.green : AppTheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Distancia: ${driver.loadedDistanceKm.toStringAsFixed(1)} km con carga / ${driver.totalDistanceKm.toStringAsFixed(1)} km total',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                );

                final statusChips = Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: meetsTarget ? Colors.green.shade50 : Colors.red.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: meetsTarget ? Colors.green.shade200 : Colors.red.shade200,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            meetsTarget ? Icons.check_circle_rounded : Icons.warning_rounded,
                            size: 14,
                            color: meetsTarget ? Colors.green.shade700 : Colors.red.shade700,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            meetsTarget ? 'Eficiencia OK' : 'Baja Eficiencia',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: meetsTarget ? Colors.green.shade800 : Colors.red.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Tooltip(
                      message: 'Pedidos Completados: ${driver.completedOrderCount} \nActivos: ${driver.activeOrderCount} \nPendiente de confirmar: ${driver.pendingConfirmationCount}',
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 14, color: Colors.blue.shade700),
                            const SizedBox(width: 4),
                            Text(
                              'Pedidos: ${driver.completedOrderCount} comp.',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.blue.shade800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );

                if (isWide) {
                  return Row(
                    children: [
                      Expanded(flex: 3, child: avatarAndName),
                      const SizedBox(width: 24),
                      Expanded(flex: 4, child: efficiencyIndicator),
                      const SizedBox(width: 24),
                      Expanded(flex: 3, child: statusChips),
                    ],
                  );
                } else {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      avatarAndName,
                      const SizedBox(height: 16),
                      efficiencyIndicator,
                      const SizedBox(height: 12),
                      statusChips,
                    ],
                  );
                }
              },
            ),
          ),
        );
      },
    );
  }

  // ── Tab 3: Route History & Audit Logs ──────────────────────────────
  Widget _buildRoutesAndLogsTab(List<RouteHistoryModel> routes) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 800;

        final leftPane = _buildCompletedRoutesPane(routes);
        final rightPane = _buildAuditTimelinePane(routes);

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: leftPane),
              VerticalDivider(width: 1, color: Colors.grey.shade300),
              Expanded(flex: 5, child: rightPane),
            ],
          );
        } else {
          return SingleChildScrollView(
            child: Column(
              children: [
                SizedBox(height: 500, child: leftPane),
                const Divider(height: 1),
                SizedBox(height: 600, child: rightPane),
              ],
            ),
          );
        }
      },
    );
  }

  Widget _buildCompletedRoutesPane(List<RouteHistoryModel> routes) {
    final completedRoutes = routes.where((r) => r.status == 'completed').toList();

    if (completedRoutes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.history_toggle_off_rounded, size: 40, color: Colors.grey),
              SizedBox(height: 12),
              Text(
                'No hay histórico de rutas completadas',
                style: TextStyle(fontWeight: FontWeight.w500, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Historial de Rutas'),
        elevation: 0,
        backgroundColor: Colors.white,
        automaticallyImplyLeading: false,
        scrolledUnderElevation: 0,
        titleTextStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          color: AppTheme.secondary,
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: completedRoutes.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final route = completedRoutes[index];
          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ExpansionTile(
              shape: const Border(),
              title: Row(
                children: [
                  Icon(Icons.directions_car_filled_rounded, color: Colors.grey.shade700, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Ruta: ${route.id.length > 8 ? route.id.substring(0, 8) : route.id}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Completada',
                      style: TextStyle(color: Colors.green.shade800, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  )
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  '${_formatTimestamp(route.createdAt)} | ${route.totalDistanceKm.toStringAsFixed(1)} km | ${route.totalMinutes.toStringAsFixed(0)} min',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
              children: [
                Container(
                  width: double.infinity,
                  color: Colors.grey.shade50,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Conductor ID: ${route.driverId}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Total pedidos asignados: ${route.orderIds.length}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Pedidos completados en esta ruta: ${route.completedOrderIds.length}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (route.completedOrderIds.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Inspeccionar pedidos de la ruta:',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: route.completedOrderIds.map((orderId) {
                            final shortId = orderId.length > 8 ? orderId.substring(0, 8) : orderId;
                            return ActionChip(
                              label: Text(shortId),
                              backgroundColor: Colors.white,
                              avatar: const Icon(Icons.search, size: 12),
                              side: const BorderSide(color: AppTheme.primary),
                              labelStyle: const TextStyle(color: AppTheme.primary, fontSize: 11),
                              onPressed: () => _triggerSearch(orderId),
                            );
                          }).toList(),
                        )
                      ]
                    ],
                  ),
                )
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAuditTimelinePane(List<RouteHistoryModel> routes) {
    // Collect order ids from completed routes to show as helper quick shortcuts
    final Set<String> quickOrderIds = {};
    for (final r in routes) {
      quickOrderIds.addAll(r.completedOrderIds);
    }
    final quickOrdersList = quickOrderIds.take(6).toList();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Trazabilidad de Pedidos'),
        elevation: 0,
        backgroundColor: Colors.white,
        automaticallyImplyLeading: false,
        scrolledUnderElevation: 0,
        titleTextStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          color: AppTheme.secondary,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Search field
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Ingresa ID del Pedido completo...',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      prefixIcon: const Icon(Icons.search, size: 20),
                    ),
                    onSubmitted: _triggerSearch,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _triggerSearch(_searchController.text),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.secondary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Buscar'),
                )
              ],
            ),
            const SizedBox(height: 12),
            // Quick links
            if (quickOrdersList.isNotEmpty) ...[
              const Text(
                'Pedidos de ejemplo en historial:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: quickOrdersList.map((id) {
                  final shortId = id.length > 8 ? id.substring(0, 8) : id;
                  return ChoiceChip(
                    label: Text(shortId),
                    selected: _selectedOrderId == id,
                    onSelected: (selected) {
                      if (selected) {
                        _triggerSearch(id);
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],
            // Results area
            Expanded(
              child: _buildTimelineContent(),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineContent() {
    if (_isSearching) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Obteniendo logs de auditoría...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (_searchError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 36),
            const SizedBox(height: 8),
            Text(_searchError!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
          ],
        ),
      );
    }

    if (_selectedOrderId.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timeline_rounded, size: 40, color: Colors.grey),
            SizedBox(height: 12),
            Text(
              'Busca o selecciona un pedido para ver su línea de tiempo de auditoría',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final logs = _currentAuditLogs;
    if (logs == null || logs.isEmpty) {
      return const Center(
        child: Text('No se encontraron registros de auditoría para este pedido'),
      );
    }

    // Sort audit logs ascending by timestamp
    final sortedLogs = List<AuditLogModel>.from(logs)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Auditoría: $_selectedOrderId',
            style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.secondary),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: sortedLogs.length,
            itemBuilder: (context, index) {
              final log = sortedLogs[index];
              final isLast = index == sortedLogs.length - 1;

              // Color coding based on audit actions
              Color bulletColor = Colors.blue;
              IconData bulletIcon = Icons.info_outline;

              final act = log.action.toLowerCase();
              if (act.contains('create') || act.contains('cread')) {
                bulletColor = Colors.blue;
                bulletIcon = Icons.add_box_rounded;
              } else if (act.contains('assign') || act.contains('asign')) {
                bulletColor = Colors.indigo;
                bulletIcon = Icons.person_add_alt_1_rounded;
              } else if (act.contains('start') || act.contains('inici')) {
                bulletColor = Colors.orange;
                bulletIcon = Icons.play_arrow_rounded;
              } else if (act.contains('transit') || act.contains('ruta')) {
                bulletColor = Colors.amber.shade800;
                bulletIcon = Icons.directions_bike_rounded;
              } else if (act.contains('complete') || act.contains('entrega')) {
                bulletColor = Colors.green;
                bulletIcon = Icons.check_circle_rounded;
              } else if (act.contains('cancel') || act.contains('rechaz')) {
                bulletColor = Colors.red;
                bulletIcon = Icons.cancel_rounded;
              }

              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Dot and line Column
                    Column(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: bulletColor.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(bulletIcon, color: bulletColor, size: 16),
                        ),
                        if (!isLast)
                          Expanded(
                            child: Container(
                              width: 2,
                              color: Colors.grey.shade300,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    // Detail card
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    log.action,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                                Text(
                                  _formatTimestamp(log.timestamp),
                                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                                ),
                              ],
                            ),
                            if (log.driverId != null && log.driverId!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Repartidor: ${log.driverId}',
                                style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
                              ),
                            ],
                            if (log.details != null && log.details!.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.grey.shade200),
                                ),
                                child: Text(
                                  log.details!,
                                  style: TextStyle(
                                    color: Colors.grey.shade800,
                                    fontSize: 11,
                                    fontFamily: 'monospace',
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
              );
            },
          ),
        ),
      ],
    );
  }
}
