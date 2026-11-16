import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teleai/app/start_page.dart';
import 'package:teleai/features/settings/data/settings.dart';
import 'package:teleai/features/telegram/data/telegram_tools.dart';

void main() {
  test('every defined tool is in the list the Tools page shows', () {
    final listed = {for (final t in telegramTools) t.name};
    final defined = <String>{};
    for (final f in Directory('lib/features/telegram/data').listSync().whereType<File>()) {
      if (!f.path.contains('telegram_')) continue;
      final src = f.readAsStringSync();
      for (final m in RegExp(r"TelegramTool\(\s*name: '([a-z_0-9]+)'").allMatches(src)) {
        defined.add(m[1]!);
      }
    }
    expect(defined.difference(listed), isEmpty);
    expect(defined.length, greaterThan(100));
  });

  test('every tool is classified as Read, Modify or Destructive', () {
    final missing = [for (final t in telegramTools) if (!toolPolicies.containsKey(t.name)) t.name];
    expect(missing, isEmpty);
  });

  test('every tool documents its returned data', () {
    final missing = [for (final t in telegramTools) if (!toolReferences.containsKey(t.name)) t.name];
    expect(missing, isEmpty);
  });

  test('every parameter has a specific description', () {
    final generic = <String>[];
    void walk(String tool, String path, Map schema) {
      for (final e in ((schema['properties'] as Map?) ?? const {}).entries) {
        final s = e.value as Map;
        final d = '${s['description'] ?? ''}';
        if (d.trim().isEmpty || d.startsWith('See the operation description')) generic.add('$tool.$path${e.key}');
        walk(tool, '$path${e.key}.', s);
        if (s['items'] case final Map items) walk(tool, '$path${e.key}[].', items);
      }
    }
    for (final t in telegramTools) {
      walk(t.name, '', t.parameters);
    }
    expect(generic, isEmpty);
  });

  test('read-only mode leaves only Read tools on, whatever their approval setting', () {
    const s = AppSettings(readOnlyMode: true);
    final on = [for (final t in telegramTools) if (t.isOn(s)) t];
    expect(on.where((t) => t.modifiesData), isEmpty);
    expect(on, isNotEmpty);
    // Modify tools that run without asking are blocked too.
    expect(telegramTools.where((t) => t.access == ToolAccess.modify && !t.requiresApproval).every((t) => !t.isOn(s)), isTrue);
  });

  test('every Explore page has tools, grouped in the drawer\'s order, and can be a start page', () {
    final explore = [for (final c in ToolCategory.values) if (c.isExplore) c];
    expect(explore, [
      ToolCategory.sections,
      ToolCategory.playlists,
      ToolCategory.movies,
      ToolCategory.cinema,
      ToolCategory.podcasts,
      ToolCategory.books,
      ToolCategory.gallery,
      ToolCategory.opportunities,
      ToolCategory.marketplace,
    ]);
    for (final c in explore) {
      expect(telegramTools.where((t) => t.category == c), isNotEmpty, reason: c.name);
    }
    expect(
      [for (final p in StartPage.values) p.name].where({'playlists', 'movies', 'cinema', 'podcasts', 'books', 'gallery', 'opportunity', 'marketplace'}.contains),
      ['playlists', 'movies', 'cinema', 'podcasts', 'books', 'gallery', 'opportunity', 'marketplace'],
    );
  });

  test('Telegram-only tools are not grouped under Apps & web', () {
    final wrong = [for (final t in telegramTools) if (t.needsTelegram && t.category.onAppsScreen) t.name];
    expect(wrong, isEmpty);
  });
}
