import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';

/// The `Email | Mobile` segmented control on Sign in and Reset password
/// (Figma 03 "method"): a pale track; the chosen segment is a raised white
/// pill with ink text, the other muted. Emits `true` when Mobile is chosen.
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
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _Segment(
              icon: HubIcons.mail,
              label: emailLabel,
              selected: !phoneSelected,
              onTap: () => onChanged(false),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _Segment(
              icon: HubIcons.phone,
              label: phoneLabel,
              selected: phoneSelected,
              onTap: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final color = selected ? AppColors.inkHeading : AppColors.inkMuted;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x1A0F2144),
                      offset: Offset(0, 6),
                      blurRadius: 20,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodyStrong.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
