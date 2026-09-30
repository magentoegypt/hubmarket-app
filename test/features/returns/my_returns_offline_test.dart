import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/core/widgets/offline_state.dart';
import 'package:hubmarket_app/features/returns/domain/returns.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fonts.dart';
import '../../support/returns_fakes.dart';
import 'returns_harness.dart';

/// My returns while the request can't reach the store.
class _OfflineReturns extends FakeReturnsRepository {
  int loads = 0;

  @override
  Future<ReturnsPage<ReturnSummary>> fetchReturns({
    int pageSize = 20,
    int currentPage = 1,
  }) async {
    loads++;
    throw const Failure(FailureKind.network);
  }
}

void main() {
  setUpAll(loadAppFonts);

  for (final locale in const ['en', 'ar']) {
    testWidgets('My returns offline: the S3 page ($locale)', (tester) async {
      final l10n = lookupAppLocalizations(Locale(locale));
      final returns = _OfflineReturns();
      final key = GlobalKey();
      await pumpReturns(
        tester,
        location: AppRoutes.returns,
        locale: locale,
        returns: returns,
        size: const Size(390, 844),
        boundary: key,
      );
      await captureScreen(tester, key, 'my_returns_offline_$locale');

      expect(find.byType(OfflineState), findsOneWidget);
      expect(find.text(l10n.actionRetry), findsNothing);
      final before = returns.loads;
      await tester.tap(find.text(l10n.offlineTryAgain));
      await tester.pumpAndSettle();
      expect(returns.loads, greaterThan(before));
      expect(find.byType(OfflineState), findsOneWidget);
    });
  }
}
