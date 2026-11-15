import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

// Every readable format becomes the same thing: a list of blocks
// (headings, paragraphs, quotes, pictures, rules) and a table of contents
// pointing into it. The reader, search, highlights and progress all work on
// blocks, whatever the book was. (The approach of the Alexandria reader.)

enum BlockType { heading, paragraph, quote, image, rule }

/// Spaces, and the Ethiopic word and sentence marks.
final wordBreak = RegExp(r'[\s፡-፨]+');
int countWords(String s) => s.split(wordBreak).where((w) => w.isNotEmpty).length;

class Block {
  const Block(this.type, {this.text = '', this.level = 0, this.image});
  final BlockType type;
  final String text;
  final int level;
  final String? image;

  int get words => countWords(text);

  Map<String, dynamic> toJson() => {'t': type.index, if (text.isNotEmpty) 'x': text, if (level != 0) 'l': level, if (image != null) 'i': image};
  factory Block.fromJson(Map j) => Block(BlockType.values[(j['t'] as num).toInt()], text: '${j['x'] ?? ''}', level: (j['l'] as num?)?.toInt() ?? 0, image: j['i'] as String?);
}

class TocEntry {
  const TocEntry(this.title, this.block, {this.depth = 0});
  final String title;
  final int block;
  final int depth;

  Map<String, dynamic> toJson() => {'t': title, 'b': block, 'd': depth};
  factory TocEntry.fromJson(Map j) => TocEntry('${j['t']}', (j['b'] as num).toInt(), depth: (j['d'] as num?)?.toInt() ?? 0);
}

class ParsedDoc {
  ParsedDoc({required this.blocks, required this.toc, this.title, this.author, this.description, this.publisher, this.language, this.year, this.coverBytes});
  final List<Block> blocks;
  final List<TocEntry> toc;
  final String? title;
  final String? author;
  final String? description;
  final String? publisher;
  final String? language;
  final String? year;

  /// Only right after parsing; not kept.
  final List<int>? coverBytes;

  late final int wordCount = blocks.fold(0, (s, b) => s + b.words);

  /// Words before each block, for progress and time left.
  late final List<int> wordOffsets = () {
    final out = List<int>.filled(blocks.length + 1, 0);
    for (var i = 0; i < blocks.length; i++) {
      out[i + 1] = out[i] + blocks[i].words;
    }
    return out;
  }();

  /// The chapters as block ranges: from each TOC entry to the next, or
  /// slices of about 80 blocks when there's no table of contents.
  late final List<({String title, int start, int end})> sections = () {
    final out = <({String title, int start, int end})>[];
    final tops = [for (final e in toc) if (e.depth == 0) e];
    final marks = tops.length >= 2 ? tops : toc;
    if (marks.isEmpty) {
      for (var i = 0; i < blocks.length; i += 80) {
        out.add((title: 'Part ${i ~/ 80 + 1}', start: i, end: (i + 80).clamp(0, blocks.length)));
      }
    } else {
      if (marks.first.block > 0) out.add((title: 'Beginning', start: 0, end: marks.first.block));
      for (var i = 0; i < marks.length; i++) {
        final end = i + 1 < marks.length ? marks[i + 1].block : blocks.length;
        if (end > marks[i].block) out.add((title: marks[i].title, start: marks[i].block, end: end));
      }
    }
    if (out.isEmpty) out.add((title: 'Text', start: 0, end: blocks.length));
    return out;
  }();

  int sectionOf(int block) {
    for (var i = sections.length - 1; i >= 0; i--) {
      if (sections[i].start <= block) return i;
    }
    return 0;
  }

  Map<String, dynamic> toJson() => {'v': 1, 'blocks': [for (final b in blocks) b.toJson()], 'toc': [for (final e in toc) e.toJson()]};
  factory ParsedDoc.fromJson(Map j) => ParsedDoc(
    blocks: [for (final b in (j['blocks'] as List)) Block.fromJson(b as Map)],
    toc: [for (final e in (j['toc'] as List)) TocEntry.fromJson(e as Map)],
  );
}

/// The formats the reader opens itself; PDF has its own viewer.
const readableFormats = {'epub', 'docx', 'txt', 'md', 'markdown', 'html', 'htm', 'xhtml', 'fb2', 'rtf'};

