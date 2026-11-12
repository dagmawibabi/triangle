import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_ai/omni_ai.dart' as omni;
import 'package:teleai/features/chat/data/creative_audio.dart';
import 'package:teleai/features/chat/data/image_input.dart';
import 'package:teleai/features/settings/data/settings.dart';
import 'package:teleai/features/telegram/data/telegram_tools.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('creative tools belong to Apps & web and need no Telegram', () {
    final creative = telegramTools.where(
      (t) => t.category == ToolCategory.creative || t.category == ToolCategory.files,
    );
    expect(
      creative.map((t) => t.name),
      containsAll([
        'generate_image',
        'generate_audio',
        'view_image',
        'generate_sound_effect',
        'generate_music',
      ]),
    );
    for (final tool in creative) {
      expect(tool.category.onAppsScreen, isTrue, reason: tool.name);
      expect(tool.category.needsTelegram, isFalse, reason: tool.name);
    }
    for (final tool in [generateSoundEffectTool, generateMusicTool]) {
      expect(
        creativeToolNeeds(tool, const AppSettings()),
        contains('ElevenLabs'),
      );
      expect(
        creativeToolNeeds(tool, const AppSettings(elevenKey: 'test-key')),
        isNull,
      );
    }
  });

  group('ElevenLabs creative audio', () {
    late omni.OmniAI ai;
    final requests = <http.Request>[];

    setUp(() {
      requests.clear();
      ai = omni.OmniAI(
        elevenLabsKey: 'test-eleven-key',
        keyStore: omni.MemoryKeyStore(),
        loadSavedKeys: false,
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response.bytes(
            [0x49, 0x44, 0x33, 0],
            200,
            headers: {'content-type': 'audio/mpeg'},
          );
        }),
      );
    });
    tearDown(() => ai.dispose());

    test(
      'sound effects send duration, influence and looping to ElevenLabs',
      () async {
        final audio = await generateElevenLabsAudio(ai, {
          'prompt': '  Rain on a window  ',
          'duration_seconds': 5.5,
          'prompt_influence': 0.6,
          'loop': true,
        }, music: false);
        final request = requests.single;
        expect(
          request.url.toString(),
          'https://api.elevenlabs.io/v1/sound-generation',
        );
        expect(request.headers['xi-api-key'], 'test-eleven-key');
        expect(jsonDecode(request.body), {
          'text': 'Rain on a window',
          'duration_seconds': 5.5,
          'prompt_influence': 0.6,
          'loop': true,
        });
        expect(audio.extension, 'mp3');
        expect(audio.bytes, [0x49, 0x44, 0x33, 0]);
      },
    );

    test('music uses milliseconds and defaults to 30 seconds', () async {
      await generateElevenLabsAudio(ai, {
        'prompt': 'A quiet piano score',
      }, music: true);
      expect(requests.single.url.path, '/v1/music');
      expect(jsonDecode(requests.single.body)['music_length_ms'], 30000);
      requests.clear();
      await generateElevenLabsAudio(ai, {
        'prompt': 'Jazz',
        'duration_seconds': 12.5,
      }, music: true);
      expect(jsonDecode(requests.single.body)['music_length_ms'], 12500);
    });

    test('invalid input makes no billable request', () {
      for (final args in <Map<String, dynamic>>[
        {'prompt': '  '},
        {'prompt': 'Rain', 'duration_seconds': -1},
        {'prompt': 'Rain', 'duration_seconds': double.nan},
        {'prompt': 'Rain', 'prompt_influence': 1.1},
      ]) {
        expect(
          () => generateElevenLabsAudio(ai, args, music: false),
          throwsArgumentError,
        );
      }
      expect(requests, isEmpty);
    });

    test('cancelled generation makes no billable request', () async {
      final token = omni.CancelToken()..cancel();
      await expectLater(
        generateElevenLabsAudio(
          ai,
          {'prompt': 'Jazz'},
          music: true,
          cancelToken: token,
        ),
        throwsA(isA<omni.AiCancelledException>()),
      );
      expect(requests, isEmpty);
    });

    test('provider errors reach the caller', () async {
      ai.dispose();
      ai = omni.OmniAI(
        elevenLabsKey: 'restricted-test-key',
        keyStore: omni.MemoryKeyStore(),
        loadSavedKeys: false,
        httpClient: MockClient(
          (_) async =>
              http.Response('{"detail":{"message":"Not permitted"}}', 403),
        ),
      );
      await expectLater(
        generateElevenLabsAudio(ai, {'prompt': 'Jazz'}, music: true),
        throwsA(isA<omni.AiException>()),
      );
    });
  });

  group('image sources', () {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    late Directory root;
    late ImageInputLoader loader;
    late MockClient client;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('triangle-image-input-');
      client = MockClient((request) async {
        if (request.url.path == '/missing') {
          return http.Response('Missing', 404);
        }
        if (request.url.path == '/page') {
          return http.Response('<html>Not an image</html>', 200);
        }
        return http.Response.bytes(
          png,
          200,
          headers: {'content-type': 'application/octet-stream'},
        );
      });
      loader = ImageInputLoader(
        directory: Directory('${root.path}/images'),
        httpClient: client,
      );
    });
    tearDown(() async {
      loader.close();
      client.close();
      await root.delete(recursive: true);
    });

    test('local extensionless files and file URLs are decoded', () async {
      final source = await File('${root.path}/screenshot').writeAsBytes(png);
      for (final input in [source.path, source.uri.toString()]) {
        final output = await loader.load(input);
        expect(output.path, endsWith('.png'));
        expect(await output.length(), greaterThan(0));
      }
    });

    test(
      'direct web images and inline data URLs produce model-readable PNGs',
      () async {
        for (final input in [
          'https://example.test/image?id=1',
          'data:image/png;base64,${base64Encode(png)}',
        ]) {
          final output = await loader.load(input);
          expect((await output.readAsBytes()).take(8), [
            137,
            80,
            78,
            71,
            13,
            10,
            26,
            10,
          ]);
        }
      },
    );

    test('missing images, webpages and non-image data fail clearly', () async {
      await expectLater(
        loader.load('https://example.test/missing'),
        throwsA(isA<HttpException>()),
      );
      await expectLater(
        loader.load('https://example.test/page'),
        throwsA(anything),
      );
      await expectLater(
        loader.load('data:text/plain;base64,aGVsbG8='),
        throwsFormatException,
      );
      await expectLater(loader.load(''), throwsFormatException);
    });
  });
}
