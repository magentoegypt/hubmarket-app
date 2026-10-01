import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/empty_state.dart';
import '../core/widgets/hub_button.dart';
import '../core/widgets/hub_top_bar.dart';
import '../l10n/l10n.dart';
import 'routes.dart';
import 'shell/hub_scaffold.dart';
import 'theme/app_colors.dart';
import 'theme/app_text_styles.dart';
import 'theme/hub_icons.dart';

/// Figma "S7 Page not found", the content: an amber disc with an orange
/// search glyph, "This page isn't available", why, and the two ways on —
/// "Search Hub Market" and "Go to Home". Shown wherever a link, a product or a
/// store turns out not to exist; [title] and [body] say it in that screen's own
/// words when the generic ones would be too vague.
class NotFoundState extends StatelessWidget {
  const NotFoundState({super.key, this.title, this.body});

  final String? title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return EmptyState(
      icon: HubIcons.search,
      discColor: AppColors.warningSubtle,
      iconColor: AppColors.accentStrong,
      title: title ?? l10n.notFoundTitle,
      // S7 sets the title in Heading 2, not the Heading 1 of the other states.
      titleStyle: AppTextStyles.of(context).heading2,
      body: body ?? l10n.notFoundBody,
      gap: 12,
      action: HubButton(
        label: l10n.notFoundSearch,
        onPressed: () => context.push(AppRoutes.search),
      ),
      secondaryAction: HubButton(
        label: l10n.notFoundHome,
        style: HubButtonStyle.outline,
        onPressed: () => context.go(AppRoutes.home),
      ),
    );
  }
}

/// S7 as a whole page — the back arrow (when there is somewhere to go back
/// to), [NotFoundState] and the tab bar with Home lit — for a location the
/// router could not match.
class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const HubScaffold(
      currentTab: AppTab.home,
      appBar: HubTopBar(),
      body: NotFoundState(),
    );
  }
}
