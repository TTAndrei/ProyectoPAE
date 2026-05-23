import 'package:flutter/material.dart';

class AppMapPinIcon extends StatelessWidget {
  const AppMapPinIcon({
    super.key,
    required this.icon,
    required this.color,
    this.stopNumber,
  });

  final IconData icon;
  final Color color;
  final int? stopNumber;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color, width: 2.4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (stopNumber == null) Icon(icon, size: 23, color: color),
          if (stopNumber != null)
            Text(
              stopNumber.toString(),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          if (stopNumber != null)
            Positioned(
              right: 1,
              bottom: 1,
              child: Icon(
                icon,
                size: 11,
                color: color.withValues(alpha: 0.85),
              ),
            ),
        ],
      ),
    );
  }
}
