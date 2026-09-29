import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/core/widgets/otp_code_field.dart';
import 'package:hubmarket_app/features/auth/presentation/screens/verify_code_screen.dart';

import 'auth_harness.dart';

/// A flow that records what the Verify screen asks of it.
class _Flow {
  final List<String> calls = [];
  Object? verifyError;
  Object? resendError;
  bool offerEmail = true;

  VerifyCodeFlow build() => VerifyCodeFlow(
    phone: '+971501234567',
    offerEmail: offerEmail,
    resend: () async {
      calls.add('resend');
      if (resendError != null) throw resendError!;
    },
    verify: (code) async {
      calls.add('verify:$code');
      if (verifyError != null) throw verifyError!;
      return null;
    },
  );
}

/// Opens the Verify screen from a host page, so its pop result is observable.
Future<({AuthHarness harness, List<Object?> results})> _open(
  WidgetTester tester,
  _Flow flow, {
  String locale = 'en',
}) async {
  final results = <Object?>[];
  final harness = AuthHarness(locale: locale);
  await tester.pumpWidget(harness.build(initialLocation: AppRoutes.home));
  await tester.pumpAndSettle();
  final context = tester.element(find.text('HOME'));
  context
      .push<VerifyCodeOutcome>(AppRoutes.verifyCode, extra: flow.build())
      .then(results.add);
  await tester.pumpAndSettle();
  return (harness: harness, results: results);
}

Future<void> _drainCountdown(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 61));

void main() {
  testWidgets('shows the masked number, six boxes and the running countdown', (
    tester,
  ) async {
    final flow = _Flow();
    await _open(tester, flow);

    expect(find.text('Verify your number'), findsOneWidget);
    expect(
      find.textContaining('+971 50 ••• 4567'),
      findsOneWidget,
      reason: 'the number is masked',
    );
    expect(find.byType(OtpCodeField), findsOneWidget);
    expect(find.text('Resend code in'), findsOneWidget);
    expect(find.text('01:00'), findsOneWidget);

    await tester.pump(const Duration(seconds: 18));
    expect(find.text('00:42'), findsOneWidget);
    await _drainCountdown(tester);
  });

  testWidgets('filling the six digits verifies the code and pops verified', (
    tester,
  ) async {
    final flow = _Flow();
    final opened = await _open(tester, flow);

    await tester.enterText(find.byType(TextField), '482193');
    await tester.pumpAndSettle();

    expect(flow.calls, ['verify:482193']);
    expect(opened.results, [VerifyCodeOutcome.verified]);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('"Verify & continue" with a short code asks for all six digits', (
    tester,
  ) async {
    final flow = _Flow();
    await _open(tester, flow);

    await tester.enterText(find.byType(TextField), '482');
    await tester.tap(find.text('Verify & continue'));
    await tester.pump();

    expect(flow.calls, isEmpty);
    expect(find.text('Enter the 6-digit code'), findsOneWidget);
    await _drainCountdown(tester);
  });

  testWidgets('resend is offered when the countdown ends, and restarts it', (
    tester,
  ) async {
    final flow = _Flow();
    await _open(tester, flow);

    expect(find.text('Resend code'), findsNothing);
    await tester.pump(const Duration(seconds: 60));
    await tester.pump();
    expect(find.text('Resend code'), findsOneWidget);

    await tester.tap(find.text('Resend code'));
    await tester.pump();
    expect(flow.calls, ['resend']);
    expect(find.text('Resend code in'), findsOneWidget);
    expect(find.text('01:00'), findsOneWidget);
    await _drainCountdown(tester);
  });

  testWidgets('"Change number" goes back with no result', (tester) async {
    final flow = _Flow();
    final opened = await _open(tester, flow);

    await tester.tap(find.text('Change number'));
    await tester.pumpAndSettle();

    expect(find.text('HOME'), findsOneWidget);
    expect(opened.results, [null]);
    expect(flow.calls, isEmpty);
  });

  testWidgets('"Use email instead" only where the flow offers it', (
    tester,
  ) async {
    final flow = _Flow();
    final opened = await _open(tester, flow);

    await tester.tap(find.text('Use email instead'));
    await tester.pumpAndSettle();
    expect(opened.results, [VerifyCodeOutcome.useEmail]);

    final register = _Flow()..offerEmail = false;
    await _open(tester, register);
    expect(find.text('Use email instead'), findsNothing);
    await _drainCountdown(tester);
  });

  testWidgets('a refused code turns the boxes red with the reason under them', (
    tester,
  ) async {
    final flow = _Flow()
      ..verifyError = const Failure(
        FailureKind.server,
        detail: 'The OTP code is not valid.',
      );
    final opened = await _open(tester, flow);

    await tester.enterText(find.byType(TextField), '000000');
    await tester.pumpAndSettle();

    expect(opened.results, isEmpty, reason: 'still on the Verify screen');
    expect(find.text("That code isn’t right. Check it and try again."),
        findsOneWidget);
    expect(
      tester.widget<OtpCodeField>(find.byType(OtpCodeField)).hasError,
      isTrue,
    );

    // Typing again clears it.
    await tester.enterText(find.byType(TextField), '1');
    await tester.pump();
    expect(find.text("That code isn’t right. Check it and try again."),
        findsNothing);
    await _drainCountdown(tester);
  });

  testWidgets('expired codes and too many attempts say so, in Arabic too', (
    tester,
  ) async {
    final flow = _Flow()
      ..verifyError = const Failure(
        FailureKind.server,
        detail: 'انتهت صلاحية كود التحقق',
      );
    await _open(tester, flow, locale: 'ar');

    await tester.enterText(find.byType(TextField), '000000');
    await tester.pumpAndSettle();
    expect(find.text('انتهت صلاحية الرمز. اطلب رمزًا جديدًا.'), findsOneWidget);

    flow.verifyError = const Failure(
      FailureKind.server,
      detail: 'You are sending OTP too much times.',
    );
    await tester.enterText(find.byType(TextField), '111111');
    await tester.pumpAndSettle();
    expect(
      find.text('محاولات كثيرة. انتظر بضع دقائق ثم حاول مرة أخرى.'),
      findsOneWidget,
    );
    await _drainCountdown(tester);
  });
}
