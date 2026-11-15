import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teleai/features/chat/presentation/widgets/dev/vercel_cards.dart' show showLogViewer;
import 'package:teleai/features/development/manage/managers.dart';
import 'package:teleai/infrastructure/telegram/telegram_client.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget app(Widget home) => ProviderScope(
    overrides: [authStateProvider.overrideWith((ref) => const Stream.empty())],
    child: MaterialApp(home: home),
  );

  testWidgets('each manager page lays out at phone width and settles without a key', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final page in const [VercelManagerScreen(), ResendManagerScreen(), MongoManagerScreen(), CloudflareManagerScreen()]) {
      await tester.pumpWidget(app(page));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull, reason: '${page.runtimeType}');
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the log viewer selects lines and shows Copy', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => showLogViewer(context, title: 'Build log', lines: [
            {'type': 'stdout', 'text': 'Installing dependencies'},
            {'type': 'stderr', 'text': 'Error: Cannot find module x'},
          ]),
          child: const Text('open'),
        ),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 lines'), findsOneWidget);
    await tester.tap(find.textContaining('Installing', findRichText: true));
    await tester.pump();
    expect(find.text('1 line selected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
