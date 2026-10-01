import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/grouped_list.dart';
import '../../../../core/widgets/hub_icon_button.dart';
import '../../../../l10n/l10n.dart';
import '../../data/account_repository.dart';
import '../../domain/saved_card.dart';

/// Account → Payment methods (Figma 20e): the cards Magento's vault holds for
/// this customer, one row each — the scheme's tile, "Visa •••• 4242", when it
/// expires and a remove button.
///
/// There is deliberately no "add card" entry point — the token is minted by a
/// gateway during a real payment, and the app takes no card payments yet, so
/// Account shows the row only while there are cards to list. Reached with
/// none (the last one removed), the screen just says so.
///
/// Left out of the frame, because the backend and the app have nothing behind
/// them: the DEFAULT badge (a vault token has no default), the note that cards
/// are saved at checkout (the app has no card checkout) and the Tabby / Tamara
/// note (neither is offered).
class PaymentMethodsScreen extends ConsumerWidget {
  const PaymentMethodsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final cards = ref.watch(savedCardsProvider);

    return Scaffold(
      backgroundColor: groupedPageColor(context),
      appBar: subpageAppBar(context, l10n.savedCardsTitle),
      body: AsyncValueView(
        value: cards,
        onRetry: () => ref.invalidate(savedCardsProvider),
        data: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          children: [
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 56),
                child: EmptyState(
                  icon: HubIcons.creditCard,
                  title: l10n.savedCardsEmptyTitle,
                  body: l10n.savedCardsEmptyBody,
                ),
              )
            else ...[
              GroupLabel(l10n.savedCardsSection, top: 0),
              GroupCard(
                children: [
                  for (final card in list)
                    _SavedCardRow(
                      card: card,
                      onDelete: () => _confirmDelete(context, ref, card),
                    ),
                ],
              ),
            ],
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

/// One card (Figma `card/Visa •••• 4242`): 14 px of padding, 12 between the
/// scheme tile, the text and the remove button.
class _SavedCardRow extends StatelessWidget {
  const _SavedCardRow({required this.card, required this.onDelete});

  final SavedCard card;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final expiry = card.expiryLabel;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          _BrandTile(card: card),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // "Visa •••• 4242": card numbers read left to right in every
                // locale.
                Text(
                  '${card.brandLabel} ${card.maskedNumber}',
                  textDirection: TextDirection.ltr,
                  style: t.bodyStrong.copyWith(color: context.scaffoldHeading),
                ),
                if (card.isExpired)
                  Text(
                    l10n.savedCardExpired,
                    style: t.caption.copyWith(color: AppColors.accentSale),
                  )
                else if (expiry != null)
                  Text(
                    l10n.savedCardExpires(expiry),
                    style: t.caption.copyWith(color: context.scaffoldMuted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          HubIconButton(
            icon: HubIcons.trash2,
            tooltip: l10n.savedCardRemove,
            onPressed: onDelete,
            color: context.scaffoldHeading,
          ),
        ],
      ),
    );
  }
}

/// The scheme's tile (Figma `row`): 48 x 32, radius 6, a 1 px `border/subtle`
/// outline. Visa is its navy with VISA in white, Mastercard white with MC in
/// red, as the frame draws them; a scheme the frame doesn't draw gets a plain
/// tile with a card icon rather than a made-up logo.
class _BrandTile extends StatelessWidget {
  const _BrandTile({required this.card});

  final SavedCard card;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final (Color fill, Widget? label) = switch (card.brandCode) {
      'VI' => (
        const Color(0xFF1A1F71),
        Text('VISA', style: t.captionStrong.copyWith(color: Colors.white)),
      ),
      'MC' => (
        Colors.white,
        Text(
          'MC',
          style: t.captionStrong.copyWith(color: const Color(0xFFEB001B)),
        ),
      ),
      _ => (Colors.white, null),
    };
    return Container(
      width: 48,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child:
          label ??
          const Icon(HubIcons.creditCard, size: 20, color: AppColors.inkSubtle),
    );
  }
}
