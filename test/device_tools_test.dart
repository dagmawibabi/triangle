import 'package:flutter_test/flutter_test.dart';
import 'package:teleai/features/telegram/data/telegram_tools.dart';

void main() {
  test('device tools sit under Device on the main Tools screen, reading ones run without asking', () {
    const reads = ['device_info', 'device_battery', 'network_info', 'installed_apps', 'read_sms', 'phone_contacts', 'read_clipboard'];
    const acts = ['make_call', 'send_sms', 'flashlight', 'vibrate', 'set_alarm', 'set_timer', 'open_app', 'media_control', 'ringer_mode'];
    for (final name in [...reads, ...acts]) {
      final t = toolNamed(name)!;
      expect(t.category, ToolCategory.device, reason: name);
      expect(t.category.onAppsScreen, isFalse, reason: name);
      expect(t.destructive, isFalse, reason: name);
      expect(t.requiresApproval, acts.contains(name), reason: name);
    }
    expect(toolNamed('send_sms')!.alwaysAsk, isTrue);
  });

  test('reading the volume does not ask; changing it does', () {
    final t = toolNamed('device_volume')!;
    expect(callNeedsApproval(t, {}), isFalse);
    expect(callNeedsApproval(t, {'stream': 'ring'}), isFalse);
    expect(callNeedsApproval(t, {'percent': 40}), isTrue);
    expect(callNeedsApproval(t, {'mute': true}), isTrue);
  });
}
