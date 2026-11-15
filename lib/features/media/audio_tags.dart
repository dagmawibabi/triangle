import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// What an audio file says about itself: ID3v2 tags (MP3s, and most songs
/// shared on Telegram), FLAC Vorbis comments and pictures, or MP4/M4A
/// atoms. Title, artist, album, year, genre, track number, the cover
/// picture, lyrics, and the stream's sample rate and channels.
class AudioTags {
  const AudioTags({
    this.title,
    this.artist,
    this.album,
    this.albumArtist,
    this.composer,
    this.year,
    this.genre,
    this.track,
    this.disc,
    this.bpm,
    this.comment,
    this.lyrics,
    this.publisher,
    this.picture,
    this.sampleRate,
    this.channels,
    this.bitrate,
    this.codec,
  });
  final String? title;
  final String? artist;
  final String? album;
  final String? albumArtist;
  final String? composer;
  final String? year;
  final String? genre;
  final String? track;
  final String? disc;
  final String? bpm;
  final String? comment;
  final String? lyrics;
  final String? publisher;
  final Uint8List? picture;

  /// Hz, from the first MP3 frame or the FLAC stream info.
  final int? sampleRate;
  final int? channels;

  /// kbps, from the first MP3 frame (constant bitrate files).
  final int? bitrate;
  final String? codec;

  static const empty = AudioTags();
  bool get isEmpty => title == null && artist == null && album == null && year == null && genre == null && picture == null && lyrics == null;

  /// For the player's details.
  Map<String, String> get info => {
    if (album != null) 'Album': album!,
    if (albumArtist != null && albumArtist != artist) 'Album artist': albumArtist!,
    if (composer != null) 'Composer': composer!,
    if (year != null) 'Year': year!,
    if (genre != null) 'Genre': genre!,
    if (track != null) 'Track': track!,
    if (disc != null && disc != '1') 'Disc': disc!,
    if (bpm != null) 'BPM': bpm!,
    if (publisher != null) 'Label': publisher!,
    if (codec != null) 'Codec': codec!,
    if (sampleRate != null) 'Sample rate': '${(sampleRate! / 1000).toStringAsFixed(sampleRate! % 1000 == 0 ? 0 : 1)} kHz',
    if (channels != null) 'Channels': channels == 1 ? 'Mono' : (channels == 2 ? 'Stereo' : '$channels ch'),
    if (bitrate != null) 'Bitrate': '$bitrate kbps',
    if (comment != null && comment!.length < 80) 'Comment': comment!,
  };
}

final _cache = <String, Future<AudioTags>>{};

/// The tags of the file at [path], read once per path.
Future<AudioTags> readAudioTags(String path) => _cache.putIfAbsent(path, () async {
  try {
    return await _read(path);
  } catch (_) {
    return AudioTags.empty;
  }
});

Future<AudioTags> _read(String path) async {
  final f = await File(path).open();
  try {
    final head = await f.read(12);
    if (head.length < 10) return AudioTags.empty;
    if (head[0] == 0x49 && head[1] == 0x44 && head[2] == 0x33) return await _id3(f, head);
    if (head[0] == 0x66 && head[1] == 0x4C && head[2] == 0x61 && head[3] == 0x43) return await _flac(f);
    if (head.length >= 8 && ascii.decode(head.sublist(4, 8), allowInvalid: true) == 'ftyp') return await _mp4(f);
    // A bare MP3 without tags: just the stream.
    final tech = _mp3Frame(Uint8List.fromList(head + await f.read(4096)), 0);
    return tech ?? AudioTags.empty;
  } finally {
    await f.close();
  }
}

// ---- ID3v2 -----------------------------------------------------------------

Future<AudioTags> _id3(RandomAccessFile f, List<int> head) async {
  final major = head[3];
  if (major < 2 || major > 4) return AudioTags.empty;
  final flags = head[5];
  final size = _syncsafe(head, 6);
  if (size <= 0 || size > 32 << 20) return AudioTags.empty;
  await f.setPosition(10);
  var body = await f.read(size);
  // The whole tag unsynchronised (v2.2/2.3): drop the 0x00 after every 0xFF.
  if (flags & 0x80 != 0 && major < 4) body = _deunsync(body);
  var start = 0;
  // An extended header to skip.
  if (flags & 0x40 != 0 && body.length > 4) {
    start = major == 4 ? _syncsafe(body, 0) : _plain(body, 0, 4) + 4;
    if (start < 0 || start >= body.length) start = 0;
  }
  final tags = _frames(body, major, start);
  // The stream after the tag: sample rate, channels, bitrate.
  await f.setPosition(10 + size + (flags & 0x10 != 0 ? 10 : 0));
  final after = await f.read(8192);
  final tech = _mp3Frame(after, 0);
  return tech == null ? tags : _merge(tags, tech);
}

