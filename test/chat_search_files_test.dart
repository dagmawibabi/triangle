import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teleai/core/files/app_files.dart';
import 'package:teleai/features/chat/data/chat_search.dart';
import 'package:teleai/features/chat/domain/chat_models.dart';
import 'package:teleai/features/telegram/data/telegram_tools.dart';

Conversation _chat(String id, String title, List<(bool, String)> lines) {
  final c = Conversation(id: id, title: title);
  for (final (i, (user, text)) in lines.indexed) {
    c.entries.add(user
        ? UserEntry(id: '$id-$i', text: text)
        : AssistantEntry(id: '$id-$i', steps: [ModelStep(text: text)]));
  }
  return c;
}

void main() {
  group('searching chats', () {
    final chats = {
      'a': _chat('a', 'Visa appointment', [(true, 'When is my visa interview?'), (false, 'It is on Monday at 9.')]),
      'b': _chat('b', 'Weekend plans', [(true, 'Plan a trip to Lalibela'), (false, 'Day 1: fly to Lalibela. Visa not needed.')]),
      'c': _chat('c', 'Budget', [(true, 'How much did I spend?')]),
    };
    final now = DateTime(2026, 11, 14);
    final summaries = [
      for (final (i, c) in chats.values.indexed)
        ConversationSummary(id: c.id, title: c.title, updatedAt: now.subtract(Duration(days: i))),
    ];
    Future<Conversation?> load(String id) async => chats[id];

    test('titles only by default', () async {
      final hits = await searchChats(summaries, 'visa', load: load);
      expect(hits.map((h) => h.summary.id), ['a']);
      expect(hits.single.snippets, isEmpty);
    });

    test('with content, messages match too, with snippets; title matches first', () async {
      final hits = await searchChats(summaries, 'visa', load: load, content: true);
      expect(hits.map((h) => h.summary.id), ['a', 'b']);
      expect(hits.first.inTitle, isTrue);
      expect(hits.last.snippets.single.fromUser, isFalse);
      expect(hits.last.snippets.single.text, contains('Visa not needed'));
    });

    test('every word has to appear, in any case', () async {
      expect((await searchChats(summaries, 'LALIBELA trip', load: load, content: true)).map((h) => h.summary.id), ['b']);
      expect(await searchChats(summaries, 'lalibela budget', load: load, content: true), isEmpty);
      expect(await searchChats(summaries, '   ', load: load, content: true), isEmpty);
    });

    test('snippets are cut around the match', () {
      final long = '${'a' * 300} the needle is here ${'b' * 300}';
      final s = snippetAround(long, ['needle']);
      expect(s, contains('needle'));
      expect(s.length, lessThan(150));
      expect(s, startsWith('…'));
      expect(s, endsWith('…'));
    });
  });

  group('saved files', () {
    late Directory root;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('appfiles');
      File('${root.path}/downloads/books/Fikir Eske Mekabir.epub')
        ..createSync(recursive: true)
        ..writeAsStringSync('book');
      File('${root.path}/downloads/invoice.pdf')
        ..createSync(recursive: true)
        ..writeAsStringSync('%PDF');
      File('${root.path}/telegram/photo-12.jpg')
        ..createSync(recursive: true)
        ..writeAsStringSync('jpg');
      File('${root.path}/downloads/partial.part')
        ..createSync(recursive: true)
        ..writeAsStringSync('x');
      File('${root.path}/elsewhere/secret.txt')
        ..createSync(recursive: true)
        ..writeAsStringSync('no');
    });
    tearDown(() => root.delete(recursive: true));

    test('lists the app folders, including subfolders, without partial files', () {
      final names = listAppFilesSync(root.path).map((f) => f.name).toSet();
      expect(names, {'Fikir Eske Mekabir.epub', 'invoice.pdf', 'photo-12.jpg'});
      expect(listAppFilesSync(root.path, folder: 'telegram').single.name, 'photo-12.jpg');
      expect(listAppFilesSync(root.path, query: 'fikir').single.folder, 'downloads');
    });

    test('finds a file by name or path from any conversation', () {
      expect(findAppFileSync(root.path, 'invoice.pdf')?.kind, 'pdf');
      expect(findAppFileSync(root.path, 'Fikir')?.name, 'Fikir Eske Mekabir.epub');
      expect(findAppFileSync(root.path, '${root.path}/telegram/photo-12.jpg')?.kind, 'image');
      expect(findAppFileSync(root.path, 'secret.txt'), isNull, reason: 'only the app\'s own folders');
    });

    test('file kinds', () {
      expect(fileKind('a.csv'), 'text');
      expect(fileKind('a.docx'), 'document');
      expect(fileKind('a.zip'), 'archive');
      expect(fileKind('a.mp3'), 'audio');
    });
  });

  test('the new tools are read-only and always offered', () {
    for (final name in ['search_ai_chats', 'list_files', 'read_file']) {
      final t = telegramTools.firstWhere((t) => t.name == name);
      expect(t.access, ToolAccess.read, reason: name);
      expect(coreToolCategories, contains(t.category), reason: name);
    }
  });
}
