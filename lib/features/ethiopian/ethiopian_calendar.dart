/// The Ethiopian calendar, worked out on the phone: dates both ways, month
/// names in Amharic, Ge'ez numerals, the Ethiopian clock, the year's
/// evangelist, public holidays (Fasika and the Muslim holidays computed for
/// each year) and the Orthodox fasts.
library;

/// A date in the Ethiopian calendar: 12 months of 30 days, then Pagume (5
/// days, 6 in a leap year).
class EtDate implements Comparable<EtDate> {
  const EtDate(this.year, this.month, this.day);
  final int year;
  final int month;
  final int day;

  static const _epoch = 1723856;

  factory EtDate.fromGregorian(DateTime g) => EtDate.fromJdn(_gregorianToJdn(g.year, g.month, g.day));

  factory EtDate.fromJdn(int jdn) {
    final r = (jdn - _epoch) % 1461;
    final n = r % 365 + 365 * (r ~/ 1460);
    final year = 4 * ((jdn - _epoch) ~/ 1461) + r ~/ 365 - r ~/ 1460;
    return EtDate(year, n ~/ 30 + 1, n % 30 + 1);
  }

  factory EtDate.today() => EtDate.fromGregorian(DateTime.now());

  int get jdn => _epoch + 365 + 365 * (year - 1) + year ~/ 4 + 30 * month + day - 31;

  DateTime get gregorian => _jdnToGregorian(jdn);

  /// Pagume has 6 days in the year before a Gregorian leap year.
  static bool isLeap(int year) => year % 4 == 3;

  static int daysIn(int year, int month) => month < 13 ? 30 : (isLeap(year) ? 6 : 5);

  bool get valid => month >= 1 && month <= 13 && day >= 1 && day <= daysIn(year, month);

  EtDate addDays(int n) => EtDate.fromJdn(jdn + n);

  int get dayOfYear => (month - 1) * 30 + day;

  /// 0 Monday … 6 Sunday, as DateTime.weekday − 1.
  int get weekdayIndex => gregorian.weekday - 1;

  String get monthName => etMonths[month - 1].$1;
  String get monthAmharic => etMonths[month - 1].$2;
  String get weekdayAmharic => etWeekdays[weekdayIndex];

  /// "ሐሙስ፣ ኅዳር 3 ቀን 2019 ዓ.ም."
  String get amharic => '$weekdayAmharic፣ $monthAmharic $day ቀን $year ዓ.ም.';

  /// "Hidar 3, 2019"
  String get english => '$monthName $day, $year';

  /// The evangelist the year is named after, in turn.
  String get evangelist => evangelistOf(year);

  static String evangelistOf(int year) => const ['Yohannes (John)', 'Matewos (Matthew)', 'Markos (Mark)', 'Lukas (Luke)'][year % 4];
  static String evangelistAmharic(int year) => const ['ዮሐንስ', 'ማቴዎስ', 'ማርቆስ', 'ሉቃስ'][year % 4];

