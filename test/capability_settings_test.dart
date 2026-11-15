import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/omni_ai.dart' as omni;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teleai/features/ai/data/ai.dart';
import 'package:teleai/features/ai/data/decision_settings.dart';
import 'package:teleai/features/settings/data/settings.dart';
import 'package:teleai/features/settings/presentation/capability_settings.dart';
import 'package:teleai/features/settings/presentation/decisions_settings.dart';
import 'package:teleai/features/settings/presentation/settings_screen.dart';
import 'package:teleai/features/telegram/data/telegram_tools.dart';
import 'package:teleai/infrastructure/telegram/telegram_client.dart';

class TestSettings extends SettingsController {
  @override
  AppSettings build() => const AppSettings(loaded: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('every omni_ai capability tool is an app tool with a policy and reference', () async {
    final ai = omni.OmniAI(loadSavedKeys: false, keyStore: omni.MemoryKeyStore(), jevKey: 'test');
    final package = {
      for (final t in [...await ai.jev.tools(), ...await ai.mcp.managementTools(), ...await ai.skills.tools(), ...await ai.vapi.tools()]) t.name,
    };
    expect(capabilityToolNames, package);
    const categories = {ToolCategory.decisions, ToolCategory.mcp, ToolCategory.skills, ToolCategory.calls};
    for (final name in capabilityToolNames) {
      final tool = telegramTools.firstWhere((t) => t.name == name);
      expect(categories, contains(tool.category), reason: name);
      expect(toolPolicies[name], isNotNull, reason: name);
      expect(toolReferences[name], isNotNull, reason: name);
    }
    for (final name in ['mcp_install', 'mcp_install_catalog', 'mcp_call_tool', 'install_skill']) {
      expect(toolPolicies[name]!.access, ToolAccess.modify, reason: name);
    }
    for (final name in ['mcp_uninstall', 'uninstall_skill']) {
      expect(toolPolicies[name]!.access, ToolAccess.destructive, reason: name);
    }
  });

  test('decision preferences reload with secrets only in secure storage', () async {
    final keys = omni.MemoryKeyStore();
    final first = ProviderContainer(overrides: [decisionKeyStoreProvider.overrideWithValue(keys)]);
    addTearDown(first.dispose);
    final controller = first.read(decisionSettingsProvider.notifier);
    await controller.ready;
    await controller.setApiKey('jev-secret');
    await controller.update(model: 'jev-1.14.0', threshold: 0.8, enabled: false, longContext: true, maxRetries: 4);
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(DecisionSettingsController.preferencesKey)!;
    expect(stored, isNot(contains('jev-secret')));
    expect(jsonDecode(stored)['model'], 'jev-1.14.0');
    final second = ProviderContainer(overrides: [decisionKeyStoreProvider.overrideWithValue(keys)]);
    addTearDown(second.dispose);
    await second.read(decisionSettingsProvider.notifier).ready;
    final loaded = second.read(decisionSettingsProvider);
    expect(loaded.apiKey, 'jev-secret');
    expect(loaded.threshold, 0.8);
    expect(loaded.enabled, isFalse);
    expect(loaded.longContext, isTrue);
    await second.read(decisionSettingsProvider.notifier).setApiKey('');
    expect(await keys.read(DecisionSettingsController.secretKey), isNull);
  });

  test('Decisions is the last AI and Models tab', () {
    expect(AiTab.values.last, AiTab.decisions);
  });

  test('saved Jev controls configure the shared OmniAI client', () async {
    final keys = omni.MemoryKeyStore();
    final container = ProviderContainer(
      overrides: [decisionKeyStoreProvider.overrideWithValue(keys), settingsProvider.overrideWith(TestSettings.new)],
    );
    addTearDown(container.dispose);
    final ai = container.read(aiProvider);
    final controller = container.read(decisionSettingsProvider.notifier);
    await controller.ready;
    await controller.setApiKey('configured-key');
    await controller.update(
      model: 'jev-1.14.0',
      baseUrl: 'https://proxy.example.com/v1',
      threshold: 0.7,
      gateConfidence: true,
      minConfidence: 0.8,
      maxRetries: 3,
      timeoutSeconds: 45,
      longContext: true,
    );
    expect(ai.jev.apiKey, 'configured-key');
    expect(ai.jev.model, 'jev-1.14.0');
    expect(ai.jev.client.baseUrl, 'https://proxy.example.com/v1');
    expect(ai.jev.threshold, 0.7);
    expect(ai.jev.minConfidence, 0.8);
    expect(ai.jev.client.maxRetries, 3);
    expect(ai.jev.client.timeout, const Duration(seconds: 45));
    expect(ai.jev.longContext, isTrue);
    await controller.setApiKey('');
    expect(ai.jev.isConfigured, isFalse);
  });

  testWidgets('Jev settings saves a key and lists its tools at phone width', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final keys = omni.MemoryKeyStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          decisionKeyStoreProvider.overrideWithValue(keys),
          settingsProvider.overrideWith(TestSettings.new),
          authStateProvider.overrideWith((ref) => const Stream.empty()),
        ],
        child: const MaterialApp(home: Scaffold(body: DecisionsSettingsPage())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('TypeSafe Jev'), findsOneWidget);
    expect(find.text('jev_decide'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'my-jev-key');
    await tester.tap(find.byTooltip('Save').first);
    await tester.pump();
    await tester.pump();
    expect(await keys.read(DecisionSettingsController.secretKey), 'my-jev-key');
    expect(tester.takeException(), isNull);
  });

  testWidgets('MCP and Skills tabs list installs, open bottom sheets and show tools', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ai = omni.OmniAI(loadSavedKeys: false, keyStore: omni.MemoryKeyStore());
    await ai.skills.add(omni.Skill.parse('notes', '---\nname: notes\ndescription: Takes tidy notes.\n---\n# Notes\nWrite short notes.', files: {'ref.md': '# Ref'}));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiProvider.overrideWithValue(ai),
          settingsProvider.overrideWith(TestSettings.new),
          authStateProvider.overrideWith((ref) => const Stream.empty()),
        ],
        child: const MaterialApp(home: McpSkillsSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('mcp_call_tool'), findsOneWidget);
    await tester.tap(find.text('Add by address'));
    await tester.pumpAndSettle();
    expect(find.text('Add an MCP server'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'docs');
    await tester.enterText(find.widgetWithText(TextField, 'Address'), 'http://example.com/mcp');
    await tester.tap(find.text('Add server'));
    await tester.pumpAndSettle();
    expect(find.text('Plain http only on this network; use https.'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Address'), 'https://example.com/mcp');
    await tester.tap(find.text('Add server'));
    await tester.pumpAndSettle();
    expect(ai.mcp['docs']?.url, 'https://example.com/mcp');

    await tester.tap(find.text('Skills'));
    await tester.pumpAndSettle();
    expect(find.text('install_skill'), findsOneWidget);
    await tester.tap(find.text('notes'));
    await tester.pumpAndSettle();
    expect(find.text('Write short notes.'), findsOneWidget);
    await tester.tap(find.text('ref.md'));
    await tester.pumpAndSettle();
    expect(find.text('Ref'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
