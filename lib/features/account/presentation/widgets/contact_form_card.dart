import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/validation/phone.dart';
import '../../../../core/validation/validators.dart';
import '../../../../core/widgets/failure_message.dart';
import '../../../../core/widgets/grouped_list.dart';
import '../../../../core/widgets/hub_button.dart';
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
    // "+971 50 123 4567", as the frame prints it.
    final mobile = customer?.mobileNumber;
    _phone = TextEditingController(
      text: mobile == null ? '' : Phone.display(mobile),
    );
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
    final t = AppTextStyles.of(context);
    // Figma `contact-form`: 14 px of padding, 12 between the parts.
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
                style: t.title.copyWith(color: context.scaffoldHeading),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.helpMessageIntro,
                style: t.caption.copyWith(color: context.scaffoldMuted),
              ),
              const SizedBox(height: 12),
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
                minLines: 3,
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
                        color: AppColors.successStrong,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.helpMessageSent,
                          style: t.caption.copyWith(
                            color: AppColors.successStrong,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              HubButton(
                label: l10n.helpMessageSend,
                loading: _busy,
                onPressed: _send,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A label above a field, as the Figma forms draw them: EN/Caption Strong
/// over a white box with a 1 px `border/strong` outline at radius 12 (the
/// global input theme). A one-line field is 52 px with its 20 px icon; the
/// message box is at least 96 px with 14 / 12 px of padding and no icon.
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
    final t = AppTextStyles.of(context);
    final multiline = maxLines > 1;
    // A one-line field is 52 px whatever the locale's line height.
    final vertical = (52 - t.body.fontSize! * t.body.height!) / 2;
    final field = TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      minLines: minLines,
      maxLines: maxLines,
      textDirection: forceLtr ? TextDirection.ltr : null,
      textAlign: forceLtr && rtl ? TextAlign.right : TextAlign.start,
      style: t.body.copyWith(color: AppColors.inkHeading),
      cursorColor: AppColors.brandPrimary,
      decoration: InputDecoration(
        isDense: true,
        contentPadding: multiline
            ? const EdgeInsets.symmetric(horizontal: 14, vertical: 12)
            : EdgeInsetsDirectional.fromSTEB(
                icon == null ? 16 : 0,
                vertical,
                16,
                vertical,
              ),
        prefixIcon: icon == null
            ? null
            : Padding(
                padding: const EdgeInsetsDirectional.only(start: 16, end: 10),
                child: Icon(icon, size: 20, color: AppColors.inkMuted),
              ),
        prefixIconConstraints: const BoxConstraints(),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: t.captionStrong.copyWith(color: context.scaffoldHeading),
          ),
          const SizedBox(height: 6),
          multiline
              ? ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 96),
                  child: field,
                )
              : field,
        ],
      ),
    );
  }
}
