import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../../../app/routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/theme_x.dart';
import '../../../core/error/failure.dart';
import '../../../core/widgets/button_spinner.dart';
import '../../../core/widgets/grouped_list.dart';
import '../../../l10n/l10n.dart';
import '../../cart/presentation/cart_controller.dart';
import '../domain/store_credit.dart';

/// Figma 20d "Buy credit": the amounts the store sells credit for, as chips
/// (the middle one chosen, as in the frame), plus "Other amount" and a field
/// for a whole amount within the store's range when a store credit product
/// takes any amount — the field alone when that is the only way to buy. The
/// orange button puts that credit in the cart (`hmAddCreditToCart`) and opens
/// the cart; the balance grows once the order's invoice is paid.
///
/// What is on sale comes from the website's store credit products
/// (`HmStoreCreditAccount.top_up`); the screen shows no card while there are
/// none.
class BuyCreditCard extends ConsumerStatefulWidget {
  const BuyCreditCard({super.key, required this.topUp});

  final StoreCreditTopUp topUp;

  @override
  ConsumerState<BuyCreditCard> createState() => _BuyCreditCardState();
}

class _BuyCreditCardState extends ConsumerState<BuyCreditCard> {
  static final NumberFormat _amountFormat = NumberFormat('#,##0.##', 'en_US');

  final TextEditingController _custom = TextEditingController();

  /// "Other amount" is chosen, or it is the only way to buy.
  late bool _other;

  /// The chosen preset's credit.
  double? _preset;

  bool _busy = false;

  StoreCreditTopUp get _topUp => widget.topUp;

  @override
  void initState() {
    super.initState();
    final initial = _topUp.initialAmount;
    if (_topUp.presets.isNotEmpty) {
      _other = false;
      _preset = initial;
    } else {
      _other = true;
      // Digits only, as the field takes them (the range is whole units).
      _custom.text = initial == null ? '' : '${initial.round()}';
    }
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  /// The credit the button buys; null while the typed amount can't be bought.
  double? get _amount {
    if (!_other) return _preset;
    final typed = double.tryParse(_custom.text.trim());
    return typed != null && _topUp.acceptsCustom(typed) ? typed : null;
  }

  /// "AED 100", in a left-to-right isolate so it keeps its order in Arabic.
  String _label(double amount) =>
      '\u2066${_topUp.currency} ${_amountFormat.format(amount)}\u2069';

  Future<void> _buy() async {
    final amount = _amount;
    if (amount == null || _busy) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(cartControllerProvider.notifier).addCreditToCart(amount);
      if (!mounted) return;
      context.push(AppRoutes.cart);
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(_failure(error, l10n))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The store's own (localized) refusal — an amount no longer on offer,
  /// credit no longer on sale — else the card's own words.
  static String _failure(Object error, AppLocalizations l10n) {
    if (error is Failure) {
      if (error.kind == FailureKind.network) return l10n.errorNetwork;
      final detail = error.detail?.trim();
      if (error.kind == FailureKind.server &&
          detail != null &&
          detail.isNotEmpty) {
        return detail;
      }
    }
    return l10n.myCreditBuyFailed;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final amount = _amount;
    final price = amount == null ? null : _topUp.priceOf(amount);
    // Said only when it differs from the credit (a bonus, or a fee).
    final shownPrice =
        amount != null &&
            price != null &&
            (price.amount - amount).abs() >= 0.005
        ? price
        : null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: groupCardColor(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.myCreditBuyTitle,
            style: t.title.copyWith(color: context.scaffoldHeading),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.myCreditBuyBody,
            style: t.caption.copyWith(color: context.scaffoldMuted),
          ),
          if (_topUp.presets.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in _topUp.presets)
                  _AmountChip(
                    label: _label(preset.credit.amount),
                    selected: !_other && _preset == preset.credit.amount,
                    onTap: _busy
                        ? null
                        : () => setState(() {
                            _other = false;
                            _preset = preset.credit.amount;
                          }),
                  ),
                if (_topUp.allowsCustomAmount)
                  _AmountChip(
                    label: l10n.myCreditBuyOther,
                    selected: _other,
                    onTap: _busy ? null : () => setState(() => _other = true),
                  ),
              ],
            ),
          ],
          if (_other && _topUp.allowsCustomAmount) ...[
            const SizedBox(height: 12),
            _CustomAmountField(
              controller: _custom,
              currency: _topUp.currency,
              range: l10n.myCreditBuyAmountRange(
                _label(_topUp.min!.amount),
                _label(_topUp.max!.amount),
              ),
              error: _custom.text.trim().isNotEmpty && amount == null
                  ? l10n.myCreditBuyAmountInvalid(
                      _label(_topUp.min!.amount),
                      _label(_topUp.max!.amount),
                    )
                  : null,
              enabled: !_busy,
              onChanged: () => setState(() {}),
              onSubmitted: _buy,
            ),
          ],
          if (shownPrice != null) ...[
            const SizedBox(height: 8),
            Text(
              l10n.myCreditBuyPrice('\u2066${shownPrice.formatted()}\u2069'),
              style: t.captionStrong.copyWith(color: context.scaffoldMuted),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: amount == null || _busy ? null : _buy,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accentStrong,
              disabledBackgroundColor: context.isDarkMode
                  ? Colors.white12
                  : AppColors.borderDefault,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: t.button,
            ),
            child: _busy
                ? const ButtonSpinner()
                : Text(
                    amount == null
                        ? l10n.myCreditBuyTitle
                        : l10n.myCreditBuyAction(_label(amount)),
                    textAlign: TextAlign.center,
                  ),
          ),
        ],
      ),
    );
  }
}

