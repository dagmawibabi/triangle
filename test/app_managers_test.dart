import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teleai/app/theme.dart';
import 'package:teleai/features/development/manage/app_managers.dart';
import 'package:teleai/infrastructure/telegram/telegram_client.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => AppColors.palette = Palette.dark);

  for (final light in [false, true]) {
    testWidgets('the app pages lay out at phone width (${light ? 'light' : 'dark'})', (tester) async {
      AppColors.palette = light ? Palette.light : Palette.dark;
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const pages = <Widget>[GitHubManagerScreen(), GmailManagerScreen(), CalendarManagerScreen(), NotionManagerScreen(), E2bManagerScreen(), VapiManagerScreen()];
      for (final page in pages) {
        await tester.pumpWidget(ProviderScope(
          overrides: [authStateProvider.overrideWith((ref) => const Stream.empty())],
          child: MaterialApp(theme: buildTheme(), home: page),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull, reason: '${page.runtimeType}');
      }
      expect(appManagerFor('github'), isA<GitHubManagerScreen>());
      expect(appManagerFor('slack'), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
