import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teleai/features/chat/data/tool_loading.dart';
import 'package:teleai/features/chat/domain/chat_models.dart';
import 'package:teleai/features/settings/data/settings.dart';
import 'package:teleai/features/telegram/data/telegram_tools.dart';

void main() {
  group('starting tool groups', () {
    test('messages bring the groups they talk about', () {
      expect(categoriesMentioned('Any new emails from Sara in my inbox?'), containsAll([ToolCategory.gmail, ToolCategory.outlook]));
      expect(categoriesMentioned('How much did I spend on transport this month?'), contains(ToolCategory.finance));
      expect(categoriesMentioned("What's the weather in Addis tomorrow?"), contains(ToolCategory.markets));
      expect(categoriesMentioned('Read me John 3:16 from the Bible'), contains(ToolCategory.bible));
      expect(categoriesMentioned('Set an alarm for 6am'), contains(ToolCategory.device));
      expect(categoriesMentioned('Ban that spammer from my group'), contains(ToolCategory.members));
      expect(categoriesMentioned('hi'), isEmpty);
    });

    test('a run starts with the core, what the chat used, and what was loaded', () {
      final c = Conversation(id: 'c');
      c.entries.add(AssistantEntry(id: 'a', steps: [
        ModelStep(tools: [ToolPart(callId: '1', name: 'finance_overview')]),
      ]));
      final start = startingCategories(c: c, message: 'and last week?', loaded: {ToolCategory.youtube});
      expect(start, containsAll(coreToolCategories));
      expect(start, contains(ToolCategory.finance), reason: 'used earlier in the chat');
      expect(start, contains(ToolCategory.youtube), reason: 'loaded earlier');
      expect(start, isNot(contains(ToolCategory.slack)));
    });

    test('a watch starts with what its instructions mention', () {
      final start = startingCategories(c: Conversation(id: 'w'), message: '', watchInstructions: 'Add any receipt to my budget');
      expect(start, contains(ToolCategory.finance));
    });

    test('the core is a small part of all the tools', () {
      String size(Iterable<TelegramTool> tools) => '${jsonEncode([for (final t in tools) t.schema]).length}';
      final core = [for (final t in telegramTools) if (coreToolCategories.contains(t.category)) t];
      final all = int.parse(size(telegramTools));
      expect(int.parse(size(core)), lessThan(all ~/ 3), reason: 'core ${size(core)} of $all characters');
    });
  });

  group('load_tools', () {
    final tool = telegramTools.firstWhere((t) => t.name == 'load_tools');

    test('offers every group outside the core, and reads only', () {
      final groups = ((tool.parameters['properties'] as Map)['groups'] as Map)['items'] as Map;
      final names = (groups['enum'] as List).cast<String>().toSet();
      expect(names, {for (final c in ToolCategory.values) if (!coreToolCategories.contains(c)) c.name});
      expect(tool.access, ToolAccess.read);
      expect(tool.category, ToolCategory.system);
      for (final c in ['gmail', 'finance', 'markets']) {
        expect(tool.description, contains(c));
      }
    });

    test('loading as needed is on by default and can be turned off', () {
      expect(const AppSettings().loadToolsOnDemand, isTrue);
      expect(const AppSettings().copyWith(loadToolsOnDemand: false).loadToolsOnDemand, isFalse);
    });
  });
}
