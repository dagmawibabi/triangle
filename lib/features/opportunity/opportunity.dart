import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../infrastructure/telegram/accounts.dart';
import '../ai/data/ai.dart';
import '../marketplace/market.dart' show parsePrice, priceText;
import '../sections/section_kit.dart';
import '../sections/ai_run.dart';
import 'package:omni_ai/omni_ai.dart' show CancelToken;
import '../settings/data/settings.dart';
import '../telegram/data/message_content.dart' show pickPhotoSize;
import '../telegram/data/telegram_store.dart';
import '../usage/usage.dart';

// Opportunity: channels and groups that post events and jobs, read as an
// events calendar and a job board. A model can read each post into a clean
// event (when, where, how to register) or job (role, pay, deadline, how to
// apply, how well it fits you); without one, dates and deadlines are guessed
// from the words. What you save, plan to attend and apply to stays here.

enum OppKind {
  event('Events', 'event'),
  job('Jobs', 'job');

  const OppKind(this.label, this.single);
  final String label;
  final String single;
}

typedef OppPicture = ({td.File? file, td.Minithumbnail? mini});

/// A post from a source: one message, or an album sent together.
class OppPost {
  OppPost({
    required this.account,
    required this.chatId,
    required this.messageIds,
    required this.source,
    required this.text,
    required this.date,
    this.pictures = const [],
    this.views = 0,
    this.links = const [],
  });
  final String account;
  final int chatId;
  final List<int> messageIds;
  final String source;
  final String text;
  final DateTime date;
  final List<OppPicture> pictures;
  final int views;

  /// Links in the post (its text and its buttons).
  final List<String> links;

  String get key => postKey(account, chatId, messageIds.first);
  int get messageId => messageIds.first;

  late final String guessTitle = () {
    for (final line in text.split('\n')) {
      final l = line.replaceAll(RegExp(r'[#*_~`>|]+'), '').replaceAll(RegExp(r'^[\s\p{So}\p{Sk}•\-–—]+', unicode: true), '').trim();
      if (l.length >= 4) return l.length > 90 ? '${l.substring(0, 90)}…' : l;
    }
    return text.isEmpty ? 'Post' : (text.length > 60 ? '${text.substring(0, 60)}…' : text);
  }();

  static OppPost? fromMessages(List<td.Message> group, String account, String source) {
    final first = group.first;
    if (first.content is td.MessageChatAddMembers || first.content is td.MessagePinMessage) return null;
    // Rich posts (Telegram's article-like messages) come as Markdown with
    // placeholders for their pictures: read them as plain words, and take
    // the pictures from their blocks.
    final text = [
      for (final m in group)
        if (m.content is td.MessageRichMessage) richPlainText(messageText(m)) else messageText(m),
    ].where((t) => t.isNotEmpty).join('\n').trim();
    if (text.length < 30) return null;
    final pics = <OppPicture>[];
    for (final m in group) {
      final c = m.content;
      if (c is td.MessageRichMessage) {
        richPictures(c.message.blocks, pics);
        continue;
      }
      final p = messagePicture(m, minWidth: 900);
      if (p.file != null || p.mini != null) pics.add(p);
    }
    final links = <String>{};
    for (final m in RegExp(r'https?://[^\s)\]>"]+').allMatches(text)) {
      links.add(m[0]!.replaceAll(RegExp(r'[.,;:!?]+$'), ''));
    }
    for (final m in group) {
      final markup = m.replyMarkup;
      if (markup is td.ReplyMarkupInlineKeyboard) {
        for (final row in markup.rows) {
          for (final b in row) {
            if (b.type case td.InlineKeyboardButtonTypeUrl(:final url)) links.add(url);
          }
        }
      }
      final content = m.content;
      if (content is td.MessageText) {
        for (final e in content.text.entities) {
          if (e.type case td.TextEntityTypeTextUrl(:final url)) links.add(url);
        }
      }
    }
    return OppPost(
      account: account,
      chatId: first.chatId,
      messageIds: [for (final m in group) m.id]..sort(),
      source: source,
      text: text,
      date: unixDate(first.date),
      pictures: pics,
      views: first.interactionInfo?.viewCount ?? 0,
      links: links.toList(),
    );
  }

  /// Words that make a post look like it is about [kind].
  bool looksLike(OppKind kind) => switch (kind) {
    OppKind.event => _eventWords.hasMatch(text) || guessWhen(text, date) != null,
    OppKind.job => _jobWords.hasMatch(text),
  };
}

/// The pictures in a rich message's blocks, in order: photos, and the
/// still frames of videos and GIFs, inside covers, collages and slideshows.
void richPictures(List<td.PageBlock> blocks, List<OppPicture> out) {
  for (final b in blocks) {
    switch (b) {
      case td.PageBlockPhoto(:final photo?):
        out.add((file: pickPhotoSize(photo.sizes, minWidth: 900)?.photo, mini: photo.minithumbnail));
      case td.PageBlockVideo(:final video?):
        out.add((file: video.thumbnail?.file, mini: video.minithumbnail));
      case td.PageBlockAnimation(:final animation?):
        out.add((file: animation.thumbnail?.file, mini: animation.minithumbnail));
      case td.PageBlockCover(:final cover):
        richPictures([cover], out);
      case td.PageBlockCollage(:final blocks) || td.PageBlockSlideshow(:final blocks):
        richPictures(blocks, out);
      default:
        break;
    }
  }
}

/// A rich message's Markdown as plain words: no picture placeholders, no
/// heading or emphasis marks; links keep their address so they stay
/// tappable.
String richPlainText(String md) {
  var t = md;
  t = t.replaceAll(RegExp(r'\[…message continues; open it to load the rest\]'), '');
  // [photo: caption] → caption; [photo], [video], [GIF], [voice message] → nothing.
  t = t.replaceAllMapped(
    RegExp(r'\[(?:photo|video|GIF|file|audio|embedded|map|unsupported block|voice message)(?::\s*([^\]]*))?\]', caseSensitive: false),
    (m) => m[1]?.trim() ?? '',
  );
  // [text](url) → text url (or just url).
  t = t.replaceAllMapped(RegExp(r'\[([^\]]+)\]\((\S+?)\)'), (m) => m[1]!.trim() == m[2] ? m[2]! : '${m[1]!.trim()} ${m[2]}');
  t = t.replaceAll(RegExp(r'^\s*#{1,6}\s*', multiLine: true), '');
  t = t.replaceAll(RegExp(r'^\s*>\s?', multiLine: true), '');
  t = t.replaceAll(RegExp(r'^\s*-{3,}\s*$', multiLine: true), '');
  t = t.replaceAll(RegExp(r'</?details[^>]*>|</?summary>'), '');
  t = t.replaceAll(RegExp(r'\*\*|__|~~|`'), '');
  t = t.replaceAllMapped(RegExp(r'(^|\s)_([^_\n]+)_(?=\s|$)'), (m) => '${m[1]}${m[2]}');
  t = t.replaceAll(RegExp(r'[ \t]+\n'), '\n').replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return t.trim();
}

final _eventWords = RegExp(
  r'\b(event|meet ?up|workshop|webinar|conference|summit|hackathon|bootcamp|seminar|session|panel|festival|concert|exhibition|expo|launch|rsvp|register|registration|join us|tickets?|venue|livestream|live stream|demo day|networking|ceremony)\b|ስብሰባ|ዝግጅት|ኮንፈረንስ|ስልጠና',
  caseSensitive: false,
);
final _jobWords = RegExp(
  r'\b(job|jobs|vacanc(y|ies)|hiring|we.?re hiring|position|opening|role|apply|application|recruit\w*|career|internship|intern|full.?time|part.?time|freelance|contract|salary|cv|resume|candidate|deadline|qualifications?|requirements?|experience)\b|ቅጥር|ክፍት የስራ|ማስታወቂያ|ደመወዝ|ልምድ',
  caseSensitive: false,
);

// ---- guessing from the words -----------------------------------------------------

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, 'jul': 7, 'aug': 8, 'sep': 9, 'sept': 9, 'oct': 10, 'nov': 11, 'dec': 12, //
};

/// A date (and time, when the words give one) in [text], read relative to
/// [posted]: "16 Nov", "Nov 16, 2026", "2026-11-16", "16/11", "tomorrow at
/// 6pm". Null when there is none.
({DateTime at, bool hasTime})? guessWhen(String text, DateTime posted) {
  final t = text.toLowerCase();
  DateTime? day;
  int? at;
  final iso = RegExp(r'\b(20\d\d)-(\d{1,2})-(\d{1,2})\b').firstMatch(t);
  final dmy = RegExp(r'\b(\d{1,2})[/.](\d{1,2})(?:[/.](20\d\d|\d\d))?\b').firstMatch(t);
  final dMon = RegExp(r'\b(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?(jan|feb|mar|apr|may|jun|jul|aug|sept?|oct|nov|dec)[a-z]*\.?(?:,?\s+(20\d\d))?').firstMatch(t);
  final monD = RegExp(r'\b(jan|feb|mar|apr|may|jun|jul|aug|sept?|oct|nov|dec)[a-z]*\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(20\d\d))?').firstMatch(t);
  DateTime? withYear(int month, int d, int? year) {
    if (month < 1 || month > 12 || d < 1 || d > 31) return null;
    if (year != null) return DateTime(year < 100 ? 2000 + year : year, month, d);
    // No year: the next one from a week before the post.
    var c = DateTime(posted.year, month, d);
    if (c.isBefore(posted.subtract(const Duration(days: 7)))) c = DateTime(posted.year + 1, month, d);
    return c;
  }

  if (iso != null) {
    day = withYear(int.parse(iso[2]!), int.parse(iso[3]!), int.parse(iso[1]!));
  } else if (dMon != null) {
    day = withYear(_months[dMon[2]!]!, int.parse(dMon[1]!), int.tryParse(dMon[3] ?? ''));
  } else if (monD != null) {
    day = withYear(_months[monD[1]!]!, int.parse(monD[2]!), int.tryParse(monD[3] ?? ''));
  } else if (dmy != null && !RegExp(r'\d[/.]\d{1,2}[/.]?\d*\s*(%|kg|km|mb|gb)').hasMatch(t)) {
    var a = int.parse(dmy[1]!), b = int.parse(dmy[2]!);
    // Day first, unless that can't be.
    if (b > 12 && a <= 12) (a, b) = (b, a);
    day = withYear(b, a, int.tryParse(dmy[3] ?? ''));
  } else if (RegExp(r'\b(today|tonight)\b').hasMatch(t)) {
    day = DateTime(posted.year, posted.month, posted.day);
  } else if (RegExp(r'\btomorrow\b').hasMatch(t)) {
    day = DateTime(posted.year, posted.month, posted.day + 1);
  }
  if (day == null) return null;
  final ampm = RegExp(r'\b(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)').firstMatch(t);
  final h24 = RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)\b').firstMatch(t);
  if (ampm != null) {
    var h = int.parse(ampm[1]!) % 12;
    if (ampm[3]!.startsWith('p')) h += 12;
    at = h * 60 + (int.tryParse(ampm[2] ?? '') ?? 0);
  } else if (h24 != null) {
    at = int.parse(h24[1]!) * 60 + int.parse(h24[2]!);
  }
  return (at: at == null ? day : day.add(Duration(minutes: at)), hasTime: at != null);
}

