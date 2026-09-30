import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/hubapp/hubapp.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/failure_message.dart';
import '../../../../core/widgets/grouped_list.dart';
import '../../../../l10n/l10n.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../catalog/domain/money.dart';
import '../../../cms/domain/cms_document.dart';
import '../../../cms/presentation/cms_navigation.dart';
import '../../../cms/presentation/widgets/cms_html_view.dart';
import '../../data/returns_repository.dart';
import '../../domain/return_draft.dart';
import '../../domain/return_photo.dart';
import '../../domain/returns.dart';
import '../returns_providers.dart';
import '../widgets/return_form_widgets.dart';
import '../widgets/return_photos.dart';
import '../widgets/return_widgets.dart';

/// Request a return (Figma 23): pick an order the server lists as returnable
/// (`hmReturnableOrders`), tick lines of one seller with their quantities,
/// say refund or exchange, why, whether the package was opened, how much of
/// a refund, add photos, what happened, and the tracking number if it's on
/// its way — then `hmCreateReturn`, and on to the new return (23c).
///
/// The website's rules the form applies (the server checks them all again):
/// only processing or complete orders and the lines its form offers, at most
/// the line's returnable quantity (whole, or everything left when partial
/// quantities are off), one seller per return, a custom refund up to the
/// lines' paid amount (the server's `unit_price`; the core order's prices
/// only from a server without it), photos of the formats and size the
/// store's upload takes, and no return window for signed-in customers.
///
/// The contract's required first message is the "Tell us what happened"
/// field, which the frame doesn't show.
class RequestReturnScreen extends ConsumerStatefulWidget {
  const RequestReturnScreen({super.key, this.order, this.orderNumber});

  /// The order to start on, when the caller has it already (Return items on
  /// the order detail).
  final ReturnableOrder? order;

  /// The order to start on by number (a deep link): looked up among the
  /// returnable orders.
  final String? orderNumber;

  @override
  ConsumerState<RequestReturnScreen> createState() =>
      _RequestReturnScreenState();
}

class _RequestReturnScreenState extends ConsumerState<RequestReturnScreen> {
  /// The form as the customer has changed it; until the first change, the
  /// form shows a fresh draft of the order it opened on.
  ReturnDraft? _draft;
  bool _showErrors = false;
  bool _submitting = false;

  final _otherReason = TextEditingController();
  final _customAmount = TextEditingController();
  final _comment = TextEditingController();
  final _tracking = TextEditingController();

  /// Text in the form's fields, which stay white in the dark theme too.
  static const _fieldText = TextStyle(
    fontSize: 14,
    color: AppColors.inkHeading,
  );

  final _itemsKey = GlobalKey();
  final _reasonKey = GlobalKey();
  final _packageKey = GlobalKey();
  final _amountKey = GlobalKey();
  final _commentKey = GlobalKey();
  final _trackingKey = GlobalKey();

  @override
  void dispose() {
    _otherReason.dispose();
    _customAmount.dispose();
    _comment.dispose();
    _tracking.dispose();
    super.dispose();
  }

  /// A fresh draft on [order], keeping what the customer already said about
  /// the return itself. A lone returnable line starts ticked.
  ReturnDraft _startDraft(ReturnableOrder order, {ReturnDraft? keep}) {
    var draft = ReturnDraft(
      order: order,
      type: keep?.type ?? ReturnType.refund,
      reasonId: keep?.reasonId,
      otherReasonSelected: keep?.otherReasonSelected ?? false,
      otherReason: _otherReason.text,
      packageOpened: keep?.packageOpened,
      comment: _comment.text,
      trackingCode: _tracking.text,
      photos: keep?.photos ?? const <ReturnPhoto>[],
    );
    final returnable = order.items.where((i) => i.isReturnable).toList();
    if (returnable.length == 1) draft = draft.toggle(returnable.single);
    return draft;
  }

  /// The order the screen was opened on, once known.
  ReturnableOrder? _initialOrder() {
    if (widget.order != null) return widget.order;
    final number = widget.orderNumber;
    if (number == null || number.isEmpty) return null;
    return ref.watch(returnableOrderProvider(number)).valueOrNull;
  }

