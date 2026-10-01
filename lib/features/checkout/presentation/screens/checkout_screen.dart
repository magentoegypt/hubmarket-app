import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../core/address/regions.dart';
import '../../../../core/config/backend_capabilities.dart';
import '../../../../core/config/free_shipping.dart';
import '../../../../core/validation/validators.dart';
import '../../../../core/widgets/address_form.dart';
import '../../../../core/widgets/failure_message.dart';
import '../../../../core/widgets/hub_top_bar.dart';
import '../../../../l10n/l10n.dart';
import '../../../account/data/account_repository.dart';
import '../../../account/domain/customer_address.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../cart/domain/cart.dart';
import '../../../cart/presentation/cart_controller.dart';
import '../../../catalog/domain/money.dart';
import '../../domain/checkout.dart';
import '../../domain/payment_refusal.dart';
import '../../domain/shipping_address_input.dart';
import '../checkout_controller.dart';
import '../checkout_credit_controller.dart';
import '../widgets/checkout_address_form.dart';
import '../widgets/checkout_packages_card.dart';
import '../widgets/checkout_parts.dart';
import '../widgets/checkout_review_step.dart';
import '../widgets/checkout_shipping_step.dart';
import '../widgets/guest_verify_card.dart';
import '../widgets/payment_failed_sheet.dart';
import '../widgets/payment_method_tile.dart';
import '../widgets/store_credit_row.dart';
import 'order_success_screen.dart';

