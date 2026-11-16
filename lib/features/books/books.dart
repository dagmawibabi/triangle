import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../infrastructure/telegram/accounts.dart';
import '../sections/section_kit.dart';
import '../telegram/data/telegram_store.dart';
import 'book_parsers.dart';

// The library: books from the channels and groups picked as sources, and
// files from the phone. Each book is copied into the app's folder, parsed
// once into blocks (see book_parsers.dart), and read in the app's reader.
// Shelves, progress, highlights, bookmarks and reading time stay here.

enum ReadStatus {
  want('Want to read'),
  reading('Reading'),
  finished('Finished'),
  abandoned('Stopped');

  const ReadStatus(this.label);
  final String label;
}

String _id() => const Uuid().v4().substring(0, 10);

@immutable
class Book {
  const Book({
    required this.id,
    required this.title,
    this.author = '',
    required this.format,
    this.fileName = '',
    this.path,
    this.size = 0,
    this.account,
    this.chatId,
    this.messageId,
    this.source = '',
    this.coverPath,
    this.mini,
    this.description = '',
    this.publisher = '',
    this.year = '',
    this.language = '',
    required this.addedAt,
    this.openedAt,
    this.finishedAt,
    this.progress = 0,
    this.block = 0,
    this.offset = 0,
    this.page = 0,
    this.pages = 0,
    this.status = ReadStatus.want,
    this.favorite = false,
    this.rating = 0,
    this.shelves = const [],
    this.words = 0,
    this.minutes = 0,
    this.notes = '',
  });
  final String id;
  final String title;
  final String author;

  /// The file's extension: epub, pdf, docx…
  final String format;
  final String fileName;

  /// The copy in the app's folder, once downloaded.
  final String? path;
  final int size;

  /// Where it was posted, for books from Telegram.
  final String? account;
  final int? chatId;
  final int? messageId;
  final String source;
  final String? coverPath;

  /// The post's blurry preview, until there's a cover.
  final String? mini;
  final String description;
  final String publisher;
  final String year;
  final String language;
  final DateTime addedAt;
  final DateTime? openedAt;
  final DateTime? finishedAt;

  /// 0..1 through the book.
  final double progress;

  /// Where the reader was: a block, and how far down its chapter (0..1).
  final int block;
  final double offset;

  /// PDFs: the page and how many.
  final int page;
  final int pages;
  final ReadStatus status;
  final bool favorite;
  final int rating;
  final List<String> shelves;
  final int words;
  final int minutes;

  /// The person's own notes about the book.
  final String notes;

  bool get downloaded => path != null && File(path!).existsSync();
  bool get readable => readableFormats.contains(format) || format == 'pdf';
  String? get postKeyOf => account == null || chatId == null || messageId == null ? null : postKey(account!, chatId!, messageId!);

  Book copyWith({
    String? title,
    String? author,
    String? path,
    String? coverPath,
    String? description,
    String? publisher,
    String? year,
    String? language,
    DateTime? openedAt,
    DateTime? finishedAt,
    bool clearFinished = false,
    double? progress,
    int? block,
    double? offset,
    int? page,
    int? pages,
    ReadStatus? status,
    bool? favorite,
    int? rating,
    List<String>? shelves,
    int? words,
    int? minutes,
    String? notes,
  }) => Book(
    id: id,
    title: title ?? this.title,
    author: author ?? this.author,
    format: format,
    fileName: fileName,
    path: path ?? this.path,
    size: size,
    account: account,
    chatId: chatId,
    messageId: messageId,
    source: source,
    coverPath: coverPath ?? this.coverPath,
    mini: mini,
    description: description ?? this.description,
    publisher: publisher ?? this.publisher,
    year: year ?? this.year,
    language: language ?? this.language,
    addedAt: addedAt,
    openedAt: openedAt ?? this.openedAt,
    finishedAt: clearFinished ? null : (finishedAt ?? this.finishedAt),
    progress: progress ?? this.progress,
    block: block ?? this.block,
    offset: offset ?? this.offset,
    page: page ?? this.page,
    pages: pages ?? this.pages,
    status: status ?? this.status,
    favorite: favorite ?? this.favorite,
    rating: rating ?? this.rating,
    shelves: shelves ?? this.shelves,
    words: words ?? this.words,
    minutes: minutes ?? this.minutes,
    notes: notes ?? this.notes,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    't': title,
    if (author.isNotEmpty) 'a': author,
    'f': format,
    if (fileName.isNotEmpty) 'fn': fileName,
    if (path != null) 'p': path,
    if (size > 0) 'sz': size,
    if (account != null) 'ac': account,
    if (chatId != null) 'c': chatId,
    if (messageId != null) 'm': messageId,
    if (source.isNotEmpty) 'src': source,
    if (coverPath != null) 'cv': coverPath,
    if (mini != null) 'mi': mini,
    if (description.isNotEmpty) 'd': description,
    if (publisher.isNotEmpty) 'pub': publisher,
    if (year.isNotEmpty) 'y': year,
    if (language.isNotEmpty) 'lang': language,
    'at': addedAt.millisecondsSinceEpoch,
    if (openedAt != null) 'op': openedAt!.millisecondsSinceEpoch,
    if (finishedAt != null) 'fin': finishedAt!.millisecondsSinceEpoch,
    if (progress > 0) 'pr': progress,
    if (block > 0) 'b': block,
    if (offset > 0) 'o': offset,
    if (page > 0) 'pg': page,
    if (pages > 0) 'pgs': pages,
    's': status.name,
    if (favorite) 'fav': true,
    if (rating > 0) 'r': rating,
    if (shelves.isNotEmpty) 'sh': shelves,
    if (words > 0) 'w': words,
    if (minutes > 0) 'min': minutes,
    if (notes.isNotEmpty) 'n': notes,
  };

