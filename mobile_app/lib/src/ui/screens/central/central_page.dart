import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/driver_model.dart';
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

  Future<void> _openCreateOrderDialog() async {
    final centralProv = context.read<CentralProvider>();
    if (centralProv.drivers.isEmpty) {
      try {
        await centralProv.loadDrivers();
      } catch (_) {}
      if (!mounted) return;
    }

    final drivers = context.read<CentralProvider>().drivers;
    final orderProv = context.read<OrderProvider>();

    final draft = await showDialog<_CreateOrderDraft>(
      context: context,
      builder: (_) => _CreateOrderDialog(drivers: drivers),
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
        driverId: draft.driverId,
        address: draft.address,
        lat: selectedCandidate.lat,
        lng: selectedCandidate.lng,
        incoterm: draft.incoterm,
        origen: draft.origen,
        destino: draft.destino,
        tipoBulto: draft.tipoBulto,
        dimensiones: draft.dimensiones,
        peso: draft.peso,
        esAdr: draft.esAdr,
        adrTipo: draft.adrTipo,
        adrCodigoUn: draft.adrCodigoUn,
        clienteNombre: draft.clienteNombre,
        clienteContacto: draft.clienteContacto,
        destinatarioNombre: draft.destinatarioNombre,
        destinatarioContacto: draft.destinatarioContacto,
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
        final screenWidth = MediaQuery.of(dialogContext).size.width;
        final dialogWidth = screenWidth < 600 ? screenWidth * 0.9 : 560.0;
        return AlertDialog(
          title: const Text('Dirección ambigua'),
          content: SizedBox(
            width: dialogWidth,
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

  String _activeTabTitle() {
    switch (_activeTab) {
      case 'dashboard':
        return 'Dashboard';
      case 'map':
        return 'Monitorización';
      case 'drivers':
        return 'Conductores';
      case 'alerts':
        return 'Alertas y Pedidos';
      case 'analytics':
        return 'Analíticas';
      default:
        return '';
    }
  }

  Widget _buildSidebar({
    required BuildContext context,
    required String companyName,
    required List<String> events,
    required SessionController session,
    required bool isMobile,
  }) {
    return Container(
      color: AppTheme.secondary,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool isCollapsedNow = !isMobile && constraints.maxWidth < 180;

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Brand Header
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                      child: (!isCollapsedNow)
                          ? Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.local_shipping,
                                      color: Colors.white, size: 22),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    '',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (!isMobile)
                                  IconButton(
                                    icon: const Icon(Icons.menu_open,
                                        color: Colors.white70),
                                    onPressed: () => setState(() => _isCollapsed = true),
                                    tooltip: 'Contraer menú',
                                  ),
                              ],
                            )
                          : Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.local_shipping,
                                      color: Colors.white, size: 22),
                                ),
                                const SizedBox(height: 16),
                                IconButton(
                                  icon: const Icon(Icons.menu, color: Colors.white70),
                                  onPressed: () => setState(() => _isCollapsed = false),
                                  tooltip: 'Expandir menú',
                                ),
                              ],
                            ),
                    ),
                    const Divider(
                        color: Colors.white24, height: 1, indent: 16, endIndent: 16),
                    const SizedBox(height: 16),

                    // Navigation Items
                    _buildSidebarItem(
                      icon: Icons.dashboard_rounded,
                      label: 'Dashboard',
                      tabId: 'dashboard',
                      isMobile: isMobile,
                      isCollapsedNow: isCollapsedNow,
                    ),
                    _buildSidebarItem(
                      icon: Icons.map_rounded,
                      label: 'Monitorización',
                      tabId: 'map',
                      isMobile: isMobile,
                      isCollapsedNow: isCollapsedNow,
                    ),
                    _buildSidebarItem(
                      icon: Icons.people_rounded,
                      label: 'Conductores',
                      tabId: 'drivers',
                      isMobile: isMobile,
                      isCollapsedNow: isCollapsedNow,
                    ),
                    _buildSidebarItem(
                      icon: Icons.notifications_active_rounded,
                      label: 'Alertas y Pedidos',
                      tabId: 'alerts',
                      badgeText: events.isNotEmpty ? '${events.length}' : null,
                      isMobile: isMobile,
                      isCollapsedNow: isCollapsedNow,
                    ),
                    _buildSidebarItem(
                      icon: Icons.analytics_rounded,
                      label: 'Analíticas',
                      tabId: 'analytics',
                      isMobile: isMobile,
                      isCollapsedNow: isCollapsedNow,
                    ),
                  ],
                ),
              ),
              SliverFillRemaining(
                hasScrollBody: false,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Divider(color: Colors.white24, height: 1),

                    // Dispatch Center status
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: (!isCollapsedNow)
                          ? Container(
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
                            )
                          : Tooltip(
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
                            ),
                    ),
                    if (isCollapsedNow) ...[
                      IconButton(
                        icon: const Icon(Icons.manage_accounts,
                            color: Colors.white70, size: 20),
                        tooltip: 'Editar Perfil',
                        onPressed: () => _showEditProfileDialog(context),
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout, color: Colors.redAccent, size: 20),
                        tooltip: 'Cerrar sesión',
                        onPressed: () => session.logout(),
                      ),
                      const SizedBox(height: 12),
                    ] else ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Column(
                          children: [
                            ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              leading: const Icon(Icons.manage_accounts,
                                  color: Colors.white70, size: 20),
                              title: const Text('Editar Perfil',
                                  style: TextStyle(color: Colors.white70, fontSize: 13)),
                              onTap: () => _showEditProfileDialog(context),
                            ),
                            ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              leading: const Icon(Icons.logout,
                                  color: Colors.redAccent, size: 20),
                              title: const Text('Cerrar sesión',
                                  style:
                                      TextStyle(color: Colors.redAccent, fontSize: 13)),
                              onTap: () => session.logout(),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
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

    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 768;

    if (isMobile) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: AppTheme.secondary,
          foregroundColor: Colors.white,
          title: Text(_activeTabTitle()),
        ),
        drawer: Drawer(
          child: _buildSidebar(
            context: context,
            companyName: companyName,
            events: events,
            session: session,
            isMobile: true,
          ),
        ),
        body: Container(
          color: AppTheme.appBackground,
          child: _buildActiveContent(
            isLoading: isLoading,
            error: error,
            drivers: drivers,
            events: events,
          ),
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          // Left Sidebar in corporate deep blue
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            width: _isCollapsed ? 80 : 260,
            child: _buildSidebar(
              context: context,
              companyName: companyName,
              events: events,
              session: session,
              isMobile: false,
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
    required bool isMobile,
    required bool isCollapsedNow,
  }) {
    final isSelected = _activeTab == tabId;
    final collapsedState = isCollapsedNow;
    final itemContent = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            setState(() {
              _activeTab = tabId;
            });
            if (isMobile) {
              Navigator.of(context).pop(); // close drawer
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: collapsedState
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
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppTheme.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                badgeText,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold),
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
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (badgeText != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            badgeText,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );

    if (collapsedState) {
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
  const _CreateOrderDialog({required this.drivers});

  final List<DriverModel> drivers;

  @override
  State<_CreateOrderDialog> createState() => _CreateOrderDialogState();
}

class _CreateOrderDialogState extends State<_CreateOrderDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _origenController = TextEditingController();
  final _destinoController = TextEditingController();
  final _dimensionesController = TextEditingController();
  final _pesoController = TextEditingController();
  final _adrTipoController = TextEditingController();
  final _adrCodigoUnController = TextEditingController();
  final _clienteNombreController = TextEditingController();
  final _clienteContactoController = TextEditingController();
  final _destinatarioNombreController = TextEditingController();
  final _destinatarioContactoController = TextEditingController();

  String _selectedType = 'pickup';
  String _selectedIncoterm = 'EXW';
  String? _selectedTipoBulto;
  String? _selectedDriverId;
  bool _esAdr = false;

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _origenController.dispose();
    _destinoController.dispose();
    _dimensionesController.dispose();
    _pesoController.dispose();
    _adrTipoController.dispose();
    _adrCodigoUnController.dispose();
    _clienteNombreController.dispose();
    _clienteContactoController.dispose();
    _destinatarioNombreController.dispose();
    _destinatarioContactoController.dispose();
    super.dispose();
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2F2E2E),
                ),
              ),
            ],
          ),
          const Divider(height: 12, color: Color(0xFFEAE7E7)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth < 600 ? screenWidth * 0.9 : 580.0;
    return AlertDialog(
      title: const Text('Crear pedido'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: dialogWidth,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSectionHeader('Datos Generales', Icons.info_outline),
                DropdownButtonFormField<String>(
                  initialValue: _selectedType,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de pedido',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'pickup', child: Text('Pickup (Recogida)')),
                    DropdownMenuItem(
                        value: 'delivery', child: Text('Delivery (Entrega)')),
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
                    labelText: 'Nombre identificador de parada (opcional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(
                    labelText: 'Dirección de parada',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Ingresa una dirección';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.place_outlined,
                        size: 15, color: Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Las coordenadas GPS se calcularán automáticamente.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.black.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ],
                ),
                _buildSectionHeader('Conductor', Icons.local_shipping_outlined),
                DropdownButtonFormField<String?>(
                  value: _selectedDriverId,
                  decoration: const InputDecoration(
                    labelText: 'Conductor asignado (opcional)',
                    hintText: 'Selecciona un conductor',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Ninguno (Pendiente / Auto-asignación)'),
                    ),
                    ...widget.drivers.map(
                      (driver) => DropdownMenuItem<String?>(
                        value: driver.id,
                        child: Text(driver.name),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedDriverId = value;
                    });
                  },
                ),
                _buildSectionHeader(
                    'Datos de Envío', Icons.inventory_2_outlined),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedIncoterm,
                        decoration: const InputDecoration(
                          labelText: 'Incoterm',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'EXW', child: Text('EXW')),
                          DropdownMenuItem(value: 'FOB', child: Text('FOB')),
                          DropdownMenuItem(value: 'CFR', child: Text('CFR')),
                          DropdownMenuItem(value: 'CIF', child: Text('CIF')),
                          DropdownMenuItem(value: 'DDP', child: Text('DDP')),
                          DropdownMenuItem(value: 'DAP', child: Text('DAP')),
                          DropdownMenuItem(value: 'FCA', child: Text('FCA')),
                          DropdownMenuItem(value: 'CPT', child: Text('CPT')),
                          DropdownMenuItem(value: 'CIP', child: Text('CIP')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _selectedIncoterm = value;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedTipoBulto,
                        decoration: const InputDecoration(
                          labelText: 'Tipo de bulto',
                          border: OutlineInputBorder(),
                          helperText: 'Opcional',
                        ),
                        items: const [
                          DropdownMenuItem(value: null, child: Text('Ninguno')),
                          DropdownMenuItem(value: 'caja', child: Text('Caja')),
                          DropdownMenuItem(
                              value: 'pallet', child: Text('Pallet')),
                          DropdownMenuItem(
                              value: 'cajon', child: Text('Cajón')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedTipoBulto = value;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _origenController,
                        decoration: const InputDecoration(
                          labelText: 'Origen del envío',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _destinoController,
                        decoration: const InputDecoration(
                          labelText: 'Destino del envío',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _dimensionesController,
                        decoration: const InputDecoration(
                          labelText: 'Dimensiones (ej: 120x80x100 cm)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _pesoController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Peso total (kg)',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value != null && value.trim().isNotEmpty) {
                            if (double.tryParse(value.trim()) == null) {
                              return 'Número inválido';
                            }
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                _buildSectionHeader(
                    'Mercancía Peligrosa (ADR)', Icons.warning_amber_rounded),
                SwitchListTile(
                  title: const Text('¿Contiene mercancía peligrosa (ADR)?'),
                  activeThumbColor: AppTheme.primary,
                  contentPadding: EdgeInsets.zero,
                  value: _esAdr,
                  onChanged: (val) {
                    setState(() {
                      _esAdr = val;
                    });
                  },
                ),
                if (_esAdr) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _adrTipoController,
                          decoration: const InputDecoration(
                            labelText: 'Tipo / Clase ADR',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (_esAdr &&
                                (value == null || value.trim().isEmpty)) {
                              return 'Especifica la clase';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _adrCodigoUnController,
                          decoration: const InputDecoration(
                            labelText: 'Código UN',
                            hintText: 'UN XXXX',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (_esAdr &&
                                (value == null || value.trim().isEmpty)) {
                              return 'Especifica código UN';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                ],
                _buildSectionHeader(
                    'Cliente y Destinatario', Icons.people_outline_rounded),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _clienteNombreController,
                        decoration: const InputDecoration(
                          labelText: 'Nombre del cliente',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _clienteContactoController,
                        decoration: const InputDecoration(
                          labelText: 'Contacto del cliente',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _destinatarioNombreController,
                        decoration: const InputDecoration(
                          labelText: 'Nombre del destinatario',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _destinatarioContactoController,
                        decoration: const InputDecoration(
                          labelText: 'Contacto del destinatario',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
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
            final pesoTxt = _pesoController.text.trim();
            final pesoVal =
                pesoTxt.isNotEmpty ? double.tryParse(pesoTxt) : null;

            Navigator.of(context).pop(
              _CreateOrderDraft(
                type: _selectedType,
                name: _nameController.text.trim().isEmpty
                    ? null
                    : _nameController.text.trim(),
                address: _addressController.text.trim(),
                driverId: _selectedDriverId,
                incoterm: _selectedIncoterm,
                origen: _origenController.text.trim().isEmpty
                    ? null
                    : _origenController.text.trim(),
                destino: _destinoController.text.trim().isEmpty
                    ? null
                    : _destinoController.text.trim(),
                tipoBulto: _selectedTipoBulto,
                dimensiones: _dimensionesController.text.trim().isEmpty
                    ? null
                    : _dimensionesController.text.trim(),
                peso: pesoVal,
                esAdr: _esAdr,
                adrTipo: _esAdr ? _adrTipoController.text.trim() : null,
                adrCodigoUn: _esAdr ? _adrCodigoUnController.text.trim() : null,
                clienteNombre: _clienteNombreController.text.trim().isEmpty
                    ? null
                    : _clienteNombreController.text.trim(),
                clienteContacto: _clienteContactoController.text.trim().isEmpty
                    ? null
                    : _clienteContactoController.text.trim(),
                destinatarioNombre:
                    _destinatarioNombreController.text.trim().isEmpty
                        ? null
                        : _destinatarioNombreController.text.trim(),
                destinatarioContacto:
                    _destinatarioContactoController.text.trim().isEmpty
                        ? null
                        : _destinatarioContactoController.text.trim(),
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
    this.driverId,
    this.name,
    this.incoterm,
    this.origen,
    this.destino,
    this.tipoBulto,
    this.dimensiones,
    this.peso,
    this.esAdr = false,
    this.adrTipo,
    this.adrCodigoUn,
    this.clienteNombre,
    this.clienteContacto,
    this.destinatarioNombre,
    this.destinatarioContacto,
  });

  final String type;
  final String? name;
  final String address;
  final String? driverId;
  final String? incoterm;
  final String? origen;
  final String? destino;
  final String? tipoBulto;
  final String? dimensiones;
  final double? peso;
  final bool esAdr;
  final String? adrTipo;
  final String? adrCodigoUn;
  final String? clienteNombre;
  final String? clienteContacto;
  final String? destinatarioNombre;
  final String? destinatarioContacto;
}
