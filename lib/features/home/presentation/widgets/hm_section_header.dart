import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';

/// A Home section header (Figma 07 "section-header/…"): an optional leading
/// glyph, the admin's title (Heading 1) and subtitle (Caption), and the
/// orange "See all →" action on the end side.
class HmSectionHeader extends StatelessWidget {
  const HmSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final action = actionLabel;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (leading != null) ...[
                      leading!,
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.heading1.copyWith(color: AppColors.inkHeading),
                      ),
                    ),
                  ],
                ),
                if ((subtitle ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.caption.copyWith(color: AppColors.inkMuted),
                  ),
                ],
              ],
            ),
          ),
          if (action != null && onAction != null) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      action,
                      style: t.bodyStrong.copyWith(
                        color: AppColors.accentStrong,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(
                      HubIcons.arrowRight,
                      size: 16,
                      color: AppColors.accentStrong,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A 30 pt tinted square behind a section's glyph (Today's Deals' tag).
class HmHeaderGlyph extends StatelessWidget {
  const HmHeaderGlyph({super.key, required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 30,
    height: 30,
    decoration: BoxDecoration(
      color: AppColors.accentSubtle,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Icon(icon, size: 18, color: AppColors.accentStrong),
  );
}

/// An emoji set as a section glyph (🏆 Best sellers, 🆕 New stores).
class HmHeaderEmoji extends StatelessWidget {
  const HmHeaderEmoji(this.emoji, {super.key});

  final String emoji;

  @override
  Widget build(BuildContext context) => Text(
    emoji,
    style: const TextStyle(fontSize: 20, height: 1.1),
  );
}