  factory Book.fromJson(Map j) {
    DateTime? at(String k) => j[k] == null ? null : DateTime.fromMillisecondsSinceEpoch((j[k] as num).toInt());
    return Book(
      id: '${j['id']}',
      title: '${j['t'] ?? 'Untitled'}',
      author: '${j['a'] ?? ''}',
      format: '${j['f'] ?? 'txt'}',
      fileName: '${j['fn'] ?? ''}',
      path: j['p'] as String?,
      size: (j['sz'] as num?)?.toInt() ?? 0,
      account: j['ac'] as String?,
      chatId: (j['c'] as num?)?.toInt(),
      messageId: (j['m'] as num?)?.toInt(),
      source: '${j['src'] ?? ''}',
      coverPath: j['cv'] as String?,
      mini: j['mi'] as String?,
      description: '${j['d'] ?? ''}',
      publisher: '${j['pub'] ?? ''}',
      year: '${j['y'] ?? ''}',
      language: '${j['lang'] ?? ''}',
      addedAt: at('at') ?? DateTime.now(),
      openedAt: at('op'),
      finishedAt: at('fin'),
      progress: (j['pr'] as num?)?.toDouble() ?? 0,
      block: (j['b'] as num?)?.toInt() ?? 0,
      offset: (j['o'] as num?)?.toDouble() ?? 0,
      page: (j['pg'] as num?)?.toInt() ?? 0,
      pages: (j['pgs'] as num?)?.toInt() ?? 0,
      status: ReadStatus.values.asNameMap()['${j['s']}'] ?? ReadStatus.want,
      favorite: j['fav'] == true,
      rating: (j['r'] as num?)?.toInt() ?? 0,
      shelves: [for (final s in (j['sh'] as List? ?? const [])) '$s'],
      words: (j['w'] as num?)?.toInt() ?? 0,
      minutes: (j['min'] as num?)?.toInt() ?? 0,
      notes: '${j['n'] ?? ''}',
    );
  }

  Map<String, dynamic> describe() => {
    'book_id': id,
    'title': title,
    if (author.isNotEmpty) 'author': author,
    'format': format,
    'status': status.name,
    'progress_percent': (progress * 100).round(),
    if (favorite) 'favorite': true,
    if (rating > 0) 'rating': rating,
    if (shelves.isNotEmpty) 'shelves': shelves,
    if (source.isNotEmpty) 'from': source,
    'downloaded': path != null,
    if (pages > 0) 'pages': pages,
    if (minutes > 0) 'minutes_read': minutes,
    if (year.isNotEmpty) 'year': year,
    if (openedAt != null) 'last_opened': openedAt!.toIso8601String().substring(0, 10),
  };
}

const highlightColors = [0xFFFFE066, 0xFF8CE99A, 0xFF74C0FC, 0xFFFFA8A8, 0xFFD0BFFF];

@immutable
class Highlight {
  const Highlight({required this.id, required this.bookId, required this.block, required this.start, required this.end, required this.text, this.color = 0, this.note = '', required this.at});
  final String id;
  final String bookId;
  final int block;
  final int start;
  final int end;
  final String text;
  final int color;
  final String note;
  final DateTime at;