  String get iso => '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  /// "2017-05-12" (year-month-day, months 1–13).
  static EtDate? parse(String s) {
    final m = RegExp(r'^\s*(\d{3,4})\s*[-/.]\s*(\d{1,2})\s*[-/.]\s*(\d{1,2})\s*$').firstMatch(s);
    if (m == null) return null;
    final d = EtDate(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    return d.valid ? d : null;
  }

  @override
  int compareTo(EtDate other) => jdn.compareTo(other.jdn);

  @override
  bool operator ==(Object other) => other is EtDate && other.jdn == jdn;

  @override
  int get hashCode => jdn;
}

const etMonths = [
  ('Meskerem', 'መስከረም'),
  ('Tikimt', 'ጥቅምት'),
  ('Hidar', 'ኅዳር'),
  ('Tahsas', 'ታኅሣሥ'),
  ('Tir', 'ጥር'),
  ('Yekatit', 'የካቲት'),
  ('Megabit', 'መጋቢት'),
  ('Miyazya', 'ሚያዝያ'),
  ('Ginbot', 'ግንቦት'),
  ('Sene', 'ሰኔ'),
  ('Hamle', 'ሐምሌ'),
  ('Nehase', 'ነሐሴ'),
  ('Pagume', 'ጳጉሜ'),
];

/// Monday first, like DateTime.weekday.
const etWeekdays = ['ሰኞ', 'ማክሰኞ', 'ረቡዕ', 'ሐሙስ', 'ዓርብ', 'ቅዳሜ', 'እሑድ'];
const enWeekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

int _gregorianToJdn(int y, int m, int d) {
  final a = (14 - m) ~/ 12;
  final y2 = y + 4800 - a;
  final m2 = m + 12 * a - 3;
  return d + (153 * m2 + 2) ~/ 5 + 365 * y2 + y2 ~/ 4 - y2 ~/ 100 + y2 ~/ 400 - 32045;
}

DateTime _jdnToGregorian(int jdn) {
  final a = jdn + 32044;
  final b = (4 * a + 3) ~/ 146097;
  final c = a - 146097 * b ~/ 4;
  final d = (4 * c + 3) ~/ 1461;
  final e = c - 1461 * d ~/ 4;
  final m = (5 * e + 2) ~/ 153;
  return DateTime(100 * b + d - 4800 + m ~/ 10, m + 3 - 12 * (m ~/ 10), e - (153 * m + 2) ~/ 5 + 1);
}

int jdnOf(DateTime g) => _gregorianToJdn(g.year, g.month, g.day);

/// A number in Ge'ez numerals: 2017 → ፳፻፲፯.
String geez(int n) {
  if (n <= 0) return '$n';
  const ones = ['', '፩', '፪', '፫', '፬', '፭', '፮', '፯', '፰', '፱'];
  const tens = ['', '፲', '፳', '፴', '፵', '፶', '፷', '፸', '፹', '፺'];
  var s = '$n';
  if (s.length.isOdd) s = '0$s';
  final out = StringBuffer();
  final pairs = s.length ~/ 2;
  for (var i = 0; i < pairs; i++) {
    final v = int.parse(s.substring(i * 2, i * 2 + 2));
    final pos = pairs - 1 - i;
    if (v == 0) {
      if (pos > 0 && pos.isEven) out.write('፼');
      continue;
    }
    // One hundred is ፻, not ፩፻.
    if (!(v == 1 && pos > 0)) out.write('${tens[v ~/ 10]}${ones[v % 10]}');
    if (pos > 0) out.write(pos.isOdd ? '፻' : '፼');
  }
  return out.toString();
}

/// The Ethiopian clock: hours count from 6 in the morning and evening.
/// 08:30 → "2:30 ጠዋት".
String ethiopianTime(DateTime t) {
  var h = (t.hour + 6) % 12;
  if (h == 0) h = 12;
  final period = switch (t.hour) {
    >= 6 && < 12 => 'ጠዋት',
    >= 12 && < 18 => 'ከሰዓት',
    >= 18 && < 24 => 'ማታ',
    _ => 'ሌሊት',
  };
  return '$h:${t.minute.toString().padLeft(2, '0')} $period';
}

/// Orthodox Easter (Fasika) in the Gregorian calendar, 1900–2099.
DateTime fasika(int gregorianYear) {
  final a = gregorianYear % 4, b = gregorianYear % 7, c = gregorianYear % 19;
  final d = (19 * c + 15) % 30;
  final e = (2 * a + 4 * b - d + 34) % 7;
  final month = (d + e + 114) ~/ 31;
  final day = (d + e + 114) % 31 + 1;
  return DateTime(gregorianYear, month, day).add(const Duration(days: 13));
}

/// A tabular Islamic date in the Gregorian calendar; the real day depends
/// on the moon being seen, so it may differ by a day.
DateTime _hijri(int y, int m, int d) {
  final jdn = d + (29.5 * (m - 1)).ceil() + (y - 1) * 354 + (3 + 11 * y) ~/ 30 + 1948440 - 1;
  return _jdnToGregorian(jdn);
}

int _hijriYearOf(DateTime g) => ((jdnOf(g) - 1948440) * 30 / 10631).floor() + 1;

enum EtEventKind { public, religious, observance, fast }

class EtEvent {
  const EtEvent(this.name, this.amharic, this.kind, this.start, {this.end, this.approximate = false, this.note});
  final String name;
  final String amharic;
  final EtEventKind kind;
  final DateTime start;

  /// The last day of a fast.
  final DateTime? end;
  final bool approximate;
  final String? note;

  bool covers(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return !day.isBefore(start) && !day.isAfter(end ?? start);
  }

