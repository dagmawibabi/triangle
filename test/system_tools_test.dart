import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/omni_ai.dart' as omni;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teleai/features/ai/data/ai.dart';
import 'package:teleai/features/ai/data/decision_settings.dart';
import 'package:teleai/features/settings/data/settings.dart';
import 'package:teleai/features/telegram/data/system_tools.dart';
import 'package:teleai/features/telegram/data/telegram_tools.dart';

const _openCodeKey = 'oc_sk_test_0123456789abcdWXYZ';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final secure = <String, String>{};

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secure.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        final args = (call.arguments as Map?) ?? const {};
        final key = '${args['key']}';
        switch (call.method) {
          case 'write':
            secure[key] = '${args['value']}';
          case 'read':
            return secure[key];
          case 'delete':
            secure.remove(key);
          case 'readAll':
            return secure;
        }
        return null;
      },
    );
  });

  Future<ProviderContainer> container() async {
    final c = ProviderContainer(overrides: [decisionKeyStoreProvider.overrideWithValue(omni.MemoryKeyStore())]);
    addTearDown(c.dispose);
    c.read(settingsProvider);
    for (var i = 0; i < 100 && !c.read(settingsProvider).loaded; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await c.read(decisionSettingsProvider.notifier).ready;
    return c;
  }

  Future<Map<String, dynamic>> run(ProviderContainer c, String name, Map<String, dynamic> a) async =>
      (await runSystemTool(c.read, name, a)).json;

  group('tool definitions', () {
    test('every system tool is under System, classified and documented', () {
      expect(systemToolNames, {'list_api_keys', 'set_api_key', 'delete_api_key', 'load_tools', 'get_app_settings', 'set_appearance', 'set_preferences'});
      for (final name in systemToolNames) {
        final t = telegramTools.firstWhere((t) => t.name == name);
        expect(t.category, ToolCategory.system, reason: name);
        expect(t.needsTelegram, isFalse, reason: name);
      }
    });

    test('reading is free, saving a key always asks, removing one is destructive', () {
      TelegramTool tool(String n) => telegramTools.firstWhere((t) => t.name == n);
      expect(tool('list_api_keys').access, ToolAccess.read);
      expect(tool('get_app_settings').access, ToolAccess.read);
      expect(tool('set_api_key').requiresApproval, isTrue);
      expect(tool('set_api_key').alwaysAsk, isTrue);
      expect(tool('delete_api_key').destructive, isTrue);
      expect(tool('set_appearance').access, ToolAccess.modify);
      expect(tool('set_appearance').destructive, isFalse);
      expect(tool('set_preferences').destructive, isFalse);
    });

    test('services cover AI, apps, cloud, web data and money', () {
      expect(apiKeyServices.map((s) => s.id), apiKeyServiceIds);
      final uses = {for (final s in apiKeyServices) ...s.uses};
      expect(uses, containsAll(['chat', 'images', 'video', 'speech', 'dictation', 'decisions']));
    });
  });

  group('API keys', () {
    test('set_api_key adds, replaces and leaves an unchanged key, never returning it', () async {
      final c = await container();
      var out = await run(c, 'set_api_key', {'service': 'opencode', 'key': _openCodeKey, 'check': false});
      expect(out['action'], 'added');
      expect(out['ends_with'], '…WXYZ');
      expect(jsonEncode(out), isNot(contains(_openCodeKey)));
      expect(c.read(settingsProvider).openCodeKey, _openCodeKey);
      expect(secure['opencode_key'], _openCodeKey);
      // The AI client has it too.
      expect(c.read(aiProvider).apiKey('opencode'), _openCodeKey);

      out = await run(c, 'set_api_key', {'service': 'opencode', 'key': _openCodeKey, 'check': false});
      expect(out['action'], 'unchanged');
      out = await run(c, 'set_api_key', {'service': 'opencode', 'key': 'oc_sk_other_key_9999', 'check': false});
      expect(out['action'], 'replaced');
      expect(out['ends_with'], '…9999');
    });

    test('the decisions key goes to Jev', () async {
      final c = await container();
      await run(c, 'set_api_key', {'service': 'jev', 'key': 'jev_secret_abcd1234', 'check': false});
      expect(c.read(decisionSettingsProvider).apiKey, 'jev_secret_abcd1234');
    });

    test('list_api_keys says what is set without showing keys', () async {
      final c = await container();
      await c.read(settingsProvider.notifier).setVercelKey('vck_live_secret_7777');
      await c.read(settingsProvider.notifier).setLmStudioUrl('192.168.1.20:1234');
      final out = await run(c, 'list_api_keys', {});
      expect(jsonEncode(out), isNot(contains('vck_live_secret_7777')));
      final rows = {for (final r in out['keys'] as List) r['service']: r as Map};
      expect(rows.keys, apiKeyServiceIds);
      expect(rows['vercel']!['set'], isTrue);
      expect(rows['vercel']!['ends_with'], '…7777');
      expect(rows['opencode']!['set'], isFalse);
      // An address isn't a secret.
      expect(rows['lmstudio']!['ends_with'], '192.168.1.20:1234');
      expect(out['set_count'], 2);
    });

    test('delete_api_key removes a key and says what is left', () async {
      final c = await container();
      await c.read(settingsProvider.notifier).setOpenRouterKey('sk-or-v1-secret-1111');
      await c.read(settingsProvider.notifier).setOpenCodeKey(_openCodeKey);
      var out = await run(c, 'delete_api_key', {'service': 'opencode'});
      expect(out['removed'], isTrue);
      expect(out['note'], contains('OpenRouter'));
      expect(c.read(settingsProvider).openCodeKey, isEmpty);
      expect(secure['opencode_key'], isEmpty);
      out = await run(c, 'delete_api_key', {'service': 'opencode'});
      expect(out['removed'], isFalse);
    });

    test('keys for apps, cloud and web data work the same way', () async {
      final c = await container();
      // A key kept in AppSettings.
      var out = await run(c, 'set_api_key', {'service': 'youtube', 'key': 'AIzaSyYouTube_test_5555'});
      expect(out['action'], 'added');
      expect(out['checked'], isFalse);
      expect(out['note'], contains('can\'t be tested here'));
      expect(c.read(settingsProvider).youtubeKey, 'AIzaSyYouTube_test_5555');
      // One kept by the info tools.
      await run(c, 'set_api_key', {'service': 'metals', 'key': 'metals_test_key_6666'});
      expect(secure['info_metals_key'], 'metals_test_key_6666');
      // R2's two halves are separate keys.
      await run(c, 'set_api_key', {'service': 'r2_secret_key', 'key': 'r2-secret-7777'});
      expect(c.read(settingsProvider).r2SecretKey, 'r2-secret-7777');
      expect(c.read(settingsProvider).r2AccessKeyId, isEmpty);

      final listed = await run(c, 'list_api_keys', {'group': 'web'});
      final rows = {for (final r in listed['keys'] as List) r['service']: r as Map};
      expect(rows.keys, everyElement(isIn(apiKeyServices.where((s) => s.group == 'web').map((s) => s.id))));
      expect(rows['youtube']!['set'], isTrue);
      expect(rows['metals']!['ends_with'], '…6666');
      expect(jsonEncode(listed), isNot(contains('metals_test_key_6666')));

      out = await run(c, 'delete_api_key', {'service': 'youtube'});
      expect(out['removed'], isTrue);
      expect(out['note'], contains('YouTube'));
      expect(c.read(settingsProvider).youtubeKey, isEmpty);
    });

    test('bad input is refused', () async {
      final c = await container();
      expect(() => run(c, 'set_api_key', {'service': 'nope', 'key': 'x'}), throwsArgumentError);
      expect(() => run(c, 'set_api_key', {'service': 'vercel', 'key': '  '}), throwsArgumentError);
      expect(() => run(c, 'set_api_key', {'service': 'vercel', 'key': 'two words'}), throwsArgumentError);
    });

    test('the key is hidden in the saved call', () {
      final hidden = redactKeyArguments(jsonEncode({'service': 'opencode', 'key': _openCodeKey}));
      expect(hidden, isNot(contains(_openCodeKey)));
      expect(jsonDecode(hidden)['key'], '[hidden …WXYZ]');
      final address = redactKeyArguments(jsonEncode({'service': 'lmstudio', 'key': '10.0.0.5:1234'}));
      expect(jsonDecode(address)['key'], '10.0.0.5:1234');
      expect(redactKeyArguments('not json'), 'not json');
    });
  });

  group('appearance and preferences', () {
    test('set_appearance changes only what it is given', () async {
      final c = await container();
      final out = await run(c, 'set_appearance', {'theme': 'light', 'accent': 'mint', 'chat_font_size': 17});
      expect(out['changed'], ['theme', 'accent', 'chat_font_size']);
      final s = c.read(settingsProvider);
      expect(s.themeMode, AppThemeMode.light);
      expect(s.accent, AccentChoice.mint);
      expect(s.chatFontSize, 17);
      expect(s.codeTheme, const AppSettings().codeTheme);
      expect((out['appearance'] as Map)['theme'], 'light');
    });

    test('set_appearance refuses unknown values and sizes out of range', () async {
      final c = await container();
      expect(() => run(c, 'set_appearance', {'theme': 'sepia'}), throwsArgumentError);
      expect(() => run(c, 'set_appearance', {'chat_font_size': 40}), throwsArgumentError);
      expect(() => run(c, 'set_appearance', {}), throwsArgumentError);
    });

    test('set_preferences and get_app_settings', () async {
      final c = await container();
      final out = await run(c, 'set_preferences', {'answer_style': 'concise', 'speech_rate': 1.5, 'auto_download_music': true});
      expect(out['changed'], ['answer_style', 'speech_rate', 'auto_download_music']);
      final read = await run(c, 'get_app_settings', {});
      final p = read['preferences'] as Map;
      expect(p['answer_style'], 'concise');
      expect(p['speech_rate'], 1.5);
      expect(p['auto_download_music'], isTrue);
      expect(() => run(c, 'set_preferences', {'speech_rate': 9}), throwsArgumentError);
    });
  });

  group('OpenCode Zen', () {
    test('is a router with its own model prefix', () {
      expect(AiRouter.of('opencode:glm-5.3'), AiRouter.openCode);
      expect(canonicalModelId('opencode:glm-5.3'), 'opencode:glm-5.3');
      expect(AiRouter.openCode.title, 'OpenCode Zen');
    });

    test('its key counts as an AI key', () {
      expect(const AppSettings(openCodeKey: 'k').hasAnyKey, isTrue);
      expect(keysChanged(const AppSettings(), const AppSettings(openCodeKey: 'k')), isTrue);
    });
  });
}