  Highlight copyWith({int? color, String? note}) => Highlight(id: id, bookId: bookId, block: block, start: start, end: end, text: text, color: color ?? this.color, note: note ?? this.note, at: at);
  Map<String, dynamic> toJson() => {'id': id, 'b': bookId, 'bl': block, 's': start, 'e': end, 't': text, if (color != 0) 'c': color, if (note.isNotEmpty) 'n': note, 'at': at.millisecondsSinceEpoch};
  factory Highlight.fromJson(Map j) => Highlight(
    id: '${j['id']}',
    bookId: '${j['b']}',
    block: (j['bl'] as num).toInt(),
    start: (j['s'] as num).toInt(),
    end: (j['e'] as num).toInt(),
    text: '${j['t'] ?? ''}',
    color: (j['c'] as num?)?.toInt() ?? 0,
    note: '${j['n'] ?? ''}',
    at: DateTime.fromMillisecondsSinceEpoch((j['at'] as num?)?.toInt() ?? 0),
  );
}

@immutable
class Bookmark {
  const Bookmark({required this.id, required this.bookId, required this.block, this.page = 0, required this.label, this.excerpt = '', required this.at});
  final String id;
  final String bookId;
  final int block;
  final int page;
  final String label;
  final String excerpt;
  final DateTime at;

  Map<String, dynamic> toJson() => {'id': id, 'b': bookId, 'bl': block, if (page > 0) 'pg': page, 'l': label, if (excerpt.isNotEmpty) 'x': excerpt, 'at': at.millisecondsSinceEpoch};
  factory Bookmark.fromJson(Map j) => Bookmark(
    id: '${j['id']}',
    bookId: '${j['b']}',
    block: (j['bl'] as num?)?.toInt() ?? 0,
    page: (j['pg'] as num?)?.toInt() ?? 0,
    label: '${j['l'] ?? ''}',
    excerpt: '${j['x'] ?? ''}',
    at: DateTime.fromMillisecondsSinceEpoch((j['at'] as num?)?.toInt() ?? 0),
  );
}

enum ReaderTheme {
  paper('Paper', 0xFFFFFFFF, 0xFF1C1C1E),
  sepia('Sepia', 0xFFF4ECD8, 0xFF5B4636),
  dusk('Dusk', 0xFF2B2B2E, 0xFFE4E4E7),
  black('Black', 0xFF000000, 0xFFC9C9CF);

  const ReaderTheme(this.label, this.bg, this.fg);
  final String label;
  final int bg;
  final int fg;
  bool get dark => this == dusk || this == black;
}

@immutable
class ReaderPrefs {
  const ReaderPrefs({this.theme = ReaderTheme.paper, this.fontSize = 18, this.lineHeight = 1.6, this.serif = true, this.margin = 20, this.justify = false, this.pdfDark = false});
  final ReaderTheme theme;
  final double fontSize;
  final double lineHeight;
  final bool serif;
  final double margin;
  final bool justify;
  final bool pdfDark;

  ReaderPrefs copyWith({ReaderTheme? theme, double? fontSize, double? lineHeight, bool? serif, double? margin, bool? justify, bool? pdfDark}) => ReaderPrefs(
    theme: theme ?? this.theme,
    fontSize: fontSize ?? this.fontSize,
    lineHeight: lineHeight ?? this.lineHeight,
    serif: serif ?? this.serif,
    margin: margin ?? this.margin,
    justify: justify ?? this.justify,
    pdfDark: pdfDark ?? this.pdfDark,
  );

  Map<String, dynamic> toJson() => {'theme': theme.name, 'size': fontSize, 'line': lineHeight, 'serif': serif, 'margin': margin, 'justify': justify, 'pdf_dark': pdfDark};
  factory ReaderPrefs.fromJson(Map j) => ReaderPrefs(
    theme: ReaderTheme.values.asNameMap()['${j['theme']}'] ?? ReaderTheme.paper,
    fontSize: (j['size'] as num?)?.toDouble() ?? 18,
    lineHeight: (j['line'] as num?)?.toDouble() ?? 1.6,
    serif: j['serif'] != false,
    margin: (j['margin'] as num?)?.toDouble() ?? 20,
    justify: j['justify'] == true,
    pdfDark: j['pdf_dark'] == true,
  );
}

enum BookSort {
  recent('Recently read'),
  added('Recently added'),
  title('Title'),
  author('Author'),
  progress('Progress');

  const BookSort(this.label);
  final String label;
}

@immutable
class BooksState {
  const BooksState({
    this.sources = const [],
    this.books = const [],
    this.shelves = const [],
    this.highlights = const [],
    this.bookmarks = const [],
    this.prefs = const ReaderPrefs(),
    this.days = const {},
    this.goal = 20,
    this.sort = BookSort.recent,
    this.grid = true,
    this.inDrawer = true,
  });
  final List<SourceRef> sources;
  final List<Book> books;

  /// The person's shelves, in order.
  final List<String> shelves;
  final List<Highlight> highlights;
  final List<Bookmark> bookmarks;
  final ReaderPrefs prefs;

