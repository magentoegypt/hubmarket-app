import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';

/// The five looks of the Figma "Button" component.
enum HubButtonStyle {
  /// Navy fill, white label.
  primary,

  /// `accent-strong` (orange) fill, white label.
  accent,

  /// White fill, 1.5 px navy outline, navy label.
  outline,

  /// No fill, orange label.
  ghost,

  /// `danger-subtle` fill, red label.
  danger,
}

/// Figma "Button": 52 px high, radius 12, 24 px of side padding, an optional
/// 20 px icon before the EN/Button label (15 Bold; AR Tajawal Bold). Full width
/// unless [expand] is false. [loading] swaps the icon for a spinner and ignores
/// taps; a null [onPressed] shows it disabled.
///
/// The theme's `FilledButton` / `OutlinedButton` already match this component
/// for the two common cases; reach for [HubButton] when the screen needs the
/// accent, ghost or danger look, an icon, or the busy state.
class HubButton extends StatelessWidget {
  const HubButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.style = HubButtonStyle.primary,
    this.icon,
    this.loading = false,
    this.expand = true,
    this.height = 52,
    this.iconSize = 20,
    this.horizontalPadding = 24,
  });

  final String label;
  final VoidCallback? onPressed;
  final HubButtonStyle style;
  final IconData? icon;
  final bool loading;
  final bool expand;
  final double height;

  /// The leading icon's size: 18 px, the 20 px "lead" slot of the footer
  /// buttons (Add new address, New return request) where a frame draws it.
  final double iconSize;

  /// The side padding: 24 px, less for two buttons side by side whose labels
  /// would otherwise be cut (the package card's Track parcel / Contact store,
  /// where the frame lets the content run into the padding).
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final (fill, ink) = switch (style) {
      HubButtonStyle.primary => (AppColors.brandPrimary, Colors.white),
      HubButtonStyle.accent => (AppColors.accentStrong, Colors.white),
      HubButtonStyle.outline => (Colors.white, AppColors.brandPrimary),
      HubButtonStyle.ghost => (Colors.transparent, AppColors.accentStrong),
      HubButtonStyle.danger => (AppColors.dangerSurface, AppColors.danger),
    };
    final enabled = onPressed != null && !loading;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    final size = expand ? Size.fromHeight(height) : Size(0, height);
    final base = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(size),
      maximumSize: WidgetStatePropertyAll(
        expand ? Size.fromHeight(height) : Size(double.infinity, height),
      ),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: horizontalPadding),
      ),
      shape: WidgetStatePropertyAll(shape),
      textStyle: WidgetStatePropertyAll(t.button),
      elevation: const WidgetStatePropertyAll(0),
    );

    final child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: ink),
          )
        else if (icon != null)
          Icon(icon, size: iconSize),
        if (loading || icon != null) const SizedBox(width: 8),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );

    return switch (style) {
      HubButtonStyle.outline => OutlinedButton(
        onPressed: enabled ? onPressed : null,
        style: base.merge(
          OutlinedButton.styleFrom(
            foregroundColor: ink,
            backgroundColor: fill,
            disabledForegroundColor: AppColors.disabled,
            side: BorderSide(
              color: enabled ? AppColors.brandPrimary : AppColors.borderStrong,
              width: 1.5,
            ),
          ),
        ),
        child: child,
      ),
      HubButtonStyle.ghost => TextButton(
        onPressed: enabled ? onPressed : null,
        style: base.merge(
          TextButton.styleFrom(
            foregroundColor: ink,
            disabledForegroundColor: AppColors.disabled,
          ),
        ),
        child: child,
      ),
      _ => FilledButton(
        onPressed: enabled ? onPressed : null,
        style: base.merge(
          FilledButton.styleFrom(
            foregroundColor: ink,
            backgroundColor: fill,
            disabledForegroundColor: AppColors.disabled,
            disabledBackgroundColor: AppColors.surfaceMuted,
          ),
        ),
        child: child,
      ),
    };
  }
}
