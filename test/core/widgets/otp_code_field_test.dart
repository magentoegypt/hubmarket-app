import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/widgets/otp_code_field.dart';

Future<void> _pump(
  WidgetTester tester,
  TextEditingController controller, {
  TextDirection direction = TextDirection.ltr,
  ValueChanged<String>? onCompleted,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: OtpCodeField(
              controller: controller,
              autofocus: false,
              onCompleted: onCompleted,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('renders each entered digit in a box', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    controller.text = '482';
    await tester.pump();

    for (final d in ['4', '8', '2']) {
      expect(find.text(d), findsOneWidget);
    }
  });

  testWidgets('fires onCompleted when 6 digits are entered', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    String? completed;
    await _pump(tester, controller, onCompleted: (c) => completed = c);

    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();

    expect(completed, '123456');
  });

  testWidgets('stays LTR even inside an RTL parent', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, direction: TextDirection.rtl);

    final directionality = tester.widget<Directionality>(
      find
          .descendant(
            of: find.byType(OtpCodeField),
            matching: find.byType(Directionality),
          )
          .first,
    );
    expect(directionality.textDirection, TextDirection.ltr);
  });
}