  /// Minutes read per day (`yyyy-mm-dd`).
  final Map<String, int> days;

  /// Minutes a day to aim for.
  final int goal;
  final BookSort sort;
  final bool grid;
  final bool inDrawer;

  Book? byId(String id) => books.where((b) => b.id == id).firstOrNull;
  Book? byPost(String key) => books.where((b) => b.postKeyOf == key).firstOrNull;

  List<Book> get sorted {
    final list = [...books];
    list.sort(switch (sort) {
      BookSort.recent => (a, b) => (b.openedAt ?? b.addedAt).compareTo(a.openedAt ?? a.addedAt),
      BookSort.added => (a, b) => b.addedAt.compareTo(a.addedAt),
      BookSort.title => (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      BookSort.author => (a, b) => a.author.toLowerCase().compareTo(b.author.toLowerCase()),
      BookSort.progress => (a, b) => b.progress.compareTo(a.progress),
    });
    return list;
  }

  int get todayMinutes => days[dayKey(DateTime.now())] ?? 0;
  int get streak {
    var n = 0;
    var d = DateTime.now();
    if (!days.containsKey(dayKey(d))) d = d.subtract(const Duration(days: 1));
    while (days.containsKey(dayKey(d))) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  static String dayKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  BooksState copyWith({
    List<SourceRef>? sources,
    List<Book>? books,
    List<String>? shelves,
    List<Highlight>? highlights,
    List<Bookmark>? bookmarks,
    ReaderPrefs? prefs,
    Map<String, int>? days,
    int? goal,
    BookSort? sort,
    bool? grid,
    bool? inDrawer,
  }) => BooksState(
    sources: sources ?? this.sources,
    books: books ?? this.books,
    shelves: shelves ?? this.shelves,
    highlights: highlights ?? this.highlights,
    bookmarks: bookmarks ?? this.bookmarks,
    prefs: prefs ?? this.prefs,
    days: days ?? this.days,
    goal: goal ?? this.goal,
    sort: sort ?? this.sort,
    grid: grid ?? this.grid,
    inDrawer: inDrawer ?? this.inDrawer,
  );
}

class BooksStore extends Notifier<BooksState> {
  static const key = 'books.v1';
  static const notesKey = 'books_notes.v1';
  late Future<void> ready;

  /// Whether the saved library has been read (until then, no books or
  /// sources means "not known yet", not "none").
  bool isReady = false;

  @override
  BooksState build() {
    ready = _load().whenComplete(() {
      isReady = true;
      state = state.copyWith();
    });
    return const BooksState();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      final j = raw == null ? const {} : jsonDecode(raw) as Map;
      final nraw = prefs.getString(notesKey);
      final n = nraw == null ? const {} : jsonDecode(nraw) as Map;
      state = BooksState(
        sources: [for (final s in (j['sources'] as List? ?? const [])) if (s is Map) SourceRef.fromJson(s)],
        books: [for (final b in (j['books'] as List? ?? const [])) if (b is Map) Book.fromJson(b)],
        shelves: [for (final s in (j['shelves'] as List? ?? const [])) '$s'],
        highlights: [for (final h in (n['highlights'] as List? ?? const [])) if (h is Map) Highlight.fromJson(h)],
        bookmarks: [for (final h in (n['bookmarks'] as List? ?? const [])) if (h is Map) Bookmark.fromJson(h)],
        prefs: j['prefs'] is Map ? ReaderPrefs.fromJson(j['prefs'] as Map) : const ReaderPrefs(),
        days: {for (final e in ((j['days'] as Map?) ?? const {}).entries) '${e.key}': (e.value as num).toInt()},
        goal: (j['goal'] as num?)?.toInt() ?? 20,
        sort: BookSort.values.asNameMap()['${j['sort']}'] ?? BookSort.recent,
        grid: j['grid'] != false,
        inDrawer: j['in_drawer'] != false,
      );
    } catch (e) {
      debugPrint('[Books] $e');
    }
  }

  Future<void> _set(BooksState s, {bool notes = false}) async {
    state = s;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      key,
      jsonEncode({
        'sources': [for (final x in s.sources) x.toJson()],
        'books': [for (final x in s.books) x.toJson()],
        'shelves': s.shelves,
        'prefs': s.prefs.toJson(),
        'days': s.days,
        'goal': s.goal,
        'sort': s.sort.name,
        'grid': s.grid,
        'in_drawer': s.inDrawer,
      }),
    );
    if (notes) {
      await prefs.setString(notesKey, jsonEncode({'highlights': [for (final h in s.highlights) h.toJson()], 'bookmarks': [for (final b in s.bookmarks) b.toJson()]}));
    }
  }

