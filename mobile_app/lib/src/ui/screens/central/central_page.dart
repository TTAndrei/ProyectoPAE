import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/central_provider.dart';
import '../../../providers/order_provider.dart';
import '../../../state/session_controller.dart';
import '../../../services/api_client.dart';
import '../../../theme/app_theme.dart';
import 'central_dashboard_screen.dart';
import 'central_map_screen.dart';
import 'central_orders_screen.dart';
import 'central_drivers_screen.dart';
import 'central_analytics_screen.dart';

class CentralPage extends StatefulWidget {
  const CentralPage({super.key});

  @override
  State<CentralPage> createState() => _CentralPageState();
}

class _CentralPageState extends State<CentralPage> {
  String _activeTab = 'dashboard';
  bool _isCollapsed = false;

  Future<void> _openCreateOrderDialog() async {
    final orderProv = context.read<OrderProvider>();

    final draft = await showDialog<_CreateOrderDraft>(
      context: context,
      builder: (_) => const _CreateOrderDialog(),
    );
    if (draft == null) return;

    try {
      final candidates = await orderProv.geocodeAddressCandidates(
        address: draft.address,
      );

      if (!mounted) return;

      GeocodeCandidate selectedCandidate;
      if (candidates.length == 1) {
        selectedCandidate = candidates.first;
      } else {
        final selected = await _openGeocodeCandidateDialog(
          address: draft.address,
          candidates: candidates,
        );
        if (!mounted || selected == null) return;
        selectedCandidate = selected;
      }

      await orderProv.createOrder(
        type: draft.type,
        name: draft.name,
        address: draft.address,
        lat: selectedCandidate.lat,
        lng: selectedCandidate.lng,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pedido creado correctamente'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al crear pedido: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<GeocodeCandidate?> _openGeocodeCandidateDialog({
    required String address,
    required List<GeocodeCandidate> candidates,
  }) async {
    return showDialog<GeocodeCandidate>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Dirección ambigua'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Se encontraron varias coincidencias para:',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.black.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  address,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                const Text('Toca la ubicación correcta:'),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: candidates.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, index) {
                      final candidate = candidates[index];
                      return Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: const Icon(Icons.place_outlined),
                          title: Text(candidate.label),
                          subtitle: Text(
                            '${candidate.lat.toStringAsFixed(5)}, ${candidate.lng.toStringAsFixed(5)}',
                          ),
                          onTap: () {
                            Navigator.of(dialogContext).pop(candidate);
                          },
                        ),
                      );
                    },
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
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final orderProv = context.watch<OrderProvider>();
    final centralProv = context.watch<CentralProvider>();
    final session = context.watch<SessionController>();

    final companyName = session.user?.company?.name ?? 'PAE Logistics';
    final drivers = centralProv.drivers;
    final events = orderProv.events;
    final isLoading = orderProv.isLoading || centralProv.isLoading;
    final error = orderProv.error ?? centralProv.error;

    return Scaffold(
      body: Row(
        children: [
          // Left Sidebar in corporate deep blue
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            width: _isCollapsed ? 80 : 260,
            color: AppTheme.secondary,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Brand Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  child: _isCollapsed
                      ? Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppTheme.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.local_shipping, color: Colors.white, size: 22),
                            ),
                            const SizedBox(height: 16),
                            IconButton(
                              icon: const Icon(Icons.menu, color: Colors.white70),
                              onPressed: () => setState(() => _isCollapsed = false),
                              tooltip: 'Expandir menú',
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppTheme.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.local_shipping, color: Colors.white, size: 22),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Logistics OS',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.menu_open, color: Colors.white70),
                              onPressed: () => setState(() => _isCollapsed = true),
                              tooltip: 'Contraer menú',
                            ),
                          ],
                        ),
                ),
                const Divider(color: Colors.white24, height: 1, indent: 16, endIndent: 16),
                const SizedBox(height: 16),

                // Navigation Items
                _buildSidebarItem(
                  icon: Icons.dashboard_rounded,
                  label: 'Dashboard',
                  tabId: 'dashboard',
                ),
                _buildSidebarItem(
                  icon: Icons.map_rounded,
                  label: 'Monitorización',
                  tabId: 'map',
                ),
                _buildSidebarItem(
                  icon: Icons.people_rounded,
                  label: 'Conductores',
                  tabId: 'drivers',
                ),
                _buildSidebarItem(
                  icon: Icons.notifications_active_rounded,
                  label: 'Alertas y Pedidos',
                  tabId: 'alerts',
                  badgeText: events.isNotEmpty ? '${events.length}' : null,
                ),
                _buildSidebarItem(
                  icon: Icons.analytics_rounded,
                  label: 'Analíticas',
                  tabId: 'analytics',
                ),

                const Spacer(),
                const Divider(color: Colors.white24, height: 1),

                // Dispatch Center status
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: _isCollapsed
                      ? Tooltip(
                          message: 'Compañía: $companyName',
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                        )
                      : Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Compañía: $companyName',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),

          // Main Content Area with screen router
          Expanded(
            child: Container(
              color: AppTheme.appBackground,
              child: _buildActiveContent(
                isLoading: isLoading,
                error: error,
                drivers: drivers,
                events: events,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem({
    required IconData icon,
    required String label,
    required String tabId,
    String? badgeText,
  }) {
    final isSelected = _activeTab == tabId;
    final itemContent = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            setState(() {
              _activeTab = tabId;
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: _isCollapsed
                ? Center(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          icon,
                          color: isSelected ? AppTheme.primary : Colors.white70,
                          size: 20,
                        ),
                        if (badgeText != null)
                          Positioned(
                            top: -4,
                            right: -8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppTheme.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                badgeText,
                                style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                      ],
                    ),
                  )
                : Row(
                    children: [
                      Icon(
                        icon,
                        color: isSelected ? AppTheme.primary : Colors.white70,
                        size: 20,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white70,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (badgeText != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            badgeText,
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );

    if (_isCollapsed) {
      return Tooltip(
        message: label,
        child: itemContent,
      );
    }
    return itemContent;
  }

  Widget _buildActiveContent({
    required bool isLoading,
    required String? error,
    required List<dynamic> drivers,
    required List<String> events,
  }) {
    if (isLoading && drivers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null && drivers.isEmpty) {
      return Center(
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Error de conexión',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(error, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    context.read<CentralProvider>().loadDrivers();
                    context.read<OrderProvider>().loadOrders();
                  },
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    switch (_activeTab) {
      case 'dashboard':
        return CentralDashboardScreen(onCreateOrder: _openCreateOrderDialog);
      case 'map':
        return const CentralMapScreen();
      case 'drivers':
        return CentralDriversScreen(
          onViewOnMap: (driver) {
            setState(() {
              _activeTab = 'map';
            });
          },
        );
      case 'alerts':
        return CentralOrdersScreen(onCreateOrder: _openCreateOrderDialog);
      case 'analytics':
        return const CentralAnalyticsScreen();
      default:
        return const SizedBox();
    }
  }
}

// ── Create Order Dialog Draft ────────────────────────────────────────

class _CreateOrderDialog extends StatefulWidget {
  const _CreateOrderDialog();

  @override
  State<_CreateOrderDialog> createState() => _CreateOrderDialogState();
}

class _CreateOrderDialogState extends State<_CreateOrderDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();

  String _selectedType = 'pickup';

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Crear pedido'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _selectedType,
                decoration: const InputDecoration(
                  labelText: 'Tipo',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'pickup', child: Text('Pickup')),
                  DropdownMenuItem(value: 'delivery', child: Text('Delivery')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedType = value;
                  });
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre empresa / cliente (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Dirección',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Ingresa una dirección';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.place_outlined, size: 17),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Las coordenadas se calculan automáticamente desde la dirección.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context).pop(
              _CreateOrderDraft(
                type: _selectedType,
                name: _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
                address: _addressController.text.trim(),
              ),
            );
          },
          child: const Text('Crear'),
        ),
      ],
    );
  }
}

class _CreateOrderDraft {
  const _CreateOrderDraft({
    required this.type,
    required this.address,
    this.name,
  });

  final String type;
  final String? name;
  final String address;
}