  /// Still looking up the order the screen was opened on by number.
  bool _initialPending() {
    final number = widget.orderNumber;
    if (widget.order != null || number == null || number.isEmpty) return false;
    return ref.watch(returnableOrderProvider(number)).isLoading;
  }

  /// What a unit of each line of [draft]'s order was paid: the server's
  /// `unit_price`, else — only from a server without it — the core order's
  /// prices.
  Map<int, Money> _unitPrices(ReturnDraft draft) {
    final fallback = draft.needsFallbackPrices
        ? ref.watch(returnUnitRefundsProvider(draft.order.number)).valueOrNull ??
              const <int, Money>{}
        : const <int, Money>{};
    return {
      for (final item in draft.order.items)
        if (item.unitPrice ?? fallback[item.orderItemId] case final unit?)
          item.orderItemId: unit,
    };
  }

  void _update(ReturnDraft draft) => setState(() => _draft = draft);

  /// Applies [change] to the latest draft — [shown] until the customer first
  /// changes something — not to the one a callback captured when it was
  /// built.
  void _edit(ReturnDraft shown, ReturnDraft Function(ReturnDraft) change) =>
      _update(change(_draft ?? shown));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final available = ref.watch(returnsAvailableProvider);
    final signedIn = ref.watch(
      authControllerProvider.select((s) => s.isAuthenticated),
    );

    Widget body;
    Widget? footer;
    if (!available) {
      body = _unavailable(l10n);
    } else if (!signedIn) {
      body = EmptyState(
        icon: Icons.assignment_return_outlined,
        title: l10n.returnsRequestTitle,
        body: l10n.returnsSignIn,
        action: FilledButton(
          onPressed: () => context.push(AppRoutes.signIn),
          child: Text(l10n.authSignInTitle),
        ),
      );
    } else {
      final config = ref.watch(returnConfigProvider);
      final orders = ref.watch(returnableOrdersControllerProvider);
      final initial = _initialOrder();
      final draft = _draft ?? (initial == null ? null : _startDraft(initial));
      if (config.hasError) {
        body = config.error is HubAppMissing
            ? _unavailable(l10n)
            : _error(l10n, config.error, () {
                ref.invalidate(returnConfigProvider);
                ref.read(returnableOrdersControllerProvider.notifier).refresh();
              });
      } else if (!config.hasValue ||
          (draft == null &&
              ((orders.isLoading && orders.items.isEmpty) ||
                  _initialPending()))) {
        body = const Center(child: CircularProgressIndicator());
      } else if (!config.requireValue.enabled ||
          orders.error is HubAppMissing) {
        body = _unavailable(l10n);
      } else if (draft == null &&
          orders.error != null &&
          orders.items.isEmpty) {
        body = _error(
          l10n,
          orders.error,
          ref.read(returnableOrdersControllerProvider.notifier).refresh,
        );
      } else if (draft == null && orders.items.isEmpty) {
        body = EmptyState(
          icon: Icons.assignment_return_outlined,
          title: l10n.returnsNoOrdersTitle,
          body: l10n.returnsNoOrdersBody,
        );
      } else {
        body = _form(l10n, config.requireValue, orders, draft);
        footer = ReturnSubmitBar(
          submitting: _submitting,
          onSubmit: draft == null
              ? null
              : () => _submit(config.requireValue, draft),
        );
      }
    }

