import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/theme/app_colors.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/features/notifications/data/notification_inbox.dart';
import 'package:hubmarket_app/features/notifications/domain/notification_item.dart';
import 'package:hubmarket_app/features/notifications/presentation/notifications_screen.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fonts.dart';

NotificationItem _item(String id, String title, {bool read = false}) =>
    NotificationItem(
      id: id,
      kind: NotificationKind.order,
      title: title,
      body: 'Your package is on its way.',
      receivedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      read: read,
    );

Widget _app({required String locale, bool dark = false, GlobalKey? boundary}) {
  final app = MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: dark ? AppTheme.dark(locale) : AppTheme.light(locale),
    locale: Locale(locale),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: const NotificationsScreen(),
  );
  return ProviderScope(
    child: boundary == null ? app : RepaintBoundary(key: boundary, child: app),
  );
}

/// The feed's row containers (the only ones with padding).
List<Container> _rows(WidgetTester tester) => tester
    .widgetList<Container>(
      find.descendant(of: find.byType(InkWell), matching: find.byType(Container)),
    )
    .where((c) => c.padding != null)
    .toList();

void main() {
  setUpAll(loadAppFonts);
  tearDown(() => NotificationInbox.instance.items.value = const []);

  for (final locale in const ['en', 'ar']) {
    final ar = locale == 'ar';

    testWidgets('dark mode: rows follow the theme, not plain white ($locale)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      NotificationInbox.instance.items.value = [
        _item('a', ar ? 'تم شحن طلبك' : 'Your order shipped'),
        _item('b', ar ? 'عرض نهاية الأسبوع' : 'Weekend offer', read: true),
      ];
      final key = GlobalKey();
      await tester.pumpWidget(_app(locale: locale, dark: true, boundary: key));
      await tester.pumpAndSettle();
      await captureScreen(tester, key, 'notifications_dark_$locale');

      final colors = [for (final row in _rows(tester)) row.color];
      expect(colors, isNot(contains(Colors.white)));
      // The read row shows the dark page; the unread one a light veil.
      expect(colors, containsAll([Colors.transparent, Colors.white10]));
      final title = tester.widget<Text>(
        find.text(ar ? 'عرض نهاية الأسبوع' : 'Weekend offer'),
      );
      expect(title.style?.color, Colors.white);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('light mode keeps the Figma rows', (tester) async {
    NotificationInbox.instance.items.value = [
      _item('a', 'Your order shipped'),
    ];
    await tester.pumpWidget(_app(locale: 'en'));
    await tester.pumpAndSettle();

    final title = tester.widget<Text>(find.text('Your order shipped'));
    expect(title.style?.color, AppColors.inkHeading);
    expect(_rows(tester).single.color, AppColors.accentSubtle);
  });
}