/// A deadline in a job post: a date after "deadline", "apply by", "closing".
DateTime? guessDeadline(String text, DateTime posted) {
  final m = RegExp(r'(deadline|apply (?:by|before)|closing date|closes|last date|until|ማብቂያ|የመጨረሻ ቀን)[^\n]{0,60}', caseSensitive: false).firstMatch(text);
  if (m == null) return null;
  return guessWhen(m[0]!, posted)?.at;
}

// ---- what the model made of a post -------------------------------------------------

@immutable
class EventInfo {
  const EventInfo({
    this.isEvent = true,
    required this.title,
    this.summary = '',
    this.start,
    this.end,
    this.allDay = false,
    this.venue = '',
    this.city = '',
    this.online = false,
    this.link = '',
    this.price = '',
    this.free,
    this.organizer = '',
    this.category = '',
    this.tags = const [],
    this.contact = '',
    required this.at,
  });
  final bool isEvent;
  final String title;
  final String summary;
  final DateTime? start;
  final DateTime? end;
  final bool allDay;
  final String venue;
  final String city;
  final bool online;

  /// Where to register or join.
  final String link;
  final String price;
  final bool? free;
  final String organizer;
  final String category;
  final List<String> tags;
  final String contact;
  final DateTime at;

  Map<String, dynamic> toJson() => {
    if (!isEvent) 'ne': true,
    'n': title,
    if (summary.isNotEmpty) 's': summary,
    if (start != null) 'st': start!.toIso8601String(),
    if (end != null) 'en': end!.toIso8601String(),
    if (allDay) 'ad': true,
    if (venue.isNotEmpty) 'v': venue,
    if (city.isNotEmpty) 'c': city,
    if (online) 'o': true,
    if (link.isNotEmpty) 'l': link,
    if (price.isNotEmpty) 'p': price,
    'f': ?free,
    if (organizer.isNotEmpty) 'org': organizer,
    if (category.isNotEmpty) 'cat': category,
    if (tags.isNotEmpty) 't': tags,
    if (contact.isNotEmpty) 'con': contact,
    'at': at.millisecondsSinceEpoch,
  };

  factory EventInfo.fromJson(Map j) => EventInfo(
    isEvent: j['ne'] != true,
    title: '${j['n'] ?? ''}',
    summary: '${j['s'] ?? ''}',
    start: DateTime.tryParse('${j['st'] ?? ''}'),
    end: DateTime.tryParse('${j['en'] ?? ''}'),
    allDay: j['ad'] == true,
    venue: '${j['v'] ?? ''}',
    city: '${j['c'] ?? ''}',
    online: j['o'] == true,
    link: '${j['l'] ?? ''}',
    price: '${j['p'] ?? ''}',
    free: j['f'] as bool?,
    organizer: '${j['org'] ?? ''}',
    category: '${j['cat'] ?? ''}',
    tags: [for (final t in (j['t'] as List? ?? const [])) '$t'],
    contact: '${j['con'] ?? ''}',
    at: DateTime.fromMillisecondsSinceEpoch((j['at'] as num?)?.toInt() ?? 0),
  );
}

@immutable
class JobInfo {
  const JobInfo({
    this.isJob = true,
    required this.title,
    this.company = '',
    this.location = '',
    this.workplace = '',
    this.type = '',
    this.level = '',
    this.salaryMin,
    this.salaryMax,
    this.currency = '',
    this.period = '',
    this.deadline,
    this.apply = '',
    this.applyLink = '',
    this.applyEmail = '',
    this.requirements = const [],
    this.skills = const [],
    this.summary = '',
    this.category = '',
    this.vacancies,
    this.match,
    this.matchReason = '',
    this.legit,
    this.legitNotes = '',
    required this.at,
  });
  final bool isJob;

  /// 0-100: how genuine the ad looks, and why.
  final int? legit;
  final String legitNotes;
  final String title;
  final String company;
  final String location;

  /// remote, hybrid, onsite or empty.
  final String workplace;

  /// Full-time, Part-time, Contract, Internship, Freelance…
  final String type;

  /// Entry, Junior, Mid, Senior, Lead, Executive…
  final String level;
  final double? salaryMin;
  final double? salaryMax;
  final String currency;

  /// month, year, hour, day, week, or empty.
  final String period;
  final DateTime? deadline;

  /// How to apply, in a sentence.
  final String apply;
  final String applyLink;
  final String applyEmail;
  final List<String> requirements;
  final List<String> skills;
  final String summary;
  final String category;
  final int? vacancies;

  /// 0-100: how well it fits the person's profile, when they have one.
  final int? match;
  final String matchReason;
  final DateTime at;

  String get salary {
    if (salaryMin == null && salaryMax == null) return '';
    final lo = salaryMin == null ? '' : priceText(salaryMin, '');
    final hi = salaryMax == null ? '' : priceText(salaryMax, '');
    final range = lo.isNotEmpty && hi.isNotEmpty && lo != hi ? '$lo–$hi' : (lo.isNotEmpty ? lo : hi);
    return [if (currency.isNotEmpty) currency, range, if (period.isNotEmpty) '/ $period'].join(' ');
  }

  Map<String, dynamic> toJson() => {
    if (!isJob) 'nj': true,
    'n': title,
    if (company.isNotEmpty) 'co': company,
    if (location.isNotEmpty) 'lo': location,
    if (workplace.isNotEmpty) 'wp': workplace,
    if (type.isNotEmpty) 'ty': type,
    if (level.isNotEmpty) 'lv': level,
    'smin': ?salaryMin,
    'smax': ?salaryMax,
    if (currency.isNotEmpty) 'cur': currency,
    if (period.isNotEmpty) 'per': period,
    if (deadline != null) 'dl': deadline!.toIso8601String(),
    if (apply.isNotEmpty) 'ap': apply,
    if (applyLink.isNotEmpty) 'al': applyLink,
    if (applyEmail.isNotEmpty) 'ae': applyEmail,
    if (requirements.isNotEmpty) 'rq': requirements,
    if (skills.isNotEmpty) 'sk': skills,
    if (summary.isNotEmpty) 's': summary,
    if (category.isNotEmpty) 'cat': category,
    'vac': ?vacancies,
    'm': ?match,
    if (matchReason.isNotEmpty) 'mr': matchReason,
    'lg': ?legit,
    if (legitNotes.isNotEmpty) 'ln': legitNotes,
    'at': at.millisecondsSinceEpoch,
  };

  factory JobInfo.fromJson(Map j) => JobInfo(
    isJob: j['nj'] != true,
    title: '${j['n'] ?? ''}',
    company: '${j['co'] ?? ''}',
    location: '${j['lo'] ?? ''}',
    workplace: '${j['wp'] ?? ''}',
    type: '${j['ty'] ?? ''}',
    level: '${j['lv'] ?? ''}',
    salaryMin: (j['smin'] as num?)?.toDouble(),
    salaryMax: (j['smax'] as num?)?.toDouble(),
    currency: '${j['cur'] ?? ''}',
    period: '${j['per'] ?? ''}',
    deadline: DateTime.tryParse('${j['dl'] ?? ''}'),
    apply: '${j['ap'] ?? ''}',
    applyLink: '${j['al'] ?? ''}',
    applyEmail: '${j['ae'] ?? ''}',
    requirements: [for (final t in (j['rq'] as List? ?? const [])) '$t'],
    skills: [for (final t in (j['sk'] as List? ?? const [])) '$t'],
    summary: '${j['s'] ?? ''}',
    category: '${j['cat'] ?? ''}',
    vacancies: (j['vac'] as num?)?.toInt(),
    match: (j['m'] as num?)?.toInt(),
    matchReason: '${j['mr'] ?? ''}',
    legit: (j['lg'] as num?)?.toInt(),
    legitNotes: '${j['ln'] ?? ''}',
    at: DateTime.fromMillisecondsSinceEpoch((j['at'] as num?)?.toInt() ?? 0),
  );
}

// ---- a post as an event or a job ---------------------------------------------------

/// An event as shown: the model's reading when there is one, else guesses.
class EventView {
  EventView(this.post, this.info) : _guess = info == null ? guessWhen(post.text, post.date) : null;
  final OppPost post;
  final EventInfo? info;
  final ({DateTime at, bool hasTime})? _guess;

  String get key => post.key;
  String get title => (info?.title.isNotEmpty ?? false) ? info!.title : post.guessTitle;
  DateTime? get start => info?.start ?? _guess?.at;
  DateTime? get end => info?.end;
  bool get hasTime => info != null ? (info!.start != null && !info!.allDay) : (_guess?.hasTime ?? false);
  bool get online => info?.online ?? RegExp(r'\b(online|zoom|google meet|webinar|livestream|live stream|virtual|telegram live)\b', caseSensitive: false).hasMatch(post.text);
  String get venue => info?.venue ?? '';
  String get city => info?.city ?? '';
  String get place => [if (venue.isNotEmpty) venue, if (city.isNotEmpty && !venue.contains(city)) city].join(', ');
  String get link => (info?.link.isNotEmpty ?? false) ? info!.link : (post.links.firstOrNull ?? '');
  String get price => info?.price ?? '';
  bool? get free => info?.free ?? (RegExp(r'\b(free|no cost|free entry|free admission)\b', caseSensitive: false).hasMatch(post.text) ? true : null);
  String get organizer => (info?.organizer.isNotEmpty ?? false) ? info!.organizer : post.source;
  String get category => info?.category ?? '';
  String get summary => info?.summary ?? '';

