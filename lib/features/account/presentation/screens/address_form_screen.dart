import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/address/regions.dart';
import '../../../../core/widgets/address_form.dart';
import '../../../../core/widgets/hub_back_button.dart';
import '../../../../l10n/l10n.dart';
import '../../data/account_repository.dart';
import '../../domain/customer_address.dart';
import '../widgets/postcode_field.dart';

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
    return Scaffold(
      appBar: AppBar(
        leading: const HubBackButton(),
        title: Text(isEdit ? l10n.addressEdit : l10n.addressAdd),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AddressForm(controller: _address),
                PostcodeField(controller: _postcode),
                const SizedBox(height: 16),
                // Save as: Home / Office / Other (the `address_label` select).
                // Options + ids come from the backend; nothing hardcoded.
                _SaveAsChips(
                  selectedId: _selectedLabelId,
                  onSelected: (id) => setState(() => _selectedLabelId = id),
                ),
                // Set as default address (Figma 64:92) — label + navy toggle.
                ValueListenableBuilder<bool>(
                  valueListenable: _address.isDefault,
                  builder: (context, value, _) => Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        l10n.addressDefaultShipping,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.inkHeading,
                        ),
                      ),
                      Switch(
                        value: value,
                        onChanged: (v) => _address.isDefault.value = v,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: AppColors.borderDefault,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.addressSave),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Save as: Home / Office / Other" chips — the `address_label` select. Options
/// + their ids come from the backend metadata; hidden when none are configured.
class _SaveAsChips extends ConsumerWidget {
  const _SaveAsChips({required this.selectedId, required this.onSelected});
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final options =
        ref.watch(addressLabelOptionsProvider).valueOrNull ?? const [];
    if (options.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.addressSaveAs,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: AppColors.inkHeading,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final opt in options)
              ChoiceChip(
                label: Text(opt.label),
                selected: selectedId == opt.value,
                onSelected: (sel) => onSelected(sel ? opt.value : null),
              ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