AudioTags _merge(AudioTags a, AudioTags tech) => AudioTags(
  title: a.title,
  artist: a.artist,
  album: a.album,
  albumArtist: a.albumArtist,
  composer: a.composer,
  year: a.year,
  genre: a.genre,
  track: a.track,
  disc: a.disc,
  bpm: a.bpm,
  comment: a.comment,
  lyrics: a.lyrics,
  publisher: a.publisher,
  picture: a.picture,
  sampleRate: tech.sampleRate ?? a.sampleRate,
  channels: tech.channels ?? a.channels,
  bitrate: tech.bitrate ?? a.bitrate,
  codec: tech.codec ?? a.codec,
);

Uint8List _deunsync(Uint8List b) {
  final out = BytesBuilder(copy: false);
  for (var i = 0; i < b.length; i++) {
    out.addByte(b[i]);
    if (b[i] == 0xFF && i + 1 < b.length && b[i + 1] == 0x00) i++;
  }
  return out.toBytes();
}

int _syncsafe(List<int> b, int at) => (b[at] & 0x7f) << 21 | (b[at + 1] & 0x7f) << 14 | (b[at + 2] & 0x7f) << 7 | (b[at + 3] & 0x7f);
int _plain(List<int> b, int at, int n) {
  var v = 0;
  for (var i = 0; i < n; i++) {
    v = v << 8 | b[at + i];
  }
  return v;
}

AudioTags _frames(Uint8List b, int major, int start) {
  final text = <String, String>{};
  Uint8List? picture;
  var pictureIsFront = false;
  String? lyrics, comment;
  var i = start;
  final idLen = major == 2 ? 3 : 4;
  final headLen = major == 2 ? 6 : 10;
  while (i + headLen <= b.length) {
    if (b[i] == 0) break;
    final id = ascii.decode(b.sublist(i, i + idLen), allowInvalid: true);
    if (!RegExp(r'^[A-Z0-9]+$').hasMatch(id)) break;
    // Some v2.4 writers use plain sizes; trust syncsafe only if it fits.
    var len = major == 2 ? _plain(b, i + 3, 3) : (major == 4 ? _syncsafe(b, i + 4) : _plain(b, i + 4, 4));
    if (major == 4 && i + headLen + len > b.length) len = _plain(b, i + 4, 4);
    final fflags = major == 2 ? 0 : b[i + 9];
    final start = i + headLen;
    if (len <= 0 || start + len > b.length) break;
    var data = b.sublist(start, start + len);
    if (major == 4) {
      // A data length indicator, then the frame maybe unsynchronised.
      if (fflags & 0x01 != 0 && data.length > 4) data = data.sublist(4);
      if (fflags & 0x02 != 0) data = _deunsync(data);
    }
    if (data.isNotEmpty) {
      if (id.startsWith('T') && id != 'TXXX' && id != 'TXX') {
        final v = _decode(data.sublist(1), data[0]).trim();
        if (v.isNotEmpty) text[id] = v;
      } else if (id == 'APIC' || id == 'PIC') {
        final (pic, type) = _picture(data, major);
        // The front cover (type 3) wins over any other picture.
        if (pic != null && (picture == null || (type == 3 && !pictureIsFront))) {
          picture = pic;
          pictureIsFront = type == 3;
        }
      } else if ((id == 'USLT' || id == 'ULT') && data.length > 4) {
        lyrics ??= _afterDescription(data).trim();
      } else if ((id == 'COMM' || id == 'COM') && data.length > 4) {
        final c = _afterDescription(data).trim();
        if (c.isNotEmpty && !c.toLowerCase().contains('itunnorm')) comment ??= c;
      }
    }
    i = start + len;
  }
  String? t(List<String> ids) {
    for (final id in ids) {
      if (text[id] case final v?) return v;
    }
    return null;
  }

  var genre = t(['TCON', 'TCO']);
  // "(17)" or "17" are ID3v1 genre numbers; keep only the words.
  if (genre != null) {
    genre = genre.replaceAll(RegExp(r'^\(\d+\)'), '').trim();
    if (genre.isEmpty || RegExp(r'^\d+$').hasMatch(genre)) genre = null;
  }
  final year = t(['TDRC', 'TYER', 'TYE', 'TDOR', 'TORY']);
  return AudioTags(
    title: t(['TIT2', 'TT2']),
    artist: t(['TPE1', 'TP1', 'TPE2', 'TP2']),
    album: t(['TALB', 'TAL']),
    albumArtist: t(['TPE2', 'TP2']),
    composer: t(['TCOM', 'TCM']),
    year: year == null || year.length < 4 ? year : year.substring(0, 4),
    genre: genre,
    track: t(['TRCK', 'TRK'])?.split('/').first,
    disc: t(['TPOS', 'TPA'])?.split('/').first,
    bpm: t(['TBPM', 'TBP']),
    publisher: t(['TPUB', 'TPB']),
    comment: comment,
    lyrics: lyrics == null || lyrics.isEmpty ? null : lyrics,
    picture: picture,
  );
}

