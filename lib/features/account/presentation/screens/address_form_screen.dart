import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/address/regions.dart';
import '../../../../core/validation/phone.dart';
import '../../../../core/validation/validators.dart';
import '../../../../core/widgets/address_form.dart';
import '../../../../core/widgets/hub_bottom_action_bar.dart';
import '../../../../core/widgets/hub_bottom_sheet.dart';
import '../../../../core/widgets/hub_button.dart';
import '../../../../core/widgets/hub_chip.dart';
import '../../../../core/widgets/hub_icon_button.dart';
import '../../../../core/widgets/hub_radio_dot.dart';
import '../../../../core/widgets/hub_top_bar.dart';
import '../../../../l10n/l10n.dart';
import '../../../auth/presentation/widgets/auth_field.dart';
import '../../data/account_repository.dart';
import '../../data/address_rules.dart';
import '../../domain/customer_address.dart';
import '../emirate_names.dart';

/// Add / edit address (Figma 24b): a close button and a hairline under the bar,
/// labelled fields with a leading icon, the emirate as a picker, "Save as"
/// chips, the "Set as default address" card and the primary "Save address"
/// pinned under the form.
///
/// Not drawn here, because the app has nothing behind them: the frame's map
/// ("Move the map to pin your building") and "Use my current location" (no map
/// or location access), the Area picker (no list of areas; Magento's `city` is
/// filled from the emirate), "Landmark" (Magento's address has no such field)
/// and "Verify this number with a one-time code" (the store has no OTP step on
/// addresses). The postcode appears only where the store demands one.
class AddressFormScreen extends ConsumerStatefulWidget {
  const AddressFormScreen({super.key, this.initial});

  final CustomerAddress? initial;

  @override
  ConsumerState<AddressFormScreen> createState() => _AddressFormScreenState();
}

class _AddressFormScreenState extends ConsumerState<AddressFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final AddressFormController _address;
  late final TextEditingController _postcode;
  bool _busy = false;
  String? _selectedLabelId;

  @override
  void initState() {
    super.initState();
    final a = widget.initial;
    _postcode = TextEditingController(text: a?.postcode ?? '');
    _address = AddressFormController(
      fullName: a?.fullName ?? '',
      phone: a?.telephone ?? '',
      area: a?.city ?? '',
      street: a?.street ?? '',
      apartment: a?.apartment ?? '',
      region: a?.region ?? '',
      regionId: a?.regionId,
      isDefault: a?.defaultShipping ?? false,
    );
    // The field shows the whole number, "+971 50 123 4567" (the controller
    // starts with the digits after the dial code).
    if (a != null && a.telephone.trim().isNotEmpty) {
      _address.phone.text = Phone.display(a.telephone);
    }
    _selectedLabelId = a?.labelOptionId;
  }

  @override
  void dispose() {
    _address.dispose();
    _postcode.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final name = _address.splitName();
    // The store's region_id when it has UAE regions, else the emirate's name.
    final region = regionInput(
      regionId: _address.regionId.value,
      regions: ref.read(regionsProvider).valueOrNull ?? const [],
      fallbackName: _address.region.text,
    );
    final address = CustomerAddress(
      id: widget.initial?.id,
      firstName: name.first,
      lastName: name.last,
      telephone: _address.e164Phone(),
      street: _address.street.text.trim(),
      apartment: _address.apartment.text.trim(),
      city: _address.area.text.trim(),
      postcode: _postcode.text.trim(),
      region: (region['region'] as String?) ?? '',
      regionId: region['region_id'] as int?,
      countryCode: addressCountryCode,
      defaultShipping: _address.isDefault.value,
      labelOptionId: _selectedLabelId,
    );
    try {
      final repo = ref.read(accountRepositoryProvider);
      final id = widget.initial?.id;
      if (id != null) {
        await repo.updateAddress(id, address);
      } else {
        await repo.createAddress(address);
      }
      ref.invalidate(addressesProvider);
      if (mounted) context.pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).errorGeneric)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isEdit = widget.initial != null;
    final postcodeRequired =
        ref.watch(postcodeRequiredProvider).valueOrNull ?? false;
    return Scaffold(
      appBar: HubTopBar(
        title: isEdit ? l10n.addressEdit : l10n.addressAdd,
        leading: HubIconButton(
          icon: HubIcons.x,
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: () => context.pop(),
        ),
        divider: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthField(
                controller: _address.fullName,
                label: l10n.fieldFullName,
                icon: HubIcons.user,
                hint: l10n.addressHintName,
                textCapitalization: TextCapitalization.words,
                validator: (v) => Validators.required(context, v),
              ),
              const SizedBox(height: 14),
              AuthField(
                controller: _address.phone,
                label: l10n.fieldPhone,
                icon: HubIcons.phone,
                hint: '+971 50 123 4567',
                keyboardType: TextInputType.phone,
                ltrInput: true,
                validator: (v) => Validators.uaePhone(context, v),
              ),
              const SizedBox(height: 14),
              _EmirateField(controller: _address),
              const SizedBox(height: 14),
              AuthField(
                controller: _address.street,
                label: l10n.fieldStreet,
                icon: HubIcons.store,
                hint: l10n.addressHintStreet,
                validator: (v) => Validators.required(context, v),
              ),
              const SizedBox(height: 14),
              AuthField(
                controller: _address.apartment,
                label: l10n.fieldApartment,
                icon: HubIcons.house,
                textInputAction: postcodeRequired
                    ? TextInputAction.next
                    : TextInputAction.done,
              ),
              if (postcodeRequired) ...[
                const SizedBox(height: 14),
                AuthField(
                  controller: _postcode,
                  label: l10n.fieldPostcode,
                  textInputAction: TextInputAction.done,
                  validator: (v) => Validators.required(context, v),
                ),
              ],
              const SizedBox(height: 14),
              // Save as: Home / Work / Other (the `address_label` select).
              // Options + ids come from the backend; nothing hardcoded.
              _SaveAsChips(
                selectedId: _selectedLabelId,
                onSelected: (id) => setState(() => _selectedLabelId = id),
              ),
              _DefaultCard(isDefault: _address.isDefault),
            ],
          ),
        ),
      ),
      bottomNavigationBar: HubBottomActionBar(
        bottomSpace: 28,
        child: HubButton(
          label: l10n.addressSave,
          style: HubButtonStyle.primary,
          loading: _busy,
          onPressed: _save,
        ),
      ),
    );
  }
}

