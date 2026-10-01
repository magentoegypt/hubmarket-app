import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/theme/app_colors.dart';
import 'package:hubmarket_app/features/cms/domain/cms_document.dart';
import 'package:hubmarket_app/features/cms/presentation/widgets/cms_html_view.dart';

/// The content page's type (Figma 28): the opening lines in ink, the sections
/// under EN/Title headings in `text/subtle`; the other screens that render CMS
/// content keep the compact look.

const _html =
    '<p>Opening line.</p>'
    '<h2>What we collect</h2><p>Your name.</p>'
    '<h2>Cookies</h2><p>A small amount of data.</p>';

Future<void> _pump(WidgetTester tester, {required bool page}) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CmsHtmlView(
              page: page,
              blocks: CmsDocument.parse(_html),
              onLink: (_) {},
            ),
          ),
        ),
      ),
    );

/// The style the view gave [text]: the one on the span it builds, under the
/// ambient style `Text.rich` adds above it.
TextStyle? _styleOf(WidgetTester tester, String text) {
  final rich = tester.widget<RichText>(
    find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText() == text),
  );
  final root = rich.text as TextSpan;
  return (root.children!.first as TextSpan).style;
}

void main() {
  testWidgets('page: ink opening, subtle sections, Title headings', (
    tester,
  ) async {
    await _pump(tester, page: true);

    expect(_styleOf(tester, 'Opening line.')?.color, AppColors.inkHeading);
    expect(_styleOf(tester, 'Your name.')?.color, AppColors.inkSubtle);
    expect(_styleOf(tester, 'A small amount of data.')?.color, AppColors.inkSubtle);
    // EN/Body 14/20 for the text, EN/Title 16/22 SemiBold for a section.
    final body = _styleOf(tester, 'Your name.')!;
    expect(body.fontSize, 14);
    expect(body.height, closeTo(20 / 14, 0.001));
    final heading = _styleOf(tester, 'What we collect')!;
    expect(heading.fontSize, 16);
    expect(heading.fontWeight, FontWeight.w600);
    expect(heading.color, AppColors.inkHeading);
  });

  testWidgets('page: 6 under a heading, 16 between sections', (tester) async {
    await _pump(tester, page: true);
    double bottom(String text) => tester
        .getBottomLeft(
          find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText() == text,
          ),
        )
        .dy;
    double top(String text) => tester
        .getTopLeft(
          find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText() == text,
          ),
        )
        .dy;
    expect(top('Your name.') - bottom('What we collect'), closeTo(6, 0.5));
    expect(top('Cookies') - bottom('Your name.'), closeTo(16, 0.5));
    expect(top('What we collect') - bottom('Opening line.'), closeTo(16, 0.5));
  });

  testWidgets('without page the content keeps its compact look', (
    tester,
  ) async {
    await _pump(tester, page: false);
    final body = _styleOf(tester, 'Opening line.')!;
    // The home, store pages and the return form still read 15 px muted text.
    expect(body.fontSize, 15);
    expect(body.color, isNot(AppColors.inkHeading));
  });
}
