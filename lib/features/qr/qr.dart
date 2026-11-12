import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/theme.dart';
import '../../core/files/generated_files.dart';
import '../telegram/presentation/link_opener.dart' show appNavigatorKey;

/// QR codes: what goes in one (a link, Wi-Fi, a contact…), drawing it to
/// a picture, reading codes from a picture, and scanning with the camera.
abstract final class Qr {
  /// The text a QR code holds for [kind] and its [f]ields.
  static String payload(String kind, Map<String, dynamic> f) {
    String v(String k) => '${f[k] ?? ''}'.trim();
    String esc(String s) => s.replaceAllMapped(RegExp(r'([\\;,:"])'), (m) => '\\${m[1]}');
    return switch (kind) {
      'wifi' => 'WIFI:T:${v('security').isEmpty ? (v('password').isEmpty ? 'nopass' : 'WPA') : v('security').toUpperCase()};S:${esc(v('ssid'))};P:${esc(v('password'))};${f['hidden'] == true ? 'H:true;' : ''};',
      'contact' => [
        'BEGIN:VCARD',
        'VERSION:3.0',
        'N:${v('last_name')};${v('first_name').isEmpty ? v('name') : v('first_name')};;;',
        'FN:${v('name').isEmpty ? '${v('first_name')} ${v('last_name')}'.trim() : v('name')}',
        if (v('phone').isNotEmpty) 'TEL:${v('phone')}',
        if (v('email').isNotEmpty) 'EMAIL:${v('email')}',
        if (v('organization').isNotEmpty) 'ORG:${v('organization')}',
        if (v('title').isNotEmpty) 'TITLE:${v('title')}',
        if (v('url').isNotEmpty) 'URL:${v('url')}',
        if (v('address').isNotEmpty) 'ADR:;;${v('address')};;;;',
        'END:VCARD',
      ].join('\n'),
      'phone' => 'tel:${v('phone')}',
      'sms' => 'SMSTO:${v('phone')}:${v('text')}',
      'email' => 'mailto:${v('email')}${[if (v('subject').isNotEmpty) 'subject=${Uri.encodeComponent(v('subject'))}', if (v('text').isNotEmpty) 'body=${Uri.encodeComponent(v('text'))}'].isEmpty ? '' : '?${[if (v('subject').isNotEmpty) 'subject=${Uri.encodeComponent(v('subject'))}', if (v('text').isNotEmpty) 'body=${Uri.encodeComponent(v('text'))}'].join('&')}'}',
      'geo' => 'geo:${v('latitude')},${v('longitude')}',
      'url' => v('url').contains('://') ? v('url') : 'https://${v('url')}',
      _ => v('text'),
    };
  }

  /// What a QR code's text is, with its parts: a link, Wi-Fi, a contact…
  static Map<String, dynamic> parse(String raw) {
    final s = raw.trim();
    final lower = s.toLowerCase();
    Map<String, String> fields(String body) {
      final out = <String, String>{};
      for (final m in RegExp(r'([A-Za-z]+):((?:\\.|[^;])*);').allMatches(body)) {
        out[m[1]!.toUpperCase()] = m[2]!.replaceAllMapped(RegExp(r'\\(.)'), (x) => x[1]!);
      }
      return out;
    }

    if (lower.startsWith('wifi:')) {
      final f = fields(s.substring(5));
      return {'type': 'wifi', 'ssid': f['S'], 'password': f['P'], 'security': f['T'] ?? 'nopass', 'hidden': f['H'] == 'true'};
    }
    if (lower.startsWith('begin:vcard')) {
      String? line(String k) => RegExp('^$k[^:]*:(.*)\$', multiLine: true, caseSensitive: false).firstMatch(s)?[1]?.trim();
      return {
        'type': 'contact',
        'name': line('FN') ?? line('N')?.replaceAll(';', ' ').trim(),
        'phone': line('TEL'),
        'email': line('EMAIL'),
        'organization': line('ORG'),
        'title': line('TITLE'),
        'url': line('URL'),
        'address': line('ADR')?.replaceAll(';', ' ').trim(),
      };
    }
    if (lower.startsWith('mecard:')) {
      final f = fields(s.substring(7));
      return {'type': 'contact', 'name': f['N']?.replaceAll(',', ' '), 'phone': f['TEL'], 'email': f['EMAIL'], 'url': f['URL'], 'address': f['ADR']};
    }
    if (lower.startsWith('tel:')) return {'type': 'phone', 'phone': s.substring(4)};
    if (lower.startsWith('smsto:') || lower.startsWith('sms:')) {
      final parts = s.substring(s.indexOf(':') + 1).split(':');
      return {'type': 'sms', 'phone': parts.first, 'text': parts.skip(1).join(':')};
    }
    if (lower.startsWith('mailto:')) {
      final u = Uri.tryParse(s);
      return {'type': 'email', 'email': u?.path, 'subject': u?.queryParameters['subject'], 'text': u?.queryParameters['body']};
    }
    if (lower.startsWith('geo:')) {
      final p = s.substring(4).split(RegExp('[,?]'));
      return {'type': 'geo', 'latitude': p.isNotEmpty ? p[0] : null, 'longitude': p.length > 1 ? p[1] : null};
    }
    final url = Uri.tryParse(s);
    if (url != null && (url.scheme == 'http' || url.scheme == 'https') && url.host.isNotEmpty && !s.contains(' ')) {
      return {'type': 'url', 'url': s, 'host': url.host};
    }
    if (RegExp(r'^[\w.-]+\.[a-z]{2,}(/\S*)?$', caseSensitive: false).hasMatch(s)) return {'type': 'url', 'url': 'https://$s', 'host': s.split('/').first};
    return {'type': 'text', 'text': s};
  }

