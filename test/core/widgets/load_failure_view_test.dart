import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/core/network/connectivity.dart';
import 'package:hubmarket_app/core/widgets/load_failure_view.dart';
import 'package:hubmarket_app/core/widgets/offline_state.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

Widget _app(
  Widget child, {
  bool online = true,
  bool dark = false,
}) => ProviderScope(
  overrides: [
    networkStatusSourceProvider.overrideWithValue(
      () => Stream<bool>.value(online),
    ),
  ],
  child: MaterialApp(
    theme: dark ? AppTheme.dark('en') : AppTheme.light('en'),
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('a request that never reached the store: the S3 page', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      _app(
        LoadFailureView(
          error: const Failure(FailureKind.network),
          onRetry: () => retries++,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(OfflineState), findsOneWidget);
    expect(find.text('You’re offline'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retries, 1);
  });

  testWidgets('any failure while the OS reports no network: the S3 page', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        LoadFailureView(
          error: const Failure(FailureKind.unknown),
          onRetry: () {},
        ),
        online: false,
      ),
    );
    await tester.pump();

    expect(find.byType(OfflineState), findsOneWidget);
  });

  testWidgets('a store failure online: the message and Retry', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      _app(
        LoadFailureView(
          error: const Failure(FailureKind.service),
          onRetry: () => retries++,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(OfflineState), findsNothing);
    expect(
      find.text('The store is temporarily unavailable. Please try again shortly.'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    expect(retries, 1);
  });

  testWidgets('the S3 page stays legible in dark mode', (tester) async {
    await tester.pumpWidget(
      _app(
        const LoadFailureView(error: Failure(FailureKind.network)),
        dark: true,
      ),
    );
    await tester.pump();

    final title = tester.widget<Text>(find.text('You’re offline'));
    expect(title.style?.color, Colors.white);
    // Without a retry there is no button.
    expect(find.byType(FilledButton), findsNothing);
  });
}
