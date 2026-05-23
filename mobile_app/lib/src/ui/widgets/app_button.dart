import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

enum AppButtonVariant { primary, outlined, text }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.isLoading = false,
    this.icon,
  });

  final String text;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final bool isLoading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600);
    
    Widget buildChild(Color progressColor) {
      if (isLoading) {
        return SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: progressColor),
        );
      }
      if (icon != null) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Text(text),
          ],
        );
      }
      return Text(text);
    }

    switch (variant) {
      case AppButtonVariant.primary:
        return ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            textStyle: textStyle,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          onPressed: onPressed,
          child: buildChild(Colors.white),
        );
      case AppButtonVariant.outlined:
        return OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.neutral,
            side: const BorderSide(color: Color(0xFFD6D6D6)),
            textStyle: textStyle,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          onPressed: onPressed,
          child: buildChild(AppTheme.neutral),
        );
      case AppButtonVariant.text:
        return TextButton(
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.neutral,
            textStyle: textStyle,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          onPressed: onPressed,
          child: buildChild(AppTheme.neutral),
        );
    }
  }
}
