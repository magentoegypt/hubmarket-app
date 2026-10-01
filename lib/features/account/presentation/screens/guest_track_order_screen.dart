import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../core/config/store_timezone.dart';
import '../../../../core/validation/validators.dart';
import '../../../../core/widgets/failure_message.dart';
import '../../../../core/widgets/hub_bottom_action_bar.dart';
import '../../../../core/widgets/hub_top_bar.dart';
import '../../../../l10n/l10n.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../auth/presentation/widgets/auth_field.dart';
import '../../../auth/presentation/widgets/auth_widgets.dart';
import '../../domain/order.dart';
import '../guest_orders_controller.dart';
import '../order_format.dart';
import '../widgets/order_packages.dart';
import '../widgets/order_status_pill.dart';

/// Track order for a guest (Figma 26): look any order up without signing in,
/// with the details on the confirmation e-mail (order number, billing last
/// name and e-mail). Backed by Magento's native `guestOrder` query; a match is
/// remembered on this device and shown right under the form — its status, how
/// far it has come and "View order details", which opens the same order page
/// customers get (22).
///
/// The frame's "Return an item" tab is not drawn: a return needs an account
/// (every returns operation takes the customer's token), so a guest has no
/// return to look up.
class GuestTrackOrderScreen extends ConsumerStatefulWidget {
  const GuestTrackOrderScreen({super.key, this.initialNumber});

  /// The order number to start with: an order a guest opened from a push or
  /// a link (`/track-order?number=`).
  final String? initialNumber;

  @override
  ConsumerState<GuestTrackOrderScreen> createState() =>
      _GuestTrackOrderScreenState();
}

