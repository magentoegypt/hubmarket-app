import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/theme_x.dart';
import 'hub_top_bar.dart';
import '../../app/theme/hub_icons.dart';

/// The grouped-settings look of the account sub-pages (Figma 20b, 20h, 27):
/// white rounded cards on a light grey page, each under a small uppercase
/// label.

/// Page background behind [GroupCard]s.
Color groupedPageColor(BuildContext context) =>
    context.isDarkMode ? AppColors.surfaceDark : AppColors.surfaceSubtle;

/// Card surface of a [GroupCard].
Color groupCardColor(BuildContext context) =>
    context.isDarkMode ? const Color(0xFF243244) : Colors.white;

/// App bar of a pushed sub-page: the Figma "App bar" ([HubTopBar]) — back button
/// and a start-aligned 18 Bold title.
PreferredSizeWidget subpageAppBar(
  BuildContext context,
  String title, {
  List<Widget>? actions,
}) => HubTopBar(title: title, actions: actions ?? const <Widget>[]);

/// Small uppercase label above a group ("POPULAR TOPICS").
class GroupLabel extends StatelessWidget {
  const GroupLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(2, 20, 2, 8),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: context.scaffoldMuted,
      ),
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
        borderRadius: BorderRadius.circular(16),
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
                    : AppColors.borderDefault,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// A tappable row inside a [GroupCard]: icon, label, optional subtitle and
/// trailing value, and a chevron.
class GroupRow extends StatelessWidget {
  const GroupRow({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.subtitle,
    this.value,
    this.valueColor,
    this.showChevron = true,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final String? subtitle;
  final String? value;
  final Color? valueColor;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: context.scaffoldHeading),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      color: context.scaffoldHeading,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.scaffoldMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (value != null && value!.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                value!,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: valueColor ?? context.scaffoldMuted,
                ),
              ),
            ],
            if (showChevron) ...[
              const SizedBox(width: 6),
              Icon(HubIcons.chevronRight, size: 20, color: context.scaffoldMuted),
            ],
          ],
        ),
      ),
    );
  }
}