/// "Emirate" (Figma 24b): the label over a 52 px field — globe, the chosen
/// emirate, chevron — which opens the list of emirates. When the list can't be
/// read the field is a plain text box so the form is never blocked.
class _EmirateField extends ConsumerWidget {
  const _EmirateField({required this.controller});

  final AddressFormController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final regions = ref.watch(regionsProvider);
    return regions.when(
      data: (list) => ValueListenableBuilder<int?>(
        valueListenable: controller.regionId,
        builder: (context, id, _) {
          // The store has no regions for the UAE, so a saved address has the
          // emirate as text only: that is what the field shows until another
          // is picked.
          RegionOption? picked;
          for (final r in list) {
            if (r.id == id) picked = r;
          }
          final shown = emirateLabel(
            l10n,
            picked?.name ?? controller.region.text,
          );
          return FormField<String>(
            initialValue: shown,
            validator: (_) => shown.isEmpty ? l10n.validationRequired : null,
            builder: (field) => _SelectField(
              label: l10n.fieldEmirate,
              icon: HubIcons.globe,
              value: shown,
              errorText: field.errorText,
              onTap: () async {
                final chosen = await showHubBottomSheet<RegionOption>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  builder: (_) => _EmiratePicker(
                    title: l10n.fieldEmirate,
                    options: list,
                    selected: picked?.id,
                  ),
                );
                if (chosen == null) return;
                controller.regionId.value = chosen.id;
                controller.region.text = chosen.name;
                // There's no separate Area/City field (matching the website),
                // so Magento's required `city` is the emirate's name.
                controller.area.text = chosen.name;
                field.didChange(emirateLabel(l10n, chosen.name));
              },
            ),
          );
        },
      ),
      loading: () => _SelectField(
        label: l10n.fieldEmirate,
        icon: HubIcons.globe,
        value: '',
        loading: true,
      ),
      // Emirate list unavailable → free text, so the form isn't blocked.
      error: (_, _) => AuthField(
        controller: controller.region,
        label: l10n.fieldEmirate,
        icon: HubIcons.globe,
        validator: (v) => Validators.required(context, v),
      ),
    );
  }
}