/// USLT/COMM: encoding, language, a description, then the text.
String _afterDescription(Uint8List d) {
  final enc = d[0];
  var i = 4;
  if (enc == 1 || enc == 2) {
    while (i + 1 < d.length && !(d[i] == 0 && d[i + 1] == 0)) {
      i += 2;
    }
    i += 2;
  } else {
    while (i < d.length && d[i] != 0) {
      i++;
    }
    i++;
  }
  if (i >= d.length) return '';
  return _decode(d.sublist(i), enc);
}

(Uint8List?, int) _picture(Uint8List d, int major) {
  if (d.isEmpty) return (null, 0);
  final enc = d[0];
  var i = 1;
  if (major == 2) {
    i += 3; // image format, e.g. "JPG"
  } else {
    while (i < d.length && d[i] != 0) {
      i++;
    }
    i++; // the mime type's terminator
  }
  final type = i < d.length ? d[i] : 0;
  i++; // picture type
  // The description, ending in one zero (or two for UTF-16).
  if (enc == 1 || enc == 2) {
    while (i + 1 < d.length && !(d[i] == 0 && d[i + 1] == 0)) {
      i += 2;
    }
    i += 2;
  } else {
    while (i < d.length && d[i] != 0) {
      i++;
    }
    i++;
  }
  if (i >= d.length) return (null, type);
  final pic = Uint8List.sublistView(d, i);
  return (_looksLikeImage(pic) ? pic : _findImage(pic), type);
}

bool _looksLikeImage(Uint8List b) =>
    b.length > 4 && ((b[0] == 0xFF && b[1] == 0xD8) || (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) || (b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46));

/// Some writers get the description wrong; find the JPEG or PNG start.
Uint8List? _findImage(Uint8List b) {
  final limit = b.length < 512 ? b.length - 4 : 512;
  for (var i = 0; i < limit; i++) {
    if ((b[i] == 0xFF && b[i + 1] == 0xD8 && b[i + 2] == 0xFF) || (b[i] == 0x89 && b[i + 1] == 0x50 && b[i + 2] == 0x4E && b[i + 3] == 0x47)) {
      return Uint8List.sublistView(b, i);
    }
  }
  return null;
}

String _decode(List<int> d, int enc) {
  switch (enc) {
    case 1:
    case 2:
      var bigEndian = enc == 2;
      var i = 0;
      if (d.length >= 2 && d[0] == 0xFF && d[1] == 0xFE) {
        bigEndian = false;
        i = 2;
      } else if (d.length >= 2 && d[0] == 0xFE && d[1] == 0xFF) {
        bigEndian = true;
        i = 2;
      }
      final units = <int>[];
      for (; i + 1 < d.length; i += 2) {
        final u = bigEndian ? d[i] << 8 | d[i + 1] : d[i + 1] << 8 | d[i];
        if (u == 0) break;
        units.add(u);
      }
      return String.fromCharCodes(units);
    case 3:
      final end = d.indexOf(0);
      return utf8.decode(end < 0 ? d : d.sublist(0, end), allowMalformed: true);
    default:
      final end = d.indexOf(0);
      final bytes = end < 0 ? d : d.sublist(0, end);
      // Many "Latin-1" tags are really UTF-8 (Amharic titles, for one).
      try {
        return utf8.decode(bytes);
      } catch (_) {
        return latin1.decode(bytes);
      }
  }
}