  /// Over: ended, or started more than six hours ago with no end.
  bool get past {
    final now = DateTime.now();
    if (end != null) return end!.isBefore(now);
    final s = start;
    if (s == null) return post.date.isBefore(now.subtract(const Duration(days: 30)));
    return hasTime ? s.add(const Duration(hours: 6)).isBefore(now) : DateTime(s.year, s.month, s.day + 1).isBefore(now);
  }

  Map<String, dynamic> describe({SavedEvent? saved}) => {
    'event_key': key,
    'title': title,
    if (start != null) 'starts': hasTime ? start!.toIso8601String().substring(0, 16) : start!.toIso8601String().substring(0, 10),
    if (end != null) 'ends': end!.toIso8601String().substring(0, 16),
    if (place.isNotEmpty) 'where': place,
    'online': online,
    if (link.isNotEmpty) 'link': link,
    if (price.isNotEmpty) 'price': price else if (free == true) 'price': 'Free',
    'organizer': organizer,
    if (category.isNotEmpty) 'category': category,
    if (summary.isNotEmpty) 'summary': summary,
    'from': post.source,
    'chat_id': post.chatId,
    'message_id': post.messageId,
    'posted': post.date.toIso8601String().substring(0, 10),
    if (info == null) 'text': post.text.length > 500 ? '${post.text.substring(0, 500)}…' : post.text,
    if (saved != null) 'my_status': saved.status.name,
  };
}

/// A job as shown.
class JobView {
  JobView(this.post, this.info) : _deadline = info == null ? guessDeadline(post.text, post.date) : null;
  final OppPost post;
  final JobInfo? info;
  final DateTime? _deadline;

  String get key => post.key;
  String get title => (info?.title.isNotEmpty ?? false) ? info!.title : post.guessTitle;
  String get company => (info?.company.isNotEmpty ?? false) ? info!.company : '';
  String get location => info?.location ?? '';
  String get workplace => info?.workplace.isNotEmpty == true
      ? info!.workplace
      : (RegExp(r'\b(remote|work from home|wfh)\b', caseSensitive: false).hasMatch(post.text) ? 'remote' : '');
  String get type {
    if (info?.type.isNotEmpty ?? false) return info!.type;
    final t = post.text.toLowerCase();
    if (RegExp(r'intern(ship)?\b').hasMatch(t)) return 'Internship';
    if (RegExp(r'part.?time').hasMatch(t)) return 'Part-time';
    if (RegExp(r'\bcontract\b').hasMatch(t)) return 'Contract';
    if (RegExp(r'\bfreelance').hasMatch(t)) return 'Freelance';
    if (RegExp(r'full.?time').hasMatch(t)) return 'Full-time';
    return '';
  }

  String get level => info?.level ?? '';
  DateTime? get deadline => info?.deadline ?? _deadline;
  String get salary {
    final s = info?.salary ?? '';
    if (s.isNotEmpty) return s;
    if (!RegExp(r'salary|ደመወዝ|pay|compensation', caseSensitive: false).hasMatch(post.text)) return '';
    final p = parsePrice(post.text);
    return p.amount == null ? '' : priceText(p.amount, p.currency);
  }

  double? get salaryValue => info?.salaryMax ?? info?.salaryMin ?? (salary.isEmpty ? null : parsePrice(post.text).amount);
  String get applyLink => (info?.applyLink.isNotEmpty ?? false) ? info!.applyLink : (post.links.firstOrNull ?? '');
  String get applyEmail {
    if (info?.applyEmail.isNotEmpty ?? false) return info!.applyEmail;
    return RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+').firstMatch(post.text)?[0] ?? '';
  }

  String get applyPhone => RegExp(r'(\+?251|0)9\d{8}|\+\d[\d ]{8,14}\d').firstMatch(post.text)?[0] ?? '';
  String get applyTelegram => RegExp(r'(^|\s)(@[A-Za-z]\w{4,31})').firstMatch(post.text)?[2] ?? '';
  int? get match => info?.match;
  bool get closed => deadline != null && DateTime(deadline!.year, deadline!.month, deadline!.day + 1).isBefore(DateTime.now());

  /// Days left to apply, when the deadline is known and not past.
  int? get daysLeft {
    final d = deadline;
    if (d == null || closed) return null;
    final now = DateTime.now();
    return DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  Map<String, dynamic> describe({TrackedJob? tracked}) => {
    'job_key': key,
    'title': title,
    if (company.isNotEmpty) 'company': company,
    if (location.isNotEmpty) 'location': location,
    if (workplace.isNotEmpty) 'workplace': workplace,
    if (type.isNotEmpty) 'type': type,
    if (level.isNotEmpty) 'level': level,
    if (salary.isNotEmpty) 'salary': salary,
    if (deadline != null) 'deadline': deadline!.toIso8601String().substring(0, 10),
    if (closed) 'closed': true,
    if (info?.apply.isNotEmpty ?? false) 'how_to_apply': info!.apply,
    if (applyLink.isNotEmpty) 'apply_link': applyLink,
    if (applyEmail.isNotEmpty) 'apply_email': applyEmail,
    if (info?.requirements.isNotEmpty ?? false) 'requirements': info!.requirements,
    if (info?.skills.isNotEmpty ?? false) 'skills': info!.skills,
    if (info?.summary.isNotEmpty ?? false) 'summary': info!.summary,
    if (match != null) 'match_percent': match,
    if (info?.matchReason.isNotEmpty ?? false) 'match_reason': info!.matchReason,
    if (info?.legit != null) 'trust_score': info!.legit,
    if (info?.legitNotes.isNotEmpty ?? false) 'trust_notes': info!.legitNotes,
    'from': post.source,
    'chat_id': post.chatId,
    'message_id': post.messageId,
    'posted': post.date.toIso8601String().substring(0, 10),
    if (info == null) 'text': post.text.length > 700 ? '${post.text.substring(0, 700)}…' : post.text,
    if (tracked != null) 'my_status': tracked.status.name,
  };
}

// ---- what the person keeps ---------------------------------------------------------

enum EventStatus {
  interested('Interested'),
  going('Going'),
  went('Went');

  const EventStatus(this.label);
  final String label;
}

/// An event the person saved, kept so it shows without reading the post.
@immutable
class SavedEvent {
  const SavedEvent({
    required this.key,
    required this.title,
    this.start,
    this.hasTime = false,
    this.place = '',
    this.online = false,
    this.link = '',
    required this.source,
    this.mini,
    this.status = EventStatus.interested,
    this.reminders = const [],
    this.note = '',
    required this.savedAt,
  });
  final String key;
  final String title;
  final DateTime? start;
  final bool hasTime;
  final String place;
  final bool online;
  final String link;
  final String source;
  final String? mini;
  final EventStatus status;

  /// Reminder ids made for it.
  final List<String> reminders;
  final String note;
  final DateTime savedAt;

  SavedEvent copyWith({EventStatus? status, List<String>? reminders, String? note}) => SavedEvent(
    key: key,
    title: title,
    start: start,
    hasTime: hasTime,
    place: place,
    online: online,
    link: link,
    source: source,
    mini: mini,
    status: status ?? this.status,
    reminders: reminders ?? this.reminders,
    note: note ?? this.note,
    savedAt: savedAt,
  );

  static SavedEvent of(EventView e, {EventStatus status = EventStatus.interested}) => SavedEvent(
    key: e.key,
    title: e.title,
    start: e.start,
    hasTime: e.hasTime,
    place: e.place,
    online: e.online,
    link: e.link,
    source: e.post.source,
    mini: e.post.pictures.firstOrNull?.mini?.data,
    status: status,
    savedAt: DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'k': key,
    't': title,
    if (start != null) 'st': start!.toIso8601String(),
    if (hasTime) 'ht': true,
    if (place.isNotEmpty) 'p': place,
    if (online) 'o': true,
    if (link.isNotEmpty) 'l': link,
    's': source,
    'm': ?mini,
    'status': status.name,
    if (reminders.isNotEmpty) 'r': reminders,
    if (note.isNotEmpty) 'n': note,
    'at': savedAt.millisecondsSinceEpoch,
  };

  factory SavedEvent.fromJson(Map j) => SavedEvent(
    key: '${j['k']}',
    title: '${j['t'] ?? 'Event'}',
    start: DateTime.tryParse('${j['st'] ?? ''}'),
    hasTime: j['ht'] == true,
    place: '${j['p'] ?? ''}',
    online: j['o'] == true,
    link: '${j['l'] ?? ''}',
    source: '${j['s'] ?? ''}',
    mini: j['m'] as String?,
    status: EventStatus.values.asNameMap()['${j['status']}'] ?? EventStatus.interested,
    reminders: [for (final r in (j['r'] as List? ?? const [])) '$r'],
    note: '${j['n'] ?? ''}',
    savedAt: DateTime.fromMillisecondsSinceEpoch((j['at'] as num?)?.toInt() ?? 0),
  );

  Map<String, dynamic> describe() => {
    'event_key': key,
    'title': title,
    if (start != null) 'starts': hasTime ? start!.toIso8601String().substring(0, 16) : start!.toIso8601String().substring(0, 10),
    if (place.isNotEmpty) 'where': place,
    if (online) 'online': true,
    if (link.isNotEmpty) 'link': link,
    'from': source,
    'status': status.name,
    if (reminders.isNotEmpty) 'reminders': reminders.length,
    if (note.isNotEmpty) 'note': note,
  };
}

/// Where an application stands.
enum JobStatus {
  saved('Saved'),
  applied('Applied'),
  interview('Interview'),
  offer('Offer'),
  rejected('Not this time');

