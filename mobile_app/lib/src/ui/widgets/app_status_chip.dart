import 'package:flutter/material.dart';

class AppStatusChip extends StatelessWidget {
  const AppStatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _colorForStatus(status).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        _labelForStatus(status),
        style: TextStyle(
          color: _colorForStatus(status),
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  Color _colorForStatus(String value) {
    switch (value) {
      case 'pending':
        return const Color(0xFFB45309);
      case 'assigned':
        return const Color(0xFF1D4ED8);
      case 'in_progress':
        return const Color(0xFF0F766E);
      case 'completed':
        return const Color(0xFF166534);
      case 'rejected':
        return const Color(0xFFB91C1C);
      default:
        return Colors.black54;
    }
  }

  String _labelForStatus(String value) {
    switch (value) {
      case 'pending':
        return 'Pendiente';
      case 'assigned':
        return 'Asignado';
      case 'in_progress':
        return 'En curso';
      case 'completed':
        return 'Completado';
      case 'rejected':
        return 'Rechazado';
      default:
        return value;
    }
  }
}
