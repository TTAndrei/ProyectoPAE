import 'package:flutter/material.dart';
import '../../models/order_model.dart';
import '../../theme/app_theme.dart';
import 'app_button.dart';
import 'app_status_chip.dart';

class DriverOrderCard extends StatelessWidget {
  const DriverOrderCard({
    super.key,
    required this.index,
    required this.order,
    required this.isLoading,
    required this.onAccept,
    required this.onReject,
    required this.onViewDetails,
  });

  final int index;
  final OrderModel order;
  final bool isLoading;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onViewDetails;

  IconData _orderTypeIcon(String type) {
    switch (type) {
      case 'pickup':
        return Icons.inventory_2_rounded;
      case 'delivery':
        return Icons.subdirectory_arrow_right_rounded;
      default:
        return Icons.location_on;
    }
  }

  String _orderTypeLabel(String type) {
    switch (type) {
      case 'pickup':
        return 'Pickup';
      case 'delivery':
        return 'Delivery';
      default:
        return type;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: AppTheme.secondary.withValues(alpha: 0.1),
                  child: Text(
                    index.toString(),
                    style: const TextStyle(
                      color: AppTheme.secondary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (order.name != null)
                        Text(
                          order.name!,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      Text(
                        order.address,
                        style: TextStyle(
                          fontWeight: order.name != null
                              ? FontWeight.w400
                              : FontWeight.w600,
                          fontSize: order.name != null ? 12 : 14,
                        ),
                      ),
                    ],
                  ),
                ),
                AppStatusChip(status: order.status),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(_orderTypeIcon(order.type),
                    size: 18, color: AppTheme.tertiary),
                const SizedBox(width: 6),
                Text('${_orderTypeLabel(order.type)} - ${order.id}'),
              ],
            ),
            if (order.estimatedExtraMinutes != null) ...[
              const SizedBox(height: 6),
              Text(
                'Extra estimado: ${order.estimatedExtraMinutes!.toStringAsFixed(1)} min',
              ),
            ],
            const SizedBox(height: 12),
            if (order.status == 'assigned')
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      onPressed: isLoading ? null : onReject,
                      icon: Icons.close,
                      text: 'Rechazar',
                      variant: AppButtonVariant.outlined,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppButton(
                      onPressed: isLoading ? null : onAccept,
                      icon: Icons.check,
                      text: 'Aceptar',
                    ),
                  ),
                ],
              ),
            if (order.status == 'in_progress')
              AppButton(
                onPressed: onViewDetails,
                text: 'Ver detalles',
                variant: AppButtonVariant.outlined,
              ),
          ],
        ),
      ),
    );
  }
}
