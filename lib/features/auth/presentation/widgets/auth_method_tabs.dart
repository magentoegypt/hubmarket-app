import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';

/// The `Email | Phone Number` segmented pill on Sign In and Forgot Password
/// (Figma). Selected segment = burgundy fill / white text; unselected = grey
/// fill / dark text. Emits `true` when the Phone segment is chosen.
class AuthMethodTabs extends StatelessWidget {
  const AuthMethodTabs({
    super.key,
    required this.emailLabel,
    required this.phoneLabel,
    required this.phoneSelected,
    required this.onChanged,
  });

  final String emailLabel;
  final String phoneLabel;
  final bool phoneSelected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _segment(emailLabel, selected: !phoneSelected, onTap: () => onChanged(false)),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _segment(phoneLabel, selected: phoneSelected, onTap: () => onChanged(true)),
          ),
        ],
      ),
    );
  }

  Widget _segment(String label, {required bool selected, required VoidCallback onTap}) {
    return Material(
      color: selected ? AppColors.brandPrimary : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : AppColors.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}
