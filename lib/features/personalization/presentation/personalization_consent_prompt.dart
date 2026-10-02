import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/hub_icons.dart';
import '../../../core/widgets/hub_button.dart';
import '../../../l10n/l10n.dart';
import '../data/personalization_identity.dart';

/// Asks once, when the Home first opens, whether Picked For You may use the
/// shopper's activity ("Personalise my picks?": Allow / Not now). Until the
/// shopper allows it the app sends no Insights event, makes no token and does
/// not ask `hmPickedForYou`; the website works the same way (no cookie consent,
/// nothing personal).
///
/// Wraps the Home's body and changes nothing about its layout. The question is
/// asked while the answer is [PersonalizationConsent.undecided]; the buttons
/// settle it for good (nothing else closes the sheet: a tap beside it, a drag
/// and the back gesture leave it open, so no answer is made up for the
/// shopper), and the Settings switch is where the shopper changes their mind.
class PersonalizationConsentPrompt extends ConsumerStatefulWidget {
  const PersonalizationConsentPrompt({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PersonalizationConsentPrompt> createState() =>
      _PersonalizationConsentPromptState();
}

class _PersonalizationConsentPromptState
    extends ConsumerState<PersonalizationConsentPrompt> {
  @override
  void initState() {
    super.initState();
    // A sheet cannot open while the page is still being built.
    WidgetsBinding.instance.addPostFrameCallback((_) => _ask());
  }

  Future<void> _ask() async {
    if (!mounted) return;
    // Not over a page that was pushed on top of the Home (a link into a
    // product, say): the next time the Home opens will do.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    if (ref.read(personalizationConsentProvider) !=
        PersonalizationConsent.undecided) {
      return;
    }
    final consent = ref.read(personalizationConsentProvider.notifier);
    final allowed = await showPersonalizationConsentSheet(context);
    await consent.set(allowed);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Opens the "Personalise my picks?" sheet over the page, with the design's
/// scrim (navy at 55 %). Resolves to true for Allow and to false for Not now;
/// the scrim, a drag and the back gesture do not close it, so the shopper
/// answers.
Future<bool> showPersonalizationConsentSheet(BuildContext context) async {
  final allowed = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.white,
    barrierColor: const Color(0x8C0F2144),
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    useSafeArea: false,
    clipBehavior: Clip.antiAlias,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const PersonalizationConsentSheet(),
  );
  return allowed ?? false;
}

/// The question: a spark in the accent tint, what the app would use the
/// shopper's activity for and under what id, where to change it later, and the
/// two answers. Not a Figma frame: built from the sheets' own pieces (the
/// "Payment failed" sheet's chrome, [HubButton]).
class PersonalizationConsentSheet extends StatelessWidget {
  const PersonalizationConsentSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final bottom = math.max(24.0, MediaQuery.paddingOf(context).bottom);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The grab handle, as every sheet draws it (this one stays shut).
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
        const SizedBox(height: 20),
        Center(
          child: Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.accentSurface,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              HubIcons.sparkles,
              size: 32,
              color: AppColors.accentStrong,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          child: Text(
            l10n.personalisationPromptTitle,
            textAlign: TextAlign.center,
            style: t.heading1.copyWith(color: AppColors.inkHeading),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.personalisationPromptBody,
          textAlign: TextAlign.center,
          style: t.body.copyWith(color: AppColors.inkMuted),
        ),
        const SizedBox(height: 10),
        Text(
          l10n.personalisationPromptNote,
          textAlign: TextAlign.center,
          style: t.caption.copyWith(color: AppColors.inkSubtle),
        ),
        const SizedBox(height: 20),
        HubButton(
          label: l10n.personalisationPromptAllow,
          onPressed: () => Navigator.of(context).pop(true),
        ),
        const SizedBox(height: 10),
        HubButton(
          label: l10n.personalisationPromptLater,
          style: HubButtonStyle.ghost,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    );
    // Back does not answer for the shopper (a refusal is not made up from an
    // accidental edge swipe): the two buttons are the only way out. Scrolls
    // rather than overflows on a short window or a large text size.
    return PopScope(
      canPop: false,
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 12, 24, bottom),
          child: content,
        ),
      ),
    );
  }
}
