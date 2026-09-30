import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../domain/cms_links.dart';
import '../cms_navigation.dart';
import '../cms_providers.dart';

/// A sentence of interface wording with some of its words linked to the
/// store's legal pages, written with tags (see [legalTextParts]) as in
/// `I agree to the <terms>Terms of Service</terms> and <privacy>…</privacy>`.
///
/// Each tagged run links to its page as the CMS block `hm_footer_legal`
/// links it ([legalLinksProvider], the website footer's own links) and opens
/// in the native content page. Words whose page the block doesn't have — and
/// all of them while it loads — stay plain, so the sentence reads the same
/// either way.
class LegalLinksText extends ConsumerStatefulWidget {
  const LegalLinksText(this.text, {super.key, this.style, this.textAlign});

  /// The localized sentence, tags included.
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  ConsumerState<LegalLinksText> createState() => _LegalLinksTextState();
}

class _LegalLinksTextState extends ConsumerState<LegalLinksText> {
  /// Link recognizers of the current build, disposed before the next one.
  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];

  static const TextStyle _linkStyle = TextStyle(
    color: AppColors.accentStrong,
    fontWeight: FontWeight.w600,
    decoration: TextDecoration.underline,
    decorationColor: AppColors.accentStrong,
  );

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  TextSpan _span(LegalTextPart part, List<CmsLink> links) {
    final page = part.page;
    final link = page == null ? null : legalLinkFor(links, page);
    if (link == null) return TextSpan(text: part.text);
    final recognizer = TapGestureRecognizer()
      ..onTap = () => openStorePageLink(context, ref, link);
    _recognizers.add(recognizer);
    return TextSpan(text: part.text, style: _linkStyle, recognizer: recognizer);
  }

  @override
  Widget build(BuildContext context) {
    // Recognizers belong to the spans of one build.
    _disposeRecognizers();
    final links =
        ref.watch(legalLinksProvider).valueOrNull ?? const <CmsLink>[];
    return Text.rich(
      TextSpan(
        children: [
          for (final part in legalTextParts(widget.text)) _span(part, links),
        ],
      ),
      style: widget.style,
      textAlign: widget.textAlign,
    );
  }
}
