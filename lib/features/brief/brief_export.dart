import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../app/theme.dart';
import '../../core/widgets/app_sheet.dart';
import '../canvas/canvas_export.dart' show pdfTheme;
import 'brief_store.dart';

/// A brief as a file to keep, print or send, or as text to paste.

final _when = DateFormat('EEE d MMM y, HH:mm');
final _short = DateFormat('d MMM HH:mm');

/// Post links ([Name](post:1:2)) read as the name outside the app.
String _plainRefs(String text) => text.replaceAllMapped(RegExp(r'\[([^\]]+)\]\(post:[^)]+\)'), (m) => m[1]!);

String _title(Brief b) => '${b.kind.label} · ${_when.format(b.at)}';

String _fileName(Brief b, String extension) =>
    'triangle-${b.kind.name}-brief-${DateFormat('yyyy-MM-dd-HHmm').format(b.at)}.$extension';

/// [b] as Markdown, as written, with a heading and the window it covers.
String briefToMarkdown(Brief b) => [
  '# ${b.kind.emoji} ${_title(b)}',
  '',
  '_Covers ${_short.format(b.since)} to ${_short.format(b.at)}_',
  '',
  _plainRefs(b.text).trim(),
  '',
].join('\n');

/// [b] as plain text, for the clipboard.
String briefToText(Brief b) => [
  _title(b),
  'Covers ${_short.format(b.since)} to ${_short.format(b.at)}',
  '',
  _plainRefs(b.text)
      .replaceAll(RegExp(r'^#+\s*', multiLine: true), '')
      .replaceAll('**', '')
      .replaceAll(RegExp(r'(?<!\w)_(.+?)_(?!\w)'), r'$1')
      .trim(),
].join('\n');

/// [b] as a PDF, set like the chat and canvas exports: headings, bullets
/// and bold kept, links as their names.
Future<Uint8List> briefToPdf(Brief b) async {
  final doc = pw.Document(theme: await pdfTheme(), title: _title(b), creator: 'Triangle');
  const muted = PdfColor.fromInt(0xFF6C6C76);
  const rule = PdfColor.fromInt(0xFFE3E3E8);

  // Bold runs (**like this**) inside a line.
  pw.Widget rich(String line, {double size = 10.5}) {
    final spans = <pw.TextSpan>[];
    final parts = line.split('**');
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;
      spans.add(pw.TextSpan(text: parts[i], style: i.isOdd ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null));
    }
    return pw.RichText(text: pw.TextSpan(style: pw.TextStyle(fontSize: size, lineSpacing: 2), children: spans));
  }

  final body = <pw.Widget>[];
  for (final raw in _plainRefs(b.text).split('\n')) {
    final line = raw.trimRight();
    if (line.trim().isEmpty) {
      body.add(pw.SizedBox(height: 6));
      continue;
    }
    final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line.trim());
    final bullet = RegExp(r'^(\s*)[-*•]\s+(.*)$').firstMatch(line);
    if (heading != null) {
      final level = heading[1]!.length;
      body.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8, bottom: 3),
          child: rich(heading[2]!.replaceAll('**', ''), size: level <= 1 ? 16 : (level == 2 ? 13.5 : 12)),
        ),
      );
    } else if (bullet != null) {
      final indent = (bullet[1]!.length / 2).clamp(0, 4) * 12.0;
      body.add(
        pw.Padding(
          padding: pw.EdgeInsets.only(left: indent, bottom: 2),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(width: 10, child: pw.Text('•', style: const pw.TextStyle(fontSize: 10.5))),
              pw.Expanded(child: rich(bullet[2]!)),
            ],
          ),
        ),
      );
    } else {
      body.add(pw.Padding(padding: const pw.EdgeInsets.only(bottom: 2), child: rich(line.trim())));
    }
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 44, 40, 44),
      footer: (ctx) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Triangle · ${b.kind.label}', style: const pw.TextStyle(fontSize: 8, color: muted)),
          pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: muted)),
        ],
      ),
      build: (ctx) => [
        pw.Text(b.kind.label, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4, bottom: 10),
          child: pw.Text(
            '${_when.format(b.at)} · covers ${_short.format(b.since)} to ${_short.format(b.at)}',
            style: const pw.TextStyle(color: muted, fontSize: 9),
          ),
        ),
        pw.Divider(color: rule, thickness: 0.6),
        ...body,
      ],
    ),
  );
  return doc.save();
}

/// Export choices for [b]: a PDF or Markdown file, or the text copied.
Future<void> showBriefExportSheet(BuildContext context, Brief b) => showFormSheet<void>(
  context,
  builder: (sheet) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Export brief', style: sheet.text.titleMedium),
      const SizedBox(height: Space.xs),
      Text('${b.kind.emoji} ${_title(b)}', style: sheet.text.bodySmall),
      const SizedBox(height: Space.l),
      for (final (icon, label, hint, kind) in const [
        (Icons.picture_as_pdf_outlined, 'PDF', 'To read, print or share', 'pdf'),
        (Icons.description_outlined, 'Markdown', 'Plain text with formatting, for notes apps', 'md'),
        (Icons.copy_rounded, 'Copy text', 'To paste into a message or email', 'copy'),
      ])
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: lead(Icon(icon)),
          title: Text(label),
          subtitle: Text(hint, style: sheet.text.bodySmall),
          trailing: Icon(kind == 'copy' ? Icons.content_paste_rounded : Icons.download_rounded),
          onTap: () async {
            Navigator.pop(sheet);
            try {
              if (kind == 'copy') {
                await Clipboard.setData(ClipboardData(text: briefToText(b)));
                if (context.mounted) showSnack(context, 'Brief copied', icon: Icons.copy_rounded);
                return;
              }
              final bytes = kind == 'pdf' ? await briefToPdf(b) : Uint8List.fromList(utf8.encode(briefToMarkdown(b)));
              final saved = await FilePicker.saveFile(
                fileName: _fileName(b, kind),
                bytes: bytes,
                mimeType: kind == 'pdf' ? 'application/pdf' : 'text/markdown',
              );
              if (saved != null && context.mounted) showSnack(context, 'Brief exported');
            } catch (e) {
              if (context.mounted) showSnack(context, 'Couldn\'t export: $e', icon: Icons.error_outline_rounded);
            }
          },
        ),
    ],
  ),
);
