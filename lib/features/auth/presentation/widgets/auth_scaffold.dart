import 'package:flutter/material.dart';

import '../../../../core/widgets/hub_top_bar.dart';

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

/// The auth app bar: the shared Figma "App bar" ([HubTopBar]) — a 40 px back
/// arrow at the start edge (it mirrors in Arabic) and an optional Heading 2
/// title next to it. The arrow always shows: these screens are entered from a
/// button, and a pop that has nowhere to go is a no-op.
class AuthAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AuthAppBar({super.key, this.title, this.onBack});

  final String? title;
  final VoidCallback? onBack;

  @override
  Size get preferredSize => const Size.fromHeight(HubTopBar.rowHeight);

  @override
  Widget build(BuildContext context) =>
      HubTopBar(title: title, onBack: onBack, showBack: true);
}
