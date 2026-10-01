import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';

/// Figma "Chip": a 36 px pill with 14 px of padding, the label in EN/Body Strong
/// (AR Medium). Unselected it is white with a 1 px `border/default` outline
/// that takes room of its own (the frame's border box: 1 + 14 px each side);
/// selected it is the navy fill with a white label.
///
/// [leading] / [trailing] sit inside the padding (an icon, a count); with no
/// [onTap] the chip is just a label.
class HubChip extends StatelessWidget {
  const HubChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.leading,
    this.trailing,
    this.semanticLabel,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? leading;
  final Widget? trailing;
  final String? semanticLabel;

  static const double height = 36;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final foreground = selected ? Colors.white : AppColors.inkHeading;
    final content = Padding(
      padding: EdgeInsets.symmetric(horizontal: selected ? 14 : 15),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 6)],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.bodyStrong.copyWith(color: foreground),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 6), trailing!],
        ],
      ),
    );
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: semanticLabel,
      child: Material(
        color: selected ? AppColors.brandPrimary : Colors.white,
        shape: StadiumBorder(
          side: selected
              ? BorderSide.none
              : const BorderSide(color: AppColors.borderStrong),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: height,
            child: Center(widthFactor: 1, child: content),
          ),
        ),
      ),
    );
  }
}
