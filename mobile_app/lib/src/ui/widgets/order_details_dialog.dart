import 'package:flutter/material.dart';
import '../../models/order_model.dart';
import '../../theme/app_theme.dart';
import 'app_button.dart';
import 'app_status_chip.dart';

class OrderDetailsDialog extends StatelessWidget {
  const OrderDetailsDialog({
    super.key,
    required this.order,
    this.onNavigate,
    this.onComplete,
    this.onAccept,
    this.onReject,
  });

  final OrderModel order;
  final VoidCallback? onNavigate;
  final VoidCallback? onComplete;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;

  String _formatDateTime(String? isoString) {
    if (isoString == null) return 'N/A';
    try {
      final parsed = DateTime.parse(isoString);
      return '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year} ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoString;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPickup = order.type == 'pickup';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Accent Banner
              Container(
                color: isPickup ? AppTheme.secondary : AppTheme.primary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Row(
                  children: [
                    Icon(
                      isPickup ? Icons.inventory_2 : Icons.local_shipping,
                      color: Colors.white,
                      size: 28,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isPickup
                                ? 'DETALLES DE RECOGIDA'
                                : 'DETALLES DE ENTREGA',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.white70,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Pedido #${order.id.substring(0, order.id.length > 8 ? 8 : order.id.length).toUpperCase()}',
                            style: const TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Estado actual:',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey,
                          ),
                        ),
                        AppStatusChip(status: order.status),
                      ],
                    ),
                    const Divider(height: 32, color: Color(0xFFEAE7E7)),

                    // Client / Merchant name
                    _buildDetailRow(
                      icon: Icons.person_outline,
                      label: isPickup
                          ? 'Remitente / Proveedor'
                          : 'Destinatario / Cliente',
                      value: order.name ??
                          (isPickup ? 'Proveedor Express' : 'Cliente General'),
                    ),
                    const SizedBox(height: 20),

                    // Address
                    _buildDetailRow(
                      icon: Icons.place_outlined,
                      label: 'Dirección Completa',
                      value: order.address,
                    ),
                    const SizedBox(height: 20),

                    // Coordinates
                    Row(
                      children: [
                        Expanded(
                          child: _buildDetailRow(
                            icon: Icons.map_outlined,
                            label: 'Latitud',
                            value: order.lat.toStringAsFixed(6),
                          ),
                        ),
                        Expanded(
                          child: _buildDetailRow(
                            icon: Icons.map_outlined,
                            label: 'Longitud',
                            value: order.lng.toStringAsFixed(6),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Shipping details section
                    _buildSectionDivider('DATOS DEL ENVÍO'),

                    if (order.incoterm != null && order.incoterm!.isNotEmpty) ...[
                      _buildDetailRow(
                        icon: Icons.gavel_outlined,
                        label: 'Incoterm',
                        value: order.incoterm!,
                      ),
                      const SizedBox(height: 16),
                    ],

                    if (order.origen != null && order.origen!.isNotEmpty) ...[
                      _buildDetailRow(
                        icon: Icons.location_on_outlined,
                        label: 'Origen del Envío',
                        value: order.origen!,
                      ),
                      const SizedBox(height: 16),
                    ],

                    if (order.destino != null && order.destino!.isNotEmpty) ...[
                      _buildDetailRow(
                        icon: Icons.flag_outlined,
                        label: 'Destino del Envío',
                        value: order.destino!,
                      ),
                      const SizedBox(height: 16),
                    ],

                    if (order.tipoBulto != null && order.tipoBulto!.isNotEmpty) ...[
                      _buildDetailRow(
                        icon: Icons.inventory_2_outlined,
                        label: 'Tipo de Bulto',
                        value: order.tipoBulto![0].toUpperCase() + order.tipoBulto!.substring(1),
                      ),
                      const SizedBox(height: 16),
                    ],

                    if (order.dimensiones != null && order.dimensiones!.isNotEmpty) ...[
                      _buildDetailRow(
                        icon: Icons.straighten_outlined,
                        label: 'Dimensiones',
                        value: order.dimensiones!,
                      ),
                      const SizedBox(height: 16),
                    ],

                    if (order.peso != null) ...[
                      _buildDetailRow(
                        icon: Icons.scale_outlined,
                        label: 'Peso total',
                        value: '${order.peso!.toStringAsFixed(1)} kg',
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ADR Warning Box
                    if (order.esAdr) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3CD),
                          border: Border.all(color: const Color(0xFFFFEBA8)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Color(0xFF856404), size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'MERCANCÍA PELIGROSA (ADR)',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF856404),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Clase: ${order.adrTipo ?? "No especificada"}\nCódigo UN: ${order.adrCodigoUn ?? "No especificado"}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF533F03),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Client & Recipient Contacts Section
                    if ((order.clienteNombre != null && order.clienteNombre!.isNotEmpty) ||
                        (order.destinatarioNombre != null && order.destinatarioNombre!.isNotEmpty)) ...[
                      _buildSectionDivider('CLIENTE Y DESTINATARIO'),
                    ],

                    if (order.clienteNombre != null && order.clienteNombre!.isNotEmpty) ...[
                      _buildDetailRow(
                        icon: Icons.person_outline,
                        label: 'Cliente / Remitente',
                        value: '${order.clienteNombre!}${order.clienteContacto != null && order.clienteContacto!.isNotEmpty ? " (${order.clienteContacto})" : ""}',
                      ),
                      const SizedBox(height: 16),
                    ],

                    if (order.destinatarioNombre != null && order.destinatarioNombre!.isNotEmpty) ...[
                      _buildDetailRow(
                        icon: Icons.local_shipping_outlined,
                        label: 'Destinatario',
                        value: '${order.destinatarioNombre!}${order.destinatarioContacto != null && order.destinatarioContacto!.isNotEmpty ? " (${order.destinatarioContacto})" : ""}',
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Timestamps & Estimates
                    _buildSectionDivider('LOGÍSTICA Y TIEMPOS'),

                    if (order.estimatedExtraMinutes != null) ...[
                      _buildDetailRow(
                        icon: Icons.timer_outlined,
                        label: 'Desvío estimado',
                        value:
                            '+${order.estimatedExtraMinutes!.toStringAsFixed(1)} minutos extra',
                      ),
                      const SizedBox(height: 20),
                    ],

                    _buildDetailRow(
                      icon: Icons.calendar_today_outlined,
                      label: 'Fecha de creación',
                      value: _formatDateTime(order.createdAt),
                    ),
                    const SizedBox(height: 20),

                    _buildDetailRow(
                      icon: Icons.edit_calendar_outlined,
                      label: 'Última actualización',
                      value: _formatDateTime(order.updatedAt),
                    ),

                    const SizedBox(height: 28),

                    // Action Buttons
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (order.status == 'assigned' &&
                            onAccept != null &&
                            onReject != null) ...[
                          Row(
                            children: [
                              Expanded(
                                child: AppButton(
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    onReject!();
                                  },
                                  icon: Icons.close,
                                  text: 'Rechazar',
                                  variant: AppButtonVariant.outlined,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: AppButton(
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    onAccept!();
                                  },
                                  icon: Icons.check,
                                  text: 'Aceptar',
                                  variant: AppButtonVariant.primary,
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          if (onComplete != null &&
                              order.status == 'in_progress') ...[
                            AppButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                                onComplete!();
                              },
                              icon: Icons.check_circle_outline,
                              text: isPickup
                                  ? 'Completar Recogida'
                                  : 'Completar Entrega',
                            ),
                            const SizedBox(height: 12),
                          ],
                          Row(
                            children: [
                              if (onNavigate != null) ...[
                                Expanded(
                                  child: AppButton(
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                      onNavigate!();
                                    },
                                    icon: Icons.navigation_outlined,
                                    text: 'Navegar',
                                    variant: (onComplete != null &&
                                            order.status == 'in_progress')
                                        ? AppButtonVariant.outlined
                                        : AppButtonVariant.primary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                              ],
                              Expanded(
                                child: AppButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  text: 'Cerrar',
                                  variant: AppButtonVariant.outlined,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey.shade400),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade500,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2F2E2E),
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionDivider(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              letterSpacing: 0.8,
            ),
          ),
          const Divider(height: 12, color: Color(0xFFEAE7E7)),
        ],
      ),
    );
  }
}