    return Scaffold(
      appBar: subpageAppBar(context, l10n.returnsRequestTitle),
      body: body,
      bottomNavigationBar: footer,
    );
  }

  Widget _unavailable(AppLocalizations l10n) => EmptyState(
    icon: Icons.assignment_return_outlined,
    title: l10n.returnsUnavailableTitle,
    body: l10n.returnsUnavailableBody,
  );

  Widget _error(AppLocalizations l10n, Object? error, VoidCallback retry) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error is Failure
                    ? failureMessage(context, error)
                    : l10n.errorGeneric,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: retry, child: Text(l10n.actionRetry)),
            ],
          ),
        ),
      );

  Widget _form(
    AppLocalizations l10n,
    ReturnConfig config,
    PagedReturnsState<ReturnableOrder> orders,
    ReturnDraft? draft,
  ) {
    final locale = Localizations.localeOf(context).languageCode;
    final units = draft == null ? const <int, Money>{} : _unitPrices(draft);
    final currency = units.values.firstOrNull?.currency ?? 'AED';
    final cap = draft?.refundCap({
      for (final e in units.entries) e.key: e.value.amount,
    });
    final errors = _showErrors && draft != null
        ? draft.validate(config, refundCap: cap)
        : const <ReturnFormError>{};
    final initialNumber = widget.orderNumber;
    final notReturnable =
        draft == null &&
        widget.order == null &&
        initialNumber != null &&
        initialNumber.isNotEmpty &&
        !_initialPending();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        ReturnStoreNote(seller: draft?.seller?.name),
        const SizedBox(height: 16),
        ReturnFieldLabel(l10n.returnsOrderLabel),
        const SizedBox(height: 6),
        ReturnPickerField(
          icon: Icons.inventory_2_outlined,
          text: draft == null
              ? null
              : [
                  '#${draft.order.number}',
                  draft.order.statusLabel,
                  returnDay(draft.order.createdAt, locale),
                ].where((s) => s.isNotEmpty).join(' · '),
          placeholder: l10n.returnsChooseOrder,
          onTap: () => _pickOrder(draft),
        ),
        if (notReturnable)
          ReturnFieldError(l10n.returnsOrderNotReturnable(initialNumber)),
        if (draft != null) ...[
          const SizedBox(height: 16),
          KeyedSubtree(
            key: _itemsKey,
            child: _items(l10n, config, draft, units, errors),
          ),
          const SizedBox(height: 16),
          ReturnFieldLabel(l10n.returnsRequestType),
          const SizedBox(height: 8),
          ReturnChoiceChips<ReturnType>(
            values: ReturnType.values,
            selected: draft.type,
            label: (t) => returnTypeLabel(l10n, t),
            onSelected: (t) => _edit(draft, (d) => d.copyWith(type: t)),
          ),
          if (config.asksForReason) ...[
            const SizedBox(height: 16),
            KeyedSubtree(
              key: _reasonKey,
              child: _reason(l10n, config, draft, errors),
            ),
          ],
          const SizedBox(height: 16),
          KeyedSubtree(
            key: _packageKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ReturnFieldLabel(l10n.returnsPackageOpened),
                const SizedBox(height: 8),
                ReturnChoiceChips<bool>(
                  values: const [true, false],
                  selected: draft.packageOpened,
                  label: (v) =>
                      v ? l10n.returnsAnswerYes : l10n.returnsAnswerNo,
                  onSelected: (v) =>
                      _edit(draft, (d) => d.copyWith(packageOpened: v)),
                ),
                if (errors.contains(ReturnFormError.packageOpened))
                  ReturnFieldError(l10n.returnsErrorPackage),
              ],
            ),
          ),
          if (draft.type == ReturnType.refund) ...[
            const SizedBox(height: 16),
            KeyedSubtree(
              key: _amountKey,
              child: _refund(l10n, draft, cap, currency, errors),
            ),
          ],
          const SizedBox(height: 16),
          KeyedSubtree(
            key: _commentKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ReturnFieldLabel(l10n.returnsComment),
                const SizedBox(height: 6),
                TextField(
                  style: _fieldText,
                  controller: _comment,
                  minLines: 3,
                  maxLines: 6,
                  keyboardType: TextInputType.multiline,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(
                      ReturnDraft.maxCommentLength,
                    ),
                  ],
                  onChanged: (v) => _edit(draft, (d) => d.copyWith(comment: v)),
                  decoration: _decoration(hint: l10n.returnsCommentHint),
                ),
                if (errors.contains(ReturnFormError.comment))
                  ReturnFieldError(l10n.returnsErrorComment),
                if (errors.contains(ReturnFormError.commentTooLong))
                  ReturnFieldError(l10n.returnsErrorCommentLong),
              ],
            ),
          ),
          if (config.acceptsPhotos) ...[
            const SizedBox(height: 16),
            ReturnPhotoField(
              label: l10n.returnsPhotos,
              photos: draft.photos,
              maxPhotos: config.attachmentMaxFiles,
              onAdd: () => _addPhotos(config, draft),
              onRemove: (index) => _edit(
                draft,
                (d) => d.copyWith(photos: [...d.photos]..removeAt(index)),
              ),
            ),
          ],
          const SizedBox(height: 16),
          KeyedSubtree(
            key: _trackingKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ReturnFieldLabel(l10n.returnsTracking),
                const SizedBox(height: 6),
                TextField(
                  style: _fieldText,
                  controller: _tracking,
                  onChanged: (v) =>
                      _edit(draft, (d) => d.copyWith(trackingCode: v)),
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(
                      ReturnDraft.maxTrackingLength + 1,
                    ),
                  ],
                  decoration: _decoration(
                    hint: l10n.returnsTrackingHint,
                    icon: Icons.local_shipping_outlined,
                  ),
                ),
                if (errors.contains(ReturnFormError.trackingTooLong))
                  ReturnFieldError(l10n.returnsErrorTrackingLong),
              ],
            ),
          ),
          if (config.policyHtml != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => _showPolicy(l10n, config.policyHtml!),
                icon: const Icon(Icons.policy_outlined, size: 18),
                label: Text(l10n.returnsPolicy),
              ),
            ),
          ],
        ],
      ],
    );
  }

  /// "Select items": the order's lines, grouped by seller when there are
  /// several — one seller per return.
  Widget _items(
    AppLocalizations l10n,
    ReturnConfig config,
    ReturnDraft draft,
    Map<int, Money> units,
    Set<ReturnFormError> errors,
  ) {
    final groups = <String, List<ReturnableItem>>{};
    for (final item in draft.order.items) {
      groups.putIfAbsent(item.sellerKey, () => []).add(item);
    }
    final grouped = groups.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReturnFieldLabel(l10n.returnsSelectItems),
        for (final group in groups.values) ...[
          if (grouped) ReturnSellerHeader(seller: group.first.seller),
          for (final item in group) ...[
            const SizedBox(height: 8),
            ReturnLineTile(
              item: item,
              availability: draft.availabilityOf(item),
              quantity: draft.quantities[item.orderItemId],
              minQuantity: ReturnDraft.minQuantity(item, config),
              blockingSeller: draft.seller?.name,
              unit: units[item.orderItemId],
              onToggle: () => _edit(draft, (d) => d.toggle(item)),
              onQuantity: (q) =>
                  _edit(draft, (d) => d.setQuantity(item, q, config)),
            ),
          ],
        ],
        if (errors.contains(ReturnFormError.items))
          ReturnFieldError(l10n.returnsErrorItems),
      ],
    );
  }

  Widget _reason(
    AppLocalizations l10n,
    ReturnConfig config,
    ReturnDraft draft,
    Set<ReturnFormError> errors,
  ) {
    final picker = config.reasonsEnabled && config.reasons.isNotEmpty;
    // Without a list, free text is the only way to give a reason.
    final writing = draft.otherReasonSelected || !picker;
    final selectedLabel = draft.otherReasonSelected
        ? l10n.returnsOtherReason
        : config.reasons
              .where((r) => r.id == draft.reasonId)
              .map((r) => r.label)
              .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReturnFieldLabel(
          ReturnDraft.reasonRequired(config)
              ? l10n.returnsReason
              : l10n.returnsReasonOptional,
        ),
        const SizedBox(height: 6),
        if (picker)
          ReturnPickerField(
            icon: Icons.replay,
            text: selectedLabel,
            placeholder: l10n.returnsChooseReason,
            onTap: () => _pickReason(l10n, config, draft),
          ),
        if (writing && config.otherReasonAllowed) ...[
          if (picker) const SizedBox(height: 8),
          TextField(
            style: _fieldText,
            controller: _otherReason,
            inputFormatters: [
              LengthLimitingTextInputFormatter(
                ReturnDraft.maxOtherReasonLength + 1,
              ),
            ],
            onChanged: (v) => _edit(
              draft,
              (d) => d.copyWith(otherReason: v, otherReasonSelected: true),
            ),
            decoration: _decoration(hint: l10n.returnsOtherReasonHint),
          ),
        ],
        if (errors.contains(ReturnFormError.reason))
          ReturnFieldError(l10n.returnsErrorReason),
        if (errors.contains(ReturnFormError.otherReasonTooLong))
          ReturnFieldError(l10n.returnsErrorOtherReasonLong),
      ],
    );
  }

  Widget _refund(
    AppLocalizations l10n,
    ReturnDraft draft,
    double? cap,
    String currency,
    Set<ReturnFormError> errors,
  ) {
    final capText = cap == null
        ? null
        : Money(amount: cap, currency: currency).formatted();
    final custom = draft.refundAmountType == RefundAmountType.custom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReturnFieldLabel(l10n.returnsRefundAmount),
        const SizedBox(height: 8),
        ReturnRadioRow(
          selected: !custom,
          label: l10n.returnsMaximumRefund,
          trailing: capText,
          onTap: () => _edit(
            draft,
            (d) => d.copyWith(refundAmountType: RefundAmountType.full),
          ),
        ),
        const SizedBox(height: 8),
        ReturnRadioRow(
          selected: custom,
          label: l10n.returnsCustomAmount,
          onTap: () => _edit(
            draft,
            (d) => d.copyWith(refundAmountType: RefundAmountType.custom),
          ),
        ),
        if (custom) ...[
          const SizedBox(height: 8),
          TextField(
            style: _fieldText,
            controller: _customAmount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (v) => _edit(draft, (d) => d.copyWith(customAmount: v)),
            decoration: _decoration(
              hint: l10n.returnsCustomAmountHint,
              prefix: currency,
              helper: capText == null
                  ? null
                  : l10n.returnsCustomAmountMax(capText),
            ),
          ),
        ],
        if (errors.contains(ReturnFormError.customAmount))
          ReturnFieldError(l10n.returnsErrorAmount),
        if (errors.contains(ReturnFormError.customAmountOverCap) &&
            capText != null)
          ReturnFieldError(l10n.returnsErrorAmountCap(capText)),
      ],
    );
  }

  /// Figma form field: white, `--hm-default` outline, 12 radius.
  InputDecoration _decoration({
    required String hint,
    IconData? icon,
    String? prefix,
    String? helper,
  }) {
    const outline = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      borderSide: BorderSide(color: AppColors.borderStrong),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.inkMuted, fontSize: 14),
      helperText: helper,
      filled: true,
      fillColor: Colors.white,
      prefixIcon: icon == null
          ? null
          : Icon(icon, size: 20, color: AppColors.inkMuted),
      prefixText: prefix == null ? null : '$prefix ',
      prefixStyle: _fieldText,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: outline,
      enabledBorder: outline,
      focusedBorder: outline.copyWith(
        borderSide: const BorderSide(color: AppColors.brandPrimary, width: 1.5),
      ),
    );
  }

  Future<void> _pickOrder(ReturnDraft? draft) async {
    final extra = draft == null ? widget.order : draft.order;
    final picked = await showModalBottomSheet<ReturnableOrder>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (_) => _OrderSheet(selected: draft?.order.number, extra: extra),
    );
    if (picked == null || !mounted) return;
    if (picked.number == draft?.order.number) return;
    _customAmount.clear();
    _update(_startDraft(picked, keep: _draft ?? draft));
  }

  Future<void> _pickReason(
    AppLocalizations l10n,
    ReturnConfig config,
    ReturnDraft draft,
  ) async {
    const other = -1;
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              ReturnSheetTitle(l10n.returnsChooseReason),
              for (final reason in config.reasons)
                ReturnSheetOption(
                  label: reason.label,
                  selected:
                      !draft.otherReasonSelected && draft.reasonId == reason.id,
                  onTap: () => Navigator.pop(sheetContext, reason.id),
                ),
              if (config.otherReasonAllowed)
                ReturnSheetOption(
                  label: l10n.returnsOtherReason,
                  selected: draft.otherReasonSelected,
                  onTap: () => Navigator.pop(sheetContext, other),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    _edit(
      draft,
      (d) => picked == other
          ? d.copyWith(otherReasonSelected: true, clearReason: true)
          : d.copyWith(reasonId: picked, otherReasonSelected: false),
    );
  }

  /// Adds photos, up to the store's limit.
  Future<void> _addPhotos(ReturnConfig config, ReturnDraft shown) async {
    final current = _draft ?? shown;
    final added = await pickReturnPhotos(
      context,
      ref,
      config: config,
      room: config.attachmentMaxFiles - current.photos.length,
    );
    if (added.isEmpty || !mounted) return;
    _edit(shown, (d) {
      final photos = [...d.photos, ...added];
      return d.copyWith(
        photos: photos.take(config.attachmentMaxFiles).toList(),
      );
    });
  }

  Future<void> _showPolicy(AppLocalizations l10n, String html) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        builder: (sheetContext) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              children: [
                ReturnSheetTitle(l10n.returnsPolicy, padding: EdgeInsets.zero),
                const SizedBox(height: 8),
                CmsHtmlView(
                  blocks: CmsDocument.parse(html),
                  compact: true,
                  onLink: (href) => openCmsHref(sheetContext, ref, href),
                ),
              ],
            ),
          ),
        ),
      );

  Future<void> _submit(ReturnConfig config, ReturnDraft shown) async {
    if (_submitting) return;
    // The latest edit, even one made since the button was last built.
    final draft = _draft ?? shown;
    final l10n = AppLocalizations.of(context);
    final fallback = draft.needsFallbackPrices
        ? ref.read(returnUnitRefundsProvider(draft.order.number)).valueOrNull ??
              const <int, Money>{}
        : const <int, Money>{};
    final cap = draft.refundCap({
      for (final e in fallback.entries) e.key: e.value.amount,
    });
    final errors = draft.validate(config, refundCap: cap);
    if (errors.isNotEmpty) {
      setState(() {
        _draft = draft;
        _showErrors = true;
      });
      _revealFirstError(errors);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.returnsFixErrors)));
      return;
    }
    setState(() {
      _draft = draft;
      _submitting = true;
    });
    try {
      final created = await ref
          .read(returnsRepositoryProvider)
          .createReturn(draft.toInput());
      if (!mounted) return;
      invalidateReturnLists(ref);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.returnsSubmitted)));
      context.pushReplacement(AppRoutes.returnDetail(created.id));
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(serverMessageOr(context, error, l10n.errorGeneric)),
          ),
        );
    }
  }

  void _revealFirstError(Set<ReturnFormError> errors) {
    final key = switch (errors) {
      _ when errors.contains(ReturnFormError.items) => _itemsKey,
      _
          when errors.contains(ReturnFormError.reason) ||
              errors.contains(ReturnFormError.otherReasonTooLong) =>
        _reasonKey,
      _ when errors.contains(ReturnFormError.packageOpened) => _packageKey,
      _
          when errors.contains(ReturnFormError.customAmount) ||
              errors.contains(ReturnFormError.customAmountOverCap) =>
        _amountKey,
      _
          when errors.contains(ReturnFormError.comment) ||
              errors.contains(ReturnFormError.commentTooLong) =>
        _commentKey,
      _ => _trackingKey,
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = key.currentContext;
      if (target == null || !target.mounted) return;
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 250),
        alignment: 0.1,
      );
    });
  }
}

/// The returnable orders, newest first, with "Show more orders" while the
/// server has more pages.
class _OrderSheet extends ConsumerWidget {
  const _OrderSheet({required this.selected, required this.extra});

  final String? selected;

  /// An order to list even when it isn't on the loaded pages (the one the
  /// form opened on).
  final ReturnableOrder? extra;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final state = ref.watch(returnableOrdersControllerProvider);
    final orders = [
      if (extra != null && !state.items.any((o) => o.number == extra!.number))
        extra!,
      ...state.items,
    ];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            ReturnSheetTitle(l10n.returnsChooseOrder),
            for (final order in orders)
              ReturnSheetOption(
                label: '#${order.number}',
                caption: [
                  order.statusLabel,
                  returnDay(order.createdAt, locale),
                  l10n.orderItemCount(order.items.length),
                ].where((s) => s.isNotEmpty).join(' · '),
                selected: order.number == selected,
                onTap: () => Navigator.pop(context, order),
              ),
            if (state.isLoadingMore || (state.isLoading && orders.isEmpty))
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (state.hasMore)
              Center(
                child: TextButton(
                  onPressed: ref
                      .read(returnableOrdersControllerProvider.notifier)
                      .loadMore,
                  child: Text(l10n.returnsMoreOrders),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