/// Checkout in three steps (Figma 17 → 18 → 18b), ending on Order placed (19):
///
/// 1. **Shipping** — a guest gives an email and the address (17a); a customer
///    starts from their default saved address. Then "Ship to", the shipping
///    methods Magento offers for it and the packages the order ships in (17).
/// 2. **Payment** — the methods the app can take (cash on delivery on Hub
///    Market) and the order summary (18).
/// 3. **Review** — address, method, payment, items and totals, then Place
///    order (18b). When the store refuses the payment, the "Payment declined"
///    sheet (S5) offers the ways on.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  late final AddressFormController _address;

  /// Only shown (and sent) when the store requires a postcode for the UAE.
  final _postcode = TextEditingController();

  /// Re-entrancy guard for place order → order placed.
  bool _placing = false;

  /// True once an address has actually been submitted in THIS screen instance.
  /// The guest-verify card (which auto-sends a live WhatsApp OTP) is gated on
  /// this — never on the session-wide `state.addressDone`, which can still hold
  /// a previous checkout's value on the first frame before `reset()` runs, and
  /// would otherwise fire a spurious OTP send on checkout re-entry.
  bool _addressSubmitted = false;

  /// Saved-address selection (signed-in customers). `_useNewAddress` reveals the
  /// form; otherwise the effective selection defaults to the customer's default
  /// shipping address.
  int? _selectedAddressId;
  bool _useNewAddress = false;

  /// "Change" on the Ship to card reopened the address form.
  bool _editingAddress = false;

  /// A signed-in customer's default address has been sent once, so step 1
  /// opens on "Ship to" (Figma 17) instead of on the address picker.
  bool _defaultAddressSent = false;

  /// False until `reset()` has run. Until then the session-wide controller
  /// can still hold the previous checkout — its step, address and total — so
  /// the first frame draws a fresh state instead.
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _address = AddressFormController();
    final customer = ref.read(authControllerProvider).customer;
    if (customer != null) {
      _email.text = customer.email;
      _address.fullName.text = '${customer.firstName} ${customer.lastName}'
          .trim();
    }
    // Start every checkout from a clean slate. The checkout controller is a
    // session-wide singleton, so without this a second checkout in the same
    // session (or a checkout after logout) inherits the previous order's
    // shipping/payment/total. Post-frame because a provider can't be mutated
    // during the widget-tree build that mounts this screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(checkoutControllerProvider.notifier).reset();
      setState(() => _started = true);
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _address.dispose();
    _postcode.dispose();
    super.dispose();
  }

  CheckoutController get _controller =>
      ref.read(checkoutControllerProvider.notifier);

  bool get _isGuest => !ref.read(authControllerProvider).isAuthenticated;

  /// The locale's comma, for the address on one line.
  String get _comma =>
      Localizations.localeOf(context).languageCode == 'ar' ? '، ' : ', ';

  /// Leaving the email field asks the store whether the address already has an
  /// account (17a's sign-in prompt).
  void _onEmailFocusChange(bool hasFocus) {
    if (!mounted || hasFocus || !_isGuest) return;
    final email = _email.text.trim();
    if (Validators.email(context, email) != null) return;
    _controller.checkGuestEmail(email);
  }

  /// Magento `CartAddressInput`. The emirate goes out as the store's
  /// `region_id` when it has UAE regions, otherwise as the free-text `region`
  /// name (Hub Market has none — see [regionInput]); the single Full Name is
  /// split into firstname/lastname and the apartment line becomes `street[1]`.
  /// `city` is the Area the shopper typed, or the emirate's name without one.
  Map<String, dynamic> _addressInput() {
    final name = _address.splitName();
    final postcode = _postcode.text.trim();
    final regions = ref.read(regionsProvider).valueOrNull ?? const [];
    return <String, dynamic>{
      'firstname': name.first,
      'lastname': name.last,
      'telephone': _address.e164Phone(),
      'street': _address.streetLines(),
      'city': CheckoutAddressForm.cityFor(_address, regions),
      'country_code': addressCountryCode,
      ...regionInput(
        regionId: _address.regionId.value,
        regions: regions,
        fallbackName: _address.region.text,
      ),
      if (postcode.isNotEmpty) 'postcode': postcode,
    };
  }

  /// The typed address on one line, as the Ship to and Review cards show it:
  /// apartment, street, area, emirate, country.
  String _typedAddressLine(AppLocalizations l10n) {
    var emirate = _address.region.text.trim();
    final regions = ref.read(regionsProvider).valueOrNull ?? const [];
    for (final r in regions) {
      if (r.id == _address.regionId.value) {
        emirate = r.name;
        break;
      }
    }
    return shipToAddressLine(
      apartment: _address.apartment.text,
      street: _address.street.text,
      area: _address.area.text,
      emirate: emirate,
      country: l10n.checkoutAddressCountry,
      separator: _comma,
    );
  }

  /// A saved address on one line, in the same order.
  String _savedAddressLine(CustomerAddress a, AppLocalizations l10n) =>
      shipToAddressLine(
        apartment: a.apartment,
        street: a.street,
        area: a.city,
        emirate: a.region.isNotEmpty ? a.region : a.city,
        country: l10n.checkoutAddressCountry,
        separator: _comma,
      );

  /// The new-address form: the shared fields plus, when the store requires
  /// one for the UAE, a postcode.
  Widget _newAddressForm() =>
      CheckoutAddressForm(controller: _address, postcode: _postcode);

  /// Default shipping address id (or the first) from the saved list.
  int? _defaultId(List<CustomerAddress> list) {
    for (final a in list) {
      if (a.defaultShipping) return a.id;
    }
    return list.isEmpty ? null : list.first.id;
  }

  Future<void> _submitAddress() async {
    // Only the email (and, when shown, the new-address form) is validated — a
    // selected saved address needs no form validation.
    if (!_formKey.currentState!.validate()) return;
    final isGuest = _isGuest;
    final saved =
        ref.read(addressesProvider).valueOrNull ?? const <CustomerAddress>[];
    if (!isGuest && !_useNewAddress && saved.isNotEmpty) {
      final id = _selectedAddressId ?? _defaultId(saved);
      await _submitSaved(
        saved.firstWhere((x) => x.id == id, orElse: () => saved.first),
      );
      return;
    }
    // A newly typed address is still saved to the address book, which is the
    // behaviour a shopper expects when they enter one at checkout. Only the
    // already-saved path had to stop re-saving.
    final input = _addressInput();
    final telephone = (input['telephone'] as String?) ?? '';
    await _send(
      shippingAddress: ShippingAddressInput.fresh(input),
      lastname: (input['lastname'] as String?) ?? '',
      telephone: telephone,
      isGuest: isGuest,
      shipTo: ShipTo(
        name: _address.fullName.text.trim(),
        telephone: telephone,
        address: _typedAddressLine(AppLocalizations.of(context)),
      ),
    );
  }

  /// A saved address goes to Magento by id, so its record supplies the
  /// lastname, phone and what the cards show.
  Future<void> _submitSaved(CustomerAddress a) => _send(
    shippingAddress: ShippingAddressInput.saved(a),
    lastname: a.lastName,
    telephone: a.telephone,
    isGuest: false,
    shipTo: ShipTo(
      name: a.fullName,
      telephone: a.telephone,
      address: _savedAddressLine(a, AppLocalizations.of(context)),
      label: a.labelText,
    ),
  );

  Future<void> _send({
    required Map<String, dynamic> shippingAddress,
    required String lastname,
    required String telephone,
    required bool isGuest,
    required ShipTo shipTo,
  }) async {
    final ok = await _controller.submitAddress(
      email: _email.text.trim(),
      shippingAddress: shippingAddress,
      lastname: lastname,
      telephone: telephone,
      isGuest: isGuest,
      shipTo: shipTo,
    );
    if (!mounted || !ok) return;
    setState(() {
      _addressSubmitted = true;
      _editingAddress = false;
    });
  }

  /// A signed-in customer lands on "Ship to" with their default address
  /// (Figma 17): sent once, as soon as the address book has loaded.
  void _sendDefaultAddress(List<CustomerAddress> saved) {
    if (!mounted || !_started || _defaultAddressSent || saved.isEmpty) return;
    if (_isGuest) return;
    final state = ref.read(checkoutControllerProvider);
    if (state.addressDone || state.isBusy) return;
    _defaultAddressSent = true;
    final id = _defaultId(saved);
    _submitSaved(
      saved.firstWhere((x) => x.id == id, orElse: () => saved.first),
    );
  }

  Future<void> _selectShipping(ShippingMethodOption method) async {
    if (ref.read(checkoutControllerProvider).selectedShipping?.id ==
        method.id) {
      return;
    }
    await _controller.selectShipping(method);
  }

  Future<void> _selectPayment(PaymentMethodOption method) async {
    if (ref.read(checkoutControllerProvider).selectedPayment?.code ==
        method.code) {
      return;
    }
    await _controller.selectPayment(method);
  }

  Future<void> _placeOrder() async {
    if (_placing) return;
    // Read before placing: a placed order resets the cart.
    final before = ref.read(checkoutControllerProvider);
    final firstName =
        ref.read(authControllerProvider).customer?.firstName ??
        before.shipTo?.firstName;
    final packages = placedPackagesOf(ref.read(cartControllerProvider).cart);
    setState(() => _placing = true);
    final PlaceOrderResult? result;
    try {
      result = await _controller.placeOrder();
    } finally {
      if (mounted) setState(() => _placing = false);
    }
    if (!mounted) return;
    if (result == null) {
      await _orderRefused(before);
      return;
    }
    // Every method checkout offers completes on placeOrder (payableInApp):
    // cash on delivery, Zero Subtotal `free`, check / money order.
    context.go(
      AppRoutes.orderSuccess,
      extra: OrderPlacedArgs(
        orderNumber: result.orderNumber,
        firstName: firstName,
        total: before.grandTotal,
        payment: before.selectedPayment,
        packages: packages,
      ),
    );
  }

  /// The store refused the order. A payment refusal opens the "Payment
  /// declined" sheet (Figma S5) with the ways on; any other refusal — stock, an
  /// address it rejects, the connection — is the one-line message it always was.
  Future<void> _orderRefused(CheckoutState before) async {
    final l10n = AppLocalizations.of(context);
    final error = ref.read(checkoutControllerProvider).error;
    if (error == null) return;
    final reason = paymentRefusalReason(error);
    final failed = before.selectedPayment;
    if (reason == null || failed == null) {
      _snack(serverMessageOr(context, error, l10n.errorGeneric));
      return;
    }
    final others = [
      for (final m in before.paymentMethods)
        if (m.code != failed.code) m,
    ];
    PaymentMethodOption? cod;
    for (final m in others) {
      if (m.isCashOnDelivery) cod = m;
    }
    final action = await showPaymentFailedSheet(
      context,
      methodTitle: failed.title,
      reason: reason,
      canTryAnotherMethod: others.isNotEmpty,
      canPayCashOnDelivery: cod != null,
    );
    if (!mounted) return;
    switch (action) {
      case PaymentFailedAction.tryAnotherMethod:
        _controller.goTo(CheckoutStep.payment);
      case PaymentFailedAction.payCashOnDelivery:
        if (cod != null) await _selectPayment(cod);
      case PaymentFailedAction.backToCart:
        context.go(AppRoutes.cart);
      case null:
        break;
    }
  }

  /// Whether back leaves checkout: only from step 1 with no reopened form.
  bool _canLeave(CheckoutState state) =>
      state.step == CheckoutStep.shipping &&
      !(_editingAddress && state.addressDone);

  /// Back closes a reopened address form, then goes a step back, then leaves.
  void _onBack() {
    final state = ref.read(checkoutControllerProvider);
    if (state.step == CheckoutStep.shipping &&
        _editingAddress &&
        state.addressDone) {
      setState(() => _editingAddress = false);
      return;
    }
    if (_controller.back()) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.cart);
    }
  }

  void _snack(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final watched = ref.watch(checkoutControllerProvider);
    final state = _started ? watched : const CheckoutState();
    final cart = ref.watch(cartControllerProvider.select((s) => s.cart));
    final isGuest = !ref.watch(authControllerProvider).isAuthenticated;
    // _placing spans place order → navigation; state.isBusy covers the
    // individual address / shipping / payment mutations.
    final busy = state.isBusy || _placing;
    // Guest delivery-phone verification is a backend switch — off on Hub
    // Market, as on its website. When on, the guest must verify the code
    // before moving on to payment.
    final guestOtp = ref.watch(
      backendCapabilitiesProvider.select((c) => c.guestCheckoutOtp),
    );
    final needsGuestOtp = guestOtp && isGuest && !state.guestOtpVerified;
    final showEditor =
        state.step == CheckoutStep.shipping &&
        (!state.addressDone || _editingAddress);

    // Surface the store's own message when Magento refuses a step (an address
    // it rejects, an out-of-stock item at placeOrder) instead of a blanket
    // "Something went wrong" (QA: "check api"). A refused Place order is
    // handled by [_placeOrder] itself, which may open the payment sheet.
    ref.listen<Object?>(checkoutControllerProvider.select((s) => s.error), (
      previous,
      next,
    ) {
      if (next != null && !identical(previous, next) && !_placing) {
        _snack(serverMessageOr(context, next, l10n.errorGeneric));
      }
    });

    if (!isGuest && !_defaultAddressSent) {
      final saved = ref.watch(addressesProvider).valueOrNull;
      if (saved != null && saved.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _sendDefaultAddress(saved),
        );
      }
    }

    // Checkout is light cards on a light page (Figma 17–18b) in both modes:
    // the address fields inherit the theme, and a dark one would draw white
    // text into the white cards.
    return Theme(
      data: AppTheme.light(Localizations.localeOf(context).languageCode),
      child: PopScope(
        canPop: _canLeave(state),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !busy) _onBack();
        },
        child: Scaffold(
          backgroundColor: AppColors.surfaceSubtle,
          appBar: HubTopBar(
            title: l10n.checkoutTitle,
            showBack: true,
            onBack: () {
              if (!busy) _onBack();
            },
          ),
          bottomNavigationBar: _footer(
            l10n,
            state,
            cart,
            busy: busy,
            showEditor: showEditor,
            needsGuestOtp: needsGuestOtp,
          ),
          body: Column(
            children: [
              CheckoutStepIndicator(
                current: state.step,
                onTap: (step) {
                  if (!busy) _controller.goTo(step);
                },
              ),
              Expanded(
                child: Stack(
                  children: [
                    AbsorbPointer(
                      absorbing: busy,
                      // Not a lazy list: every address field must stay mounted
                      // for the form to validate it.
                      child: SingleChildScrollView(
                        key: ValueKey(showEditor ? 'address' : state.step.name),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        child: _stepBody(
                          l10n,
                          state,
                          cart,
                          isGuest: isGuest,
                          guestOtp: guestOtp,
                          showEditor: showEditor,
                        ),
                      ),
                    ),
                    // Single busy indicator over a translucent barrier —
                    // reinforces the AbsorbPointer lock without stacking spinners.
                    if (busy)
                      const Positioned.fill(
                        child: ColoredBox(
                          color: Color(0x33000000),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepBody(
    AppLocalizations l10n,
    CheckoutState state,
    Cart cart, {
    required bool isGuest,
    required bool guestOtp,
    required bool showEditor,
  }) {
    final children = switch (state.step) {
      CheckoutStep.shipping when showEditor => _addressEditor(
        l10n,
        state,
        isGuest,
      ),
      CheckoutStep.shipping => _shippingChoices(
        l10n,
        state,
        cart,
        isGuest: isGuest,
        guestOtp: guestOtp,
      ),
      CheckoutStep.payment => _paymentStep(l10n, state, cart),
      CheckoutStep.review => _reviewStep(l10n, state, cart),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          children[i],
        ],
      ],
    );
  }

  /// 17a: contact (guests) and the address — typed, or picked from the address
  /// book.
  List<Widget> _addressEditor(
    AppLocalizations l10n,
    CheckoutState state,
    bool isGuest,
  ) => [
    Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isGuest) ...[
            ContactCard(
              email: _email,
              onEmailFocusChange: _onEmailFocusChange,
              registeredEmail: state.registeredEmail,
              onSignIn: () => context.push(AppRoutes.signIn),
              onForgotPassword: () => context.push(AppRoutes.forgotPassword),
            ),
            const SizedBox(height: 12),
          ],
          CheckoutCard(
            title: l10n.checkoutShippingAddressTitle,
            children: [isGuest ? _newAddressForm() : _savedAddresses()],
          ),
        ],
      ),
    ),
  ];

  /// A signed-in customer picks a saved address (default selected) or opens
  /// the form; with none saved, the form is all there is.
  Widget _savedAddresses() => ref
      .watch(addressesProvider)
      .when(
        data: (list) {
          if (list.isEmpty) return _newAddressForm();
          return SavedAddressPicker(
            addresses: list,
            selectedId: _useNewAddress
                ? null
                : (_selectedAddressId ?? _defaultId(list)),
            useNew: _useNewAddress,
            onSelect: (a) => setState(() {
              _useNewAddress = false;
              _selectedAddressId = a.id;
            }),
            onUseNew: () => setState(() {
              _useNewAddress = true;
              _selectedAddressId = null;
            }),
            newAddressForm: _newAddressForm(),
          );
        },
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, _) => _newAddressForm(),
      );

  /// 17: where it ships, how, and in how many packages.
  List<Widget> _shippingChoices(
    AppLocalizations l10n,
    CheckoutState state,
    Cart cart, {
    required bool isGuest,
    required bool guestOtp,
  }) {
    final threshold = ref.watch(freeShippingThresholdProvider).valueOrNull;
    final currency = (state.grandTotal ?? cart.totals.grandTotal)?.currency;
    return [
      if (state.shipTo != null)
        ShipToCard(
          shipTo: state.shipTo!,
          onChange: () => setState(() => _editingAddress = true),
        ),
      // When the backend asks for it, guest checkout verifies the delivery
      // phone by OTP before payment. Keyed by the *submitted* phone so a
      // changed number remounts it (re-requesting the code); shown only after
      // a real submit this session so it never auto-sends on re-entry.
      if (guestOtp && isGuest && _addressSubmitted)
        GuestVerifyCard(
          key: ValueKey(state.submittedPhone),
          phone: state.submittedPhone,
        ),
      ShippingMethodsCard(
        methods: state.shippingMethods,
        selected: state.selectedShipping,
        onSelect: _selectShipping,
        freeShippingOver: threshold == null || currency == null
            ? null
            : Money(amount: threshold, currency: currency),
      ),
      // One package per store (HubApp); nothing without it.
      if (packageCountOf(cart) != null) CheckoutPackagesCard(cart: cart),
    ];
  }

  /// "4 items · 2 packages" beside the summary's title (the packages part only
  /// when the lines name their stores).
  String _summaryCount(AppLocalizations l10n, Cart cart) {
    final items = l10n.cartItemCount(cart.itemCount);
    final packages = packageCountOf(cart);
    return packages == null
        ? items
        : '$items · ${l10n.checkoutPackageCount(packages)}';
  }

  /// 18: the methods the app can take, and the order summary.
  List<Widget> _paymentStep(
    AppLocalizations l10n,
    CheckoutState state,
    Cart cart,
  ) => [
    Text(
      l10n.checkoutPaymentMethodTitle,
      style: CheckoutText.of(context).heading2,
    ),
    // "Use my credit" (HubAppAccount), while the customer can spend some.
    if (ref.watch(checkoutCreditProvider.select((s) => s.offered)))
      const CheckoutStoreCreditRow(),
    for (final method in state.paymentMethods)
      PaymentMethodTile(
        method: method,
        selected: state.selectedPayment?.code == method.code,
        onTap: () => _selectPayment(method),
      ),
    CheckoutTotalsCard(
      title: l10n.checkoutOrderSummaryTitle,
      trailing: _summaryCount(l10n, cart),
      spacing: 10,
      cart: cart,
      shipping: state.selectedShipping,
      grandTotal: state.grandTotal,
    ),
  ];

  /// 18b: everything once more before Place order.
  List<Widget> _reviewStep(
    AppLocalizations l10n,
    CheckoutState state,
    Cart cart,
  ) {
    final payment = state.selectedPayment;
    return [
      Text(l10n.checkoutReviewTitle, style: CheckoutText.of(context).heading1),
      ReviewShippingCard(
        shipTo: state.shipTo,
        method: state.selectedShipping,
        onEdit: () => _controller.goTo(CheckoutStep.shipping),
      ),
      if (payment != null)
        ReviewPaymentCard(
          method: payment,
          onEdit: () => _controller.goTo(CheckoutStep.payment),
        ),
      ReviewItemsCard(cart: cart),
      CheckoutTotalsCard(
        title: l10n.checkoutOrderTotal,
        cart: cart,
        shipping: state.selectedShipping,
        grandTotal: state.grandTotal,
      ),
      const ReviewTermsNote(),
    ];
  }

  /// The pinned action for the step on screen.
  Widget _footer(
    AppLocalizations l10n,
    CheckoutState state,
    Cart cart, {
    required bool busy,
    required bool showEditor,
    required bool needsGuestOtp,
  }) {
    final t = CheckoutText.of(context);
    final total = state.grandTotal ?? cart.totals.grandTotal;
    // The "encrypted" line belongs to a payment taken online; cash on delivery
    // and a free order have nothing to encrypt.
    final online = state.selectedPayment?.isOnline ?? false;
    switch (state.step) {
      case CheckoutStep.shipping:
        if (showEditor) {
          return CheckoutFooter(
            children: [
              FilledButton(
                onPressed: busy ? null : _submitAddress,
                child: Text(l10n.checkoutContinueToShipping),
              ),
            ],
          );
        }
        return CheckoutFooter(
          children: [
            CheckoutAmountRow(
              label: l10n.checkoutTotalInclShipping,
              value: total?.formatted() ?? '—',
              valueStyle: t.price,
            ),
            if (needsGuestOtp)
              Text(
                l10n.checkoutVerifyMobileTitle,
                textAlign: TextAlign.center,
                style: t.caption,
              ),
            // The store offers only methods the app can't take yet (an online
            // gateway): say so rather than leave a dead button.
            if (!busy &&
                state.selectedShipping != null &&
                state.paymentMethods.isEmpty)
              Text(
                l10n.checkoutNoPaymentMethods,
                textAlign: TextAlign.center,
                style: t.caption,
              ),
            FilledButton(
              onPressed: (busy || !state.shippingDone || needsGuestOtp)
                  ? null
                  : _controller.continueToPayment,
              child: Text(l10n.checkoutContinueToPayment),
            ),
          ],
        );
      case CheckoutStep.payment:
        return CheckoutFooter(
          spacing: 10,
          children: [
            if (online) CheckoutSecureNote(l10n.checkoutPaymentsEncrypted),
            FilledButton.icon(
              onPressed: (busy || !state.paymentDone)
                  ? null
                  : _controller.continueToReview,
              icon: const Icon(HubIcons.arrowRight, size: 20),
              label: Text(l10n.checkoutReviewOrder),
            ),
          ],
        );
      case CheckoutStep.review:
        return CheckoutFooter(
          spacing: 10,
          children: [
            if (online) CheckoutSecureNote(l10n.checkoutPaymentSecure),
            FilledButton.icon(
              onPressed:
                  (busy ||
                      needsGuestOtp ||
                      !state.canEnter(CheckoutStep.review))
                  ? null
                  : _placeOrder,
              icon: const Icon(HubIcons.lock, size: 20),
              label: Text(
                total == null
                    ? l10n.checkoutPlaceOrder
                    : '${l10n.checkoutPlaceOrder} · ${total.formatted()}',
              ),
            ),
          ],
        );
    }
  }
}
