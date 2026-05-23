import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.labelText,
    this.hintText,
    this.obscureText = false,
    this.validator,
    this.fillColor,
    this.style,
    this.labelStyle,
    this.focusedBorderColor,
  });

  final TextEditingController? controller;
  final String? labelText;
  final String? hintText;
  final bool obscureText;
  final String? Function(String?)? validator;
  final Color? fillColor;
  final TextStyle? style;
  final TextStyle? labelStyle;
  final Color? focusedBorderColor;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      validator: validator,
      style: style,
      decoration: InputDecoration(
        labelText: labelText,
        labelStyle: labelStyle,
        hintText: hintText,
        filled: true,
        fillColor: fillColor ?? const Color(0xFFF0F0F0),
        hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF8A8A8A)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: focusedBorderColor ?? AppTheme.primary,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
      ),
    );
  }
}
