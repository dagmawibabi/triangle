import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/omni_ai.dart' show VapiCall;
import 'package:teleai/features/development/manage/app_managers.dart' show vapiSafeCall;

void main() {
  test('calls with strings where objects belong still parse', () {
    final raw = {
      'id': 'call_1',
      'status': 'ended',
      'customer': '+251911000000',
      'analysis': 'They have it in stock until 8pm.',
      'monitor': 'none',
      'artifact': {'recording': 'https://rec.example/a.wav', 'messages': 'oops', 'transcript': 'Agent: hi'},
      'cost': '0.12',
    };
    expect(() => VapiCall.fromJson(raw), throwsA(anything));
    final c = VapiCall.fromJson(vapiSafeCall(raw));
    expect(c.customerNumber, '+251911000000');
    expect(c.summary, 'They have it in stock until 8pm.');
    expect(c.recordingUrl, 'https://rec.example/a.wav');
    expect(c.transcript, 'Agent: hi');
  });

  test('a normal call is left as it was', () {
    final c = VapiCall.fromJson(vapiSafeCall({
      'id': 'call_2',
      'status': 'in-progress',
      'customer': {'number': '+1', 'name': 'Bob'},
      'analysis': {'summary': 'ok', 'successEvaluation': 'true'},
      'artifact': {'messages': [{'role': 'bot', 'message': 'Hello'}]},
      'cost': 0.5,
    }));
    expect(c.customerName, 'Bob');
    expect(c.summary, 'ok');
    expect(c.lines.single.text, 'Hello');
    expect(c.cost, 0.5);
    expect(c.isLive, isTrue);
  });
}