// ---- MP3 frame header ------------------------------------------------------------

AudioTags? _mp3Frame(List<int> b, int from) {
  const rates = {
    3: [44100, 48000, 32000],
    2: [22050, 24000, 16000],
    0: [11025, 12000, 8000],
  };
  const v1l3 = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320];
  const v2l3 = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160];
  for (var i = from; i + 4 < b.length; i++) {
    if (b[i] != 0xFF || (b[i + 1] & 0xE0) != 0xE0) continue;
    final version = (b[i + 1] >> 3) & 3;
    final layer = (b[i + 1] >> 1) & 3;
    final br = (b[i + 2] >> 4) & 0xF;
    final sr = (b[i + 2] >> 2) & 3;
    if (version == 1 || layer == 0 || br == 0 || br == 15 || sr == 3) continue;
    final rate = rates[version]![sr];
    final kbps = layer == 1 ? (version == 3 ? v1l3[br] : v2l3[br]) : null;
    final mode = (b[i + 3] >> 6) & 3;
    // A Xing/Info header means VBR: the frame's bitrate isn't the file's.
    final window = String.fromCharCodes(b.sublist(i, (i + 200).clamp(0, b.length)).map((c) => c >= 32 && c < 127 ? c : 32));
    final vbr = window.contains('Xing') || window.contains('VBRI');
    return AudioTags(
      sampleRate: rate,
      channels: mode == 3 ? 1 : 2,
      bitrate: vbr ? null : kbps,
      codec: layer == 1 ? (vbr ? 'MP3 (VBR)' : 'MP3') : 'MPEG audio',
    );
  }
  return null;
}

// ---- FLAC ------------------------------------------------------------------

Future<AudioTags> _flac(RandomAccessFile f) async {
  await f.setPosition(4);
  final text = <String, String>{};
  Uint8List? picture;
  int? rate, channels;
  for (var guard = 0; guard < 64; guard++) {
    final h = await f.read(4);
    if (h.length < 4) break;
    final last = h[0] & 0x80 != 0;
    final type = h[0] & 0x7F;
    final len = _plain(h, 1, 3);
    if (len > 24 << 20) break;
    if (type == 0 || type == 4 || type == 6) {
      final d = await f.read(len);
      if (type == 0 && d.length >= 18) {
        rate = (d[10] << 12) | (d[11] << 4) | (d[12] >> 4);
        channels = ((d[12] >> 1) & 7) + 1;
      } else if (type == 4) {
        _vorbis(d, text);
      } else if (type == 6 && d.length > 32) {
        final bd = ByteData.sublistView(d);
        final picType = bd.getUint32(0);
        var i = 4;
        final mimeLen = bd.getUint32(i);
        i += 4 + mimeLen;
        final descLen = bd.getUint32(i);
        i += 4 + descLen + 16;
        final dataLen = bd.getUint32(i);
        i += 4;
        if (i + dataLen <= d.length && (picture == null || picType == 3)) picture = Uint8List.sublistView(d, i, i + dataLen);
      }
    } else {
      await f.setPosition(await f.position() + len);
    }
    if (last) break;
  }
  return _fromVorbis(text, picture, rate, channels, 'FLAC');
}

void _vorbis(Uint8List d, Map<String, String> out) {
  if (d.length < 8) return;
  final bd = ByteData.sublistView(d);
  var i = 0;
  final vendor = bd.getUint32(i, Endian.little);
  i += 4 + vendor;
  if (i + 4 > d.length) return;
  final n = bd.getUint32(i, Endian.little);
  i += 4;
  for (var k = 0; k < n && i + 4 <= d.length; k++) {
    final len = bd.getUint32(i, Endian.little);
    i += 4;
    if (i + len > d.length) break;
    final s = utf8.decode(d.sublist(i, i + len), allowMalformed: true);
    i += len;
    final eq = s.indexOf('=');
    if (eq > 0) out.putIfAbsent(s.substring(0, eq).toUpperCase(), () => s.substring(eq + 1));
  }
}