  const JobStatus(this.label);
  final String label;
}

@immutable
class TrackedJob {
  const TrackedJob({
    required this.key,
    required this.title,
    this.company = '',
    this.location = '',
    this.salary = '',
    this.deadline,
    this.applyLink = '',
    this.applyEmail = '',
    required this.source,
    this.mini,
    this.status = JobStatus.saved,
    this.note = '',
    this.appliedAt,
    this.reminders = const [],
    required this.savedAt,
    required this.updatedAt,
  });
  final String key;
  final String title;
  final String company;
  final String location;
  final String salary;
  final DateTime? deadline;
  final String applyLink;
  final String applyEmail;
  final String source;
  final String? mini;
  final JobStatus status;
  final String note;
  final DateTime? appliedAt;
  final List<String> reminders;
  final DateTime savedAt;
  final DateTime updatedAt;

  TrackedJob copyWith({JobStatus? status, String? note, DateTime? appliedAt, List<String>? reminders}) => TrackedJob(
    key: key,
    title: title,
    company: company,
    location: location,
    salary: salary,
    deadline: deadline,
    applyLink: applyLink,
    applyEmail: applyEmail,
    source: source,
    mini: mini,
    status: status ?? this.status,
    note: note ?? this.note,
    appliedAt: appliedAt ?? this.appliedAt,
    reminders: reminders ?? this.reminders,
    savedAt: savedAt,
    updatedAt: DateTime.now(),
  );

  static TrackedJob of(JobView j, {JobStatus status = JobStatus.saved}) => TrackedJob(
    key: j.key,
    title: j.title,
    company: j.company,
    location: [j.location, if (j.workplace.isNotEmpty) j.workplace].where((s) => s.isNotEmpty).join(' · '),
    salary: j.salary,
    deadline: j.deadline,
    applyLink: j.applyLink,
    applyEmail: j.applyEmail,
    source: j.post.source,
    mini: j.post.pictures.firstOrNull?.mini?.data,
    status: status,
    appliedAt: status == JobStatus.applied ? DateTime.now() : null,
    savedAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'k': key,
    't': title,
    if (company.isNotEmpty) 'c': company,
    if (location.isNotEmpty) 'lo': location,
    if (salary.isNotEmpty) 'sa': salary,
    if (deadline != null) 'dl': deadline!.toIso8601String(),
    if (applyLink.isNotEmpty) 'al': applyLink,
    if (applyEmail.isNotEmpty) 'ae': applyEmail,
    's': source,
    'm': ?mini,
    'status': status.name,
    if (note.isNotEmpty) 'n': note,
    if (appliedAt != null) 'ap': appliedAt!.toIso8601String(),
    if (reminders.isNotEmpty) 'r': reminders,
    'at': savedAt.millisecondsSinceEpoch,
    'up': updatedAt.millisecondsSinceEpoch,
  };

  factory TrackedJob.fromJson(Map j) => TrackedJob(
    key: '${j['k']}',
    title: '${j['t'] ?? 'Job'}',
    company: '${j['c'] ?? ''}',
    location: '${j['lo'] ?? ''}',
    salary: '${j['sa'] ?? ''}',
    deadline: DateTime.tryParse('${j['dl'] ?? ''}'),
    applyLink: '${j['al'] ?? ''}',
    applyEmail: '${j['ae'] ?? ''}',
    source: '${j['s'] ?? ''}',
    mini: j['m'] as String?,
    status: JobStatus.values.asNameMap()['${j['status']}'] ?? JobStatus.saved,
    note: '${j['n'] ?? ''}',
    appliedAt: DateTime.tryParse('${j['ap'] ?? ''}'),
    reminders: [for (final r in (j['r'] as List? ?? const [])) '$r'],
    savedAt: DateTime.fromMillisecondsSinceEpoch((j['at'] as num?)?.toInt() ?? 0),
    updatedAt: DateTime.fromMillisecondsSinceEpoch((j['up'] as num?)?.toInt() ?? 0),
  );

  Map<String, dynamic> describe() => {
    'job_key': key,
    'title': title,
    if (company.isNotEmpty) 'company': company,
    if (location.isNotEmpty) 'location': location,
    if (salary.isNotEmpty) 'salary': salary,
    if (deadline != null) 'deadline': deadline!.toIso8601String().substring(0, 10),
    if (applyLink.isNotEmpty) 'apply_link': applyLink,
    if (applyEmail.isNotEmpty) 'apply_email': applyEmail,
    'status': status.name,
    if (appliedAt != null) 'applied_on': appliedAt!.toIso8601String().substring(0, 10),
    if (note.isNotEmpty) 'note': note,
    'from': source,
  };
}

// ---- the store ---------------------------------------------------------------------

/// What the AI tidy-up does, like the Marketplace's: which details it
/// fills in for events and jobs, and the person's own instructions.
@immutable
class OppAi {
  const OppAi({
    this.enabled = false,
    this.auto = true,
    this.model = 'cheap',
    this.hideOthers = true,
    this.eventSummary = true,
    this.eventPlace = true,
    this.eventPrice = true,
    this.eventLink = true,
    this.eventTags = true,
    this.jobPay = true,
    this.jobApply = true,
    this.jobRequirements = true,
    this.jobSummary = true,
    this.jobMatch = true,
    this.jobTrust = true,
    this.extra = '',
  });
  final bool enabled;

  /// Tidies posts as they load, without asking.
  final bool auto;

  /// free, cheap, main or a model id (see [automationModel]).
  final String model;

  /// Leaves out posts the model says aren't events (or jobs).
  final bool hideOthers;

  // Events: a two-line summary, where (venue, city, online), price,
  // the registration link, and category and tags.
  final bool eventSummary;
  final bool eventPlace;
  final bool eventPrice;
  final bool eventLink;
  final bool eventTags;

  // Jobs: pay, how to apply, requirements and skills, a summary, how well
  // it fits the person's profile, and how trustworthy the ad looks.
  final bool jobPay;
  final bool jobApply;
  final bool jobRequirements;
  final bool jobSummary;
  final bool jobMatch;
  final bool jobTrust;

  /// The person's own instructions for the model.
  final String extra;

  OppAi copyWith({
    bool? enabled,
    bool? auto,
    String? model,
    bool? hideOthers,
    bool? eventSummary,
    bool? eventPlace,
    bool? eventPrice,
    bool? eventLink,
    bool? eventTags,
    bool? jobPay,
    bool? jobApply,
    bool? jobRequirements,
    bool? jobSummary,
    bool? jobMatch,
    bool? jobTrust,
    String? extra,
  }) => OppAi(
    enabled: enabled ?? this.enabled,
    auto: auto ?? this.auto,
    model: model ?? this.model,
    hideOthers: hideOthers ?? this.hideOthers,
    eventSummary: eventSummary ?? this.eventSummary,
    eventPlace: eventPlace ?? this.eventPlace,
    eventPrice: eventPrice ?? this.eventPrice,
    eventLink: eventLink ?? this.eventLink,
    eventTags: eventTags ?? this.eventTags,
    jobPay: jobPay ?? this.jobPay,
    jobApply: jobApply ?? this.jobApply,
    jobRequirements: jobRequirements ?? this.jobRequirements,
    jobSummary: jobSummary ?? this.jobSummary,
    jobMatch: jobMatch ?? this.jobMatch,
    jobTrust: jobTrust ?? this.jobTrust,
    extra: extra ?? this.extra,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'auto': auto,
    'model': model,
    'hide_others': hideOthers,
    'event_summary': eventSummary,
    'event_place': eventPlace,
    'event_price': eventPrice,
    'event_link': eventLink,
    'event_tags': eventTags,
    'job_pay': jobPay,
    'job_apply': jobApply,
    'job_requirements': jobRequirements,
    'job_summary': jobSummary,
    'job_match': jobMatch,
    'job_trust': jobTrust,
    if (extra.isNotEmpty) 'extra': extra,
  };

  factory OppAi.fromJson(Map j) => OppAi(
    enabled: j['enabled'] == true,
    auto: j['auto'] != false,
    model: '${j['model'] ?? 'cheap'}',
    hideOthers: j['hide_others'] != false,
    eventSummary: j['event_summary'] != false,
    eventPlace: j['event_place'] != false,
    eventPrice: j['event_price'] != false,
    eventLink: j['event_link'] != false,
    eventTags: j['event_tags'] != false,
    jobPay: j['job_pay'] != false,
    jobApply: j['job_apply'] != false,
    jobRequirements: j['job_requirements'] != false,
    jobSummary: j['job_summary'] != false,
    jobMatch: j['job_match'] != false,
    jobTrust: j['job_trust'] != false,
    extra: '${j['extra'] ?? ''}',
  );
}

/// Which events show.
enum EventWhen {
  upcoming('Upcoming'),
  today('Today'),
  week('This week'),
  weekend('This weekend'),
  month('This month'),
  past('Past');

  const EventWhen(this.label);
  final String label;
}

enum JobSort {
  newest('Newest'),
  deadline('Deadline soonest'),
  salary('Highest pay'),
  match('Best match');

  const JobSort(this.label);
  final String label;
}

@immutable
class OpportunityState {
  const OpportunityState({
    this.eventSources = const [],
    this.jobSources = const [],
    this.events = const {},
    this.jobs = const {},
    this.savedEvents = const [],
    this.tracked = const [],
    this.hidden = const {},
    this.ai = const OppAi(),
    this.profile = '',
    this.inDrawer = true,
    this.city = '',
    this.lastSeenEvents,
    this.lastSeenJobs,
  });
  final List<SourceRef> eventSources;
  final List<SourceRef> jobSources;
  final Map<String, EventInfo> events;
  final Map<String, JobInfo> jobs;
  final List<SavedEvent> savedEvents;
  final List<TrackedJob> tracked;
  final Set<String> hidden;
  final OppAi ai;

  /// What the person does and wants, for matching jobs: skills,
  /// experience, the kind of work and place.
  final String profile;
  final bool inDrawer;

  /// The person's city, to put nearby events first.
  final String city;
  final DateTime? lastSeenEvents;
  final DateTime? lastSeenJobs;

