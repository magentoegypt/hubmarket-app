import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// EN / AR pill toggle (Figma): a light-grey rounded track with the active
/// segment filled burgundy (white label). Shared by the Welcome screen and the
/// menu drawer.
class LanguageToggle extends StatelessWidget {
  const LanguageToggle({
    super.key,
    required this.activeLocale,
    required this.onChanged,
  });

  final String activeLocale;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        // Oval / stadium pill per Figma.
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [_segment('EN', 'en'), _segment('AR', 'ar')],
      ),
    );
  }

  Widget _segment(String label, String value) {
    final selected = (activeLocale == 'ar' ? 'ar' : 'en') == value;
    return GestureDetector(
      onTap: () => onChanged(value),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.inkMuted,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
