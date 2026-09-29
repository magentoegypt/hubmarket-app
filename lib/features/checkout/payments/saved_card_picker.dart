import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/theme_x.dart';
import '../../../l10n/l10n.dart';
import '../../account/data/account_repository.dart';
import '../../account/domain/saved_card.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/checkout.dart';

/// The saved-card list that renders *inside* the N-Genius card row — a radio
/// list of stored cards plus "Use a new card", and the "save this card" opt-in.
///
/// Nothing is drawn for a guest, and nothing is drawn when the store has
/// neither saved cards nor a vault method: the whole feature is invisible until
/// the backend ships §④, which is why it can be merged ahead of it.
///
/// Cards are only offered when a vault method came back in
/// `available_payment_methods` — a card we cannot actually spend must not be
/// selectable.
class SavedCardPicker extends ConsumerWidget {
  const SavedCardPicker({
    super.key,
    required this.vaultMethod,
    required this.selectedHash,
    required this.saveCard,
    required this.onSelectCard,
    required this.onUseNewCard,
    required this.onSaveCardChanged,
    this.enabled = true,
    this.showSaveOption = true,
  });

  /// The `ngeniusonline_vault` option, or null when the store offers none.
  final PaymentMethodOption? vaultMethod;

  /// `public_hash` of the chosen card; null means "use a new card".
  final String? selectedHash;
  final bool saveCard;

  final ValueChanged<SavedCard> onSelectCard;
  final VoidCallback onUseNewCard;
  final ValueChanged<bool> onSaveCardChanged;
  final bool enabled;

  /// The opt-in is a cart-time decision. On the post-order retry screen the
  /// order already exists and there is nothing left to tokenise, so it hides.
  final bool showSaveOption;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(authControllerProvider).isAuthenticated) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final cards = vaultMethod == null
        ? const <SavedCard>[]
        : ref.watch(savedCardsProvider).valueOrNull ?? const <SavedCard>[];

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cards.isNotEmpty) ...[
            const Divider(height: 1),
            const SizedBox(height: 8),
            Text(
              l10n.checkoutSavedCardsLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.scaffoldMuted,
              ),
            ),
            for (final card in cards)
              _CardRow(
                card: card,
                selected: selectedHash == card.publicHash,
                enabled: enabled && !card.isExpired,
                onTap: () => onSelectCard(card),
              ),
            _NewCardRow(
              selected: selectedHash == null,
              enabled: enabled,
              onTap: onUseNewCard,
            ),
          ],
          // Only offered on the new-card branch: an already-tokenised card has
          // nothing left to save.
          if (showSaveOption && selectedHash == null)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 4),
              child: _SaveCardCheckbox(
                value: saveCard,
                enabled: enabled,
                onChanged: onSaveCardChanged,
              ),
            ),
        ],
      ),
    );
  }
}

class _CardRow extends StatelessWidget {
  const _CardRow({
    required this.card,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final SavedCard card;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final expiry = card.expiryLabel;
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 18,
                color: selected ? AppColors.brandPrimary : AppColors.inkMuted,
              ),
              const SizedBox(width: 10),
              Icon(
                Icons.credit_card_outlined,
                size: 18,
                color: context.scaffoldMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        card.brandLabel,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    // A card number reads left-to-right in every locale.
                    Text(
                      card.maskedNumber,
                      textDirection: TextDirection.ltr,
                    ),
                  ],
                ),
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
                  style: TextStyle(fontSize: 12, color: context.scaffoldMuted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewCardRow extends StatelessWidget {
  const _NewCardRow({
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: enabled ? onTap : null,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            size: 18,
            color: selected ? AppColors.brandPrimary : AppColors.inkMuted,
          ),
          const SizedBox(width: 10),
          Icon(Icons.add, size: 18, color: context.scaffoldMuted),
          const SizedBox(width: 8),
          Expanded(child: Text(AppLocalizations.of(context).checkoutUseNewCard)),
        ],
      ),
    ),
  );
}

class _SaveCardCheckbox extends StatelessWidget {
  const _SaveCardCheckbox({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: enabled ? () => onChanged(!value) : null,
    child: Row(
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: value,
            visualDensity: VisualDensity.compact,
            onChanged: enabled ? (next) => onChanged(next ?? false) : null,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            AppLocalizations.of(context).checkoutSaveCard,
            style: TextStyle(fontSize: 13, color: context.scaffoldMuted),
          ),
        ),
      ],
    ),
  );
}