AudioTags _fromVorbis(Map<String, String> t, Uint8List? picture, int? rate, int? channels, String codec) {
  final year = t['DATE'] ?? t['YEAR'];
  return AudioTags(
    title: t['TITLE'],
    artist: t['ARTIST'],
    album: t['ALBUM'],
    albumArtist: t['ALBUMARTIST'],
    composer: t['COMPOSER'],
    year: year == null || year.length < 4 ? year : year.substring(0, 4),
    genre: t['GENRE'],
    track: t['TRACKNUMBER']?.split('/').first,
    disc: t['DISCNUMBER']?.split('/').first,
    bpm: t['BPM'],
    publisher: t['LABEL'] ?? t['ORGANIZATION'],
    comment: t['COMMENT'] ?? t['DESCRIPTION'],
    lyrics: t['LYRICS'] ?? t['UNSYNCEDLYRICS'],
    picture: picture,
    sampleRate: rate,
    channels: channels,
    codec: codec,
  );
}

// ---- MP4 / M4A ---------------------------------------------------------------

Future<AudioTags> _mp4(RandomAccessFile f) async {
  final size = await f.length();
  // Only reads the metadata boxes: walks the top level, then into moov.
  Future<Map<String, (int, int)>> boxes(int from, int to) async {
    final out = <String, (int, int)>{};
    var at = from;
    while (at + 8 <= to) {
      await f.setPosition(at);
      final h = await f.read(16);
      if (h.length < 8) break;
      var len = _plain(h, 0, 4);
      final type = ascii.decode(h.sublist(4, 8), allowInvalid: true);
      var head = 8;
      if (len == 1 && h.length >= 16) {
        len = _plain(h, 8, 8);
        head = 16;
      } else if (len == 0) {
        len = to - at;
      }
      if (len < head) break;
      out.putIfAbsent(type, () => (at + head, at + len));
      at += len;
    }
    return out;
  }

  final top = await boxes(0, size);
  final moov = top['moov'];
  if (moov == null) return AudioTags.empty;
  final inMoov = await boxes(moov.$1, moov.$2);
  final udta = inMoov['udta'];
  if (udta == null) return const AudioTags(codec: 'AAC');
  final inUdta = await boxes(udta.$1, udta.$2);
  final meta = inUdta['meta'];
  if (meta == null) return const AudioTags(codec: 'AAC');
  // meta is a full box: 4 bytes of version and flags.
  final inMeta = await boxes(meta.$1 + 4, meta.$2);
  final ilst = inMeta['ilst'];
  if (ilst == null) return const AudioTags(codec: 'AAC');
  if (ilst.$2 - ilst.$1 > 32 << 20) return const AudioTags(codec: 'AAC');
  await f.setPosition(ilst.$1);
  final d = await f.read(ilst.$2 - ilst.$1);
  final text = <String, String>{};
  Uint8List? picture;
  var i = 0;
  while (i + 8 <= d.length) {
    final len = _plain(d, i, 4);
    if (len < 8 || i + len > d.length) break;
    final name = latin1.decode(d.sublist(i + 4, i + 8));
    // Its data box: size, 'data', type, locale, value.
    final j = i + 8;
    if (j + 16 <= i + len && ascii.decode(d.sublist(j + 4, j + 8), allowInvalid: true) == 'data') {
      final dlen = _plain(d, j, 4);
      final value = Uint8List.sublistView(d, j + 16, (j + dlen).clamp(j + 16, i + len));
      if (name == 'covr') {
        picture ??= value;
      } else if (name == 'trkn' || name == 'disk') {
        if (value.length >= 4) text[name] = '${_plain(value, 2, 2)}';
      } else if (name == 'tmpo') {
        if (value.length >= 2) text[name] = '${_plain(value, 0, 2)}';
      } else {
        text[name] = utf8.decode(value, allowMalformed: true);
      }
    }
    i += len;
  }
  String? t(String k) => text[k]?.trim().isEmpty ?? true ? null : text[k]!.trim();
  final year = t('©day');
  return AudioTags(
    title: t('©nam'),
    artist: t('©ART'),
    album: t('©alb'),
    albumArtist: t('aART'),
    composer: t('©wrt'),
    year: year == null || year.length < 4 ? year : year.substring(0, 4),
    genre: t('©gen'),
    track: t('trkn'),
    disc: t('disk'),
    bpm: t('tmpo'),
    comment: t('©cmt'),
    lyrics: t('©lyr'),
    picture: picture,
    codec: 'AAC',
  );
}
