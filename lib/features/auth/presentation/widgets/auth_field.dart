import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';

/// Figma auth input (Sign In 59:16 / 59:21): the app-wide filled-grey field
/// (from the theme) with a muted leading icon and a placeholder — no floating
/// label. The optional [suffixIcon] hosts the password visibility toggle.
class AuthField extends StatelessWidget {
  const AuthField({
    super.key,
    required this.controller,
    required this.icon,
    required this.hint,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.textCapitalization = TextCapitalization.none,
    this.obscureText = false,
    this.suffixIcon,
    this.validator,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final IconData icon;
  final String hint;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final TextCapitalization textCapitalization;
  final bool obscureText;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      obscureText: obscureText,
      validator: validator,
      onFieldSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 20, color: AppColors.inkFaint),
        suffixIcon: suffixIcon,
      ),
    );
  }
}