  List<SourceRef> sourcesOf(OppKind k) => k == OppKind.event ? eventSources : jobSources;
  SavedEvent? savedEvent(String key) => savedEvents.where((e) => e.key == key).firstOrNull;
  TrackedJob? trackedJob(String key) => tracked.where((e) => e.key == key).firstOrNull;

  OpportunityState copyWith({
    List<SourceRef>? eventSources,
    List<SourceRef>? jobSources,
    Map<String, EventInfo>? events,
    Map<String, JobInfo>? jobs,
    List<SavedEvent>? savedEvents,
    List<TrackedJob>? tracked,
    Set<String>? hidden,
    OppAi? ai,
    String? profile,
    bool? inDrawer,
    String? city,
    DateTime? lastSeenEvents,
    DateTime? lastSeenJobs,
  }) => OpportunityState(
    eventSources: eventSources ?? this.eventSources,
    jobSources: jobSources ?? this.jobSources,
    events: events ?? this.events,
    jobs: jobs ?? this.jobs,
    savedEvents: savedEvents ?? this.savedEvents,
    tracked: tracked ?? this.tracked,
    hidden: hidden ?? this.hidden,
    ai: ai ?? this.ai,
    profile: profile ?? this.profile,
    inDrawer: inDrawer ?? this.inDrawer,
    city: city ?? this.city,
    lastSeenEvents: lastSeenEvents ?? this.lastSeenEvents,
    lastSeenJobs: lastSeenJobs ?? this.lastSeenJobs,
  );
}

enum OppTidyStatus { idle, running, paused, stopping, stopped, done }

/// One call to the model: what was sent, what came back, and its cost.
@immutable
class OppTrace {
  const OppTrace({required this.model, required this.system, required this.prompt, this.response, this.error, this.inputTokens = 0, this.outputTokens = 0, this.cost, required this.ms, required this.at, this.batch = 0});
  final String model;
  final String system;

  /// The posts sent, as JSON.
  final String prompt;
  final String? response;
  final String? error;
  final int inputTokens;
  final int outputTokens;
  final double? cost;
  final int ms;
  final DateTime at;
  final int batch;
}

/// One post's result in the tidy-up.
@immutable
class OppTidyLog {
  const OppTidyLog({required this.kind, required this.name, required this.source, this.line = '', this.error, required this.at, this.trace, this.index, this.postKey, this.postText = '', this.skipped = false, this.legit});
  final OppKind kind;
  final String name;
  final String source;

  /// What it came out as: "Sat 22 Nov · Bole · Free", "ETB 40,000 · closes 30 Nov".
  final String line;
  final String? error;
  final DateTime at;
  final OppTrace? trace;
  final int? index;
  final String? postKey;
  final String postText;

  /// The model said it isn't an event (or a job).
  final bool skipped;
  final int? legit;
}

/// The AI tidy-up's progress.
@immutable
class OppTidyJob {
  const OppTidyJob({this.status = OppTidyStatus.idle, this.total = 0, this.done = 0, this.failed = 0, this.current = const [], this.log = const [], this.startedAt, this.endedAt, this.model = '', this.lastError});
  final OppTidyStatus status;
  final int total;
  final int done;
  final int failed;

  /// The posts being read now.
  final List<String> current;

  /// Newest first.
  final List<OppTidyLog> log;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String model;
  final String? lastError;

  bool get active => status == OppTidyStatus.running || status == OppTidyStatus.paused || status == OppTidyStatus.stopping;
  bool get running => active;
  String? get error => lastError;
  int get left => (total - done).clamp(0, 1 << 30);
  double get fraction => total == 0 ? 0 : done / total;

  OppTidyJob copyWith({OppTidyStatus? status, int? total, int? done, int? failed, List<String>? current, List<OppTidyLog>? log, DateTime? endedAt, String? lastError}) => OppTidyJob(
    status: status ?? this.status,
    total: total ?? this.total,
    done: done ?? this.done,
    failed: failed ?? this.failed,
    current: current ?? this.current,
    log: log ?? this.log,
    startedAt: startedAt,
    endedAt: endedAt ?? this.endedAt,
    model: model,
    lastError: lastError ?? this.lastError,
  );
}

/// The old name, for code that only reads progress.
typedef OppReadJob = OppTidyJob;

class OpportunityStore extends Notifier<OpportunityState> {
  static const _key = 'opportunity.v1';
  static const _readKey = 'opportunity_read.v1';
  late Future<void> ready;

  @override
  OpportunityState build() {
    ready = _load();
    return const OpportunityState();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      final j = raw == null ? const {} : jsonDecode(raw) as Map;
      final rraw = prefs.getString(_readKey);
      final r = rraw == null ? const {} : jsonDecode(rraw) as Map;
      state = OpportunityState(
        eventSources: [for (final s in (j['event_sources'] as List? ?? const [])) if (s is Map) SourceRef.fromJson(s)],
        jobSources: [for (final s in (j['job_sources'] as List? ?? const [])) if (s is Map) SourceRef.fromJson(s)],
        savedEvents: [for (final s in (j['saved_events'] as List? ?? const [])) if (s is Map) SavedEvent.fromJson(s)],
        tracked: [for (final s in (j['tracked'] as List? ?? const [])) if (s is Map) TrackedJob.fromJson(s)],
        hidden: {for (final h in (j['hidden'] as List? ?? const [])) '$h'},
        ai: j['ai'] is Map ? OppAi.fromJson(j['ai'] as Map) : const OppAi(),
        profile: '${j['profile'] ?? ''}',
        inDrawer: j['in_drawer'] != false,
        city: '${j['city'] ?? ''}',
        lastSeenEvents: DateTime.tryParse('${j['seen_events'] ?? ''}'),
        lastSeenJobs: DateTime.tryParse('${j['seen_jobs'] ?? ''}'),
        events: {for (final e in ((r['events'] as Map?) ?? const {}).entries) if (e.value is Map) '${e.key}': EventInfo.fromJson(e.value as Map)},
        jobs: {for (final e in ((r['jobs'] as Map?) ?? const {}).entries) if (e.value is Map) '${e.key}': JobInfo.fromJson(e.value as Map)},
      );
    } catch (e) {
      debugPrint('[Opportunity] $e');
    }
  }

