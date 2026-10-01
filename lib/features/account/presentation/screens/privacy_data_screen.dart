import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/widgets/grouped_list.dart';
import '../../../../core/widgets/hub_button.dart';
import '../../../../core/widgets/hub_checkbox.dart';
import '../../../../l10n/l10n.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../cms/presentation/cms_navigation.dart';
import '../../../cms/presentation/cms_providers.dart';
import '../../../store_credit/domain/credit_money.dart';
import '../../../store_credit/presentation/store_credit_providers.dart';
import '../delete_account_action.dart';
import '../../../../app/theme/hub_icons.dart';

/// Privacy & data (Figma 20b): the store's policies and account deletion.
///
/// Built from what the backend can do today. Left out of the frame, because
/// nothing behind them exists: "Download my data" (no data-export endpoint),
/// "Cookie & personalisation consent" (the app sets no tracking cookies and
/// has no consent store), the password confirmation (core `deleteCustomer`
/// takes none, and customers who joined by WhatsApp code may not have one)
/// and "open orders must be delivered or cancelled first" (Magento does not
/// enforce it). The credit balance line shows once the store has store
/// credit (HubAppAccount) and the customer's balance is above zero.
class PrivacyDataScreen extends ConsumerWidget {
  const PrivacyDataScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final signedIn = ref.watch(
      authControllerProvider.select((s) => s.isAuthenticated),
    );
    final legal = ref.watch(legalLinksProvider).valueOrNull ?? const [];

    return HubScaffold(
      currentTab: AppTab.account,
      appBar: subpageAppBar(context, l10n.privacyDataTitle),
      body: ColoredBox(
        color: groupedPageColor(context),
        // The frame's body: 14 under the bar, 16 between its parts.
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          children: [
            if (legal.isNotEmpty) ...[
              GroupLabel(l10n.privacyPolicies, top: 0, bottom: 16),
              GroupCard(
                children: [
                  for (final link in legal)
                    GroupRow(
                      icon: legalLinkIcon(link),
                      label: link.label,
                      onTap: () => openStorePageLink(context, ref, link),
                    ),
                ],
              ),
            ],
            if (signedIn) ...[
              if (legal.isNotEmpty) const SizedBox(height: 16),
              const _DeleteAccountCard(),
            ],
          ],
        ),
      ),
    );
  }
}

/// The destructive card: what goes, what stays, an explicit "I understand"
/// and the delete button, which stays disabled until it is ticked.
class _DeleteAccountCard extends ConsumerStatefulWidget {
  const _DeleteAccountCard();

  @override
  ConsumerState<_DeleteAccountCard> createState() => _DeleteAccountCardState();
}

class _DeleteAccountCardState extends ConsumerState<_DeleteAccountCard> {
  bool _understood = false;
  bool _busy = false;

  Future<void> _delete() async {
    setState(() => _busy = true);
    final deleted = await deleteAccountNow(context, ref);
    if (!deleted && mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    // Deleting the account forfeits its store credit: say so while there is
    // some (Build 2 with store credit on).
    final credit = ref.watch(storeCreditEnabledProvider)
        ? ref.watch(storeCreditBalanceProvider).valueOrNull?.balance
        : null;
    final losses = [
      l10n.deleteAccountLoseOrders,
      l10n.deleteAccountLoseSaved,
      if (credit != null && credit.amount > 0)
        // "AED 120.00" in a left-to-right isolate, so it keeps its order in
        // RTL.
        l10n.deleteAccountLoseCredit('\u2066${credit.ledger}\u2069'),
    ];
    // Figma `delete-account`: 16 px of padding, 12 between the parts, a 2 px
    // `danger-subtle` border at radius 16.
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: groupCardColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.dangerSurface, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(HubIcons.trash2, color: AppColors.danger, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.deleteAccountTitle,
                  style: t.heading2.copyWith(color: AppColors.danger),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            l10n.deleteAccountIntro,
            style: t.body.copyWith(color: context.scaffoldHeading),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < losses.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  HubIcons.triangleAlert,
                  size: 14,
                  color: AppColors.danger,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    losses[i],
                    style: t.caption.copyWith(
                      color: context.isDarkMode
                          ? context.scaffoldMuted
                          : AppColors.inkSubtle,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.warningSubtle,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(HubIcons.info, size: 16, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.deleteAccountRecordsNote,
                    style: t.caption.copyWith(color: AppColors.warning),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _busy
                ? null
                : () => setState(() => _understood = !_understood),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HubCheckbox(
                  value: _understood,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _understood = v),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.deleteAccountUnderstand,
                    style: t.body.copyWith(color: context.scaffoldHeading),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          HubButton(
            label: l10n.deleteAccountAction,
            style: HubButtonStyle.danger,
            loading: _busy,
            onPressed: _understood ? _delete : null,
          ),
        ],
      ),
    );
  }
}
