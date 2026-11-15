import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teleai/features/chat/presentation/widgets/dev/dev_card_kit.dart' show looksLikeHtml;
import 'package:teleai/features/chat/presentation/widgets/dev/vercel_cards.dart' show highlightLog;
import 'package:teleai/features/parcels/parcel_api.dart';
import 'package:teleai/features/telegram/data/telegram_tools.dart';

void main() {
  test('carriers are guessed from the number', () {
    expect(guessCarriers('1Z999AA10123456784').first.name, 'UPS');
    expect(guessCarriers('RR123456785ET').first.name, 'Ethiopian Postal Service');
    expect(guessCarriers('9400111899223817345678').first.name, 'USPS');
    expect(guessCarriers('anything').map((g) => g.name), contains('17TRACK (any carrier)'));
  });

  test('a 17TRACK answer reads as status, latest scan and timeline', () {
    final s = parcelSummary('RR1', {
      'number': 'RR1',
      'track_info': {
        'latest_status': {'status': 'OutForDelivery', 'sub_status': 'OutForDelivery_Other'},
        'shipping_info': {'shipper_address': {'country': 'CN'}, 'recipient_address': {'country': 'ET'}},
        'time_metrics': {'days_of_transit': 9, 'estimated_delivery_date': {'to': '2026-11-20T00:00:00Z'}},
        'tracking': {
          'providers': [
            {
              'provider': {'name': 'Ethiopian Post'},
              'events': [
                {'time_iso': '2026-11-10T08:00:00Z', 'description': 'Accepted', 'location': 'Shenzhen'},
                {'time_iso': '2026-11-15T08:00:00Z', 'description': 'Out for delivery', 'location': 'Addis Ababa'},
              ],
            },
          ],
        },
      },
    });
    expect(s['status_label'], 'Out for delivery');
    expect(s['carrier'], 'Ethiopian Post');
    expect((s['latest'] as Map)['text'], 'Out for delivery');
    expect((s['events'] as List).length, 2);
    expect(s['to'], 'ET');
    expect(parcelSummary('X', null)['status'], 'Pending');
  });

  test('package tools are classified and documented', () {
    for (final n in ['track_package', 'tracked_packages', 'untrack_package']) {
      final t = toolNamed(n)!;
      expect(t.category, ToolCategory.parcels);
      expect(t.needsTelegram, isFalse);
    }
    expect(toolNamed('untrack_package')!.requiresApproval, isTrue);
    expect(toolNamed('track_package')!.access, ToolAccess.read);
  });

  test('build logs are coloured by meaning', () {
    Color? colorOf(String line, String word) {
      Color? found;
      void walk(TextSpan s) {
        if (s.text == word) found = s.style?.color;
        for (final c in s.children ?? const <InlineSpan>[]) {
          if (c is TextSpan) walk(c);
        }
      }

      for (final s in highlightLog(line)) {
        walk(s);
      }
      return found;
    }

    expect(colorOf('npm ERR! code ELIFECYCLE', 'ERR!'), const Color(0xFFFF6B6B));
    expect(colorOf('Build Completed in 12s', '12s'), const Color(0xFF67E8F9));
    expect(colorOf('warning: unused var', 'warning'), const Color(0xFFFFC857));
    expect(colorOf('Compiled successfully', 'successfully'), const Color(0xFF4ADE80));
  });

  test('HTML code blocks get a preview', () {
    expect(looksLikeHtml('<!DOCTYPE html><html></html>', ''), isTrue);
    expect(looksLikeHtml('<div></div>', 'html'), isTrue);
    expect(looksLikeHtml('print(1)', 'python'), isFalse);
  });
}
