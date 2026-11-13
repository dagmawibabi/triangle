import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teleai/features/assistant/system_prompt.dart';
import 'package:teleai/features/chat/data/image_input.dart';
import 'package:teleai/features/settings/data/settings.dart';
import 'package:teleai/features/settings/presentation/system_prompt_screen.dart';

/// A 1×1 GIF with two frames (black, then white), 100 ms each.
Uint8List _twoFrameGif() {
  final b = BytesBuilder();
  b.add('GIF89a'.codeUnits);
  b.add([1, 0, 1, 0, 0x80, 0, 0]); // 1×1, a 2-colour global table
  b.add([0, 0, 0, 255, 255, 255]);
  b.add([0x21, 0xFF, 0x0B, ...'NETSCAPE2.0'.codeUnits, 3, 1, 0, 0, 0]);
  for (final pixel in [0x44, 0x4C]) {
    b.add([0x21, 0xF9, 4, 0, 10, 0, 0, 0]); // 10/100 s
    b.add([0x2C, 0, 0, 0, 0, 1, 0, 1, 0, 0]);
    b.add([2, 2, pixel, 0x01, 0]); // LZW: clear, colour, end
  }
  b.add([0x3B]);
  return b.toBytes();
}

Map<String, String> _values() => {
      for (final k in systemPromptPlaceholders.keys) k: '<$k>',
      'external_content_rule': '- RULE',
      'watch': '',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('system prompt', () {
    test('the built-in template uses exactly the documented placeholders', () {
      final used = {for (final m in RegExp(r'\{\{([a-z_]+)\}\}').allMatches(defaultSystemPromptTemplate)) m[1]!};
      expect(used, systemPromptPlaceholders.keys.toSet());
    });

    test('renders the built-in template with every value filled in', () {
      final p = buildSystemPrompt(enabled: true, template: defaultSystemPromptTemplate, values: _values());
      expect(p, startsWith('You are Triangle'));
      expect(p, contains('User: <user>.'));
      expect(p, contains('- RULE'));
      expect(p, isNot(contains('{{')));
      // The rule isn't added twice when the template has it.
      expect('- RULE'.allMatches(p).length, 1);
    });

    test('off or cleared, nothing is sent but a watch\'s instructions', () {
      final watch = {..._values(), 'watch': 'This turn was started by the watch "W".'};
      for (final p in [
        buildSystemPrompt(enabled: false, template: defaultSystemPromptTemplate, values: watch),
        buildSystemPrompt(enabled: true, template: '', values: watch),
      ]) {
        expect(p, 'This turn was started by the watch "W".');
      }
      expect(buildSystemPrompt(enabled: false, template: 'x', values: _values()), isEmpty);
    });

    test('a custom template is sent exactly as written', () {
      final p = buildSystemPrompt(enabled: true, template: 'Be a pirate. Time: {{now}}. {{nope}}', values: _values());
      expect(p, 'Be a pirate. Time: <now>. {{nope}}');
    });

    test('the built-in prompt is much shorter than before but keeps its rules', () {
      expect(defaultSystemPromptTemplate.length, lessThan(6000));
      for (final rule in ['never invent', 'rate-limits', 'only when the user asked', 'never forward it to Saved Messages', 'remember', 'investment advice', 'pirated', 'cite it with a markdown link']) {
        expect(defaultSystemPromptTemplate, contains(rule), reason: rule);
      }
    });

    test('settings save, clear and reset it', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(settingsProvider);
      for (var i = 0; i < 100 && !c.read(settingsProvider).loaded; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final ctl = c.read(settingsProvider.notifier);
      expect(activeSystemPromptTemplate(c.read(settingsProvider)), defaultSystemPromptTemplate);
      await ctl.setSystemPrompt('Mine {{now}}');
      expect(activeSystemPromptTemplate(c.read(settingsProvider)), 'Mine {{now}}');
      await ctl.setSystemPrompt('');
      expect(systemPromptStatus(c.read(settingsProvider)), startsWith('Cleared'));
      await ctl.setSystemPromptEnabled(false);
      expect(systemPromptStatus(c.read(settingsProvider)), startsWith('Off'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('system_prompt_custom'), isTrue);
      await ctl.resetSystemPrompt();
      final s = c.read(settingsProvider);
      expect(s.systemPromptEnabled, isTrue);
      expect(s.systemPromptCustom, isFalse);
      expect(activeSystemPromptTemplate(s), defaultSystemPromptTemplate);
    });
  });

  group('GIF frames', () {
    test('frames are spread over the animation, skipping the very ends', () {
      expect(spreadFrames(100, 4), [12, 37, 62, 87]);
      expect(spreadFrames(3, 6), [0, 1, 2]);
      expect(spreadFrames(0, 6), isEmpty);
    });

    test('MP4 and WebM are recognised as video', () {
      expect(isVideoBytes([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6F, 0x6D]), isTrue);
      expect(isVideoBytes([0x1A, 0x45, 0xDF, 0xA3, 0, 0]), isTrue);
      expect(isVideoBytes(_twoFrameGif()), isFalse);
    });

    testWidgets('an animated GIF gives each frame with its time', (tester) async {
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('gif_frames');
        addTearDown(() => dir.delete(recursive: true));
        final gif = File('${dir.path}/two.gif')..writeAsBytesSync(_twoFrameGif());
        final loader = ImageInputLoader(directory: Directory('${dir.path}/out'));
        try {
          final f = await loader.loadFrames(gif.path, maxFrames: 6);
          expect(f.animated, isTrue);
          expect(f.frameCount, 2);
          expect(f.images, hasLength(2));
          expect(f.images.map((i) => i.at), [Duration.zero, const Duration(milliseconds: 100)]);
          expect(f.duration, const Duration(milliseconds: 200));
          expect(f.images.every((i) => i.file.existsSync()), isTrue);
          // One frame when only one is asked for.
          final one = await loader.loadFrames(gif.path, maxFrames: 1);
          expect(one.images, hasLength(1));
        } finally {
          loader.close();
        }
      });
    });
  });
}