  Future<void> _set(OpportunityState s, {bool read = false}) async {
    state = s;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'event_sources': [for (final x in s.eventSources) x.toJson()],
        'job_sources': [for (final x in s.jobSources) x.toJson()],
        'saved_events': [for (final x in s.savedEvents) x.toJson()],
        'tracked': [for (final x in s.tracked) x.toJson()],
        'hidden': s.hidden.toList(),
        'ai': s.ai.toJson(),
        'profile': s.profile,
        'in_drawer': s.inDrawer,
        'city': s.city,
        if (s.lastSeenEvents != null) 'seen_events': s.lastSeenEvents!.toIso8601String(),
        if (s.lastSeenJobs != null) 'seen_jobs': s.lastSeenJobs!.toIso8601String(),
      }),
    );
    if (read) {
      List<MapEntry<String, T>> newest<T>(Map<String, T> m, DateTime Function(T) at) => (m.entries.toList()..sort((a, b) => at(b.value).compareTo(at(a.value)))).take(1200).toList();
      await prefs.setString(
        _readKey,
        jsonEncode({
          'events': {for (final e in newest(s.events, (EventInfo x) => x.at)) e.key: e.value.toJson()},
          'jobs': {for (final e in newest(s.jobs, (JobInfo x) => x.at)) e.key: e.value.toJson()},
        }),
      );
    }
  }

  Future<void> setSources(OppKind k, List<SourceRef> v) => _set(k == OppKind.event ? state.copyWith(eventSources: v) : state.copyWith(jobSources: v));
  Future<void> addSources(OppKind k, Iterable<SourceRef> v) {
    final cur = state.sourcesOf(k);
    final have = {for (final s in cur) s.key};
    return setSources(k, [...cur, for (final s in v) if (have.add(s.key)) s]);
  }

  Future<void> setAi(OppAi v) => _set(state.copyWith(ai: v));
  Future<void> setProfile(String v) => _set(state.copyWith(profile: v.trim()));
  Future<void> setCity(String v) => _set(state.copyWith(city: v.trim()));
  Future<void> setInDrawer(bool v) => _set(state.copyWith(inDrawer: v));
  Future<void> seen(OppKind k) => _set(k == OppKind.event ? state.copyWith(lastSeenEvents: DateTime.now()) : state.copyWith(lastSeenJobs: DateTime.now()));
  Future<void> setHidden(String key, bool v) => _set(state.copyWith(hidden: v ? {...state.hidden, key} : ({...state.hidden}..remove(key))));

  // ---- events you keep ----

  Future<void> saveEvent(EventView e, EventStatus status) async {
    await ready;
    final have = state.savedEvent(e.key);
    final next = have == null ? SavedEvent.of(e, status: status) : have.copyWith(status: status);
    await _set(state.copyWith(savedEvents: [next, for (final x in state.savedEvents) if (x.key != e.key) x]));
  }

  Future<void> updateSavedEvent(String key, SavedEvent Function(SavedEvent) f) =>
      _set(state.copyWith(savedEvents: [for (final x in state.savedEvents) x.key == key ? f(x) : x]));
  Future<void> unsaveEvent(String key) => _set(state.copyWith(savedEvents: [for (final x in state.savedEvents) if (x.key != key) x]));

  // ---- jobs you track ----

  Future<void> track(JobView j, JobStatus status) async {
    await ready;
    final have = state.trackedJob(j.key);
    final next = have == null ? TrackedJob.of(j, status: status) : have.copyWith(status: status, appliedAt: status == JobStatus.applied && have.appliedAt == null ? DateTime.now() : null);
    await _set(state.copyWith(tracked: [next, for (final x in state.tracked) if (x.key != j.key) x]));
  }

  Future<void> updateTracked(String key, TrackedJob Function(TrackedJob) f) => _set(state.copyWith(tracked: [for (final x in state.tracked) x.key == key ? f(x) : x]));
  Future<void> untrack(String key) => _set(state.copyWith(tracked: [for (final x in state.tracked) if (x.key != key) x]));

  Future<void> forgetReadings(OppKind k) => _set(k == OppKind.event ? state.copyWith(events: const {}) : state.copyWith(jobs: const {}), read: true);

  // ---- the AI reading ----

  final readJob = ValueNotifier<OppTidyJob>(const OppTidyJob());

  /// The call in flight: its thinking and answer as they stream.
  final live = AiLiveNotifier();
  final _queue = <(OppKind, OppPost)>[];
  final _queued = <String>{};
  Completer<int>? _run;
  Completer<void>? _resume;
  bool _stop = false;
  CancelToken? _cancel;
  OppTrace? _trace;

  /// Posts already sent this session, so the automatic pass doesn't send
  /// the same failing ones again and again.
  final _tried = <String>{};

  /// Stopped by the person: the automatic pass waits until they run it.
  bool _held = false;

  bool get busy => _run != null;

  /// Queues [posts] that have no reading yet (all of them with [force]) for
  /// the model. Completes with how many were read once the queue is empty.
  /// [auto] passes (as posts load) skip what was tried this session and
  /// stay off after the person pressed Stop.
  Future<int> read(OppKind kind, List<OppPost> posts, {bool force = false, bool auto = false}) async {
    await ready;
    if (auto && _held) return _run?.future ?? 0;
    if (!auto) _held = false;
    final have = kind == OppKind.event ? state.events : state.jobs;
    final todo = [
      for (final p in posts)
        if ((force || !have.containsKey(p.key)) && !(auto && _tried.contains('${kind.name}:${p.key}')) && _queued.add('${kind.name}:${p.key}')) p,
    ];
    _tried.addAll(todo.map((p) => '${kind.name}:${p.key}'));
    if (todo.isEmpty) return _run?.future ?? Future.value(0);
    _queue.addAll(todo.map((p) => (kind, p)));
    final j = readJob.value;
    if (_run == null) {
      _stop = false;
      readJob.value = OppTidyJob(
        status: OppTidyStatus.running,
        total: todo.length,
        startedAt: DateTime.now(),
        model: automationModel(ref.read(aiProvider), ref.read(settingsProvider), state.ai.model),
        log: j.log,
      );
      _run = Completer<int>();
      unawaited(_work());
    } else {
      readJob.value = j.copyWith(total: j.total + todo.length);
    }
    return _run!.future;
  }

  Future<void> _work() async {
    var done = 0;
    try {
      while (_queue.isNotEmpty && !_stop) {
        if (_resume != null) await _resume!.future;
        if (_stop) break;
        final k = _queue.first.$1;
        final batch = [for (final x in _queue.where((x) => x.$1 == k).take(2)) x.$2];
        _queue.removeWhere((x) => x.$1 == k && batch.contains(x.$2));
        readJob.value = readJob.value.copyWith(current: [for (final p in batch) p.guessTitle]);
        live.begin(items: [for (final p in batch) p.guessTitle]);
        _cancel = CancelToken();
        try {
          final got = await _ask(k, batch);
          done += got.length;
          readJob.value = readJob.value.copyWith(
            done: readJob.value.done + batch.length,
            failed: readJob.value.failed + batch.where((p) => !got.containsKey(p.key)).length,
            log: [
              for (final (i, p) in batch.indexed)
                got[p.key] ??
                    OppTidyLog(kind: k, name: p.guessTitle, source: p.source, error: 'No answer for this one', at: DateTime.now(), trace: _trace, index: i, postKey: p.key, postText: p.text),
              ...readJob.value.log,
            ].take(80).toList(),
          );
        } on AiCancelled {
          // Stopped mid-call: these weren't read, nor did they fail.
          _tried.removeAll(batch.map((p) => '${k.name}:${p.key}'));
          _queued.removeAll(batch.map((p) => '${k.name}:${p.key}'));
          break;
        } catch (e) {
          readJob.value = readJob.value.copyWith(
            done: readJob.value.done + batch.length,
            failed: readJob.value.failed + batch.length,
            lastError: aiErrorText(e),
            log: [
              for (final (i, p) in batch.indexed)
                OppTidyLog(kind: k, name: p.guessTitle, source: p.source, error: aiErrorText(e), at: DateTime.now(), trace: _trace, index: i, postKey: p.key, postText: p.text),
              ...readJob.value.log,
            ].take(80).toList(),
          );
        } finally {
          _queued.removeAll(batch.map((p) => '${k.name}:${p.key}'));
          _cancel = null;
        }
      }
    } finally {
      final stopped = _stop;
      for (final (k, p) in _queue) {
        _queued.remove('${k.name}:${p.key}');
      }
      _queue.clear();
      live.idle();
      readJob.value = readJob.value.copyWith(status: stopped ? OppTidyStatus.stopped : OppTidyStatus.done, current: const [], endedAt: DateTime.now());
      final r = _run;
      _run = null;
      _resume = null;
      r?.complete(done);
    }
  }

  /// Holds the tidy-up after the batch being read.
  void pauseTidy() {
    if (_run == null || _resume != null) return;
    _resume = Completer<void>();
    readJob.value = readJob.value.copyWith(status: OppTidyStatus.paused);
  }

  void resumeTidy() {
    final r = _resume;
    _resume = null;
    if (_run != null) readJob.value = readJob.value.copyWith(status: OppTidyStatus.running);
    r?.complete();
  }

  /// Stops now: the call in flight is dropped, and so is the rest of the
  /// queue. The automatic pass stays off until the person runs it again.
  void stopTidy() {
    _held = true;
    if (_run == null) return;
    _stop = true;
    _cancel?.cancel();
    resumeTidy();
    readJob.value = readJob.value.copyWith(status: OppTidyStatus.stopping);
  }

  void stopReading() => stopTidy();

  void clearTidyLog() => readJob.value = readJob.value.copyWith(log: const []);

  Future<Map<String, OppTidyLog>> _ask(OppKind kind, List<OppPost> batch) async {
    final cfg = state.ai;
    final ai = ref.read(aiProvider);
    final settings = ref.read(settingsProvider);
    final model = automationModel(ai, settings, state.ai.model);
    final now = DateTime.now();
    final posts = [
      for (final (i, p) in batch.indexed)
        {
          'i': i,
          'from': p.source,
          'posted': p.date.toIso8601String().substring(0, 16),
          if (p.links.isNotEmpty) 'links': p.links.take(6).toList(),
          'text': p.text.length > 2200 ? '${p.text.substring(0, 2200)}…' : p.text,
        },
    ];
    final today = 'Today is ${now.toIso8601String().substring(0, 10)} (${const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][now.weekday - 1]}), '
        'local time zone UTC${now.timeZoneOffset.isNegative ? '-' : '+'}${now.timeZoneOffset.inHours.abs().toString().padLeft(2, '0')}.';
    final profile = cfg.jobMatch ? state.profile.trim() : '';
    final eventFields = [
      'is_event (false for posts that announce no event: news, ads, results of past events)',
      'title (clean, under 70 chars, no emoji)',
      if (cfg.eventSummary) 'summary (2 plain sentences: what it is and who it is for)',
      'start and end (ISO, null if unknown)',
      'all_day (true if no time is given)',
      if (cfg.eventPlace) 'venue (place name and address if given); city; online (true if held online or streamed)',
      if (cfg.eventLink) 'link (the registration, ticket or join link, from the links if one fits)',
      if (cfg.eventPrice) 'price (e.g. "Free", "500 ETB", or empty); free (true, false or null)',
      'organizer',
      if (cfg.eventTags) 'category (one of: Tech, Business, Startup, Arts, Music, Faith, Education, Health, Sports, Community, Career, Science, Food, Party, Film, Other); tags (up to 4 short words)',
      'contact (phone, @username or email to ask about it)',
    ];
    final jobFields = [
      'is_job (false for posts that offer no job: news, tips, ads for courses)',
      'title (the role, under 70 chars, no emoji)',
      'company',
      'location (city or area)',
      'workplace (remote, hybrid, onsite or empty)',
      'type (Full-time, Part-time, Contract, Internship, Freelance, Volunteer or empty)',
      'level (Entry, Junior, Mid, Senior, Lead, Executive or empty)',
      if (cfg.jobPay) 'salary_min and salary_max (numbers or null); currency (ISO, e.g. ETB, USD); period (month, year, hour, day or empty)',
      'deadline (ISO date or null)',
      'vacancies (number or null)',
      if (cfg.jobApply) 'apply (one sentence: how to apply); apply_link; apply_email',
      if (cfg.jobRequirements) 'requirements (up to 6 short items: degree, years, must-haves); skills (up to 8)',
      if (cfg.jobSummary) 'summary (2 plain sentences about the role)',
      'category (Engineering, Design, Product, Data, Marketing, Sales, Finance, Accounting, Admin, Customer service, Healthcare, Education, Legal, Logistics, Hospitality, NGO, Government, Other)',
      if (cfg.jobTrust)
        'legit (0-100: how genuine the ad looks: a named employer, a realistic role and pay, a proper way to apply; low for fees to apply or train, pay that is too good, vague duties, only a personal phone or Telegram, pressure to hurry) and legit_notes (one short sentence why)',
      if (profile.isNotEmpty) 'match (0-100: how well the job fits this person, honestly; 50 means partly) and match_reason (one short sentence why). The person: $profile',
    ];
    final extra = cfg.extra.trim().isEmpty ? '' : '\nThe user adds: ${cfg.extra.trim()}';
    // A few fields done is enough: what the post doesn't say is left out.
    const partial = ' Only "i" and the title are required: leave out any field the post does not make clear rather than guessing. Be quick; do not deliberate.';
    final system = kind == OppKind.event
        ? 'You read Telegram posts about events into clean calendar entries for an events app. Posts are in any language '
              '(Amharic, English…); write fields in English unless the post is only in another language. Never invent '
              'details that are not in the post. Dates: resolve "tomorrow", weekdays and missing years from the posted '
              'date; give local times as ISO 8601 without a zone ("2026-11-16T18:00"), converted to the user\'s zone if the '
              'post names another one. $today Answer with only a JSON array, one object per post, each with "i" and: '
              '${eventFields.join('; ')}.$partial$extra'
        : 'You read Telegram job posts into clean listings for a job board. Posts are in any language (Amharic, '
              'English…); write fields in English unless the post is only in another language. Never invent details. '
              '$today Answer with only a JSON array, one object per post, each with "i" and: ${jobFields.join('; ')}.$partial$extra';
    final prompt = const JsonEncoder.withIndent('  ').convert(posts);
    final started = DateTime.now();
    final main = canonicalModelId(settings.model);
    final List<Map<String, dynamic>> list;
    final AiCallResult result;
    try {
      (list, result) = await aiJsonCall(
        ai: ai,
        model: model,
        fallbackModel: main == model ? null : main,
        system: system,
        prompt: prompt,
        maxOutputTokens: 800 * batch.length + 1600,
        cancel: _cancel ?? CancelToken(),
        live: live,
      );
    } on AiCancelled {
      rethrow;
    } catch (e) {
      _trace = OppTrace(model: model, system: system, prompt: prompt, error: aiErrorText(e), ms: DateTime.now().difference(started).inMilliseconds, at: started, batch: batch.length);
      rethrow;
    }
    _trace = OppTrace(
      model: result.model,
      system: system,
      prompt: prompt,
      response: result.text,
      inputTokens: result.inputTokens,
      outputTokens: result.outputTokens,
      cost: result.cost,
      ms: result.ms,
      at: started,
      batch: batch.length,
    );
    try {
      ref.read(usageProvider.notifier).recordChat(model: result.model, usage: result.usage, info: ref.read(modelCatalogProvider).byId(result.model));
    } catch (_) {}
    if (list.isEmpty) return const {};
    String s(Map o, String k) => '${o[k] ?? ''}'.trim() == 'null' ? '' : '${o[k] ?? ''}'.trim();
    double? n(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}'.replaceAll(RegExp(r'[^\d.]'), ''));
    List<String> strs(Object? v) => [for (final x in (v is List ? v : const [])) if ('$x'.trim().isNotEmpty) '$x'.trim()];
    final events = <String, EventInfo>{};
    final jobs = <String, JobInfo>{};
    for (final o in list) {
      final i = (o['i'] as num?)?.toInt();
      if (i == null || i < 0 || i >= batch.length) continue;
      final p = batch[i];
      if (kind == OppKind.event) {
        events[p.key] = EventInfo(
          isEvent: o['is_event'] != false,
          title: s(o, 'title').isEmpty ? p.guessTitle : s(o, 'title'),
          summary: s(o, 'summary'),
          start: DateTime.tryParse(s(o, 'start')),
          end: DateTime.tryParse(s(o, 'end')),
          allDay: o['all_day'] == true,
          venue: s(o, 'venue'),
          city: s(o, 'city'),
          online: o['online'] == true,
          link: s(o, 'link'),
          price: s(o, 'price'),
          free: o['free'] is bool ? o['free'] as bool : null,
          organizer: s(o, 'organizer'),
          category: s(o, 'category'),
          tags: strs(o['tags']),
          contact: s(o, 'contact'),
          at: DateTime.now(),
        );
      } else {
        jobs[p.key] = JobInfo(
          isJob: o['is_job'] != false,
          title: s(o, 'title').isEmpty ? p.guessTitle : s(o, 'title'),
          company: s(o, 'company'),
          location: s(o, 'location'),
          workplace: s(o, 'workplace').toLowerCase(),
          type: s(o, 'type'),
          level: s(o, 'level'),
          salaryMin: n(o['salary_min']),
          salaryMax: n(o['salary_max']),
          currency: s(o, 'currency').toUpperCase(),
          period: s(o, 'period').toLowerCase(),
          deadline: DateTime.tryParse(s(o, 'deadline')),
          vacancies: (o['vacancies'] as num?)?.toInt(),
          apply: s(o, 'apply'),
          applyLink: s(o, 'apply_link'),
          applyEmail: s(o, 'apply_email'),
          requirements: strs(o['requirements']),
          skills: strs(o['skills']),
          summary: s(o, 'summary'),
          category: s(o, 'category'),
          match: (o['match'] as num?)?.round().clamp(0, 100),
          matchReason: s(o, 'match_reason'),
          legit: (o['legit'] as num?)?.round().clamp(0, 100),
          legitNotes: s(o, 'legit_notes'),
          at: DateTime.now(),
        );
      }
    }
    await _set(kind == OppKind.event ? state.copyWith(events: {...state.events, ...events}) : state.copyWith(jobs: {...state.jobs, ...jobs}), read: true);
    final out = <String, OppTidyLog>{};
    for (final (i, p) in batch.indexed) {
      final e = events[p.key];
      final j = jobs[p.key];
      if (e == null && j == null) continue;
      String line;
      if (e != null) {
        final st = e.start;
        line = [
          if (st != null) '${st.day}/${st.month}${e.allDay ? '' : ' ${st.hour.toString().padLeft(2, '0')}:${st.minute.toString().padLeft(2, '0')}'}',
          if (e.online) 'Online' else if (e.city.isNotEmpty || e.venue.isNotEmpty) (e.venue.isNotEmpty ? e.venue : e.city),
          if (e.free == true) 'Free' else if (e.price.isNotEmpty) e.price,
          if (e.category.isNotEmpty) e.category,
        ].join(' · ');
      } else {
        line = [
          if (j!.company.isNotEmpty) j.company,
          if (j.salary.isNotEmpty) j.salary,
          if (j.deadline != null) 'closes ${j.deadline!.day}/${j.deadline!.month}',
          if (j.match != null) '${j.match}% fit',
        ].join(' · ');
      }
      out[p.key] = OppTidyLog(
        kind: kind,
        name: e?.title ?? j!.title,
        source: p.source,
        line: line,
        at: DateTime.now(),
        trace: _trace,
        index: i,
        postKey: p.key,
        postText: p.text,
        skipped: e != null ? !e.isEvent : !j!.isJob,
        legit: j?.legit,
      );
    }
    return out;
  }

  /// A cover letter or message for [job], from the person's profile.
  Future<String> draftApplication(JobView job, {String extra = ''}) async {
    final ai = ref.read(aiProvider);
    final model = canonicalModelId(ref.read(settingsProvider).model);
    final how = [
      if (job.applyEmail.isNotEmpty) 'by email to ${job.applyEmail}',
      if (job.applyLink.isNotEmpty) 'through ${job.applyLink}',
      if (job.applyTelegram.isNotEmpty) 'on Telegram to ${job.applyTelegram}',
    ];
    final r = await ai.generateText(
      model: model,
      system:
          'You write short, specific job applications. Use only facts from the person\'s profile; never invent '
          'experience. Match the post\'s language. Under 220 words. ${how.isEmpty ? '' : 'They will apply ${how.join(' or ')}: '
              'for email start with a "Subject:" line.'} No placeholders like [Your Name] unless the profile lacks the name.',
      prompt: 'The person:\n${state.profile.isEmpty ? '(no profile given: keep it general and say what to fill in)' : state.profile}\n\n'
          'The job post:\n${job.post.text}${extra.trim().isEmpty ? '' : '\n\nAlso: ${extra.trim()}'}',
      maxOutputTokens: 900,
    );
    return r.text.trim();
  }
}

