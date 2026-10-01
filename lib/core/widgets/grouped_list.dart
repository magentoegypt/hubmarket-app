import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';
import '../../app/theme/hub_icons.dart';
import '../../app/theme/theme_x.dart';
import 'hub_top_bar.dart';

/// The grouped-settings look of the Account frames (20, 20b, 20e, 20h, 27):
/// white 14 px cards on the light grey page, each under a small muted label,
/// rows of an icon, a label, an optional value and a chevron, a hairline
/// between rows.

/// Page background behind [GroupCard]s.
Color groupedPageColor(BuildContext context) =>
    context.isDarkMode ? AppColors.surfaceDark : AppColors.surfaceSubtle;

/// Card surface of a [GroupCard].
Color groupCardColor(BuildContext context) =>
    context.isDarkMode ? const Color(0xFF243244) : Colors.white;

/// App bar of a pushed sub-page: the Figma "App bar" ([HubTopBar]) — back button
/// and a start-aligned 18 Bold title. [divider] draws the 1 px `border/subtle`
/// rule on the bar's last pixel, as the frames on a white page do (20c, 20g,
/// 28); the bar keeps its 56 px.
PreferredSizeWidget subpageAppBar(
  BuildContext context,
  String title, {
  List<Widget>? actions,
  bool divider = false,
}) => HubTopBar(
  title: title,
  actions: actions ?? const <Widget>[],
  bottom: divider ? const _AppBarDivider() : null,
);

/// A hairline over the last pixel of the app bar's row: it takes no height of
/// its own, so the bar stays the frame's 56 px.
class _AppBarDivider extends StatelessWidget implements PreferredSizeWidget {
  const _AppBarDivider();

  @override
  Size get preferredSize => Size.zero;

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 0,
    child: OverflowBox(
      maxHeight: 1,
      alignment: Alignment.bottomCenter,
      child: Divider(height: 1, thickness: 1, color: AppColors.borderSubtle),
    ),
  );
}

/// Small muted label above a group ("POPULAR TOPICS"): EN/Caption Strong, the
/// text in capitals. [top] is the gap above it (18 between groups, 14 under the
/// app bar), [bottom] the gap to the card (8; 20b draws 16).
class GroupLabel extends StatelessWidget {
  const GroupLabel(this.text, {super.key, this.top = 18, this.bottom = 8});

  final String text;
  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsetsDirectional.only(top: top, bottom: bottom),
    child: Text(
      text.toUpperCase(),
      style: AppTextStyles.of(
        context,
      ).captionStrong.copyWith(color: context.scaffoldMuted),
    ),
  );
}

/// A white rounded card holding [children] separated by hairlines.
class GroupCard extends StatelessWidget {
  const GroupCard({super.key, required this.children, this.padding});

  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: groupCardColor(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: context.isDarkMode
                    ? Colors.white12
                    : AppColors.borderSubtle,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// A tappable row inside a [GroupCard]: a 20 px icon, the label (EN/Body), an
/// optional subtitle and trailing value (EN/Body Strong, muted unless
/// [valueColor] says otherwise) and a chevron. 14 px of padding and 12 between
/// the parts, so a one-line row is 48 px (EN) high.
class GroupRow extends StatelessWidget {
  const GroupRow({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.iconColor,
    this.labelColor,
    this.subtitle,
    this.value,
    this.valueColor,
    this.showChevron = true,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  /// The icon's colour; `text/subtle` by default, the label's own for a row
  /// that says something (Sign out).
  final Color? iconColor;
  final Color? labelColor;
  final String? subtitle;
  final String? value;
  final Color? valueColor;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final dark = context.isDarkMode;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 20,
                color: iconColor ?? (dark ? Colors.white70 : AppColors.inkSubtle),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: t.body.copyWith(
                      color: labelColor ?? context.scaffoldHeading,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(
                      subtitle!,
                      style: t.caption.copyWith(color: context.scaffoldMuted),
                    ),
                ],
              ),
            ),
            if (value != null && value!.isNotEmpty) ...[
              const SizedBox(width: 12),
              Text(
                value!,
                style: t.bodyStrong.copyWith(
                  color: valueColor ?? context.scaffoldMuted,
                ),
              ),
            ],
            if (showChevron) ...[
              const SizedBox(width: 12),
              Icon(HubIcons.chevronRight, size: 18, color: context.scaffoldMuted),
            ],
          ],
        ),
      ),
    );
  }
}
