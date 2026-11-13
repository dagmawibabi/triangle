import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teleai/core/files/generated_files.dart';

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('names'));
  tearDown(() => dir.delete(recursive: true));

  String name(File f) => f.uri.pathSegments.last;

  test('a file keeps its own name', () async {
    expect(name(await claimFile(dir, 'report.pdf')), 'report.pdf');
  });

  test('a taken name is numbered at the end, like a browser', () async {
    final a = await claimFile(dir, 'report.pdf');
    await a.writeAsString('first');
    expect(name(await claimFile(dir, 'report.pdf')), 'report (2).pdf');
    expect(name(await claimFile(dir, 'report.pdf')), 'report (3).pdf');
    expect(await a.readAsString(), 'first', reason: 'the earlier file is never replaced');
    expect(name(await claimFile(dir, 'notes')), 'notes');
    expect(name(await claimFile(dir, 'notes')), 'notes (2)');
  });

  test('saves at the same time get different names', () async {
    final files = await Future.wait([for (var i = 0; i < 5; i++) claimFile(dir, 'same.txt')]);
    expect(files.map(name).toSet(), hasLength(5));
  });

  test('names in any script stay as they are; only impossible characters change', () {
    expect(safeFileName('ሪፖርት 2026.pdf'), 'ሪፖርት 2026.pdf');
    expect(safeFileName('تقرير.docx'), 'تقرير.docx');
    expect(safeFileName('a:b*c?.txt'), 'a_b_c_.txt');
    expect(safeFileName('folder/inner/photo.jpg'), 'photo.jpg');
    expect(safeFileName('..hidden'), 'hidden');
    expect(safeFileName('   '), 'file');
  });
}