class _GuestTrackOrderScreenState extends ConsumerState<GuestTrackOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _resultKey = GlobalKey();
  late final _number = TextEditingController(
    text: widget.initialNumber?.trim() ?? '',
  );
  final _email = TextEditingController();
  final _lastname = TextEditingController();
  bool _busy = false;

  /// The order the last lookup found, until a field is edited.
  CustomerOrder? _found;

  @override
  void dispose() {
    _number.dispose();
    _email.dispose();
    _lastname.dispose();
    super.dispose();
  }

  /// What is on screen no longer answers the form once it is changed.
  void _edited(String _) {
    if (_found != null) setState(() => _found = null);
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context);
    try {
      final order = await ref
          .read(guestOrdersControllerProvider.notifier)
          .lookup(
            number: _number.text.trim(),
            email: _email.text.trim(),
            lastname: _lastname.text.trim(),
          );
      if (!mounted) return;
      setState(() => _found = order);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final result = _resultKey.currentContext;
        if (result == null) return;
        Scrollable.ensureVisible(
          result,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      });
    } catch (error) {
      if (!mounted) return;
      // Magento answers an unknown order with its own message ("We couldn't
      // locate an order with the information provided.") — surface it rather
      // than a generic failure, so the user knows *what* to correct.
      _snack(serverMessageOr(context, error, l10n.guestTrackNotFound));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final signedIn = ref.watch(
      authControllerProvider.select((a) => a.isAuthenticated),
    );
    // The footer gives way to the keyboard rather than ride above it.
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
    final found = _found;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: HubTopBar(title: l10n.guestTrackTitle, divider: true),
      bottomNavigationBar: signedIn || typing
          ? null
          : HubBottomActionBar(
              bottomSpace: 28,
              child: AuthFooterPrompt(
                prompt: l10n.guestTrackHaveAccount,
                action: l10n.guestTrackSignIn,
                onTap: () => context.push(AppRoutes.signIn),
              ),
            ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Figma 26 "intro": the box, "Find your order" and what to enter.
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accentSubtle,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  HubIcons.box,
                  size: 26,
                  color: AppColors.accentStrong,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.guestTrackHeading,
              style: t.heading2.copyWith(color: AppColors.inkHeading),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.guestTrackIntro,
              style: t.body.copyWith(color: AppColors.inkSubtle),
            ),
            const SizedBox(height: 12),
            AuthField(
              controller: _number,
              label: l10n.guestTrackOrderNumber,
              icon: HubIcons.box,
              ltrInput: true,
              validator: (v) => Validators.required(context, v),
              onChanged: _edited,
            ),
            const SizedBox(height: 12),
            AuthField(
              controller: _lastname,
              label: l10n.guestTrackLastname,
              icon: HubIcons.user,
              textCapitalization: TextCapitalization.words,
              validator: (v) => Validators.required(context, v),
              onChanged: _edited,
            ),
            const SizedBox(height: 12),
            AuthField(
              controller: _email,
              label: l10n.guestTrackEmail,
              icon: HubIcons.mail,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              ltrInput: true,
              validator: (v) => Validators.email(context, v),
              onChanged: _edited,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            AuthButton.primary(
              label: l10n.guestTrackSubmit,
              busy: _busy,
              onPressed: _submit,
            ),
            if (found != null) ...[
              const SizedBox(height: 12),
              _ResultCard(
                key: _resultKey,
                order: found,
                onView: () => context.push(AppRoutes.orderDetail, extra: found),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// How many of the four steps — Confirmed, Packed, Shipped, Delivered — the
/// order has filled, from what the backend recorded: an invoice (or a store
/// already processing) confirms it, a shipment means it was packed and shipped,
/// a complete order is delivered. A cancelled order has none.
int orderProgress(CustomerOrder order) {
  if (order.isCancelled) return 0;
  if (order.isDelivered) return 4;
  final packages = orderPackageViews(order);
  if (order.hasShipment || order.hasTracking || anyPackageShipped(packages)) {
    return 3;
  }
  final processing = order.packages.any(
    (p) =>
        p.stage == OrderPackageStage.processing ||
        p.stage == OrderPackageStage.complete,
  );
  return order.hasInvoice || processing ? 1 : 0;
}

/// Figma 26 "result": the order's number and status, a line on what it holds,
/// the four steps as a bar, and "View order details".
class _ResultCard extends ConsumerWidget {
  const _ResultCard({super.key, required this.order, required this.onView});

  final CustomerOrder order;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final zone = ref.watch(storeTimezoneProvider).valueOrNull ?? '';
    final stores = orderPackageViews(order)?.length ?? 0;
    final caption = [
      l10n.orderPlacedOn(orderFmtDate(order.date, locale, zone)),
      l10n.orderItemCount(order.itemCount),
      if (stores >= 2) l10n.orderPackagesCount(stores),
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.orderNumber(order.number),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.title.copyWith(color: AppColors.inkHeading),
                ),
              ),
              const SizedBox(width: 8),
              OrderStatusPill(order: order, verticalPadding: 4),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            caption,
            style: t.caption.copyWith(color: AppColors.inkSubtle),
          ),
          const SizedBox(height: 10),
          _Progress(reached: orderProgress(order)),
          const SizedBox(height: 14),
          InkWell(
            onTap: onView,
            borderRadius: BorderRadius.circular(6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.guestTrackViewOrder,
                    style: t.bodyStrong.copyWith(color: AppColors.accentStrong),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  HubIcons.chevronRight,
                  size: 18,
                  color: AppColors.accentStrong,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The four steps as a 4 px bar each — green once reached, the step the order
/// is at in dark ink — with its name under it.
class _Progress extends StatelessWidget {
  const _Progress({required this.reached});

  /// How many steps are filled, 0 to 4.
  final int reached;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final labels = [
      l10n.orderProgressConfirmed,
      l10n.orderProgressPacked,
      l10n.orderStepShipped,
      l10n.orderStepDelivered,
    ];
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: i < reached
                        ? AppColors.successStrong
                        : AppColors.borderSubtle,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  labels[i],
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: t.micro.copyWith(
                    color: i == reached - 1
                        ? AppColors.inkHeading
                        : AppColors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