  /// Draws [data] as a QR code with a white margin and saves it as a PNG.
  static Future<File> save(String data, {int size = 900, String name = 'qr'}) async {
    final painter = QrPainter(
      data: data,
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
      gapless: true,
      eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
      dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
    );
    final margin = size * 0.08;
    final total = size + margin * 2;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..drawRect(Rect.fromLTWH(0, 0, total, total), Paint()..color = Colors.white);
    canvas.translate(margin, margin);
    painter.paint(canvas, Size(size.toDouble(), size.toDouble()));
    final image = await recorder.endRecording().toImage(total.round(), total.round());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final safe = name.replaceAll(RegExp(r'[^\w\- ]'), '').trim();
    return saveGeneratedBytes('${safe.isEmpty ? 'qr' : safe}.png', bytes!.buffer.asUint8List(), folder: 'exports');
  }

  /// Whether [data] fits in a QR code.
  static bool fits(String data) => QrValidator.validate(data: data, version: QrVersions.auto, errorCorrectionLevel: QrErrorCorrectLevel.M).status == QrValidationStatus.valid;

  /// Every QR and barcode in the picture at [path].
  static Future<List<Map<String, dynamic>>> read(String path) async {
    final controller = MobileScannerController(autoStart: false);
    try {
      final capture = await controller.analyzeImage(path);
      return [for (final b in capture?.barcodes ?? const <Barcode>[]) if ((b.rawValue ?? '').isNotEmpty) _describe(b)];
    } finally {
      await controller.dispose();
    }
  }

  static Map<String, dynamic> _describe(Barcode b) => {
    'value': b.rawValue,
    'format': b.format.name,
    ...parse(b.rawValue ?? ''),
  };

  /// Opens the camera full screen until a code is seen (or the person
  /// closes it). Null when closed or when no screen is open.
  static Future<Map<String, dynamic>?> scan({String? prompt}) async {
    final nav = appNavigatorKey.currentState;
    if (nav == null) return null;
    final b = await nav.push<Barcode>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => _ScanScreen(prompt: prompt)));
    return b == null ? null : _describe(b);
  }
}

class _ScanScreen extends StatefulWidget {
  const _ScanScreen({this.prompt});
  final String? prompt;

  @override
  State<_ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<_ScanScreen> {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final box = MediaQuery.sizeOf(context).width * 0.7;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Scan a code'),
        actions: [
          IconButton(tooltip: 'Torch', icon: const Icon(Icons.flashlight_on_outlined), onPressed: () => _controller.toggleTorch()),
          IconButton(tooltip: 'Switch camera', icon: const Icon(Icons.cameraswitch_outlined), onPressed: () => _controller.switchCamera()),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              if (_done) return;
              final b = capture.barcodes.where((x) => (x.rawValue ?? '').isNotEmpty).firstOrNull;
              if (b == null) return;
              _done = true;
              Navigator.of(context).pop(b);
            },
          ),
          // A clear window over a dimmed view, so it's obvious where to aim.
          ColorFiltered(
            colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.55), BlendMode.srcOut),
            child: Stack(
              children: [
                Container(decoration: const BoxDecoration(color: Colors.black, backgroundBlendMode: BlendMode.dstOut)),
                Center(
                  child: Container(width: box, height: box, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24))),
                ),
              ],
            ),
          ),
          Center(
            child: Container(
              width: box,
              height: box,
              decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 2.5), borderRadius: BorderRadius.circular(24)),
            ),
          ),
          Positioned(
            left: Space.xl,
            right: Space.xl,
            bottom: MediaQuery.paddingOf(context).bottom + Space.x4,
            child: Text(
              widget.prompt ?? 'Point the camera at a QR code or barcode',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
