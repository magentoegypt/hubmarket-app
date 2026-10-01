import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';

/// The layout every auth screen shares (Figma 03 – 06, S6): a 56-px app bar
/// with the back arrow (and, on Register, the title beside it), then a white
/// body that stacks [content] [gap] apart and pins [bottom] — the primary
/// action and the links under it — to the foot of the screen, scrolling
/// together with the rest once the keyboard or a long form needs the room.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.content,
    this.bottom = const <Widget>[],
    this.title,
    this.gap = 18,
    this.topPadding = 8,
    this.onBack,
  });

  final List<Widget> content;
  final List<Widget> bottom;
  final String? title;
  final double gap;

  /// Space between the app bar and the first item (4 under a title, else 8).
  final double topPadding;

  /// Replaces the default `Navigator.maybePop` of the back arrow.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AuthAppBar(title: title, onBack: onBack),
      // The last line sits on the home-indicator inset, as in the frames, and
      // never closer than 16 px to the edge where there is none.
      body: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 16),
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsetsDirectional.fromSTEB(16, topPadding, 16, 0),
              sliver: SliverList(
                delegate: SliverChildListDelegate(_spaced(content)),
              ),
            ),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: EdgeInsetsDirectional.fromSTEB(16, gap, 16, 0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _spaced(bottom),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _spaced(List<Widget> items) => <Widget>[
    for (var i = 0; i < items.length; i++) ...[
      if (i > 0) SizedBox(height: gap),
      items[i],
    ],
  ];
}

/// The auth app bar: a round 40-px back arrow at the start edge (it mirrors in
/// Arabic) and an optional Heading 2 title next to it.
class AuthAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AuthAppBar({super.key, this.title, this.onBack});

  final String? title;
  final VoidCallback? onBack;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return Material(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 40,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    // `arrow_back` mirrors itself in RTL (matchTextDirection).
                    icon: const Icon(HubIcons.arrowLeft, size: 22),
                    color: AppColors.inkHeading,
                    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                    onPressed: onBack ?? () => Navigator.maybePop(context),
                  ),
                ),
                const SizedBox(width: 4),
                if (title != null)
                  Expanded(
                    child: Text(
                      title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.heading2.copyWith(color: AppColors.inkHeading),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
