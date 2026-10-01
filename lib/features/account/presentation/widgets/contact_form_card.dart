import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/validation/validators.dart';
import '../../../../core/widgets/button_spinner.dart';
import '../../../../core/widgets/failure_message.dart';
import '../../../../core/widgets/grouped_list.dart';
import '../../../../l10n/l10n.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../data/account_repository.dart';
import '../../../../app/theme/hub_icons.dart';

/// "Send us a message" (Figma 27): Magento's own contact form (`contactUs`),
/// which e-mails the store's contact address. Prefilled for a signed-in
/// customer. The Help centre shows it only when storeConfig
/// `contact_enabled` is on.
class ContactFormCard extends ConsumerStatefulWidget {
  const ContactFormCard({super.key});

  @override
  ConsumerState<ContactFormCard> createState() => _ContactFormCardState();
}

class _ContactFormCardState extends ConsumerState<ContactFormCard> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  final _comment = TextEditingController();
  bool _busy = false;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    final customer = ref.read(authControllerProvider).customer;
    _name = TextEditingController(text: customer?.fullName ?? '');
    _email = TextEditingController(text: customer?.email ?? '');
    _phone = TextEditingController(text: customer?.mobileNumber ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref
          .read(accountRepositoryProvider)
          .sendContactMessage(
            name: _name.text.trim(),
            email: _email.text.trim(),
            telephone: _phone.text.trim(),
            comment: _comment.text.trim(),
          );
      if (!mounted) return;
      _comment.clear();
      setState(() => _sent = true);
      messenger.showSnackBar(SnackBar(content: Text(l10n.helpMessageSent)));
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(serverMessageOr(context, error, l10n.errorGeneric)),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GroupCard(
      padding: const EdgeInsets.all(14),
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.helpMessageTitle,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: context.scaffoldHeading,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.helpMessageIntro,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: context.scaffoldMuted,
                ),
              ),
              const SizedBox(height: 14),
              _LabeledField(
                label: l10n.helpMessageName,
                controller: _name,
                icon: HubIcons.user,
                textCapitalization: TextCapitalization.words,
                validator: (v) => Validators.required(context, v),
              ),
              _LabeledField(
                label: l10n.helpMessageEmail,
                controller: _email,
                icon: HubIcons.mail,
                keyboardType: TextInputType.emailAddress,
                validator: (v) => Validators.email(context, v),
              ),
              _LabeledField(
                label: l10n.helpMessagePhone,
                controller: _phone,
                icon: HubIcons.phone,
                keyboardType: TextInputType.phone,
                forceLtr: true,
              ),
              _LabeledField(
                label: l10n.helpMessageBody,
                controller: _comment,
                minLines: 4,
                maxLines: 8,
                keyboardType: TextInputType.multiline,
                validator: (v) => Validators.required(context, v),
              ),
              if (_sent)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      const Icon(
                        HubIcons.circleCheck,
                        size: 18,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.helpMessageSent,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.success,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              FilledButton(
                onPressed: _busy ? null : _send,
                child: _busy
                    ? const ButtonSpinner()
                    : Text(
                        l10n.helpMessageSend,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A label above an outlined field, as in the Figma forms.
class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.controller,
    this.icon,
    this.validator,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.minLines,
    this.maxLines = 1,
    this.forceLtr = false,
  });

  final String label;
  final TextEditingController controller;
  final IconData? icon;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final int? minLines;
  final int maxLines;

  /// Phone numbers read left-to-right in Arabic too (a leading `+` must not
  /// jump to the end), while still sitting at the field's start edge.
  final bool forceLtr;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: context.hairline),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: context.scaffoldHeading,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            validator: validator,
            keyboardType: keyboardType,
            textCapitalization: textCapitalization,
            minLines: minLines,
            maxLines: maxLines,
            textDirection: forceLtr ? TextDirection.ltr : null,
            textAlign: forceLtr && rtl ? TextAlign.right : TextAlign.start,
            decoration: InputDecoration(
              prefixIcon: icon == null
                  ? null
                  : Icon(icon, size: 20, color: context.scaffoldMuted),
              filled: true,
              fillColor: groupCardColor(context),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              border: border,
              enabledBorder: border,
              focusedBorder: border.copyWith(
                borderSide: const BorderSide(
                  color: AppColors.brandPrimary,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
