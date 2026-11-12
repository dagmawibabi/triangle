import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teleai/features/chat/domain/chat_models.dart';
import 'package:teleai/features/chat/presentation/widgets/rich_results.dart';
import 'package:teleai/features/device/device.dart';
import 'package:teleai/features/screen/screen_tools.dart';
import 'package:teleai/features/telegram/data/telegram_tools.dart';

void main() {
  TelegramTool tool(String name) => telegramTools.firstWhere((t) => t.name == name);

  test('screen control offers reading, acting and system buttons', () {
    final names = {for (final t in telegramTools) t.name};
    expect(names, containsAll(screenToolNames));
    expect(screenToolNames, containsAll(['screen_read', 'screen_tap', 'screen_type', 'screen_scroll', 'screen_swipe', 'screen_press', 'screen_screenshot', 'screen_wait', 'screen_status']));
  });

  test('reading never changes anything; taps, typing and swipes ask first', () {
    for (final n in ['screen_status', 'screen_read', 'screen_screenshot', 'screen_wait']) {
      expect(tool(n).modifiesData, isFalse, reason: n);
    }
    for (final n in ['screen_tap', 'screen_type', 'screen_swipe']) {
      expect(tool(n).modifiesData, isTrue, reason: n);
      expect(tool(n).requiresApproval, isTrue, reason: n);
      // The approval card says what the action is for.
      expect((tool(n).parameters['required'] as List), contains('why'), reason: n);
    }
    expect(tool('screen_scroll').modifiesData, isTrue);
    expect(tool('screen_press').modifiesData, isTrue);
  });

  test('away from Android the tools say so instead of failing', () async {
    Device.debugSupported = false;
    addTearDown(() => Device.debugSupported = null);
    final out = await runScreenTool('screen_read', const {});
    expect('${out.json['error']}', contains('Android'));
    final status = await runScreenTool('screen_status', const {});
    expect(status.json['enabled'], isFalse);
    expect(status.json['how_to_turn_on'], isNotNull);
  });

  test('a tap needs a target', () async {
    final out = await runScreenTool('screen_tap', const {'why': 'Send'});
    expect(out.json['error'], isNotNull);
  });

  testWidgets('a screen read shows the app and its elements, never a password', (tester) async {
    final part = ToolPart(callId: '1', name: 'screen_read', arguments: '{}', status: ToolStatus.done)
      ..result =
          '{"app":"Settings","package":"com.android.settings","count":3,"password_fields":1,"elements":['
          '{"id":1,"role":"text","text":"Network & internet"},'
          '{"id":2,"role":"switch","text":"Dark theme","clickable":true,"checked":false},'
          '{"id":3,"role":"field","text":"••••","password":true,"editable":true}]}';
    final card = richResultFor(part);
    expect(card, isNotNull);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: card))));
    expect(find.text('SCREEN · SETTINGS'), findsOneWidget);
    expect(find.text('Dark theme'), findsOneWidget);
    expect(find.text('Passwords hidden'), findsOneWidget);
  });
}
