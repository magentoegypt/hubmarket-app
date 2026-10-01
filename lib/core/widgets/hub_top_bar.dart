import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';
import 'hub_back_button.dart';

/// Figma "App bar": a 56 px row under the status bar — an optional 40 px back
/// button at 12 px from the edge, the title (EN/Heading 2: 18 Bold) after it,
/// and the 40 px icon buttons ([actions], see `HubIconButton`) at the end.
///
/// Pass it as `appBar:` of a `Scaffold` / `HubScaffold`. [showBack] defaults to
/// "this route can be popped", so tab roots get none and pushed pages get one.
/// [subtitle] puts a muted caption under the title (the cart's "4 items · 2
/// stores"); [titleWidget] replaces the title for anything richer.
class HubTopBar extends StatelessWidget implements PreferredSizeWidget {
  const HubTopBar({
    super.key,
    this.title,
    this.titleWidget,
    this.subtitle,
    this.showBack,
    this.onBack,
    this.leading,
    this.actions = const <Widget>[],
    this.backgroundColor = Colors.white,
    this.foregroundColor,
    this.bottom,
    this.horizontalPadding = 12,
  });

  final String? title;
  final Widget? titleWidget;
  final String? subtitle;

  /// Null: show the back button when the route can be popped.
  final bool? showBack;

  /// Replaces the default back (`Navigator.maybePop`).
  final VoidCallback? onBack;

  /// Replaces the back button.
  final Widget? leading;
  final List<Widget> actions;
  final Color backgroundColor;

  /// Title and back-icon colour; ink by default (white on a navy bar).
  final Color? foregroundColor;

  /// A strip under the row (tabs, a search field, a divider).
  final PreferredSizeWidget? bottom;
  final double horizontalPadding;

  static const double rowHeight = 56;

  @override
  Size get preferredSize =>
      Size.fromHeight(rowHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final ink = foregroundColor ?? AppColors.inkHeading;
    final back =
        showBack ?? (ModalRoute.of(context)?.impliesAppBarDismissal ?? false);
    final lead =
        leading ??
        (back ? HubBackButton(color: ink, onPressed: onBack) : null);
    final dark = ThemeData.estimateBrightnessForColor(backgroundColor) ==
        Brightness.dark;

    final titleColumn = titleWidget ??
        (title == null
            ? const SizedBox.shrink()
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.heading2.copyWith(color: ink),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.caption.copyWith(color: AppColors.inkMuted),
                    ),
                ],
              ));

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Material(
        color: backgroundColor,
        child: SafeArea(
          bottom: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: rowHeight,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: Row(
                    children: [
                      if (lead != null) ...[lead, const SizedBox(width: 4)],
                      Expanded(
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: titleColumn,
                        ),
                      ),
                      ...actions,
                    ],
                  ),
                ),
              ),
              if (bottom != null) bottom!,
            ],
          ),
        ),
      ),
    );
  }
}