/// A select that opens a picker: the label over a 52 px field with a leading
/// icon, the value (or the hint) and a chevron — the look of `AuthField`, for
/// a choice rather than typing.
class _SelectField extends StatelessWidget {
  const _SelectField({
    required this.label,
    required this.icon,
    required this.value,
    this.onTap,
    this.errorText,
    this.loading = false,
  });

  final String label;
  final IconData icon;
  final String value;
  final VoidCallback? onTap;
  final String? errorText;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final red = errorText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: t.captionStrong.copyWith(color: AppColors.inkHeading),
        ),
        const SizedBox(height: 6),
        Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: red ? AppColors.danger : AppColors.borderStrong,
              width: red ? 1.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: loading ? null : onTap,
            child: SizedBox(
              height: 52,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(icon, size: 20, color: AppColors.inkMuted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.body.copyWith(color: AppColors.inkHeading),
                      ),
                    ),
                    if (loading)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      const Icon(
                        HubIcons.chevronDown,
                        size: 20,
                        color: AppColors.inkMuted,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (red) ...[
          const SizedBox(height: 6),
          AuthHelperLine.error(errorText!),
        ],
      ],
    );
  }
}

/// The emirates to choose from: one row each, the chosen one marked with the
/// frames' radio.
class _EmiratePicker extends StatelessWidget {
  const _EmiratePicker({
    required this.title,
    required this.options,
    required this.selected,
  });

  final String title;
  final List<RegionOption> options;
  final int? selected;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: t.heading2.copyWith(color: context.scaffoldHeading),
          ),
          const SizedBox(height: 4),
          for (final option in options)
            InkWell(
              onTap: () => Navigator.of(context).pop(option),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: context.isDarkMode
                          ? Colors.white12
                          : AppColors.borderSubtle,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    HubRadioDot(selected: option.id == selected),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        emirateLabel(AppLocalizations.of(context), option.name),
                        style: t.body.copyWith(color: context.scaffoldHeading),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Save as" (Figma 24b "address-label"): the label over the chips — one per
/// `address_label` option the backend defines, in the store view's language;
/// the chosen one is navy. Tapping it again clears it. Hidden when the store
/// has no options.
class _SaveAsChips extends ConsumerWidget {
  const _SaveAsChips({required this.selectedId, required this.onSelected});

  final String? selectedId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final options =
        ref.watch(addressLabelOptionsProvider).valueOrNull ?? const [];
    if (options.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.addressSaveAs,
            style: t.captionStrong.copyWith(color: context.scaffoldHeading),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final opt in options)
                HubChip(
                  label: opt.label,
                  selected: selectedId == opt.value,
                  onTap: () =>
                      onSelected(selectedId == opt.value ? null : opt.value),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Set as default address / Used first at checkout" (Figma 24b "default"): a
/// 1 px bordered card with the 44 x 26 switch.
class _DefaultCard extends StatelessWidget {
  const _DefaultCard({required this.isDefault});

  final ValueNotifier<bool> isDefault;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: isDefault,
      builder: (context, value, _) => Semantics(
        toggled: value,
        label: l10n.addressDefaultShipping,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => isDefault.value = !value,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: context.isDarkMode
                    ? Colors.white12
                    : AppColors.borderSubtle,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.addressDefaultShipping,
                        style: t.bodyStrong.copyWith(
                          color: context.scaffoldHeading,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.addressDefaultHint,
                        style: t.caption.copyWith(
                          color: context.scaffoldMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _Switch(on: value),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Figma "switch": a 44 x 26 track — navy when on, `--hm-default` when off — and
/// a 20 px white thumb 3 px in from the end it sits at. The row around it
/// takes the tap.
class _Switch extends StatelessWidget {
  const _Switch({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 150),
    width: 44,
    height: 26,
    padding: const EdgeInsets.all(3),
    alignment: on
        ? AlignmentDirectional.centerEnd
        : AlignmentDirectional.centerStart,
    decoration: BoxDecoration(
      color: on ? AppColors.brandPrimary : AppColors.borderStrong,
      borderRadius: BorderRadius.circular(13),
    ),
    child: Container(
      width: 20,
      height: 20,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
    ),
  );
}
