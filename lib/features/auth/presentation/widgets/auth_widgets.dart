import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';

/// The Figma "Button" component as the auth screens use it: 52 px, radius 12,
/// Button text (Bold 15). [AuthButton.primary] is the navy fill,
/// [AuthButton.outline] the navy outline ("Continue with WhatsApp code") and
/// [AuthButton.text] the orange text-only action ("Use email instead",
/// "Back to sign in"). [busy] swaps the label for a spinner and disables it.
class AuthButton extends StatelessWidget {
  const AuthButton.primary({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.leading,
  }) : _style = _AuthButtonStyle.primary;

  const AuthButton.outline({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.leading,
  }) : _style = _AuthButtonStyle.outline;

  const AuthButton.text({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.leading,
  }) : _style = _AuthButtonStyle.text;

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final Widget? leading;
  final _AuthButtonStyle _style;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final foreground = switch (_style) {
      _AuthButtonStyle.primary => Colors.white,
      _AuthButtonStyle.outline => AppColors.brandPrimary,
      _AuthButtonStyle.text => AppColors.accentStrong,
    };
    final child = busy
        ? SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[
                IconTheme(
                  data: IconThemeData(size: 20, color: foreground),
                  child: leading!,
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    final base = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(52)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 24),
      ),
      shape: WidgetStatePropertyAll(shape),
      textStyle: WidgetStatePropertyAll(t.button),
    );
    final onPressed = busy ? null : this.onPressed;
    return switch (_style) {
      _AuthButtonStyle.primary => FilledButton(
        onPressed: onPressed,
        style: base.merge(
          FilledButton.styleFrom(
            backgroundColor: AppColors.brandPrimary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: busy
                ? AppColors.brandPrimary
                : AppColors.brandPrimary.withValues(alpha: 0.4),
            disabledForegroundColor: Colors.white,
          ),
        ),
        child: child,
      ),
      _AuthButtonStyle.outline => OutlinedButton(
        onPressed: onPressed,
        style: base.merge(
          OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: AppColors.brandPrimary,
            side: const BorderSide(color: AppColors.brandPrimary, width: 1.5),
          ),
        ),
        child: child,
      ),
      _AuthButtonStyle.text => TextButton(
        onPressed: onPressed,
        style: base.merge(
          TextButton.styleFrom(foregroundColor: AppColors.accentStrong),
        ),
        child: child,
      ),
    };
  }
}

enum _AuthButtonStyle { primary, outline, text }

/// The round speech bubble of the frames' icon set (lucide "message-circle")
/// — the WhatsApp-code mark on Sign in and the Verify badge. Material has only
/// square bubbles. Sized and coloured by the ambient [IconTheme] unless given;
/// the stroke scales with the size as in the frames (2 px at 24).
class MessageCircleIcon extends StatelessWidget {
  const MessageCircleIcon({super.key, this.size, this.color});

  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final side = size ?? theme.size ?? 24;
    return CustomPaint(
      size: Size.square(side),
      painter: _MessageCirclePainter(
        color ?? theme.color ?? AppColors.inkHeading,
      ),
    );
  }
}

class _MessageCirclePainter extends CustomPainter {
  const _MessageCirclePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    canvas.scale(scale);
    // lucide message-circle: M7.9 20A9 9 0 1 0 4 16.1L2 22Z
    final path = Path()
      ..moveTo(7.9, 20)
      ..arcToPoint(
        const Offset(4, 16.1),
        radius: const Radius.circular(9),
        largeArc: true,
        clockwise: false,
      )
      ..lineTo(2, 22)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_MessageCirclePainter old) => old.color != color;
}

/// An inline orange link (Body Strong): "Forgot password?", "Change number",
/// "Create account".
class AuthLink extends StatelessWidget {
  const AuthLink({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Text(
          label,
          style: t.bodyStrong.copyWith(color: AppColors.accentStrong),
        ),
      ),
    );
  }
}

/// "New to Hub Market? Create account" — a muted prompt and a link, centred.
class AuthFooterPrompt extends StatelessWidget {
  const AuthFooterPrompt({
    super.key,
    required this.prompt,
    required this.action,
    required this.onTap,
  });

  final String prompt;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      children: [
        Text(prompt, style: t.body.copyWith(color: AppColors.inkMuted)),
        AuthLink(label: action, onTap: onTap),
      ],
    );
  }
}

/// The "or" rule between Sign in and "Continue with WhatsApp code".
class AuthOrDivider extends StatelessWidget {
  const AuthOrDivider({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return Row(
      children: [
        const Expanded(child: Divider(height: 1, color: AppColors.borderSubtle)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(label, style: t.caption.copyWith(color: AppColors.inkMuted)),
        ),
        const Expanded(child: Divider(height: 1, color: AppColors.borderSubtle)),
      ],
    );
  }
}

/// The S6 error banner: a pale red card with an alert icon, a Body Strong
/// title and an optional Caption line.
class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({super.key, required this.title, this.message});

  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.dangerSurface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 20,
              color: AppColors.danger,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: t.bodyStrong.copyWith(color: AppColors.danger),
                  ),
                  if (message != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      message!,
                      style: t.caption.copyWith(color: AppColors.danger),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The blue note under the reset-link field (06): info icon + Body text.
class AuthInfoNote extends StatelessWidget {
  const AuthInfoNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.infoSubtle,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 20, color: AppColors.info),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: t.body.copyWith(color: AppColors.info)),
          ),
        ],
      ),
    );
  }
}

/// A Register check row (Figma 04 "terms" / "newsletter"): a 20-px rounded
/// box — navy with a white tick when on, outlined when off — and its label.
class AuthCheckRow extends StatelessWidget {
  const AuthCheckRow({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
    this.emphasised = true,
    this.error = false,
  });

  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;

  /// Ink label (terms) vs muted label (the optional newsletter opt-in).
  final bool emphasised;

  /// Outlines the box in red — the terms were required but not accepted.
  final bool error;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return Semantics(
      checked: value,
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: value ? AppColors.brandPrimary : Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: value
                    ? null
                    : Border.all(
                        color: error ? AppColors.danger : AppColors.borderControl,
                        width: 1.5,
                      ),
              ),
              child: value
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: t.body.copyWith(
                  color: emphasised ? AppColors.inkHeading : AppColors.inkMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
