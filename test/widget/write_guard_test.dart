import 'package:beaver_v2/presentation/providers/write_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every write in the app goes through [runWrite]: the repository call happens
/// first and the provider refetches afterwards, so a failure means nothing
/// changed and offering «Повторить» is safe.

/// Pumps a screen with a single button that runs [action] through [runWrite] and
/// records what it returned.
Future<List<bool>> _pumpAction(
  WidgetTester tester,
  Future<void> Function() action, {
  String failureMessage = 'Не удалось сохранить',
}) async {
  final results = <bool>[];

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                results.add(
                  await runWrite(
                    context,
                    action,
                    failureMessage: failureMessage,
                  ),
                );
              },
              child: const Text('Записать'),
            ),
          ),
        ),
      ),
    ),
  );
  return results;
}

void main() {
  testWidgets('a write that succeeds reports success and says nothing', (
    tester,
  ) async {
    var calls = 0;
    final results = await _pumpAction(tester, () async => calls++);

    await tester.tap(find.text('Записать'));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(results, [true]);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a failed write surfaces the message with a «Повторить» action', (
    tester,
  ) async {
    await _pumpAction(
      tester,
      () async => throw StateError('нет сети'),
      failureMessage: 'Не удалось изменить баланс',
    );

    await tester.tap(find.text('Записать'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    expect(find.text('Не удалось изменить баланс'), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'Повторить'), findsOneWidget);
  });

  testWidgets('«Повторить» runs the same action again', (tester) async {
    var calls = 0;
    final results = await _pumpAction(tester, () async {
      calls++;
      // Fails once, then succeeds — the retry is what makes the write land.
      if (calls == 1) throw StateError('нет сети');
    });

    await tester.tap(find.text('Записать'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(results, [true]);
  });

  testWidgets('a failure the user waves away reports failure, not success', (
    tester,
  ) async {
    var calls = 0;
    final results = await _pumpAction(tester, () async {
      calls++;
      throw StateError('нет сети');
    });

    await tester.tap(find.text('Записать'));
    await tester.pump();
    await tester.pumpAndSettle();

    // Swiping the SnackBar away is a refusal, not a retry: the caller must hear
    // that the write did not land, or it would close the sheet as if it had.
    await tester.drag(find.byType(SnackBar), const Offset(0, 100));
    await tester.pumpAndSettle();
    await tester.pump();

    expect(calls, 1);
    expect(results, [false]);
  });
}
