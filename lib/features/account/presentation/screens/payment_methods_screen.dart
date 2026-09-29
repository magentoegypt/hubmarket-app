import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../l10n/l10n.dart';
import '../../data/account_repository.dart';
import '../../domain/saved_card.dart';

/// Account → Payment Methods: the cards Magento's vault holds for this
/// customer, with a remove action.
///
/// There is deliberately no "add card" entry point — a card can only be stored
/// by paying with it and ticking the save opt-in at checkout, because the token
/// is minted by the gateway during a real authorization.
class PaymentMethodsScreen extends ConsumerWidget {
  const PaymentMethodsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final cards = ref.watch(savedCardsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.savedCardsTitle)),
      body: AsyncValueView(
        value: cards,
        onRetry: () => ref.invalidate(savedCardsProvider),
        data: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 56),
                child: EmptyState(
                  icon: Icons.credit_card_outlined,
                  title: l10n.savedCardsEmptyTitle,
                  body: l10n.savedCardsEmptyBody,
                ),
              )
            else
              for (final card in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _SavedCardTile(
                    card: card,
                    onDelete: () => _confirmDelete(context, ref, card),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    SavedCard card,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.savedCardRemoveConfirmTitle),
        content: Text(l10n.savedCardRemoveConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.savedCardRemove),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(accountRepositoryProvider).deleteSavedCard(card.publicHash);
      messenger.showSnackBar(SnackBar(content: Text(l10n.savedCardRemoved)));
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.savedCardRemoveFailed)),
      );
    }
    // Refresh either way: a failed delete may still have landed server-side.
    ref.invalidate(savedCardsProvider);
  }
}

class _SavedCardTile extends StatelessWidget {
  const _SavedCardTile({required this.card, required this.onDelete});

  final SavedCard card;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final expiry = card.expiryLabel;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 8, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.scaffoldFaint),
      ),
      child: Row(
        children: [
          Icon(
            Icons.credit_card_outlined,
            size: 20,
            color: context.scaffoldMuted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        card.brandLabel,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: context.scaffoldHeading,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Card numbers read left-to-right in every locale.
                    Text(
                      card.maskedNumber,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(color: context.scaffoldHeading),
                    ),
                  ],
                ),
                if (card.isExpired)
                  Text(
                    l10n.savedCardExpired,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.accentSale,
                    ),
                  )
                else if (expiry != null)
                  Text(
                    expiry,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.scaffoldMuted,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: onDelete,
            tooltip: l10n.savedCardRemove,
            icon: const Icon(
              Icons.delete_outline,
              size: 20,
              color: AppColors.accentSale,
            ),
          ),
        ],
      ),
    );
  }
}