  Book? find(String idOrTitle) {
    final q = idOrTitle.trim().toLowerCase();
    if (q.isEmpty) return null;
    return state.byId(idOrTitle.trim()) ?? state.books.where((b) => b.title.toLowerCase() == q).firstOrNull ?? state.books.where((b) => b.title.toLowerCase().contains(q)).firstOrNull;
  }

  // sources
  Future<void> setSources(List<SourceRef> v) => _set(state.copyWith(sources: v));
  Future<void> addSources(Iterable<SourceRef> v) {
    final have = {for (final s in state.sources) s.key};
    return _set(state.copyWith(sources: [...state.sources, for (final s in v) if (have.add(s.key)) s]));
  }

  Future<void> removeSource(String k) => _set(state.copyWith(sources: [for (final s in state.sources) if (s.key != k) s]));

  // books
  Future<void> update(String id, Book Function(Book) f) => _set(state.copyWith(books: [for (final b in state.books) b.id == id ? f(b) : b]));
  Future<void> setStatus(String id, ReadStatus s) => update(id, (b) => b.copyWith(status: s, finishedAt: s == ReadStatus.finished ? DateTime.now() : null, clearFinished: s != ReadStatus.finished, progress: s == ReadStatus.finished ? 1 : null));
  Future<void> setFavorite(String id, bool v) => update(id, (b) => b.copyWith(favorite: v));
  Future<void> setRating(String id, int v) => update(id, (b) => b.copyWith(rating: v.clamp(0, 5)));
  Future<void> setShelves(String id, List<String> v) async {
    final all = [...state.shelves, for (final s in v) if (!state.shelves.contains(s)) s];
    await _set(state.copyWith(shelves: all, books: [for (final b in state.books) b.id == id ? b.copyWith(shelves: v) : b]));
  }

