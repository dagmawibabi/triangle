import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teleai/features/components/component_cards.dart';
import 'package:teleai/features/components/components.dart';
import 'package:teleai/app/theme.dart';
import 'package:teleai/features/telegram/data/telegram_tools.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('show_component is a read-only creative tool with docs', () {
    final t = telegramTools.firstWhere((t) => t.name == 'show_component');
    expect(t.category, ToolCategory.creative);
    expect(toolPolicies['show_component']?.access, ToolAccess.read);
    expect(toolReferences['show_component'], isNotNull);
    expect(t.requiresApproval, isFalse);
  });

  test('every sample passes the tool and the data reaches the card', () async {
    for (final k in ComponentKind.values) {
      final out = await runShowComponent(const ComponentPrefs(), Map<String, dynamic>.from(componentSamples[k]!));
      expect(out.json['error'], isNull, reason: k.name);
      expect(out.json['shown'], k.name);
      expect((out.full as Map)['component'], k.name);
    }
  });

  test('bad data and turned-off components explain themselves', () async {
    final bad = await runShowComponent(const ComponentPrefs(), {'component': 'chart', 'labels': ['a']});
    expect(bad.json['error'], contains('series'));
    final off = await runShowComponent(const ComponentPrefs(disabled: {ComponentKind.gauge}), {'component': 'gauge', 'value': 3});
    expect(off.json['error'], contains('turned off'));
    expect(off.json['error'], isNot(contains('gauge,')));
    final unknown = await runShowComponent(const ComponentPrefs(), {'component': 'map'});
    expect(unknown.json['error'], contains('chart'));
  });

  testWidgets('every component and chart type draws at phone width', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final samples = [
      for (final k in ComponentKind.values) componentSamples[k]!,
      for (final type in ['line', 'bar', 'hbar', 'pie', 'donut'])
        {...componentSamples[ComponentKind.chart]!, 'chart_type': type},
    ];
    for (final d in samples) {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: ListView(padding: const EdgeInsets.all(16), children: [ComponentView(data: d)])),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '${d['component']} ${d['chart_type'] ?? ''}');
    }
    // Touching a chart reads its values.
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: Scaffold(body: ListView(padding: const EdgeInsets.all(16), children: [ComponentView(data: componentSamples[ComponentKind.chart]!)]))),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.byType(CustomPaint).last));
    await tester.pumpAndSettle();
    expect(find.textContaining('Received'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('decoration never turns black on a light page with the monochrome accent', () {
    final before = AppColors.palette;
    addTearDown(() {
      AppColors.palette = before;
      AppColors.applyAccent(const Color(0xFFF4F4F5));
    });
    AppColors.palette = Palette.light;
    AppColors.applyAccent(const Color(0xFFF4F4F5));
    expect(AppColors.accent.computeLuminance(), lessThan(0.05), reason: 'buttons stay near-black, as designed');
    expect(AppColors.tint.computeLuminance(), greaterThan(0.1));
    AppColors.applyAccent(const Color(0xFF3B7DDD));
    expect(AppColors.tint, AppColors.accent, reason: 'a coloured accent is used as is');
    AppColors.palette = Palette.dark;
    AppColors.applyAccent(const Color(0xFFF4F4F5));
    expect(AppColors.tint, AppColors.accent);
  });
}
