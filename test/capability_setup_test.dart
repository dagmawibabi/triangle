import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teleai/features/chat/domain/chat_models.dart';
import 'package:teleai/features/chat/presentation/widgets/info_card_kit.dart' show SheetTitle;
import 'package:teleai/features/chat/presentation/widgets/rich_results.dart';
import 'package:teleai/features/telegram/data/system_tools.dart' show redactKeyArguments;
import 'package:teleai/features/telegram/data/telegram_tools.dart';

final _broken = {
  'id': 'linear',
  'transport': 'http',
  'address': 'https://mcp.linear.app/mcp',
  'header_names': <String>[],
  'auth': 'none',
  'connect_ms': 412,
  'permissions': {'default': 'app', 'allow': 0, 'ask': 0, 'off': 0},
  'calls_7d': 4,
  'failed_7d': 3,
  'status': 'fail',
  'findings': [
    {'status': 'fail', 'title': 'Needs a sign-in with linear.app', 'detail': 'Sign in in Settings.'},
    {'status': 'warn', 'title': '3 of 4 calls failed this week'},
  ],
};

final _working = {
  'id': 'docs',
  'transport': 'http',
  'address': 'https://docs.example.com/mcp',
  'header_names': ['Authorization'],
  'auth': 'header',
  'server_name': 'Docs',
  'protocol': '2025-06-18',
  'connect_ms': 220,
  'list_ms': 80,
  'tools': 3,
  'tool_names': ['search', 'read_page', 'list'],
  'resources': 2,
  'prompts': 0,
  'permissions': {'default': 'ask', 'allow': 1, 'ask': 2, 'off': 0},
  'calls_7d': 0,
  'failed_7d': 0,
  'status': 'ok',
  'findings': [
    {'status': 'ok', 'title': 'Connected in 220 ms'},
    {'status': 'ok', 'title': '3 tools'},
  ],
};

final _skill = {
  'name': 'pdf-forms',
  'description': 'Fills PDF forms. Use when the user sends a PDF form.',
  'source': 'acme/skills@pdf-forms',
  'deferred': false,
  'chars': 4000,
  'lines': 120,
  'est_tokens': 1000,
  'files': ['references/fields.md'],
  'files_bytes': 2048,
  'missing_files': ['scripts/fill.py'],
  'loads_30d': 2,
  'failed_30d': 0,
  'update_available': true,
  'status': 'warn',
  'findings': [
    {'status': 'warn', 'title': 'Mentions 1 file it doesn\'t have', 'detail': 'scripts/fill.py'},
    {'status': 'improve', 'title': 'Update available'},
    {'status': 'ok', 'title': 'Clear description'},
  ],
};

final _samples = <String, Map<String, dynamic>>{
  'mcp_diagnose': {
    'checked_at': '2026-11-16T10:00:00.000',
    'counts': {'broken': 1, 'warnings': 1, 'suggestions': 0, 'passed': 2},
    'servers': [_broken, _working],
  },
  'skill_diagnose': {
    'checked_at': '2026-11-16T10:00:00.000',
    'installed': 1,
    'prompt_tokens': 40,
    'counts': {'broken': 0, 'warnings': 1, 'suggestions': 1, 'passed': 1},
    'general': [
      {'status': 'improve', 'title': 'a and b have the same description'},
    ],
    'skills': [_skill],
  },
  'mcp_setup': {
    'server': 'docs',
    'changed': ['Set header Authorization', 'search → Allow'],
    'check': _working,
  },
  'skill_setup': {
    'skill': 'pdf-forms',
    'changed': ['New description', 'Deferred'],
    'check': _skill,
  },
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the setup and diagnose tools are listed, with policies and references', () {
    for (final name in ['mcp_diagnose', 'mcp_setup', 'skill_diagnose', 'skill_setup']) {
      final tool = toolNamed(name);
      expect(tool, isNotNull, reason: name);
      expect(toolReferences[name], isNotNull, reason: name);
    }
    expect(toolNamed('mcp_setup')!.requiresApproval, isTrue);
    expect(toolNamed('skill_setup')!.requiresApproval, isTrue);
    expect(toolNamed('mcp_diagnose')!.requiresApproval, isFalse);
  });

  test('mcp_setup header values are hidden in the saved call', () {
    final saved = jsonDecode(redactKeyArguments(jsonEncode({
      'server': 'docs',
      'headers': {'Authorization': 'Bearer sk-secret-123456', 'X-Old': ''},
    }))) as Map;
    final headers = saved['headers'] as Map;
    expect('${headers['Authorization']}', isNot(contains('secret')));
    expect(headers['X-Old'], '');
  });

  testWidgets('every MCP and skill setup card lays out and opens its sheet', (tester) async {
    tester.view.physicalSize = const Size(360, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final e in _samples.entries) {
      final part = ToolPart(callId: e.key, name: e.key, status: ToolStatus.done, result: jsonEncode(e.value));
      final card = richResultFor(part);
      expect(card, isNotNull, reason: e.key);
      // A fresh app for each card: otherwise the last card's sheet is still
      // open, and its backdrop takes the tap meant for this card.
      await tester.pumpWidget(
        ProviderScope(
          key: ValueKey(e.key),
          child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: card!))),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: e.key);
      await tester.tap(find.byWidget(card).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '${e.key} sheet');
      expect(find.byType(SheetTitle), findsOneWidget, reason: '${e.key} sheet');
    }
  });
}