/// Every format the library keeps (others open in another app).
const bookFormats = {...readableFormats, 'pdf', 'mobi', 'azw', 'azw3', 'djvu', 'doc', 'odt', 'cbz', 'cbr'};

String extOf(String name) => name.contains('.') ? name.split('.').last.toLowerCase() : '';

/// Parses the book at [path]; pictures go into [imageDir].
Future<ParsedDoc> parseBook(String path, Directory imageDir) async {
  final ext = extOf(path);
  final bytes = await File(path).readAsBytes();
  switch (ext) {
    case 'epub':
      return parseEpub(bytes, imageDir);
    case 'docx':
      return parseDocx(bytes, imageDir);
    case 'fb2':
      return parseFb2(utf8.decode(bytes, allowMalformed: true), imageDir);
    case 'html' || 'htm' || 'xhtml':
      final blocks = htmlToBlocks(utf8.decode(bytes, allowMalformed: true));
      return ParsedDoc(blocks: blocks, toc: headingsToc(blocks));
    case 'rtf':
      return parsePlain(_rtfToText(latin1.decode(bytes)));
    default:
      return parsePlain(utf8.decode(bytes, allowMalformed: true), markdown: ext == 'md' || ext == 'markdown');
  }
}

// ---- EPUB --------------------------------------------------------------------