  int get days => end == null ? 1 : end!.difference(start).inDays + 1;
}

/// The holidays, observances and fasts of Ethiopian year [year], in order.
List<EtEvent> etEvents(int year, {bool fasts = true}) {
  DateTime et(int m, int d) => EtDate(year, m, d).gregorian;
  final first = et(1, 1);
  final last = EtDate(year, 13, EtDate.daysIn(year, 13)).gregorian;
  final out = <EtEvent>[
    EtEvent('Enkutatash (New Year)', 'እንቁጣጣሽ', EtEventKind.public, et(1, 1)),
    EtEvent('Meskel (Finding of the True Cross)', 'መስቀል', EtEventKind.public, et(1, 17)),
    EtEvent('Hidar Tsion', 'ኅዳር ጽዮን', EtEventKind.observance, et(3, 21)),
    EtEvent('Kulubi Gabriel', 'ቁልቢ ገብርኤል', EtEventKind.observance, et(4, 19)),
    EtEvent('Genna (Christmas)', 'ገና', EtEventKind.public, DateTime(first.year + 1, 1, 7)),
    EtEvent('Ketera (Epiphany Eve)', 'ከተራ', EtEventKind.observance, et(5, 10)),
    EtEvent('Timket (Epiphany)', 'ጥምቀት', EtEventKind.public, et(5, 11)),
    EtEvent('Adwa Victory Day', 'የዓድዋ ድል በዓል', EtEventKind.public, et(6, 23)),
    EtEvent('International Labour Day', 'የሠራተኞች ቀን', EtEventKind.public, DateTime(first.year + 1, 5, 1)),
    EtEvent('Patriots\' Victory Day', 'የአርበኞች ቀን', EtEventKind.public, et(8, 27)),
    EtEvent('Downfall of the Derg', 'ግንቦት 20', EtEventKind.public, et(9, 20)),
    EtEvent('Buhe', 'ቡሄ', EtEventKind.observance, et(12, 13)),
    EtEvent('Filseta (Assumption)', 'ፍልሰታ', EtEventKind.religious, et(12, 16)),
  ];
  // Fasika and the days that hang on it, for the Gregorian years the
  // Ethiopian year spans.
  for (final gy in {first.year, last.year}) {
    final e = fasika(gy);
    DateTime off(int d) => e.add(Duration(days: d));
    out.addAll([
      EtEvent('Debre Zeit (Mid-Lent)', 'ደብረ ዘይት', EtEventKind.observance, off(-28)),
      EtEvent('Hosanna (Palm Sunday)', 'ሆሣዕና', EtEventKind.religious, off(-7)),
      EtEvent('Siklet (Good Friday)', 'ስቅለት', EtEventKind.public, off(-2)),
      EtEvent('Fasika (Easter)', 'ፋሲካ', EtEventKind.public, e),
      EtEvent('Erget (Ascension)', 'ዕርገት', EtEventKind.religious, off(39)),
      EtEvent('Paraclete (Pentecost)', 'ጰራቅሊጦስ', EtEventKind.religious, off(49)),
    ]);
    if (fasts) {
      out.addAll([
        EtEvent('Tsome Nenewe (Fast of Nineveh)', 'ጾመ ነነዌ', EtEventKind.fast, off(-69), end: off(-67)),
        EtEvent('Abiy Tsom (Great Lent)', 'ዐቢይ ጾም', EtEventKind.fast, off(-55), end: off(-1)),
        EtEvent('Tsome Hawariat (Fast of the Apostles)', 'ጾመ ሐዋርያት', EtEventKind.fast, off(50), end: EtDate.fromGregorian(off(50)).year == year ? et(11, 4) : EtDate(year + 1, 11, 4).gregorian),
      ]);
    }
  }
  if (fasts) {
    out.addAll([
      EtEvent('Tsome Nebiyat (Advent)', 'ጾመ ነቢያት', EtEventKind.fast, et(3, 15), end: et(4, 28)),
      EtEvent('Tsome Filseta (Fast of the Assumption)', 'ጾመ ፍልሰታ', EtEventKind.fast, et(12, 1), end: et(12, 15)),
    ]);
  }
  // The Muslim holidays, from the Hijri years the Ethiopian year spans.
  for (var hy = _hijriYearOf(first) - 1; hy <= _hijriYearOf(last) + 1; hy++) {
    out.addAll([
      EtEvent('Mawlid (Prophet\'s Birthday)', 'መውሊድ', EtEventKind.public, _hijri(hy, 3, 12), approximate: true),
      EtEvent('Eid al-Fitr', 'ኢድ አል ፈጥር', EtEventKind.public, _hijri(hy, 10, 1), approximate: true),
      EtEvent('Eid al-Adha (Arafa)', 'ኢድ አል አድሃ', EtEventKind.public, _hijri(hy, 12, 10), approximate: true),
    ]);
  }
  final kept = out.where((e) => !e.start.isBefore(first) && !e.start.isAfter(last)).toList()..sort((a, b) => a.start.compareTo(b.start));
  return kept;
}

/// The Wednesday and Friday fasts, except in the fifty days after Fasika
/// and when Genna or Timket falls on them.
bool weeklyFast(DateTime d) {
  if (d.weekday != DateTime.wednesday && d.weekday != DateTime.friday) return false;
  final e = fasika(d.year);
  final day = DateTime(d.year, d.month, d.day);
  if (day.isAfter(e) && !day.isAfter(e.add(const Duration(days: 49)))) return false;
  if (d.month == 1 && (d.day == 7 || d.day == 19 || d.day == 20)) return false;
  return true;
}