/// A 36px pill: navy with white text when chosen, outlined otherwise.
class _AmountChip extends StatelessWidget {
  const _AmountChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDarkMode;
    final fill = selected
        ? (dark ? Colors.white : AppColors.brandPrimary)
        : Colors.transparent;
    final ink = selected
        ? (dark ? AppColors.brandPrimary : Colors.white)
        : context.scaffoldHeading;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: fill,
        shape: StadiumBorder(
          side: selected
              ? BorderSide.none
              : BorderSide(
                  color: dark ? Colors.white24 : AppColors.borderStrong,
                ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            // As wide as its label, not the row.
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: AppTextStyles.of(
                  context,
                ).bodyStrong.copyWith(color: ink),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The custom amount: whole numbers only, "AED 150" left to right in both
/// languages, and the store's range under it — or why the typed amount can't
/// be bought — in the page's own direction.
class _CustomAmountField extends StatelessWidget {
  const _CustomAmountField({
    required this.controller,
    required this.currency,
    required this.range,
    required this.error,
    required this.enabled,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final String currency;
  final String range;
  final String? error;
  final bool enabled;
  final VoidCallback onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final errorBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.myCreditBuyAmountLabel,
          style: t.captionStrong.copyWith(color: context.scaffoldHeading),
        ),
        const SizedBox(height: 6),
        Directionality(
          textDirection: TextDirection.ltr,
          child: TextField(
            controller: controller,
            enabled: enabled,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(7),
            ],
            style: t.bodyStrong.copyWith(color: context.scaffoldHeading),
            decoration: InputDecoration(
              prefixText: '$currency ',
              prefixStyle: t.body.copyWith(color: context.scaffoldMuted),
              enabledBorder: error == null ? null : errorBorder,
              focusedBorder: error == null ? null : errorBorder,
            ),
            onChanged: (_) => onChanged(),
            onSubmitted: (_) => onSubmitted(),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          error ?? range,
          style: t.caption.copyWith(
            color: error == null ? context.scaffoldMuted : AppColors.danger,
          ),
        ),
      ],
    );
  }
}