Future<ParsedDoc> parseEpub(List<int> bytes, Directory imageDir) async {
  final zip = ZipDecoder().decodeBytes(bytes);
  final files = <String, ArchiveFile>{for (final f in zip.files) if (f.isFile) f.name: f};

  String? readText(String name) {
    final f = files[name] ?? files[Uri.decodeFull(name)];
    if (f == null) return null;
    return utf8.decode(f.content, allowMalformed: true);
  }

  final container = XmlDocument.parse(readText('META-INF/container.xml') ?? '<x/>');
  final opfPath = container.findAllElements('rootfile', namespace: '*').firstOrNull?.getAttribute('full-path') ??
      files.keys.firstWhere((n) => n.endsWith('.opf'), orElse: () => 'content.opf');
  final opfDir = p.posix.dirname(opfPath) == '.' ? '' : p.posix.dirname(opfPath);
  final opf = XmlDocument.parse(readText(opfPath) ?? '<package/>');

  String resolve(String base, String href) {
    final clean = Uri.decodeFull(href.split('#').first);
    return p.posix.normalize(base.isEmpty ? clean : p.posix.join(base, clean));
  }

  String? meta(String name) {
    final v = opf.findAllElements(name, namespace: '*').firstOrNull?.innerText.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  final manifest = <String, ({String href, String type, String props})>{};
  for (final item in opf.findAllElements('item', namespace: '*')) {
    final id = item.getAttribute('id');
    final href = item.getAttribute('href');
    if (id == null || href == null) continue;
    manifest[id] = (href: resolve(opfDir, href), type: item.getAttribute('media-type') ?? '', props: item.getAttribute('properties') ?? '');
  }

  List<int>? cover;
  var coverHref = manifest.values.where((m) => m.props.contains('cover-image')).firstOrNull?.href;
  if (coverHref == null) {
    final coverId = opf.findAllElements('meta', namespace: '*').where((m) => m.getAttribute('name') == 'cover').firstOrNull?.getAttribute('content');
    coverHref = manifest[coverId]?.href;
  }
  coverHref ??= manifest.entries.where((e) => e.value.type.startsWith('image/') && e.key.toLowerCase().contains('cover')).firstOrNull?.value.href;
  if (coverHref != null) cover = files[coverHref]?.content;

  final spine = opf.findAllElements('itemref', namespace: '*').map((e) => e.getAttribute('idref')).whereType<String>().toList();
  final blocks = <Block>[];
  final chapterStart = <String, int>{};
  final anchors = <String, int>{};
  final extracted = <String, String>{};
  await imageDir.create(recursive: true);

  for (final idref in spine) {
    final item = manifest[idref];
    if (item == null) continue;
    final src = readText(item.href);
    if (src == null) continue;
    final dir = p.posix.dirname(item.href) == '.' ? '' : p.posix.dirname(item.href);
    chapterStart[item.href] = blocks.length;

    String? resolveImage(String s) {
      final full = resolve(dir, s);
      if (extracted.containsKey(full)) return extracted[full];
      final f = files[full];
      if (f == null) return null;
      final out = File(p.join(imageDir.path, '${extracted.length}${p.extension(full)}'));
      out.writeAsBytesSync(f.content);
      return extracted[full] = out.path;
    }

    blocks.addAll(htmlToBlocks(src, resolveImage: resolveImage, baseIndex: blocks.length, onAnchor: (id, b) => anchors['${item.href}#$id'] = b));
  }

  var toc = <TocEntry>[];
  int? target(String base, String href) {
    final file = resolve(base, href);
    final frag = href.contains('#') ? href.split('#').last : null;
    if (frag != null && anchors.containsKey('$file#$frag')) return anchors['$file#$frag'];
    return chapterStart[file];
  }

  final navItem = manifest.values.where((m) => m.props.split(' ').contains('nav')).firstOrNull;
  if (navItem != null) {
    final navDir = p.posix.dirname(navItem.href) == '.' ? '' : p.posix.dirname(navItem.href);
    try {
      final navDoc = XmlDocument.parse((readText(navItem.href) ?? '<x/>').replaceAll('&nbsp;', '&#160;'));
      final nav = navDoc.findAllElements('nav', namespace: '*').where((n) => (n.getAttribute('epub:type') ?? n.getAttribute('type', namespace: '*') ?? '').contains('toc')).firstOrNull ??
          navDoc.findAllElements('nav', namespace: '*').firstOrNull;
      if (nav != null) {
        void walk(XmlElement ol, int depth) {
          for (final li in ol.childElements.where((e) => e.localName == 'li')) {
            final a = li.childElements.where((e) => e.localName == 'a' || e.localName == 'span').firstOrNull;
            final href = a?.getAttribute('href');
            final title = a?.innerText.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
            final b = href == null ? null : target(navDir, href);
            if (b != null && title.isNotEmpty) toc.add(TocEntry(title, b, depth: depth));
            for (final sub in li.childElements.where((e) => e.localName == 'ol')) {
              walk(sub, depth + 1);
            }
          }
        }

        for (final ol in nav.childElements.where((e) => e.localName == 'ol')) {
          walk(ol, 0);
        }
      }
    } catch (_) {}
  }

  if (toc.isEmpty) {
    final ncxId = opf.findAllElements('spine', namespace: '*').firstOrNull?.getAttribute('toc');
    final ncxHref = manifest[ncxId]?.href ?? manifest.values.where((m) => m.type.contains('dtbncx')).firstOrNull?.href;
    if (ncxHref != null) {
      final ncxDir = p.posix.dirname(ncxHref) == '.' ? '' : p.posix.dirname(ncxHref);
      try {
        final ncx = XmlDocument.parse(readText(ncxHref) ?? '<x/>');
        void walk(XmlElement parent, int depth) {
          for (final np in parent.childElements.where((e) => e.localName == 'navPoint')) {
            final title = np.findAllElements('text', namespace: '*').firstOrNull?.innerText.trim() ?? '';
            final src = np.findAllElements('content', namespace: '*').firstOrNull?.getAttribute('src');
            final b = src == null ? null : target(ncxDir, src);
            if (b != null && title.isNotEmpty) toc.add(TocEntry(title, b, depth: depth));
            walk(np, depth + 1);
          }
        }

        final map = ncx.findAllElements('navMap', namespace: '*').firstOrNull;
        if (map != null) walk(map, 0);
      } catch (_) {}
    }
  }

  if (toc.isEmpty) toc = headingsToc(blocks);
  toc.sort((a, b) => a.block.compareTo(b.block));

  return ParsedDoc(
    blocks: blocks,
    toc: toc,
    title: meta('title'),
    author: opf.findAllElements('creator', namespace: '*').map((e) => e.innerText.trim()).where((s) => s.isNotEmpty).join(', '),
    description: meta('description') == null ? null : stripTags(meta('description')!),
    publisher: meta('publisher'),
    language: meta('language'),
    year: RegExp(r'\d{4}').firstMatch(meta('date') ?? '')?.group(0),
    coverBytes: cover,
  );
}

List<TocEntry> headingsToc(List<Block> blocks) => [
  for (var i = 0; i < blocks.length; i++)
    if (blocks[i].type == BlockType.heading && blocks[i].level <= 2 && blocks[i].text.length < 120) TocEntry(blocks[i].text, i, depth: blocks[i].level - 1),
];

// ---- HTML --------------------------------------------------------------------

List<Block> htmlToBlocks(String source, {String? Function(String src)? resolveImage, void Function(String id, int block)? onAnchor, int baseIndex = 0}) {
  final doc = html.parse(source);
  final body = doc.body;
  if (body == null) return const [];
  final out = <Block>[];
  final buf = StringBuffer();

  void flush([BlockType type = BlockType.paragraph, int level = 0]) {
    final text = _clean(buf.toString());
    buf.clear();
    if (text.isEmpty) return;
    out.add(Block(type, text: text, level: level));
  }

  void walk(dom.Node node) {
    if (node is dom.Text) {
      buf.write(node.text);
      return;
    }
    if (node is! dom.Element) return;
    final tag = node.localName ?? '';
    final id = node.id;
    if (id.isNotEmpty) onAnchor?.call(id, baseIndex + out.length + (buf.toString().trim().isEmpty ? 0 : 1));
    switch (tag) {
      case 'script' || 'style' || 'head':
        return;
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        flush();
        buf.write(node.text);
        flush(BlockType.heading, int.parse(tag.substring(1)));
        return;
      case 'blockquote':
        flush();
        final inner = _clean(node.text);
        if (inner.isNotEmpty) out.add(Block(BlockType.quote, text: inner));
        return;
      case 'hr':
        flush();
        out.add(const Block(BlockType.rule));
        return;
      case 'br':
        buf.write('\n');
        return;
      case 'img' || 'image':
        final src = node.attributes['src'] ?? node.attributes['xlink:href'] ?? node.attributes['href'];
        if (src != null && resolveImage != null) {
          final path = resolveImage(src);
          if (path != null) {
            flush();
            out.add(Block(BlockType.image, image: path, text: node.attributes['alt'] ?? ''));
          }
        }
        return;
      case 'p' || 'div' || 'li' || 'section' || 'article' || 'tr' || 'dt' || 'dd' || 'figure' || 'figcaption' || 'pre' || 'table' || 'ul' || 'ol':
        flush();
        if (tag == 'li') buf.write('• ');
        for (final c in node.nodes) {
          walk(c);
        }
        flush();
        return;
      default:
        for (final c in node.nodes) {
          walk(c);
        }
    }
  }

  for (final n in body.nodes) {
    walk(n);
  }
  flush();
  return out;
}

String _clean(String s) => s
    .replaceAll('\u00AD', '')
    .replaceAll(RegExp(r'[ \t\r\f\u00A0]+'), ' ')
    .replaceAll(RegExp(r' *\n *'), '\n')
    .replaceAll(RegExp(r'\n{2,}'), '\n')
    .trim();

String stripTags(String s) => _clean(html.parse(s).body?.text ?? s);

// ---- DOCX --------------------------------------------------------------------

Future<ParsedDoc> parseDocx(List<int> bytes, Directory imageDir) async {
  final zip = ZipDecoder().decodeBytes(bytes);
  final files = <String, ArchiveFile>{for (final f in zip.files) if (f.isFile) f.name: f};
  String? text(String n) => files[n] == null ? null : utf8.decode(files[n]!.content, allowMalformed: true);
  final document = XmlDocument.parse(text('word/document.xml') ?? '<x/>');

  final styleNames = <String, String>{};
  final styles = text('word/styles.xml');
  if (styles != null) {
    for (final s in XmlDocument.parse(styles).findAllElements('style', namespace: '*')) {
      final id = s.getAttribute('w:styleId') ?? s.getAttribute('styleId', namespace: '*');
      final name = s.findElements('name', namespace: '*').firstOrNull?.getAttribute('w:val');
      if (id != null && name != null) styleNames[id] = name.toLowerCase();
    }
  }
  final rels = <String, String>{};
  final relXml = text('word/_rels/document.xml.rels');
  if (relXml != null) {
    for (final r in XmlDocument.parse(relXml).findAllElements('Relationship', namespace: '*')) {
      final id = r.getAttribute('Id');
      final target = r.getAttribute('Target');
      if (id != null && target != null) rels[id] = p.posix.normalize(target.startsWith('/') ? target.substring(1) : 'word/$target');
    }
  }
  await imageDir.create(recursive: true);
  var imageCount = 0;
  final blocks = <Block>[];
  for (final para in document.findAllElements('p', namespace: '*')) {
    if (para.name.prefix != 'w') continue;
    final pPr = para.findElements('pPr', namespace: '*').firstOrNull;
    final styleId = pPr?.findElements('pStyle', namespace: '*').firstOrNull?.getAttribute('w:val') ?? '';
    final styleName = styleNames[styleId] ?? styleId.toLowerCase();
    final outline = pPr?.findElements('outlineLvl', namespace: '*').firstOrNull?.getAttribute('w:val');
    final isList = pPr?.findElements('numPr', namespace: '*').isNotEmpty ?? false;
    final buf = StringBuffer();
    for (final node in para.descendants.whereType<XmlElement>()) {
      switch (node.localName) {
        case 't':
          buf.write(node.innerText);
        case 'tab':
          buf.write('\t');
        case 'br' || 'cr':
          buf.write('\n');
        case 'blip':
          final media = rels[node.getAttribute('r:embed')];
          final f = media == null ? null : files[media];
          if (f != null) {
            final out = File(p.join(imageDir.path, 'd${imageCount++}${p.extension(media!)}'));
            await out.writeAsBytes(f.content);
            if (buf.toString().trim().isNotEmpty) {
              blocks.add(Block(BlockType.paragraph, text: buf.toString().trim()));
              buf.clear();
            }
            blocks.add(Block(BlockType.image, image: out.path));
          }
      }
    }
    final s = buf.toString().replaceAll(RegExp(r'[ \u00A0]+'), ' ').trim();
    if (s.isEmpty) continue;
    final heading = RegExp(r'heading\s*(\d)').firstMatch(styleName);
    if (styleName == 'title') {
      blocks.add(Block(BlockType.heading, text: s, level: 1));
    } else if (styleName == 'subtitle') {
      blocks.add(Block(BlockType.heading, text: s, level: 3));
    } else if (heading != null) {
      blocks.add(Block(BlockType.heading, text: s, level: int.parse(heading.group(1)!).clamp(1, 6)));
    } else if (outline != null) {
      blocks.add(Block(BlockType.heading, text: s, level: (int.tryParse(outline) ?? 0) + 1));
    } else if (styleName.contains('quote')) {
      blocks.add(Block(BlockType.quote, text: s));
    } else {
      blocks.add(Block(BlockType.paragraph, text: isList ? '• $s' : s));
    }
  }
  String? core(String name) {
    final c = text('docProps/core.xml');
    if (c == null) return null;
    final v = XmlDocument.parse(c).findAllElements(name, namespace: '*').firstOrNull?.innerText.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  return ParsedDoc(blocks: blocks, toc: headingsToc(blocks), title: core('title'), author: core('creator'), description: core('description'), year: RegExp(r'\d{4}').firstMatch(core('created') ?? '')?.group(0));
}

// ---- FB2 ---------------------------------------------------------------------

Future<ParsedDoc> parseFb2(String src, Directory imageDir) async {
  final doc = XmlDocument.parse(src);
  final blocks = <Block>[];
  final toc = <TocEntry>[];
  await imageDir.create(recursive: true);
  final binaries = <String, String>{};
  for (final b in doc.findAllElements('binary', namespace: '*')) {
    final id = b.getAttribute('id');
    if (id == null) continue;
    try {
      final f = File(p.join(imageDir.path, 'f${binaries.length}.${(b.getAttribute('content-type') ?? 'image/jpeg').split('/').last}'));
      await f.writeAsBytes(base64Decode(b.innerText.replaceAll(RegExp(r'\s'), '')));
      binaries[id] = f.path;
    } catch (_) {}
  }
  void walk(XmlElement e, int depth) {
    for (final c in e.childElements) {
      switch (c.localName) {
        case 'section':
          walk(c, depth + 1);
        case 'title':
          final t = c.innerText.replaceAll(RegExp(r'\s+'), ' ').trim();
          if (t.isNotEmpty) {
            toc.add(TocEntry(t, blocks.length, depth: (depth - 1).clamp(0, 5)));
            blocks.add(Block(BlockType.heading, text: t, level: depth.clamp(1, 6)));
          }
        case 'p' || 'v' || 'subtitle' || 'text-author':
          final t = c.innerText.trim();
          if (t.isNotEmpty) blocks.add(Block(c.localName == 'subtitle' ? BlockType.heading : BlockType.paragraph, text: t, level: c.localName == 'subtitle' ? 4 : 0));
        case 'epigraph' || 'cite':
          final t = c.innerText.replaceAll(RegExp(r'\s+'), ' ').trim();
          if (t.isNotEmpty) blocks.add(Block(BlockType.quote, text: t));
        case 'empty-line':
          break;
        case 'image':
          final href = (c.getAttribute('l:href') ?? c.getAttribute('xlink:href') ?? c.getAttribute('href', namespace: '*') ?? '').replaceFirst('#', '');
          if (binaries[href] case final path?) blocks.add(Block(BlockType.image, image: path));
        default:
          walk(c, depth);
      }
    }
  }

  for (final body in doc.findAllElements('body', namespace: '*')) {
    walk(body, 0);
  }
  final info = doc.findAllElements('title-info', namespace: '*').firstOrNull;
  final author = info?.findAllElements('author', namespace: '*').map((a) => a.childElements.map((x) => x.innerText.trim()).where((x) => x.isNotEmpty).join(' ')).join(', ');
  final coverId = info?.findAllElements('image', namespace: '*').firstOrNull?.attributes.where((a) => a.name.local == 'href').firstOrNull?.value.replaceFirst('#', '');
  return ParsedDoc(
    blocks: blocks,
    toc: toc.isEmpty ? headingsToc(blocks) : toc,
    title: info?.findAllElements('book-title', namespace: '*').firstOrNull?.innerText.trim(),
    author: author,
    description: info?.findAllElements('annotation', namespace: '*').firstOrNull?.innerText.trim(),
    language: info?.findAllElements('lang', namespace: '*').firstOrNull?.innerText.trim(),
    coverBytes: coverId != null && binaries[coverId] != null ? File(binaries[coverId]!).readAsBytesSync() : null,
  );
}

// ---- plain text and Markdown ---------------------------------------------------

ParsedDoc parsePlain(String text, {bool markdown = false}) {
  final blocks = <Block>[];
  final paras = text.replaceAll('\r\n', '\n').split(RegExp(r'\n\s*\n'));
  for (final raw in paras) {
    final s = raw.trim();
    if (s.isEmpty) continue;
    final h = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(s);
    if (markdown && h != null && !s.contains('\n')) {
      blocks.add(Block(BlockType.heading, text: h.group(2)!.trim(), level: h.group(1)!.length));
    } else if (markdown && s.startsWith('>')) {
      blocks.add(Block(BlockType.quote, text: s.split('\n').map((l) => l.replaceFirst(RegExp(r'^>\s?'), '')).join('\n')));
    } else if (markdown && RegExp(r'^(-{3,}|\*{3,})$').hasMatch(s)) {
      blocks.add(const Block(BlockType.rule));
    } else if (!markdown && s.length < 70 && !s.contains('\n') && RegExp(r'^(chapter|part|book|ምዕራፍ|ክፍል)\b', caseSensitive: false).hasMatch(s)) {
      blocks.add(Block(BlockType.heading, text: s, level: 2));
    } else {
      final clean = markdown ? s.replaceAll(RegExp(r'(\*\*|__|`)'), '') : s;
      // Hard-wrapped lines join into one paragraph.
      blocks.add(Block(BlockType.paragraph, text: clean.replaceAll(RegExp(r'(?<![.!?:።])\n(?!\s*[-•*\d])'), ' ')));
    }
  }
  return ParsedDoc(blocks: blocks, toc: headingsToc(blocks));
}

String _rtfToText(String rtf) => rtf
    .replaceAll(RegExp(r'\\par[d]?'), '\n\n')
    .replaceAll(RegExp(r'\{\\\*[^{}]*\}'), '')
    .replaceAll(RegExp(r'\\[a-z]+-?\d* ?'), '')
    .replaceAll(RegExp(r'[{}]'), '');
