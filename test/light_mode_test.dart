import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teleai/app/theme.dart';
import 'package:teleai/features/chat/presentation/widgets/dev/dev_card_kit.dart';
import 'package:teleai/features/chat/presentation/widgets/dev/vercel_cards.dart' show showLogViewer;
import 'package:teleai/features/development/manage/managers.dart';
import 'package:teleai/infrastructure/telegram/telegram_client.dart';

double _contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppColors.palette = Palette.light;
    AppColors.applyAccent(const Color(0xFFF4F4F5));
  });
  tearDown(() => AppColors.palette = Palette.dark);

  Widget app(Widget home) => ProviderScope(
    overrides: [authStateProvider.overrideWith((ref) => const Stream.empty())],
    child: MaterialApp(theme: buildTheme(), home: home),
  );

  test('buttons and code colours read on a white page', () {
    final visit = solidIconButton;
    final bg = visit.backgroundColor!.resolve({})!;
    final fg = visit.foregroundColor!.resolve({})!;
    expect(_contrast(bg, fg), greaterThan(7));
    expect(_contrast(bg, AppColors.bg), greaterThan(7));
    for (final v in <Object>['s', 1, true, {r'$oid': 'x'}, {r'$date': 'x'}]) {
      expect(_contrast(jsonColor(v), Colors.white), greaterThan(3), reason: '$v');
    }
    expect(_contrast(mongoGreen, Colors.white), greaterThan(3));
  });

  testWidgets('the log viewer keeps a light title on its dark bar', (tester) async {
    await tester.pumpWidget(app(Builder(
      builder: (context) => Scaffold(
        body: TextButton(onPressed: () => showLogViewer(context, title: 'Build log', lines: [{'text': 'hi'}]), child: const Text('open')),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final title = tester.widget<Text>(find.text('Build log'));
    final color = title.style?.color ?? DefaultTextStyle.of(tester.element(find.text('Build log'))).style.color!;
    expect(_contrast(color, const Color(0xFF111118)), greaterThan(7));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the manager pages lay out in light mode', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final page in const [VercelManagerScreen(), ResendManagerScreen(), MongoManagerScreen(), CloudflareManagerScreen()]) {
      await tester.pumpWidget(app(page));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull, reason: '${page.runtimeType}');
    }
    await tester.pumpWidget(const SizedBox());
  });
}
