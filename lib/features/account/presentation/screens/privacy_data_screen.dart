import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/widgets/button_spinner.dart';
import '../../../../core/widgets/grouped_list.dart';
import '../../../../l10n/l10n.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../cms/presentation/cms_navigation.dart';
import '../../../cms/presentation/cms_providers.dart';
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
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
          children: [
            if (legal.isNotEmpty) ...[
              GroupLabel(l10n.privacyPolicies),
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
              const SizedBox(height: 20),
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
    final body = TextStyle(
      fontSize: 14,
      height: 1.45,
      color: context.scaffoldHeading,
    );
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
        l10n.deleteAccountLoseCredit('\u2066${credit.formatted()}\u2069'),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: groupCardColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.dangerSurface, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                HubIcons.trash2,
                color: AppColors.danger,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.deleteAccountTitle,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.danger,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(l10n.deleteAccountIntro, style: body),
          const SizedBox(height: 10),
          for (final item in losses)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(
                      HubIcons.triangleAlert,
                      size: 16,
                      color: AppColors.danger,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item,
                      style: TextStyle(
                        fontSize: 13,
                        color: context.scaffoldMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.accentSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  HubIcons.info,
                  size: 18,
                  color: AppColors.accentStrong,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.deleteAccountRecordsNote,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: AppColors.accentStrong,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: _busy
                ? null
                : () => setState(() => _understood = !_understood),
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Checkbox(
                  value: _understood,
                  activeColor: AppColors.brandPrimary,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _understood = v ?? false),
                ),
                Expanded(child: Text(l10n.deleteAccountUnderstand, style: body)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.dangerSurface,
                foregroundColor: AppColors.danger,
                disabledBackgroundColor: AppColors.dangerSurface.withValues(
                  alpha: 0.6,
                ),
                disabledForegroundColor: AppColors.danger.withValues(
                  alpha: 0.45,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: (_understood && !_busy) ? _delete : null,
              child: _busy
                  ? const ButtonSpinner()
                  : Text(
                      l10n.deleteAccountAction,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
