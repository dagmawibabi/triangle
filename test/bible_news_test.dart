import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teleai/features/bible/bible.dart';
import 'package:teleai/features/chat/domain/chat_models.dart';
import 'package:teleai/features/chat/presentation/widgets/bible_result_cards.dart';
import 'package:teleai/features/chat/presentation/widgets/news_result_cards.dart';
import 'package:teleai/features/telegram/data/telegram_tools.dart';

ToolPart _part(String name, Map<String, dynamic> result) =>
    ToolPart(callId: 'c', name: name, arguments: '{}')
      ..result = jsonEncode(result)
      ..status = ToolStatus.done;

void main() {
  group('Bible references', () {
    test('read the usual forms', () {
      expect(BibleRef.parse('John 3:16')!.passageId, 'JHN.3.16');
      expect(BibleRef.parse('john 3:16-18')!.passageId, 'JHN.3.16-18');
      expect(BibleRef.parse('Psalm 23')!.passageId, 'PSA.23');
      expect(BibleRef.parse('Ps 23')!.wholeChapter, isTrue);
      expect(BibleRef.parse('1 Cor 13:4-7')!.passageId, '1CO.13.4-7');
      expect(BibleRef.parse('Rom 8:28-9:2')!.passageId, 'ROM.8.28-9.2');
      expect(BibleRef.parse('Rom 8:28-9:2')!.crossesChapters, isTrue);
      expect(BibleRef.parse('JHN.3.16-18')!.label, 'John 3:16–18');
      expect(BibleRef.parse('Song of Solomon 2:4')!.book.code, 'SNG');
      expect(BibleRef.parse('JHN.3.16')!.label, 'John 3:16');
      expect(BibleRef.parse('1co.13.4-7')!.book.code, '1CO');
      expect(BibleRef.parse('Hezekiah 1:1'), isNull);
      expect(BibleRef.parse('John 30:1'), isNull);
    });

    test('chapters page within a book', () {
      final r = BibleRef.parse('Jude 1')!;
      expect(r.nextChapter, isNull);
      expect(r.previousChapter, isNull);
      expect(BibleRef.parse('Genesis 2')!.nextChapter!.label, 'Genesis 3');
    });

    test('every verse of the day is a valid reference, and it stays put for a day', () {
      for (final v in verseOfTheDayRefs) {
        expect(BibleRef.parse(v), isNotNull, reason: v);
      }
      expect(verseOfTheDayFallback(DateTime(2026, 5, 1, 8)), verseOfTheDayFallback(DateTime(2026, 5, 1, 23)));
      expect(bibleBooks, hasLength(66));
    });
  });

  test('the new tools are listed, classified and documented', () {
    for (final n in ['reddit_posts', 'reddit_post', 'hn_stories', 'hn_item', 'hn_user', 'bible_passage', 'bible_chapter', 'bible_compare']) {
      final t = toolNamed(n);
      expect(t, isNotNull, reason: n);
      expect(t!.modifiesData, isFalse, reason: n);
    }
  });

  testWidgets('news and Bible cards draw', (tester) async {
    final cards = [
      newsResultFor(_part('hn_stories', {}), {
        'list': 'top',
        'stories': [
          {'rank': 1, 'title': 'Show HN: a thing', 'site': 'example.com', 'points': 120, 'author': 'pg', 'comments': 40, 'created': '2026-11-10T10:00'},
        ],
      }),
      newsResultFor(_part('reddit_post', {}), {
        'post': {'title': 'Hello', 'subreddit': 'flutterdev', 'author': 'me', 'score': 12, 'comments': 2, 'created': '2026-11-10T10:00'},
        'comments': [
          {
            'author': 'a',
            'score': 3,
            'text': 'Nice',
            'replies': [
              {'author': 'b', 'text': 'Agreed'},
            ],
          },
        ],
      }),
      bibleResultFor(_part('bible_passage', {}), {
        'reference': 'John 3:16',
        'passage_id': 'JHN.3.16',
        'text': '16 For God so loved the world…',
        'version': {'version_id': 1, 'abbreviation': 'KJV', 'title': 'King James Version'},
      }),
    ];
    expect(cards.every((c) => c != null), isTrue);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: ListView(children: [for (final c in cards) c!])),
        ),
      ),
    );
    expect(find.text('Show HN'), findsOneWidget);
    expect(find.text('a thing'), findsOneWidget);
    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('John 3:16'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
