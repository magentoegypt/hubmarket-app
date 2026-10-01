import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';

/// A Home section header (Figma 07 "section-header/…"): an optional leading
/// glyph, the admin's title (Heading 1) and subtitle (Caption, 2 pt under it),
/// and the orange "See all →" action (Body Strong, 2 pt before a 16 pt arrow)
/// on the end side, centred on the whole header.
///
/// The header is as tall as its text: 28 for a title, 46 with a subtitle (30
/// with the 30 pt glyph). The action's tap target is the header's full height,
/// so it never makes the header taller than the frame draws it.
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
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (leading != null) ...[
                          leading!,
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            title,
                            // "Top Brands on Hub Market" takes two lines in
                            // English and three in Arabic.
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: t.heading1.copyWith(
                              color: AppColors.inkHeading,
                            ),
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
            ),
            if (action != null && onAction != null)
              InkWell(
                onTap: onAction,
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
          ],
        ),
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

/// An emoji set as a section glyph (🏆 Best sellers, 🆕 New stores): a 22 pt
/// square, as the frame draws it.
class HmHeaderEmoji extends StatelessWidget {
  const HmHeaderEmoji(this.emoji, {super.key});

  final String emoji;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 22,
    height: 22,
    child: FittedBox(
      child: Text(emoji, style: const TextStyle(fontSize: 20, height: 1)),
    ),
  );
}
