import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/driver_model.dart';
import '../../../providers/central_provider.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_empty_card.dart';

class CentralDriversScreen extends StatefulWidget {
  const CentralDriversScreen({super.key, required this.onViewOnMap});

  final Function(DriverModel) onViewOnMap;

  @override
  State<CentralDriversScreen> createState() => _CentralDriversScreenState();
}

class _CentralDriversScreenState extends State<CentralDriversScreen> {
  bool _showSlideOver = false;

  // Form Controllers
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
    });

    final centralProv = context.read<CentralProvider>();

    try {
      await centralProv.registerDriver(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        name: _nameController.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conductor registrado con éxito'),
          backgroundColor: Colors.green,
        ),
      );

      // Reset Form & Close SlideOver
      _nameController.clear();
      _usernameController.clear();
      _passwordController.clear();
      setState(() {
        _showSlideOver = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Widget _buildStatusChip(bool isAvailable) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isAvailable
            ? Colors.green.withValues(alpha: 0.1)
            : Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: isAvailable ? Colors.green : Colors.red,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isAvailable ? 'En Turno' : 'Fuera de Servicio',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isAvailable ? Colors.green : Colors.red,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingStars(String driverId) {
    final hash = driverId.hashCode.abs();
    final starCount = 4 + (hash % 2); // 4 or 5 stars
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        return Icon(
          index < starCount ? Icons.star_rounded : Icons.star_border_rounded,
          color: Colors.amber,
          size: 16,
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final centralProv = context.watch<CentralProvider>();
    final drivers = centralProv.drivers;
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isWide = screenWidth > 768;

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              isWide
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Gestión de Conductores',
                              style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.secondary),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Total de repartidores registrados: ${drivers.length}',
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                        AppButton(
                          onPressed: () {
                            setState(() {
                              _showSlideOver = true;
                            });
                          },
                          icon: Icons.person_add_rounded,
                          text: 'Añadir Conductor',
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Gestión de Conductores',
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.secondary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Total de repartidores registrados: ${drivers.length}',
                          style: const TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: AppButton(
                            onPressed: () {
                              setState(() {
                                _showSlideOver = true;
                              });
                            },
                            icon: Icons.person_add_rounded,
                            text: 'Añadir Conductor',
                          ),
                        ),
                      ],
                    ),
              const SizedBox(height: 24),

              // Drivers Table View
              Expanded(
                child: Card(
                  color: Colors.white,
                  child: drivers.isEmpty
                      ? AppEmptyCard(message: 'No hay conductores registrados')
                      : SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columnSpacing: 24,
                              dataRowMinHeight: 64,
                              dataRowMaxHeight: 64,
                              columns: const [
                                DataColumn(
                                    label: Text('Conductor',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold))),
                                DataColumn(
                                    label: Text('Compañía',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold))),
                                DataColumn(
                                    label: Text('Estado',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold))),
                                DataColumn(
                                    label: Text('Valoración',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold))),
                                DataColumn(
                                    label: Text('Acciones',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold))),
                              ],
                              rows: drivers.map((driver) {
                                return DataRow(
                                  cells: [
                                    // Conductor (Name + Username)
                                    DataCell(
                                      Row(
                                        children: [
                                          CircleAvatar(
                                            backgroundColor: AppTheme.secondary
                                                .withValues(alpha: 0.1),
                                            child: Text(
                                              driver.name.isNotEmpty
                                                  ? driver.name[0].toUpperCase()
                                                  : 'U',
                                              style: const TextStyle(
                                                  color: AppTheme.secondary,
                                                  fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                driver.name,
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold),
                                              ),
                                              Text(
                                                '@${driver.username}',
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Compañía
                                    DataCell(
                                      Text(driver.company != null
                                          ? driver.company!.name
                                          : 'PAE Logistics'),
                                    ),
                                    // Estado
                                    DataCell(
                                      _buildStatusChip(driver.isAvailable),
                                    ),
                                    // Valoración
                                    DataCell(
                                      _buildRatingStars(driver.id),
                                    ),
                                    // Acciones
                                    DataCell(
                                      Row(
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.map_rounded),
                                            tooltip: 'Ver en mapa',
                                            color: AppTheme.secondary,
                                            onPressed: driver.lat != null
                                                ? () =>
                                                    widget.onViewOnMap(driver)
                                                : null,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),

        // Slide-over Panel (Drawer implementation)
        if (_showSlideOver) ...[
          // Semi-transparent overlay to block background interaction slightly
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                if (!_isSaving) {
                  setState(() {
                    _showSlideOver = false;
                  });
                }
              },
              child: Container(
                color: Colors.black.withValues(alpha: 0.2),
              ),
            ),
          ),
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            child: Material(
              elevation: 16,
              child: Container(
                width: screenWidth < 600 ? screenWidth : 420.0,
                height: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(left: BorderSide(color: Colors.black12)),
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Slide-over Header
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 20),
                        color: AppTheme.secondary,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Añadir Conductor',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold),
                            ),
                            IconButton(
                              icon:
                                  const Icon(Icons.close, color: Colors.white),
                              onPressed: () {
                                if (!_isSaving) {
                                  setState(() {
                                    _showSlideOver = false;
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                      ),

                      // Scrollable Form Body
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Información de Cuenta',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: AppTheme.secondary),
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _nameController,
                                decoration: const InputDecoration(
                                  labelText: 'Nombre Completo',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.person),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Ingresa el nombre completo';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _usernameController,
                                decoration: const InputDecoration(
                                  labelText: 'Nombre de Usuario',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.alternate_email),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Ingresa un nombre de usuario';
                                  }
                                  if (value.trim().length < 3) {
                                    return 'Debe tener al menos 3 caracteres';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _passwordController,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  labelText: 'Contraseña de Acceso',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.lock),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Ingresa la contraseña';
                                  }
                                  if (value.length < 6) {
                                    return 'Debe tener al menos 6 caracteres';
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Form Action Buttons at bottom
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          border:
                              Border(top: BorderSide(color: Colors.black12)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16)),
                                onPressed: _isSaving
                                    ? null
                                    : () {
                                        setState(() {
                                          _showSlideOver = false;
                                        });
                                      },
                                child: const Text('Cancelar'),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: AppButton(
                                onPressed: _isSaving ? null : _submitRegister,
                                text:
                                    _isSaving ? 'Registrando...' : 'Registrar',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
