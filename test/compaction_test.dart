import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_ai/omni_ai.dart' as omni;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teleai/features/ai/data/ai.dart';
import 'package:teleai/features/chat/data/chat_controller.dart';
import 'package:teleai/features/chat/domain/chat_models.dart';
import 'package:teleai/features/settings/data/settings.dart';

class _Settings extends SettingsController {
  @override
  AppSettings build() => const AppSettings(loaded: true, model: 'opencode:summariser');
}

/// A chat with [n] questions and answers; message i says "fact i".
Conversation _chat(int n, {String Function(int i)? say}) {
  final c = Conversation(id: 'long');
  for (var i = 0; i < n; i++) {
    c.entries
      ..add(UserEntry(id: 'u$i', text: say?.call(i) ?? 'question $i about fact $i'))
      ..add(AssistantEntry(id: 'a$i', done: true, steps: [ModelStep(text: 'answer $i: fact $i noted')]));
  }
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late List<String> prompts;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('compact');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
    prompts = [];
    // The summariser: answers each request with "summary N".
    final client = MockClient((req) async {
      final body = jsonDecode(req.body) as Map;
      final messages = body['messages'] as List;
      prompts.add('${(messages.last as Map)['content']}');
      final events = [
        {
          'choices': [
            {'index': 0, 'delta': {'content': 'summary ${prompts.length}'}},
          ],
        },
        {
          'choices': [
            {'index': 0, 'delta': {}, 'finish_reason': 'stop'},
          ],
        },
      ];
      return http.Response('${events.map((e) => 'data: ${jsonEncode(e)}\n\n').join()}data: [DONE]\n\n', 200,
          headers: {'content-type': 'text/event-stream'});
    });
    final ai = omni.OmniAI(loadSavedKeys: false, keyStore: omni.MemoryKeyStore())
      ..register(omni.OpenAICompatibleProvider(id: 'opencode', name: 'Mock', baseUrl: 'https://mock.test/v1', apiKey: 'k', httpClient: client));
    container = ProviderContainer(overrides: [
      aiProvider.overrideWithValue(ai),
      settingsProvider.overrideWith(_Settings.new),
    ]);
  });

  tearDown(() async {
    container.dispose();
    // A save the app started may still hold a file open (Windows locks it).
    for (var i = 0; i < 10; i++) {
      try {
        await tmp.delete(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
  });

  ChatController controller() => container.read(chatControllerProvider.notifier);

  test('compacts everything before the last two questions', () async {
    final c = _chat(5);
    expect(await controller().compact(c), CompactResult.done);
    expect(c.summary, 'summary 1');
    expect(c.summaryUntil, 'a2', reason: 'the last two questions (3 and 4) stay as they are');
    expect(prompts.single, contains('fact 0'));
    expect(prompts.single, contains('answer 2'));
    expect(prompts.single, isNot(contains('question 3')));
  });

  test('a second compaction reads only what is new, with the earlier summary', () async {
    final c = _chat(5);
    await controller().compact(c);
    c.entries
      ..add(UserEntry(id: 'u5', text: 'question 5 about fact 5'))
      ..add(AssistantEntry(id: 'a5', done: true, steps: [ModelStep(text: 'answer 5')]));
    expect(await controller().compact(c), CompactResult.done);
    expect(c.summaryUntil, 'a3');
    final second = prompts.last;
    expect(second, contains('Summary of what came before:\nsummary 1'));
    expect(second, contains('question 3'));
    expect(second, isNot(contains('question 0')), reason: 'already in the summary');
    expect(c.summary, 'summary 2');
  });

  test('nothing new, too short, and a long chat summarised in pieces', () async {
    final c = _chat(5);
    await controller().compact(c);
    expect(await controller().compact(c), CompactResult.nothingNew);
    expect(await controller().compact(_chat(2)), CompactResult.tooShort);

    prompts.clear();
    // About 260,000 characters before the last two questions.
    final long = _chat(12, say: (i) => 'question $i ${'word ' * 4500}');
    expect(await controller().compact(long), CompactResult.done);
    expect(prompts.length, greaterThan(1), reason: 'read in pieces, not cut');
    expect(prompts.last, contains('question 9'), reason: 'the newest part is read too');
    expect(prompts[1], contains('Summary of what came before:\nsummary 1'));
  });

  group('when to compact automatically', () {
    test('when the oldest messages would fall out of what the model reads', () {
      expect(needsCompaction(entriesSinceSummary: 37, used: 1000, window: 200000, chatTokens: 500), isTrue);
      expect(needsCompaction(entriesSinceSummary: 20, used: 1000, window: 200000, chatTokens: 500), isFalse);
    });

    test('near the window only when the chat is a good share of it', () {
      expect(needsCompaction(entriesSinceSummary: 10, used: 170000, window: 200000, chatTokens: 60000), isTrue);
      // Instructions and tools fill the window: compacting wouldn't help.
      expect(needsCompaction(entriesSinceSummary: 10, used: 170000, window: 200000, chatTokens: 5000), isFalse);
      expect(needsCompaction(entriesSinceSummary: 10, used: 170000, window: null, chatTokens: 60000), isFalse);
    });

    test('long text is split between messages', () {
      final text = List.generate(30, (i) => 'User: ${'x' * 9000}').join('\n\n');
      final pieces = transcriptPieces(text);
      expect(pieces.length, greaterThan(2));
      expect(pieces.every((p) => p.length <= 100000), isTrue);
      expect(pieces.join('\n\n').replaceAll('\n', ''), text.replaceAll('\n', ''));
    });
  });
}