final opportunityProvider = NotifierProvider<OpportunityStore, OpportunityState>(OpportunityStore.new);

// ---- the feeds ---------------------------------------------------------------------

@immutable
class OppFeedState {
  const OppFeedState({this.bySource = const {}, this.loading = const {}, this.next = const {}, this.errors = const {}});
  final Map<String, List<OppPost>> bySource;
  final Set<String> loading;
  final Map<String, int> next;
  final Map<String, String> errors;
  bool get anyLoading => loading.isNotEmpty;
  bool hasMore(String k) => (next[k] ?? 1) != 0;
}

class OppFeed extends Notifier<OppFeedState> {
  OppFeed(this.kind) : _memory = FeedMemory('opp_${kind.name}');
  final OppKind kind;
  final FeedMemory _memory;

  /// The posts read from each source this run, newest first, for [_memory].
  final _ids = <String, List<int>>{};

  @override
  OppFeedState build() => const OppFeedState();

  Future<void> load(SourceRef s, {bool more = false, int want = 40}) async {
    if (state.loading.contains(s.key) || (more && state.next[s.key] == 0)) return;
    state = OppFeedState(bySource: state.bySource, loading: {...state.loading, s.key}, next: state.next, errors: {...state.errors}..remove(s.key));
    try {
      final client = ref.read(telegramClientFamily(s.account));
      final title = ref.read(telegramStoreFamily(s.account)).chat(s.chatId)?.title ?? s.title;
      // First time this run: what it showed last time, at once.
      if (!more && !state.bySource.containsKey(s.key)) {
        final kept = [for (final g in groupAlbums(await _memory.recall(client, s))) ?OppPost.fromMessages(g, s.account, title)];
        if (kept.isNotEmpty && !state.bySource.containsKey(s.key)) {
          state = OppFeedState(bySource: {...state.bySource, s.key: kept}, loading: state.loading, next: state.next, errors: state.errors);
        }
      }
      var from = more ? (state.next[s.key] ?? 0) : 0;
      final found = <OppPost>[];
      final ids = more ? [...?_ids[s.key]] : <int>[];
      var next = 0;
      for (var round = 0; round < 4 && found.length < want; round++) {
        final page = await loadChatPage(client, s.chatId, from: from, limit: 60);
        ids.addAll(page.messages.map((m) => m.id));
        for (final g in groupAlbums(page.messages)) {
          final p = OppPost.fromMessages(g, s.account, title);
          if (p != null) found.add(p);
        }
        next = page.next;
        if (next == 0 || page.messages.isEmpty) {
          next = 0;
          break;
        }
        from = next;
      }
      final have = more ? (state.bySource[s.key] ?? const <OppPost>[]) : const <OppPost>[];
      final keys = {for (final p in have) p.key};
      final fresh = [for (final p in found) if (keys.add(p.key)) p];
      state = OppFeedState(
        bySource: {...state.bySource, s.key: [...have, ...fresh]},
        loading: {...state.loading}..remove(s.key),
        next: {...state.next, s.key: next},
        errors: state.errors,
      );
      _ids[s.key] = ids;
      unawaited(_memory.remember(s, ids, max: 300));
      final o = ref.read(opportunityProvider);
      if (o.ai.enabled && o.ai.auto && fresh.isNotEmpty) unawaited(ref.read(opportunityProvider.notifier).read(kind, fresh, auto: true));
    } catch (e) {
      state = OppFeedState(bySource: state.bySource, loading: {...state.loading}..remove(s.key), next: state.next, errors: {...state.errors, s.key: '$e'});
    }
  }