  Future<void> remove(String id, {bool deleteFile = true}) async {
    final b = state.byId(id);
    await _set(
      state.copyWith(
        books: [for (final x in state.books) if (x.id != id) x],
        highlights: [for (final h in state.highlights) if (h.bookId != id) h],
        bookmarks: [for (final h in state.bookmarks) if (h.bookId != id) h],
      ),
      notes: true,
    );
    if (deleteFile && b != null) {
      try {
        final dir = await _dir(id);
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  // shelves
  Future<void> addShelf(String name) {
    final n = name.trim();
    if (n.isEmpty || state.shelves.contains(n)) return Future.value();
    return _set(state.copyWith(shelves: [...state.shelves, n]));
  }

  Future<void> renameShelf(String from, String to) => _set(state.copyWith(
    shelves: [for (final s in state.shelves) s == from ? to : s],
    books: [for (final b in state.books) b.shelves.contains(from) ? b.copyWith(shelves: [for (final s in b.shelves) s == from ? to : s]) : b],
  ));

  Future<void> deleteShelf(String name) => _set(state.copyWith(
    shelves: [for (final s in state.shelves) if (s != name) s],
    books: [for (final b in state.books) b.shelves.contains(name) ? b.copyWith(shelves: [for (final s in b.shelves) if (s != name) s]) : b],
  ));

  Future<void> moveShelf(int from, int to) {
    final list = [...state.shelves];
    if (from < 0 || from >= list.length) return Future.value();
    final s = list.removeAt(from);
    list.insert(to.clamp(0, list.length), s);
    return _set(state.copyWith(shelves: list));
  }

  // notes
  Future<Highlight> addHighlight(String bookId, int block, int start, int end, String text, {int color = 0, String note = ''}) async {
    final h = Highlight(id: _id(), bookId: bookId, block: block, start: start, end: end, text: text, color: color, note: note, at: DateTime.now());
    await _set(state.copyWith(highlights: [...state.highlights, h]), notes: true);
    return h;
  }

  Future<void> updateHighlight(String id, Highlight Function(Highlight) f) => _set(state.copyWith(highlights: [for (final h in state.highlights) h.id == id ? f(h) : h]), notes: true);
  Future<void> removeHighlight(String id) => _set(state.copyWith(highlights: [for (final h in state.highlights) if (h.id != id) h]), notes: true);

  Future<Bookmark> addBookmark(String bookId, {int block = 0, int page = 0, required String label, String excerpt = ''}) async {
    final b = Bookmark(id: _id(), bookId: bookId, block: block, page: page, label: label, excerpt: excerpt, at: DateTime.now());
    await _set(state.copyWith(bookmarks: [...state.bookmarks, b]), notes: true);
    return b;
  }

  Future<void> removeBookmark(String id) => _set(state.copyWith(bookmarks: [for (final b in state.bookmarks) if (b.id != id) b]), notes: true);

  // reading
  Future<void> setPrefs(ReaderPrefs p) => _set(state.copyWith(prefs: p));
  Future<void> setGoal(int minutes) => _set(state.copyWith(goal: minutes.clamp(1, 600)));
  Future<void> setSort(BookSort v) => _set(state.copyWith(sort: v));
  Future<void> setGrid(bool v) => _set(state.copyWith(grid: v));
  Future<void> setInDrawer(bool v) => _set(state.copyWith(inDrawer: v));

  Timer? _later;

  /// Where the reader is in [id]: saved in a moment, not every frame.
  void savePosition(String id, {int? block, double? offset, double? progress, int? page, int? pages}) {
    state = state.copyWith(books: [
      for (final b in state.books)
        if (b.id == id)
          b.copyWith(
            block: block,
            offset: offset,
            progress: progress,
            page: page,
            pages: pages,
            openedAt: DateTime.now(),
            status: b.status == ReadStatus.want ? ReadStatus.reading : null,
          )
        else
          b,
    ]);
    _later?.cancel();
    _later = Timer(const Duration(seconds: 3), () => _set(state));
  }

  /// One more minute spent reading [id].
  Future<void> readMinute(String id) {
    final day = BooksState.dayKey(DateTime.now());
    return _set(state.copyWith(
      days: {...state.days, day: (state.days[day] ?? 0) + 1},
      books: [for (final b in state.books) b.id == id ? b.copyWith(minutes: b.minutes + 1) : b],
    ));
  }

  // ---- files ---------------------------------------------------------------------

  Future<Directory> _dir(String id) async => Directory('${(await getApplicationSupportDirectory()).path}/books/$id');

  /// Adds a file from the phone: copied in, then read for its title,
  /// author and cover.
  Future<Book> importFile(String path, {String? shelf}) async {
    await ready;
    final id = _id();
    final name = path.split(RegExp(r'[\\/]')).last;
    final dir = await _dir(id);
    await dir.create(recursive: true);
    final copy = await File(path).copy('${dir.path}/$name');
    final b = Book(
      id: id,
      title: _stripExt(name),
      format: extOf(name),
      fileName: name,
      path: copy.path,
      size: await copy.length(),
      addedAt: DateTime.now(),
      shelves: shelf == null ? const [] : [shelf],
    );
    await _set(state.copyWith(books: [b, ...state.books]));
    await prepare(id);
    return state.byId(id)!;
  }

  /// Adds a book posted in Telegram (not downloaded until opened, unless
  /// [download]).
  Future<Book> addPost(BookPost p, {bool download = false, String? shelf}) async {
    await ready;
    final have = state.byPost(p.key);
    if (have != null) return have;
    final b = Book(
      id: _id(),
      title: p.title,
      format: p.format,
      fileName: p.fileName,
      size: p.size,
      account: p.account,
      chatId: p.chatId,
      messageId: p.messageId,
      source: p.source,
      mini: p.mini?.data,
      description: p.caption,
      addedAt: DateTime.now(),
      shelves: shelf == null ? const [] : [shelf],
    );
    await _set(state.copyWith(books: [b, ...state.books]));
    if (download) await this.download(b.id);
    return state.byId(b.id)!;
  }

  final _downloading = <String, ValueNotifier<double>>{};
  ValueListenable<double>? downloadProgress(String id) => _downloading[id];

  /// The Telegram file each download is fetching, by book.
  final _fileIds = <String, (String account, int fileId)>{};

  /// Books whose download the person paused (what's fetched is kept).
  final paused = ValueNotifier<Set<String>>(const {});

  /// Pauses [id]'s download; [download] again resumes it.
  Future<void> pauseDownload(String id) async {
    paused.value = {...paused.value, id};
    final f = _fileIds[id];
    if (f == null) return;
    try {
      await ref.read(telegramClientFamily(f.$1)).send<td.Ok>(td.CancelDownloadFile(fileId: f.$2, onlyIfPending: false));
    } catch (_) {}
  }

  /// Stops [id]'s download and deletes what was fetched.
  Future<void> cancelDownload(String id) async {
    paused.value = {...paused.value}..remove(id);
    final f = _fileIds[id];
    if (f == null) return;
    try {
      final client = ref.read(telegramClientFamily(f.$1));
      await client.send<td.Ok>(td.CancelDownloadFile(fileId: f.$2, onlyIfPending: false));
      await client.send<td.Ok>(td.DeleteFile(fileId: f.$2));
    } catch (_) {}
  }

  /// Downloads a Telegram book into the app's folder and reads it.
  Future<Book> download(String id, {void Function(double)? onProgress}) async {
    final b = state.byId(id);
    if (b == null) throw 'No such book.';
    if (b.downloaded) return b;
    if (b.account == null || b.chatId == null || b.messageId == null) throw 'This book has no file.';
    final progress = _downloading.putIfAbsent(id, () => ValueNotifier(0));
    paused.value = {...paused.value}..remove(id);
    try {
      final client = ref.read(telegramClientFamily(b.account!));
      final m = await client.send<td.Message>(td.GetMessage(chatId: b.chatId!, messageId: b.messageId!), limited: true);
      final doc = m.content is td.MessageDocument ? (m.content as td.MessageDocument).document : null;
      if (doc == null) throw 'The post no longer has the file.';
      _fileIds[id] = (b.account!, doc.document.id);
      final sub = client.updates.listen((u) {
        if (u is td.UpdateFile && u.file.id == doc.document.id) {
          final total = u.file.size > 0 ? u.file.size : u.file.expectedSize;
          if (total > 0) {
            progress.value = u.file.local.downloadedSize / total;
            onProgress?.call(progress.value);
          }
        }
      });
      td.File got;
      try {
        got = await client.send<td.File>(
          td.DownloadFile(fileId: doc.document.id, priority: 32, offset: 0, limit: 0, synchronous: true),
          timeout: const Duration(minutes: 20),
        );
      } finally {
        await sub.cancel();
      }
      if (!got.local.isDownloadingCompleted) throw paused.value.contains(id) ? const DownloadPaused() : 'Couldn\'t download it.';
      final dir = await _dir(id);
      await dir.create(recursive: true);
      final name = b.fileName.isEmpty ? 'book.${b.format}' : b.fileName;
      final copy = await File(got.local.path).copy('${dir.path}/$name');
      await update(id, (x) => x.copyWith(path: copy.path));
      await prepare(id);
      return state.byId(id)!;
    } finally {
      _downloading.remove(id)?.dispose();
    }
  }

  /// Reads a book's title, author, description and cover from the file,
  /// and keeps the parsed text for the reader.
  Future<void> prepare(String id) async {
    final b = state.byId(id);
    if (b == null || b.path == null || !readableFormats.contains(b.format)) return;
    try {
      final doc = await openDoc(b);
      final dir = await _dir(id);
      String? cover;
      if (doc.coverBytes != null && doc.coverBytes!.isNotEmpty) {
        final f = File('${dir.path}/cover.jpg');
        await f.writeAsBytes(doc.coverBytes!);
        cover = f.path;
      }
      await update(id, (x) => x.copyWith(
        title: (doc.title?.trim().isNotEmpty ?? false) ? doc.title!.trim() : null,
        author: (doc.author?.trim().isNotEmpty ?? false) ? doc.author!.trim() : null,
        description: (doc.description?.trim().isNotEmpty ?? false) && x.description.length < 40 ? doc.description!.trim() : null,
        publisher: doc.publisher,
        year: doc.year,
        language: doc.language,
        coverPath: cover,
        words: doc.wordCount,
      ));
    } catch (e) {
      debugPrint('[Books] prepare $id: $e');
    }
  }

  final _docs = <String, ParsedDoc>{};

  /// The book's text as blocks: from the cache, or parsed and cached.
  Future<ParsedDoc> openDoc(Book b) async {
    final have = _docs[b.id];
    if (have != null) return have;
    final dir = await _dir(b.id);
    final cache = File('${dir.path}/doc.json');
    if (await cache.exists()) {
      try {
        final d = ParsedDoc.fromJson(jsonDecode(await cache.readAsString()) as Map);
        return _docs[b.id] = d;
      } catch (_) {}
    }
    final d = await parseBook(b.path!, Directory('${dir.path}/img'));
    await cache.writeAsString(jsonEncode(d.toJson()));
    _docs[b.id] = d;
    return d;
  }
}

/// A download stopped on purpose: paused or cancelled.
class DownloadPaused implements Exception {
  const DownloadPaused();
  @override
  String toString() => 'Paused';
}

String _stripExt(String n) {
  final i = n.lastIndexOf('.');
  return (i > 0 ? n.substring(0, i) : n).replaceAll(RegExp(r'[_]+'), ' ').trim();
}

final booksProvider = NotifierProvider<BooksStore, BooksState>(BooksStore.new);

// ---- books posted in the sources ---------------------------------------------------

/// A book file posted in a source.
class BookPost {
  BookPost({
    required this.account,
    required this.chatId,
    required this.messageId,
    required this.source,
    required this.fileName,
    required this.size,
    required this.date,
    this.caption = '',
    this.thumb,
    this.mini,
  });
  final String account;
  final int chatId;
  final int messageId;
  final String source;
  final String fileName;
  final int size;
  final DateTime date;
  final String caption;
  final td.File? thumb;
  final td.Minithumbnail? mini;

  String get key => postKey(account, chatId, messageId);
  String get format => extOf(fileName);
  String get title {
    final first = caption.split('\n').map((l) => l.trim()).firstWhere((l) => l.length > 3 && l.length < 120, orElse: () => '');
    return first.isNotEmpty ? first : _stripExt(fileName);
  }

  static BookPost? fromMessage(td.Message m, String account, String source) {
    if (m.content case td.MessageDocument(:final document) when bookFormats.contains(extOf(document.fileName))) {
      return BookPost(
        account: account,
        chatId: m.chatId,
        messageId: m.id,
        source: source,
        fileName: document.fileName,
        size: document.document.size > 0 ? document.document.size : document.document.expectedSize,
        date: unixDate(m.date),
        caption: messageText(m),
        thumb: document.thumbnail?.file,
        mini: document.minithumbnail,
      );
    }
    return null;
  }

  Map<String, dynamic> describe() => {
    'post_key': key,
    'title': title,
    'file_name': fileName,
    'format': format,
    if (size > 0) 'size': sizeText(size),
    'from': source,
    'chat_id': chatId,
    'message_id': messageId,
    'posted': date.toIso8601String().substring(0, 10),
  };
}

@immutable
class BookFeedState {
  const BookFeedState({this.bySource = const {}, this.loading = const {}, this.next = const {}, this.errors = const {}});
  final Map<String, List<BookPost>> bySource;
  final Set<String> loading;
  final Map<String, int> next;
  final Map<String, String> errors;
  bool get anyLoading => loading.isNotEmpty;
  bool hasMore(String k) => (next[k] ?? 1) != 0;
}

class BookFeed extends Notifier<BookFeedState> {
  static final _memory = FeedMemory('books');
  final _ids = <String, List<int>>{};

  @override
  BookFeedState build() => const BookFeedState();

  Future<void> load(SourceRef s, {bool more = false, String query = ''}) async {
    if (state.loading.contains(s.key) || (more && state.next[s.key] == 0)) return;
    state = BookFeedState(bySource: state.bySource, loading: {...state.loading, s.key}, next: state.next, errors: {...state.errors}..remove(s.key));
    try {
      final client = ref.read(telegramClientFamily(s.account));
      final title = ref.read(telegramStoreFamily(s.account)).chat(s.chatId)?.title ?? s.title;
      // First time this run: what it showed last time, at once.
      if (!more && query.isEmpty && !state.bySource.containsKey(s.key)) {
        final kept = [for (final m in await _memory.recall(client, s)) ?BookPost.fromMessage(m, s.account, title)];
        if (kept.isNotEmpty && !state.bySource.containsKey(s.key)) {
          state = BookFeedState(bySource: {...state.bySource, s.key: kept}, loading: state.loading, next: state.next, errors: state.errors);
        }
      }
      var from = more ? (state.next[s.key] ?? 0) : 0;
      final found = <BookPost>[];
      final ids = more ? [...?_ids[s.key]] : <int>[];
      var next = 0;
      for (var round = 0; round < 4 && found.length < 30; round++) {
        final page = await loadChatPage(client, s.chatId, filter: const td.SearchMessagesFilterDocument(), query: query, from: from, limit: 80);
        found.addAll([for (final m in page.messages) ?BookPost.fromMessage(m, s.account, title)]);
        ids.addAll(page.messages.map((m) => m.id));
        next = page.next;
        if (next == 0) break;
        from = next;
      }
      final have = more ? (state.bySource[s.key] ?? const <BookPost>[]) : const <BookPost>[];
      final keys = {for (final b in have) b.key};
      state = BookFeedState(
        bySource: {...state.bySource, s.key: [...have, for (final b in found) if (keys.add(b.key)) b]},
        loading: {...state.loading}..remove(s.key),
        next: {...state.next, s.key: next},
        errors: state.errors,
      );
      if (query.isEmpty) {
        _ids[s.key] = ids;
        unawaited(_memory.remember(s, ids, max: 300));
      }
    } catch (e) {
      state = BookFeedState(bySource: state.bySource, loading: {...state.loading}..remove(s.key), next: state.next, errors: {...state.errors, s.key: '$e'});
    }
  }

  Future<void> loadAll(Iterable<SourceRef> sources, {bool refresh = false}) =>
      pooled([for (final s in sources) if (refresh || !state.bySource.containsKey(s.key)) s], 3, (s) => load(s));

  List<BookPost> all(List<SourceRef> sources) {
    final out = [for (final s in sources) ...?state.bySource[s.key]]..sort((a, b) => b.date.compareTo(a.date));
    return out;
  }
}

final bookFeedProvider = NotifierProvider<BookFeed, BookFeedState>(BookFeed.new);
