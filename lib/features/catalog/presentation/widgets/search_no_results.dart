import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../l10n/l10n.dart';
import 'search_style.dart';

/// A search that found nothing (Figma S2): the search glyph in a grey disc,
/// "No results for “…”" and a hint.
///
/// The frame's "Popular right now" rail is Build 2: the store has no
/// best-seller data to rank "popular" by, and Today's Deals (the other
/// candidate) waits for the Hub Market App module too. The "Try" suggestions
/// and "Browse … stores" button are left out as well: Magento's
/// `products.suggestions` comes back empty behind the Algolia adapter, and
/// vendor pages need the public vendor API (Build 2).
class SearchNoResults extends StatelessWidget {
  const SearchNoResults({super.key, required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final display = TextStyle(
      fontFamily: isEn ? AppTheme.displayFont : null,
      fontSize: 22,
      height: 28 / 22,
      fontWeight: FontWeight.w700,
      color: context.scaffoldHeading,
    );
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(top: 24, bottom: 24),
      children: [
        Center(
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: SearchStyle.pillFill(context),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.search, size: 48, color: context.scaffoldMuted),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            l10n.searchNoResultsTitle(isolateQuery(query)),
            textAlign: TextAlign.center,
            style: display,
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            l10n.searchNoResultsBody,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 20 / 14,
              color: context.scaffoldMuted,
            ),
          ),
        ),
      ],
    );
  }
}
