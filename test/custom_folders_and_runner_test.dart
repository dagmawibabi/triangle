import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teleai/features/chat/presentation/widgets/tool_runner.dart';
import 'package:teleai/features/components/component_cards.dart';
import 'package:teleai/features/components/components.dart';
import 'package:teleai/features/custom_folders/custom_folders.dart';
import 'package:teleai/features/settings/data/settings.dart';
import 'package:teleai/features/telegram/data/telegram_tools.dart';

class _Settings extends SettingsController {
  @override
  AppSettings build() => const AppSettings(loaded: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('custom folders keep chats per account, in many folders, and reload', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final store = c.read(customFoldersProvider.notifier);
    await store.ready;
    final work = await store.create('Work', emoji: '💼', chats: const [FolderChatRef('a', 1), FolderChatRef('a', 1), FolderChatRef('b', 9)]);
    expect(work.chats, hasLength(2));
    final fun = await store.create('Fun');
    await store.addChats(fun.id, const [FolderChatRef('a', 1), FolderChatRef('a', 2)]);
    expect(store.foldersOf('a', 1).map((f) => f.name), ['Work', 'Fun']);
    await store.setChats(work.id, 'a', [3, 4]);
    expect(store.byId(work.id)!.chatIdsIn('a'), [3, 4]);
    expect(store.byId(work.id)!.chatIdsIn('b'), [9]);
    await store.removeChats(fun.id, const [FolderChatRef('a', 2)]);
    expect(store.find('fun')!.chatIdsIn('a'), [1]);
    await store.reorder(1, 0);
    expect(c.read(customFoldersProvider).folders.first.name, 'Fun');

    final again = ProviderContainer();
    addTearDown(again.dispose);
    await again.read(customFoldersProvider.notifier).ready;
    expect(again.read(customFoldersProvider).folders.map((f) => f.name), ['Fun', 'Work']);
    expect(await again.read(customFoldersProvider.notifier).delete(work.id), isTrue);
    expect(again.read(customFoldersProvider).folders, hasLength(1));
  });

  test('custom folder tools are registered with policies and references', () {
    for (final t in customFolderTools) {
      expect(telegramTools.where((x) => x.name == t.name), hasLength(1), reason: t.name);
      expect(toolPolicies[t.name], isNotNull, reason: t.name);
      expect(toolReferences[t.name], isNotNull, reason: t.name);
    }
    expect(toolNamed('delete_custom_folder')!.destructive, isTrue);
  });

  test('reporting, Premium and Business tools are registered with the right safety', () {
    const names = [
      'report_chat', 'report_spam', 'set_group_protection', 'list_emoji_statuses', 'set_emoji_status', 'saved_message_tags',
      'telegram_transcribe', 'story_stealth_mode', 'list_boost_slots', 'boost_chat', 'giveaway_info', 'list_quick_replies',
      'set_away_message', 'set_greeting_message', 'set_opening_hours', 'set_business_location', 'set_business_bot',
    ];
    for (final n in names) {
      final t = toolNamed(n);
      expect(t, isNotNull, reason: n);
      expect(toolPolicies[n], isNotNull, reason: n);
      expect(toolReferences[n], isNotNull, reason: n);
      expect(t!.needsTelegram, isTrue, reason: n);
    }
    // Reports and a bot reading private chats always ask, whatever the approval setting.
    for (final n in ['report_chat', 'report_spam', 'set_business_bot']) {
      expect(toolNamed(n)!.alwaysAsk, isTrue, reason: n);
    }
    for (final n in ['list_emoji_statuses', 'list_boost_slots', 'list_quick_replies', 'giveaway_info']) {
      expect(toolNamed(n)!.requiresApproval, isFalse, reason: n);
    }
  });

  testWidgets('a comparison with pros and cons written as text still draws', (tester) async {
    final out = await runShowComponent(const ComponentPrefs(), {
      'component': 'comparison',
      'options': [
        {'name': 'A', 'score': '8', 'pros': 'fast; cheap', 'cons': 'loud'},
        {'name': 'B', 'pros': '["quiet","small"]', 'cons': null},
      ],
    });
    expect(out.json['error'], isNull);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: Scaffold(body: ListView(children: [ComponentView(data: Map<String, dynamic>.from(out.full as Map))]))),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('cheap'), findsOneWidget);
    expect(find.text('quiet'), findsOneWidget);
  });

  testWidgets('the Try it form builds for every tool', (tester) async {
    tester.view.physicalSize = const Size(400, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final t in telegramTools) {
      await tester.pumpWidget(ProviderScope(
        overrides: [settingsProvider.overrideWith(_Settings.new)],
        child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ToolTryPanel(key: ValueKey(t.name), tool: t)))),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: t.name);
    }
  });
}