  Future<void> loadAll(Iterable<SourceRef> sources, {bool refresh = false}) =>
      pooled([for (final s in sources) if (refresh || !state.bySource.containsKey(s.key)) s], 3, (s) => load(s));

  OppPost? byKey(String key) {
    final k = parsePostKey(key);
    for (final list in state.bySource.values) {
      for (final p in list) {
        if (p.key == key || (k != null && p.chatId == k.chatId && p.messageIds.contains(k.messageId))) return p;
      }
    }
    return null;
  }

  /// One post, read from Telegram when it isn't loaded.
  Future<OppPost?> fetch(String key) async {
    final have = byKey(key);
    if (have != null) return have;
    final k = parsePostKey(key);
    if (k == null) return null;
    final client = ref.read(telegramClientFamily(k.account));
    final m = await client.send<td.Message>(td.GetMessage(chatId: k.chatId, messageId: k.messageId), limited: true);
    var group = [m];
    if (m.mediaAlbumId != 0) {
      final around = await client.send<td.Messages>(td.GetChatHistory(chatId: k.chatId, fromMessageId: k.messageId, offset: -10, limit: 20, onlyLocal: false), limited: true);
      group = [for (final x in around.messages) if (x.mediaAlbumId == m.mediaAlbumId) x]..sort((a, b) => a.id.compareTo(b.id));
      if (group.isEmpty) group = [m];
    }
    return OppPost.fromMessages(group, k.account, ref.read(telegramStoreFamily(k.account)).chat(k.chatId)?.title ?? '');
  }
}

final oppFeedProvider = NotifierProvider.family<OppFeed, OppFeedState, OppKind>(OppFeed.new);

// ---- what shows ----------------------------------------------------------------------

/// Every visible source's events, filtered and in time order.
List<EventView> allEvents(
  OpportunityState o,
  OppFeedState feed, {
  String? sourceKey,
  String query = '',
  EventWhen when = EventWhen.upcoming,
  bool? online,
  bool freeOnly = false,
  String? category,
  DateTime? day,
  bool includeHidden = false,
}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final q = query.trim().toLowerCase();
  final out = <EventView>[];
  final seen = <String>{};
  for (final s in o.eventSources) {
    if (sourceKey != null ? s.key != sourceKey : s.hidden) continue;
    for (final p in feed.bySource[s.key] ?? const <OppPost>[]) {
      if (!includeHidden && o.hidden.contains(p.key)) continue;
      final info = o.events[p.key];
      if (info != null && !info.isEvent && o.ai.hideOthers) continue;
      if (info == null && !p.looksLike(OppKind.event)) continue;
      final e = EventView(p, info);
      // The same event posted twice (forwards, reposts).
      if (!seen.add('${e.title.toLowerCase()}|${e.start?.toIso8601String().substring(0, 10)}')) continue;
      if (online != null && e.online != online) continue;
      if (freeOnly && e.free != true) continue;
      if (category != null && e.category != category) continue;
      final st = e.start;
      if (day != null) {
        if (st == null || st.year != day.year || st.month != day.month || st.day != day.day) continue;
      } else {
        final ok = switch (when) {
          EventWhen.upcoming => !e.past,
          EventWhen.past => e.past,
          EventWhen.today => st != null && !st.isBefore(today) && st.isBefore(today.add(const Duration(days: 1))) && !e.past,
          EventWhen.week => st != null && !e.past && st.isBefore(today.add(Duration(days: 8 - today.weekday))),
          EventWhen.weekend => st != null && !e.past && (st.weekday >= 6) && st.isBefore(today.add(Duration(days: 8 - today.weekday))),
          EventWhen.month => st != null && !e.past && st.year == today.year && st.month == today.month,
        };
        if (!ok) continue;
      }
      if (q.isNotEmpty && !'${e.title} ${e.summary} ${e.place} ${e.organizer} ${e.category} ${p.text}'.toLowerCase().contains(q)) continue;
      out.add(e);
    }
  }
  int cmp(EventView a, EventView b) {
    final x = a.start, y = b.start;
    if (x == null && y == null) return b.post.date.compareTo(a.post.date);
    if (x == null) return 1;
    if (y == null) return -1;
    return when == EventWhen.past ? y.compareTo(x) : x.compareTo(y);
  }

  out.sort(cmp);
  // Near the person first within a day, when their city is set.
  return out;
}

/// Every visible source's jobs, filtered and sorted.
List<JobView> allJobs(
  OpportunityState o,
  OppFeedState feed, {
  String? sourceKey,
  String query = '',
  String? workplace,
  String? type,
  String? level,
  String? category,
  bool hideClosed = true,
  int? closingWithinDays,
  double? minSalary,
  JobSort sort = JobSort.newest,
  bool includeHidden = false,
}) {
  final q = query.trim().toLowerCase();
  final out = <JobView>[];
  final seen = <String>{};
  for (final s in o.jobSources) {
    if (sourceKey != null ? s.key != sourceKey : s.hidden) continue;
    for (final p in feed.bySource[s.key] ?? const <OppPost>[]) {
      if (!includeHidden && o.hidden.contains(p.key)) continue;
      final info = o.jobs[p.key];
      if (info != null && !info.isJob && o.ai.hideOthers) continue;
      if (info == null && !p.looksLike(OppKind.job)) continue;
      final j = JobView(p, info);
      if (!seen.add('${j.title.toLowerCase()}|${j.company.toLowerCase()}')) continue;
      if (hideClosed && j.closed) continue;
      if (workplace != null && j.workplace != workplace) continue;
      if (type != null && j.type.toLowerCase() != type.toLowerCase()) continue;
      if (level != null && j.level.toLowerCase() != level.toLowerCase()) continue;
      if (category != null && (info?.category ?? '') != category) continue;
      if (closingWithinDays != null && (j.daysLeft == null || j.daysLeft! > closingWithinDays)) continue;
      if (minSalary != null && (j.salaryValue == null || j.salaryValue! < minSalary)) continue;
      if (q.isNotEmpty &&
          !'${j.title} ${j.company} ${j.location} ${j.type} ${j.level} ${info?.skills.join(' ') ?? ''} ${info?.summary ?? ''} ${p.text}'.toLowerCase().contains(q)) {
        continue;
      }
      out.add(j);
    }
  }
  int nulls<T extends Comparable<Object>>(T? a, T? b, {bool desc = false}) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return desc ? b.compareTo(a) : a.compareTo(b);
  }

  out.sort(switch (sort) {
    JobSort.newest => (a, b) => b.post.date.compareTo(a.post.date),
    JobSort.deadline => (a, b) => nulls<DateTime>(a.deadline, b.deadline),
    JobSort.salary => (a, b) => nulls<num>(a.salaryValue, b.salaryValue, desc: true),
    JobSort.match => (a, b) => nulls<num>(a.match, b.match, desc: true),
  });
  return out;
}

// ---- calendars ------------------------------------------------------------------------

String _ics(DateTime d, {bool date = false}) {
  final u = d.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  if (date) return '${d.year}${two(d.month)}${two(d.day)}';
  return '${u.year}${two(u.month)}${two(u.day)}T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
}

String _escape(String s) => s.replaceAll(r'\', r'\\').replaceAll(';', r'\;').replaceAll(',', r'\,').replaceAll('\n', r'\n');

/// An .ics calendar file for an event, to open in any calendar app.
Future<File> eventCalendarFile({required String title, required DateTime start, DateTime? end, bool allDay = false, String place = '', String details = '', String link = ''}) async {
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/event_${start.millisecondsSinceEpoch}.ics');
  final finish = end ?? (allDay ? start.add(const Duration(days: 1)) : start.add(const Duration(hours: 2)));
  final body = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Triangle//Opportunity//EN',
    'BEGIN:VEVENT',
    'UID:${start.millisecondsSinceEpoch}-${title.hashCode}@triangle',
    'DTSTAMP:${_ics(DateTime.now())}',
    if (allDay) 'DTSTART;VALUE=DATE:${_ics(start, date: true)}' else 'DTSTART:${_ics(start)}',
    if (allDay) 'DTEND;VALUE=DATE:${_ics(finish, date: true)}' else 'DTEND:${_ics(finish)}',
    'SUMMARY:${_escape(title)}',
    if (place.isNotEmpty) 'LOCATION:${_escape(place)}',
    if (details.isNotEmpty || link.isNotEmpty) 'DESCRIPTION:${_escape([details, link].where((s) => s.isNotEmpty).join('\n\n'))}',
    if (link.isNotEmpty) 'URL:$link',
    'BEGIN:VALARM',
    'TRIGGER:-PT1H',
    'ACTION:DISPLAY',
    'DESCRIPTION:${_escape(title)}',
    'END:VALARM',
    'END:VEVENT',
    'END:VCALENDAR',
  ].join('\r\n');
  await f.writeAsString(body);
  return f;
}

/// A Google Calendar "add event" link.
Uri googleCalendarLink({required String title, required DateTime start, DateTime? end, bool allDay = false, String place = '', String details = ''}) {
  final finish = end ?? (allDay ? start.add(const Duration(days: 1)) : start.add(const Duration(hours: 2)));
  return Uri.https('calendar.google.com', '/calendar/render', {
    'action': 'TEMPLATE',
    'text': title,
    'dates': allDay ? '${_ics(start, date: true)}/${_ics(finish, date: true)}' : '${_ics(start)}/${_ics(finish)}',
    if (place.isNotEmpty) 'location': place,
    if (details.isNotEmpty) 'details': details.length > 1200 ? '${details.substring(0, 1200)}…' : details,
  });
}
