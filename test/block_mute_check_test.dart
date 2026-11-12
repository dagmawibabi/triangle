import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teleai/features/chat/domain/chat_models.dart';
import 'package:teleai/features/chat/presentation/widgets/safety_result_cards.dart';
import 'package:teleai/features/settings/data/system_check.dart';
import 'package:teleai/features/telegram/data/content_filters.dart';
import 'package:teleai/features/telegram/data/telegram_tools.dart';

void main() {
  group('muted words', () {
    final f = ContentFilters(mutedWords: const ['cat', 'spoiler alert', 'c++', 'ሰላም']);

    test('match whole words in any case', () {
      expect(f.mutedWordIn('My CAT sleeps'), 'cat');
      expect(f.mutedWordIn('SPOILER ALERT: he lives'), 'spoiler alert');
      expect(f.mutedWordIn('I love c++!'), 'c++');
      expect(f.mutedWordIn('ሰላም ነው'), 'ሰላም');
    });

    test('leave words that only contain them alone', () {
      expect(f.mutedWordIn('education'), isNull);
      expect(f.mutedWordIn('cats'), isNull);
      expect(f.mutedWordIn('ሰላምታ'), isNull);
      expect(f.mutedWordIn(''), isNull);
    });

    test('survive a save and load', () {
      final back = ContentFilters.fromJson(
        f.copyWith(blockedChats: {-100123: 'News'}, labelMutedWords: false, inArchived: true).toJson(),
      );
      expect(back.mutedWords, f.mutedWords);
      expect(back.blockedChats, {-100123: 'News'});
      expect(back.labelMutedWords, isFalse);
      expect(back.inArchived, isTrue);
      expect(back.labelBlockedAccounts, isTrue);
    });
  });

  group('system check', () {
    List<CheckGroup> sample() {
      final a = CheckGroup('ai', 'AI & models', Icons.auto_awesome_outlined)
        ..results.addAll(const [
          CheckResult(CheckStatus.ok, 'Keys work'),
          CheckResult(CheckStatus.fail, 'No model', 'Pick one.'),
        ])
        ..done = true;
      final b = CheckGroup('privacy', 'Privacy & safety', Icons.shield_outlined)
        ..results.addAll(const [
          CheckResult(CheckStatus.improve, 'App lock is off'),
          CheckResult(CheckStatus.info, 'Nothing is hidden'),
        ])
        ..done = true;
      return [a, b];
    }

    test('scores passes fully, suggestions by half, and ignores notes', () {
      // 1 ok + 0.5 suggestion out of 3 scored = 50.
      expect(SystemChecker.score(sample()), 50);
      expect(SystemChecker.score([CheckGroup('x', 'X', Icons.circle)]), isNull);
    });

    test('reports counts and areas, most serious first', () {
      final j = SystemChecker.toJson(sample());
      expect(j['counts'], {'broken': 1, 'warnings': 0, 'suggestions': 1, 'passed': 1, 'notes': 1});
      final ai = (j['areas'] as List).first as Map;
      expect(ai['worst'], 'fail');
      expect(((ai['results'] as List).first as Map)['title'], 'No model');
    });

    test('every area has a title and icon', () {
      expect(systemCheckAreas.keys, containsAll(['ai', 'telegram', 'connection', 'routines', 'privacy', 'upkeep']));
    });

    test('the system check and Block & mute tools are on the tool list', () {
      final names = {for (final t in telegramTools) t.name};
      expect(names, containsAll(['system_check', 'list_hidden', 'block_chat', 'unblock_chat', 'mute_words', 'unmute_words', 'block_mute_settings']));
      final check = telegramTools.firstWhere((t) => t.name == 'system_check');
      expect(check.modifiesData, isFalse);
    });
  });

  group('cards', () {
    Future<void> pump(WidgetTester tester, String name, Map<String, dynamic> j) async {
      final w = safetyResultFor(ToolPart(callId: '1', name: name, arguments: '{}'), j);
      expect(w, isNotNull);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: w))));
    }

    testWidgets('a system check shows its score and what needs attention', (tester) async {
      final j = SystemChecker.toJson((() {
        final g = CheckGroup('ai', 'AI & models', Icons.auto_awesome_outlined)
          ..results.addAll(const [CheckResult(CheckStatus.fail, 'No model'), CheckResult(CheckStatus.ok, 'Keys work')])
          ..done = true;
        return [g];
      })());
      await pump(tester, 'system_check', j);
      expect(find.text('50'), findsOneWidget);
      expect(find.text('1 thing needs attention'), findsOneWidget);
      expect(find.textContaining('No model'), findsOneWidget);
    });

    testWidgets('muting shows the words', (tester) async {
      await pump(tester, 'mute_words', {
        'muted': ['spoilers'],
        'blocked_chats': [
          {'id': -1001, 'title': 'Deals', 'kind': 'channel'},
        ],
        'muted_words': ['spoilers'],
        'blocked_accounts': 2,
        'notices': {'accounts': true, 'chats': false, 'words': true},
        'in_archived': false,
      });
      expect(find.text('Muted “spoilers”'), findsOneWidget);
      expect(find.text('Deals'), findsOneWidget);
      expect(find.textContaining('2 blocked accounts'), findsOneWidget);
    });
  });
}
