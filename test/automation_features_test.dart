import 'package:flutter_test/flutter_test.dart';
import 'package:teleai/features/assistant/activity_log.dart';
import 'package:teleai/features/assistant/device_events.dart';
import 'package:teleai/features/assistant/tool_allowlist.dart';
import 'package:teleai/features/assistant/watches.dart';
import 'package:teleai/features/routines/routine_runner.dart';
import 'package:teleai/features/routines/routines.dart';
import 'package:teleai/features/telegram/data/telegram_tools.dart';
import 'package:teleai/features/vault/vault.dart';

void main() {
  group('tool allowlists', () {
    test('picks by name, category and area', () {
      final unknown = <String>[];
      final list = ToolAllowlist.parse(['read_messages', 'Gmail', 'device', 'nonsense'], unknown: unknown);
      expect(unknown, ['nonsense']);
      expect(list.allows(toolNamed('read_messages')!), isTrue);
      expect(list.allows(toolNamed('send_message')!), isFalse);
      final deviceTool = telegramTools.firstWhere((t) => t.category == ToolCategory.device);
      expect(list.allows(deviceTool), isTrue);
      final gmail = telegramTools.where((t) => t.category == ToolCategory.gmail);
      expect(gmail.every(list.allows), isTrue);
    });

    test('watches allow every tool unless they say otherwise, and keep their list', () {
      final w = Watch(id: 'a', name: 'A', scope: WatchScope.schedule, mode: WatchMode.act, createdAt: DateTime(2026));
      expect(w.tools, isNull);
      expect(w.model, WatchModel.free);
      final limited = w.copyWith(tools: ToolAllowlist.parse(['messages']), model: WatchModel.main);
      final back = Watch.fromJson(limited.toJson());
      expect(back.tools!.allows(toolNamed('read_messages')!), isTrue);
      expect(back.tools!.allows(toolNamed('create_watch')!), isFalse);
      expect(back.model, WatchModel.main);
      expect(Watch.fromJson(back.copyWith(allTools: true).toJson()).tools, isNull);
    });

    test('watches saved before models existed start on the free model', () {
      final old = Watch.fromJson({'id': 'x', 'name': 'Old', 'scope': 'allDms', 'mode': 'act'});
      expect(old.model, WatchModel.free);
    });
  });

  group('phone triggers', () {
    test('round-trip through JSON and describe themselves', () {
      const c = DeviceCondition(kind: DeviceTriggerKind.arrive, lat: 9.03, lng: 38.74, radius: 200, placeName: 'Home');
      final back = DeviceCondition.fromJson(c.toJson())!;
      expect(back.kind, DeviceTriggerKind.arrive);
      expect(back.lat, 9.03);
      expect(back.radius, 200);
      expect(back.describe(), 'Arrive at Home');
      final w = Watch(id: 'p', name: 'Home', scope: WatchScope.device, mode: WatchMode.notify, device: c, createdAt: DateTime(2026));
      expect(Watch.fromJson(w.toJson()).device!.placeName, 'Home');
      expect(WatchScope.device.needsTelegram, isFalse);
    });

    test('tool arguments become a condition, or an error', () {
      expect(phoneConditionFrom({}).error, isNotNull);
      expect(phoneConditionFrom({'phone_event': 'arrive'}).error, isNotNull);
      final ok = phoneConditionFrom({'phone_event': 'battery_low', 'battery_below': 15});
      expect(ok.error, isNull);
      expect(ok.condition!.threshold, 15);
    });
  });

  group('routines', () {
    test('fill variables', () {
      final out = RoutineRunner.fill(
        'Hi {{last}} / {{step1}} / {{ trigger }} / {{vault:home address}} / {{unknown}}',
        last: 'L',
        outputs: ['one', 'two'],
        trigger: 'T',
        vault: [(label: 'Home address', value: 'Bole Rd')],
      );
      expect(out, 'Hi L / one / T / Bole Rd / {{unknown}}');
    });

    test('tool inputs take the schema types', () {
      final args = RoutineRunner.coerceArgs('read_messages', {'chat_id': '{{last}}', 'limit': '5', 'unread_only': 'true'}, (s) => s.replaceAll('{{last}}', '42'));
      expect(args, {'chat_id': 42, 'limit': 5, 'unread_only': true});
    });

    test('round-trip through JSON', () {
      final r = Routine(
        id: 'r1',
        name: 'Morning',
        createdAt: DateTime(2026),
        trigger: const RoutineTrigger(kind: RoutineTriggerKind.daily, at: '07:30', days: {1, 2, 3, 4, 5}),
        steps: const [
          RoutineStep(id: 's1', kind: RoutineStepKind.ask, prompt: 'Brief me'),
          RoutineStep(id: 's2', kind: RoutineStepKind.condition, test: ConditionTest.notContains, value: 'NOTHING'),
          RoutineStep(id: 's3', kind: RoutineStepKind.notify, title: 'Hi', body: '{{last}}'),
        ],
      );
      final back = Routine.fromJson(r.toJson());
      expect(back.trigger.describe(), 'Weekdays at 07:30');
      expect(back.steps.map((s) => s.kind), [RoutineStepKind.ask, RoutineStepKind.condition, RoutineStepKind.notify]);
      expect(back.steps[1].test, ConditionTest.notContains);
      expect(back.model, WatchModel.free);
    });

    test('templates only use tools that exist and may be routine steps', () {
      for (final t in routineTemplates()) {
        for (final s in t.steps.where((s) => s.kind == RoutineStepKind.tool)) {
          final tool = toolNamed(s.tool);
          expect(tool, isNotNull, reason: '${t.name}: ${s.tool}');
          expect(tool!.destructive || tool.alwaysAsk, isFalse);
        }
      }
    });
  });

  group('activity log', () {
    test('sent messages can be deleted, reactions and pins reversed', () {
      final sent = undoFor('send_message', {'chat_id': 1}, {'sent': true}, [(1, 10), (1, 11)]);
      expect(sent!.kind, UndoKind.deleteMessages);
      expect(sent.messages, [(1, 10), (1, 11)]);
      final react = undoFor('react_to_message', {'chat_id': 1, 'message_id': 2, 'emoji': '👍'}, {'done': true, 'removed': false}, const []);
      expect(react!.args['remove'], isTrue);
      expect(undoFor('send_message', const {}, {'error': 'x'}, [(1, 2)]), isNull);
      expect(undoFor('mark_as_read', const {}, {'done': true}, const []), isNull);
    });

    test('entries round-trip through JSON', () {
      final e = ActivityEntry(
        id: 'e',
        at: DateTime(2026, 1, 2),
        tool: 'send_message',
        toolLabel: 'Sending',
        source: ActivitySource.watch,
        sourceName: 'DMs',
        approval: ActivityApproval.rule,
        outcome: ActivityOutcome.done,
        undo: const UndoAction(kind: UndoKind.deleteMessages, label: 'Delete', messages: [(5, 6)]),
      );
      final back = ActivityEntry.fromJson(e.toJson());
      expect(back.canUndo, isTrue);
      expect(back.undo!.messages, [(5, 6)]);
      expect(back.approval, ActivityApproval.rule);
    });
  });

  test('vault items hide sensitive values unless revealed', () {
    final i = VaultItem(
      id: 'v',
      label: 'Passport',
      value: 'EP1234567',
      category: VaultCategory.identity,
      sensitive: true,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    expect(i.describe(reveal: false)['value'], isNot(contains('EP1234567')));
    expect(i.describe()['value'], 'EP1234567');
    expect(i.masked, '••••4567');
    expect(VaultItem.fromJson(i.toJson()).sensitive, isTrue);
  });
}
