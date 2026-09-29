import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/shell/marketing_footer.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/config/store_contact.dart';
import '../../../../core/util/launch.dart';
import '../../../../core/widgets/hub_back_button.dart';
import '../../../../l10n/l10n.dart';

/// Help & FAQ (Figma `66:2`): a help search, up to three contact actions (Live
/// Chat / Call Us / Email), and a searchable FAQ accordion. FAQ content lives in
/// ARB; contact channels come from the backend ([storeContactProvider]) and a
/// channel the store doesn't publish has no card.
class HelpScreen extends ConsumerStatefulWidget {
  const HelpScreen({super.key});

  @override
  ConsumerState<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends ConsumerState<HelpScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = ref.watch(storeContactProvider);
    final whatsapp = c.whatsapp;
    final phone = c.phone;
    final email = c.email;
    final channels = <Widget>[
      if (whatsapp != null)
        _ContactCard(
          icon: Icons.headset_mic_outlined,
          label: l10n.helpLiveChat,
          onTap: () => _open(Uri.parse(whatsapp)),
        ),
      if (phone != null)
        _ContactCard(
          icon: Icons.call_outlined,
          label: l10n.helpCallUs,
          onTap: () => _open(Uri(scheme: 'tel', path: phone)),
        ),
      if (email != null)
        _ContactCard(
          icon: Icons.mail_outline,
          label: l10n.helpEmailLabel,
          onTap: () => _open(mailtoUri(email)),
        ),
    ];
    final faqs = <(String, String)>[
      (l10n.helpQ1, l10n.helpA1),
      (l10n.helpQ2, l10n.helpA2),
      (l10n.helpQ3, l10n.helpA3),
      (l10n.helpQ4, l10n.helpA4),
      (l10n.helpQ5, l10n.helpA5),
      (l10n.helpQ6, l10n.helpA6),
      (l10n.helpQ7, l10n.helpA7),
      (l10n.helpQ8, l10n.helpA8),
      (l10n.helpQPayments, l10n.helpAPayments),
      (l10n.helpQOrders, l10n.helpAOrders),
      (l10n.helpQ9, l10n.helpA9),
      (l10n.helpQ10, l10n.helpA10),
    ];
    final filtered = _query.isEmpty
        ? faqs
        : faqs
              .where(
                (f) =>
                    f.$1.toLowerCase().contains(_query) ||
                    f.$2.toLowerCase().contains(_query),
              )
              .toList();

    return HubScaffold(
      currentTab: AppTab.account,
      appBar: AppBar(
        centerTitle: true,
        leading: const HubBackButton(),
        title: Text(l10n.accountHelp),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          const _Band(),
          // Help search.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: TextField(
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: l10n.helpSearchHint,
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white10
                    : AppColors.surfaceMuted,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const _Band(),
          // Contact actions — only the channels the store publishes.
          if (channels.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  for (var i = 0; i < channels.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: channels[i]),
                  ],
                ],
              ),
            ),
            const _Band(),
          ],
          // Frequently Asked.
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 4),
            child: Text(
              l10n.helpFrequentlyAsked,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : AppColors.inkHeading,
              ),
            ),
          ),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: Text(l10n.stateEmpty)),
            )
          else
            for (var i = 0; i < filtered.length; i++)
              _FaqTile(
                key: ValueKey(filtered[i].$1),
                question: filtered[i].$1,
                answer: filtered[i].$2,
                // First item open by default when not searching (Figma).
                initiallyExpanded: _query.isEmpty && i == 0,
                showDivider: i != filtered.length - 1,
              ),
          const MarketingFooter(),
        ],
      ),
    );
  }

  Future<void> _open(Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final ok = await launchExternalUri(uri);
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.errorGeneric)));
    }
  }
}

/// 8px light section separator (Figma).
class _Band extends StatelessWidget {
  const _Band();
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 8,
    child: ColoredBox(
      color: Theme.of(context).brightness == Brightness.dark
          ? Colors.white10
          : AppColors.surfaceMuted,
    ),
  );
}

/// A bordered contact card: blush circular icon chip + label.
class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: dark ? const Color(0xFF243244) : Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: dark ? Colors.white24 : AppColors.borderDefault,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  color: AppColors.surfaceTint,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 22, color: AppColors.brandPrimary),
              ),
              const SizedBox(height: 9),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: dark ? Colors.white : AppColors.inkHeading,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A flat, divider-separated FAQ row that expands to reveal its answer.
class _FaqTile extends StatelessWidget {
  const _FaqTile({
    super.key,
    required this.question,
    required this.answer,
    required this.initiallyExpanded,
    required this.showDivider,
  });

  final String question;
  final String answer;
  final bool initiallyExpanded;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    // Dark mode: the question text was AppColors.inkHeading (#1F2937) on the
    // #1F2937 dark scaffold — invisible. Branch the text/divider for dark only,
    // leaving light mode unchanged.
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          iconColor: dark ? Colors.white70 : AppColors.inkMuted,
          collapsedIconColor: dark ? Colors.white70 : AppColors.inkMuted,
          title: Text(
            question,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: dark ? Colors.white : AppColors.inkHeading,
            ),
          ),
          children: [
            Text(
              answer,
              style: TextStyle(
                color: dark ? Colors.white70 : AppColors.inkMuted,
                height: 1.4,
              ),
            ),
          ],
        ),
        if (showDivider)
          Divider(
            height: 1,
            thickness: 1,
            indent: 16,
            endIndent: 16,
            color: dark ? Colors.white12 : AppColors.borderDefault,
          ),
      ],
    );
  }
}
