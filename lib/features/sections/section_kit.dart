import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme.dart';
import '../../core/widgets/app_sheet.dart';
import '../../infrastructure/telegram/telegram_client.dart';
import '../media/audio_player_ui.dart';
import '../telegram/data/file_loader.dart';
import '../telegram/data/message_content.dart';
import '../telegram/data/telegram_store.dart';
import '../telegram/presentation/chat_list_screen.dart' show inTelegramOrder;
import '../telegram/presentation/tg_avatar.dart';

// What Marketplace, Movies, Books and Gallery share: channels and groups
// picked as sources, their posts read page by page, Telegram pictures
// shown from the phone's cache, and the branded header every one wears.

/// A Telegram channel or group a section reads from.
@immutable
class SourceRef {
  const SourceRef({required this.account, required this.chatId, required this.title, this.hidden = false});
  final String account;
  final int chatId;
  final String title;

  /// Kept, but left out of the main feed.
  final bool hidden;

  String get key => '$account:$chatId';

  SourceRef copyWith({String? title, bool? hidden}) =>
      SourceRef(account: account, chatId: chatId, title: title ?? this.title, hidden: hidden ?? this.hidden);

  Map<String, dynamic> toJson() => {'a': account, 'c': chatId, 't': title, if (hidden) 'h': true};

  factory SourceRef.fromJson(Map j) => SourceRef(
    account: '${j['a'] ?? ''}',
    chatId: (j['c'] as num?)?.toInt() ?? 0,
    title: '${j['t'] ?? 'Chat'}',
    hidden: j['h'] == true,
  );

  Map<String, dynamic> describe() => {'chat_id': chatId, 'title': title, if (hidden) 'hidden': true};
}

/// A post's id across accounts: `account:chat:message`.
String postKey(String account, int chatId, int messageId) => '$account:$chatId:$messageId';

/// [postKey] read back; null if it isn't one.
({String account, int chatId, int messageId})? parsePostKey(String key) {
  final parts = key.split(':');
  if (parts.length < 3) return null;
  final m = int.tryParse(parts.last), c = int.tryParse(parts[parts.length - 2]);
  if (m == null || c == null) return null;
  return (account: parts.sublist(0, parts.length - 2).join(':'), chatId: c, messageId: m);
}

/// One page of a chat's messages: all of them (history) or only those
/// matching [filter]. [from] continues from a previous page's `next`.
Future<({List<td.Message> messages, int next})> loadChatPage(
  TelegramClient client,
  int chatId, {
  td.SearchMessagesFilter? filter,
  String query = '',
  int from = 0,
  int limit = 50,
}) async {
  if (filter == null && query.isEmpty) {
    // History can come back short while TDLib fetches from the server; ask
    // again until a page fills or the chat runs out.
    final out = <td.Message>[];
    var at = from;
    for (var round = 0; round < 4 && out.length < limit; round++) {
      final r = await client.send<td.Messages>(
        td.GetChatHistory(chatId: chatId, fromMessageId: at, offset: 0, limit: limit - out.length, onlyLocal: false),
        limited: true,
      );
      if (r.messages.isEmpty) break;
      out.addAll(r.messages.where((m) => !out.any((x) => x.id == m.id)));
      at = r.messages.last.id;
    }
    return (messages: out, next: out.isEmpty ? 0 : out.last.id);
  }
  final r = await client.send<td.FoundChatMessages>(
    td.SearchChatMessages(
      chatId: chatId,
      query: query,
      senderId: null,
      fromMessageId: from,
      offset: 0,
      limit: limit,
      filter: filter ?? const td.SearchMessagesFilterEmpty(),
      topicId: null,
    ),
    limited: true,
  );
  return (messages: r.messages, next: r.messages.isEmpty ? 0 : r.nextFromMessageId);
}

/// Messages of one album (several photos sent together) as one post.
List<List<td.Message>> groupAlbums(List<td.Message> messages) {
  final out = <List<td.Message>>[];
  for (final m in messages) {
    if (m.mediaAlbumId != 0 && out.isNotEmpty && out.last.first.mediaAlbumId == m.mediaAlbumId && out.last.first.chatId == m.chatId) {
      out.last.add(m);
    } else {
      out.add([m]);
    }
  }
  return out;
}

/// The words of a message (text or caption).
String messageText(td.Message m) => gistOf(m.content).text.trim();

/// A message's best picture at about [minWidth] and its blurry preview.
({td.File? file, td.Minithumbnail? mini}) messagePicture(td.Message m, {int minWidth = 600}) => switch (m.content) {
  td.MessagePhoto(:final photo) => (file: pickPhotoSize(photo.sizes, minWidth: minWidth)?.photo, mini: photo.minithumbnail),
  td.MessageVideo(:final video) => (file: video.thumbnail?.file, mini: video.minithumbnail),
  td.MessageAnimation(:final animation) => (file: animation.thumbnail?.file, mini: animation.minithumbnail),
  td.MessageDocument(:final document) => (file: document.thumbnail?.file, mini: document.minithumbnail),
  td.MessageAudio(:final audio) => (file: audio.albumCoverThumbnail?.file, mini: audio.albumCoverMinithumbnail),
  td.MessageText(:final linkPreview) => (file: _previewPhoto(linkPreview), mini: null),
  _ => (file: null, mini: null),
};

td.File? _previewPhoto(td.LinkPreview? p) {
  final t = p?.type;
  if (t is td.LinkPreviewTypePhoto) return pickPhotoSize(t.photo.sizes)?.photo;
  if (t is td.LinkPreviewTypeArticle && t.photo != null) return pickPhotoSize(t.photo!.sizes)?.photo;
  return null;
}

/// A picture from Telegram: the phone's copy when there is one, else the
/// blurry preview while it downloads in the background.
class TgPicture extends ConsumerStatefulWidget {
  const TgPicture({super.key, this.file, this.mini, this.fit = BoxFit.cover, this.width, this.height, this.cacheWidth = 600, this.placeholder, this.autoload = true});
  final td.File? file;
  final td.Minithumbnail? mini;
  final BoxFit fit;
  final double? width;
  final double? height;
  final int cacheWidth;
  final Widget? placeholder;

  /// Downloads the picture when it isn't on the phone yet; off, only the
  /// phone's copy (or the blurry preview) shows.
  final bool autoload;

  @override
  ConsumerState<TgPicture> createState() => _TgPictureState();
}

class _TgPictureState extends ConsumerState<TgPicture> {
  String? _path;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(TgPicture old) {
    super.didUpdateWidget(old);
    if (old.file?.id != widget.file?.id || (widget.autoload && !old.autoload)) {
      if (old.file?.id != widget.file?.id) _path = null;
      _load();
    }
  }

  Future<void> _load() async {
    final f = widget.file;
    if (f == null) return;
    final loader = ref.read(fileLoaderProvider);
    final have = loader.cachedPath(f);
    if (have != null) {
      _path = have;
      return;
    }
    if (!widget.autoload) return;
    final p = await loader.download(f, priority: 3);
    if (p != null && mounted) setState(() => _path = p);
  }

  @override
  Widget build(BuildContext context) {
    final p = _path;
    if (p != null) {
      return Image(
        image: ResizeImage(FileImage(File(p)), width: widget.cacheWidth, policy: ResizeImagePolicy.fit),
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _blur(),
      );
    }
    return _blur();
  }

  Widget _blur() {
    final m = widget.mini;
    if (m == null) return widget.placeholder ?? Container(width: widget.width, height: widget.height, color: AppColors.surface2);
    return ClipRect(
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Image.memory(base64Decode(m.data), fit: widget.fit, width: widget.width, height: widget.height, gaplessPlayback: true),
      ),
    );
  }
}

/// Lets the person tick the channels and groups to read from. Returns the
/// new list, or null if cancelled.
Future<List<SourceRef>?> pickSources(
  BuildContext context, {
  required String account,
  required List<SourceRef> current,
  required String title,
  String? hint,
}) => showAppSheet<List<SourceRef>>(
  context,
  initialSize: 0.85,
  builder: (context, scroll) => _SourcePicker(account: account, current: current, scroll: scroll, title: title, hint: hint),
);

class _SourcePicker extends ConsumerStatefulWidget {
  const _SourcePicker({required this.account, required this.current, required this.scroll, required this.title, this.hint});
  final String account;
  final List<SourceRef> current;
  final ScrollController scroll;
  final String title;
  final String? hint;

  @override
  ConsumerState<_SourcePicker> createState() => _SourcePickerState();
}

class _SourcePickerState extends ConsumerState<_SourcePicker> {
  late final Map<int, SourceRef> _picked = {
    for (final s in widget.current)
      if (s.account == widget.account) s.chatId: s,
  };
  String _q = '';
  ChatKind? _kind = ChatKind.channel;

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(telegramStoreProvider);
    final q = _q.toLowerCase();
    final all = inTelegramOrder(store.chats.values.where((c) => c.title.isNotEmpty && c.isListed), 'main');
    final list = [
      for (final c in all)
        if ((q.isEmpty || c.title.toLowerCase().contains(q)) && (_kind == null || store.kindOf(c) == _kind)) c,
    ];
    final others = widget.current.where((s) => s.account != widget.account).toList();
    return Column(
      children: [
        Text(widget.title, style: context.text.titleLarge),
        if (widget.hint != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, 4, Space.xl, 0),
            child: Text(widget.hint!, style: context.text.bodySmall, textAlign: TextAlign.center),
          ),
        const SizedBox(height: Space.m),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.l),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Find a channel or group'),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        const SizedBox(height: Space.s),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            children: [
              for (final (k, label) in const [(ChatKind.channel, 'Channels'), (ChatKind.group, 'Groups'), (null, 'All chats')])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(label: Text(label), selected: _kind == k, onSelected: (_) => setState(() => _kind = k)),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            controller: widget.scroll,
            padding: const EdgeInsets.only(bottom: Space.xl),
            children: [
              for (final c in list.take(400))
                CheckboxListTile(
                  value: _picked.containsKey(c.id),
                  secondary: TgAvatar(chatId: c.id, title: c.title, size: 40),
                  title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(switch (store.kindOf(c)) {
                    ChatKind.channel => 'Channel',
                    ChatKind.group => 'Group',
                    ChatKind.bot => 'Bot',
                    ChatKind.saved => 'Saved Messages',
                    _ => 'Chat',
                  }, style: context.text.bodySmall),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _picked[c.id] = SourceRef(account: widget.account, chatId: c.id, title: c.title);
                    } else {
                      _picked.remove(c.id);
                    }
                  }),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.m),
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () {
                // Keep the order they were in; new ones go at the end.
                final kept = [
                  for (final s in widget.current)
                    if (s.account != widget.account || _picked.containsKey(s.chatId)) s,
                ];
                final have = {for (final s in kept) s.key};
                Navigator.pop(context, [...kept, for (final s in _picked.values) if (!have.contains(s.key)) s]);
              },
              child: Text('Use ${_picked.length + others.length} ${_picked.length + others.length == 1 ? 'source' : 'sources'}'),
            ),
          ),
        ),
      ],
    );
  }
}

/// A section's page: a dark branded header with a faint grid and a glow
/// in its colour (the look of the Vercel and MongoDB pages), its title in
/// the app bar, a summary that folds away, and optional sticky tabs.
class SectionScaffold extends StatelessWidget {
  const SectionScaffold({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.hero,
    this.slivers = const [],
    this.views = const [],
    this.tabs,
    this.actions = const [],
    this.fab,
    this.expandedHeight = 220,
    this.bottomBar,
    this.initialTab = 0,
  });
  final int initialTab;
  final String title;
  final IconData icon;
  final Color color;
  final Widget hero;

  /// Without [tabs]: the slivers under the header.
  final List<Widget> slivers;

  /// With [tabs]: one page per tab.
  final List<Widget> views;
  final List<Tab>? tabs;
  final List<Widget> actions;
  final Widget? fab;
  final double expandedHeight;

  /// Something fixed under the page, like the player bar.
  final Widget? bottomBar;

  @override
  Widget build(BuildContext context) {
    final bg = Color.lerp(color, Colors.black, 0.86)!;
    final appBar = SliverAppBar(
      pinned: true,
      stretch: true,
      expandedHeight: expandedHeight + (tabs == null ? 0 : 46),
      backgroundColor: bg,
      foregroundColor: Colors.white,
      titleSpacing: 0,
      title: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              gradient: LinearGradient(colors: [color, Color.lerp(color, Colors.white, 0.3)!]),
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 12)],
            ),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
          const SizedBox(width: Space.s),
          Flexible(child: Text(title, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
        ],
      ),
      actions: [...actions, const SizedBox(width: Space.xs)],
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        stretchModes: const [StretchMode.zoomBackground],
        background: DecoratedBox(
          decoration: BoxDecoration(color: bg),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(painter: _GridPainter()),
              Positioned(
                right: -80,
                top: -60,
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [color.withValues(alpha: 0.45), color.withValues(alpha: 0)]),
                  ),
                ),
              ),
              Positioned(right: -24, bottom: 20 + (tabs == null ? 0 : 46), child: Icon(icon, size: 170, color: Colors.white.withValues(alpha: 0.05))),
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(Space.l, kToolbarHeight + Space.s, Space.l, Space.l + (tabs == null ? 0 : 46)),
                  child: Align(alignment: Alignment.bottomLeft, child: hero),
                ),
              ),
            ],
          ),
        ),
      ),
      bottom: tabs == null
          ? null
          : TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              indicatorColor: color,
              dividerColor: Colors.white12,
              tabs: tabs!,
            ),
    );
    if (tabs == null) {
      return Scaffold(
        floatingActionButton: fab,
        bottomNavigationBar: bottomBar,
        body: CustomScrollView(slivers: [appBar, ...slivers]),
      );
    }
    return DefaultTabController(
      length: tabs!.length,
      initialIndex: initialTab,
      child: Scaffold(
        floatingActionButton: fab,
        bottomNavigationBar: bottomBar,
        body: NestedScrollView(
          headerSliverBuilder: (context, _) => [appBar],
          body: TabBarView(children: views),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0x12FFFFFF)
      ..strokeWidth = 1;
    const step = 28.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    // Fade the grid out toward the bottom.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0x66000000)],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A big number and a small word on a section header.
class SectionStat extends StatelessWidget {
  const SectionStat(this.value, this.label, {super.key});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: Space.s, horizontal: Space.m),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(Radii.m),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, fontFeatures: tabularFigures)),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 11.5)),
        ],
      ),
    ),
  );
}

/// A row of [SectionStat]s with a line above them.
class SectionHero extends StatelessWidget {
  const SectionHero({super.key, required this.subtitle, required this.stats});
  final String subtitle;
  final List<(String, String)> stats;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      const SizedBox(height: Space.m),
      Row(
        children: [
          for (final (i, s) in stats.indexed) ...[
            if (i > 0) const SizedBox(width: Space.s),
            SectionStat(s.$1, s.$2),
          ],
        ],
      ),
    ],
  );
}

/// What a section says before it has sources.
class SectionEmpty extends StatelessWidget {
  const SectionEmpty({super.key, required this.icon, required this.title, required this.body, this.action, this.onAction});
  final IconData icon;
  final String title;
  final String body;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(Space.x4),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.surface2, border: Border.all(color: AppColors.line)),
          child: Icon(icon, size: 34, color: AppColors.text2),
        ),
        const SizedBox(height: Space.l),
        Text(title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.center),
        const SizedBox(height: Space.xs),
        Text(body, style: context.text.bodySmall, textAlign: TextAlign.center),
        if (action != null) ...[
          const SizedBox(height: Space.l),
          FilledButton.icon(onPressed: onAction, icon: const Icon(Icons.add_rounded), label: Text(action!)),
        ],
      ],
    ),
  );
}

/// The player bar, fixed under a page (for pages that aren't the chat).
class BottomAudioBar extends StatelessWidget {
  const BottomAudioBar({super.key});

  @override
  Widget build(BuildContext context) => const SafeArea(
    top: false,
    child: AudioMiniBar(margin: EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.s)),
  );
}

/// A source's chip: avatar and name, tappable.
class SourceChip extends StatelessWidget {
  const SourceChip({super.key, required this.source, this.selected = false, required this.onTap, this.onLongPress});
  final SourceRef source;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: GestureDetector(
      onLongPress: onLongPress,
      child: ChoiceChip(
        avatar: TgAvatar(chatId: source.chatId, title: source.title, size: 22),
        label: Text(source.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    ),
  );
}

/// Waits for [work] while showing a snack, and reports a failure.
Future<T?> withSnack<T>(BuildContext context, String doing, Future<T> Function() work) async {
  showSnack(context, doing, icon: Icons.hourglass_top_rounded);
  try {
    return await work();
  } catch (e) {
    if (context.mounted) showSnack(context, 'Couldn\'t finish: $e', icon: Icons.error_outline_rounded);
    return null;
  }
}

/// A short "3 h ago" for [d].
String agoText(DateTime d) {
  final e = DateTime.now().difference(d);
  if (e.inMinutes < 1) return 'just now';
  if (e.inHours < 1) return '${e.inMinutes} min ago';
  if (e.inDays < 1) return '${e.inHours} h ago';
  if (e.inDays < 30) return '${e.inDays} d ago';
  if (e.inDays < 365) return '${(e.inDays / 30).floor()} mo ago';
  return '${(e.inDays / 365).floor()} y ago';
}

/// [unix] seconds as a date.
DateTime unixDate(int unix) => DateTime.fromMillisecondsSinceEpoch(unix * 1000);

/// A size like "12.4 MB".
String sizeText(int bytes) {
  if (bytes <= 0) return '';
  if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
  if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
  return '${(bytes / 1024).ceil()} KB';
}

/// Runs [tasks] at most [width] at a time.
Future<void> pooled<T>(Iterable<T> items, int width, Future<void> Function(T) task) async {
  final it = items.iterator;
  Future<void> worker() async {
    while (true) {
      if (!it.moveNext()) return;
      final v = it.current;
      try {
        await task(v);
      } catch (_) {}
    }
  }

  await Future.wait([for (var i = 0; i < width; i++) worker()]);
}

/// Every page from every source, newest first overall, up to [perSource]
/// messages a source.
Future<List<td.Message>> loadFromSources(
  TelegramClient client,
  Iterable<SourceRef> sources, {
  td.SearchMessagesFilter? filter,
  int perSource = 60,
  bool Function(td.Message)? keep,
}) async {
  final out = <td.Message>[];
  await pooled(sources, 3, (s) async {
    var from = 0;
    var got = 0;
    for (var round = 0; round < 6 && got < perSource; round++) {
      final page = await loadChatPage(client, s.chatId, filter: filter, from: from, limit: 50);
      if (page.messages.isEmpty) break;
      for (final m in page.messages) {
        if (keep == null || keep(m)) {
          out.add(m);
          got++;
        }
      }
      if (page.next == 0) break;
      from = page.next;
    }
  });
  out.sort((a, b) => b.date.compareTo(a.date));
  return out;
}

/// Whether the dev [timer] still matters; a tiny debounce.
class Debounce {
  Timer? _t;
  void call(Duration d, VoidCallback f) {
    _t?.cancel();
    _t = Timer(d, f);
  }

  void cancel() => _t?.cancel();
}

/// Whether the drawer's Explore heading (Marketplace, Movies, Books,
/// Gallery) is open.
class SectionsDrawerOpen extends Notifier<bool> {
  static const _key = 'sections_drawer_open';

  @override
  bool build() {
    SharedPreferences.getInstance().then((p) => state = p.getBool(_key) ?? true).ignore();
    return true;
  }

  Future<void> set(bool v) async {
    state = v;
    await (await SharedPreferences.getInstance()).setBool(_key, v);
  }
}

final sectionsDrawerOpenProvider = NotifierProvider<SectionsDrawerOpen, bool>(SectionsDrawerOpen.new);

/// Whether the drawer shows the Explore heading at all.
class ExploreEnabled extends Notifier<bool> {
  static const _key = 'explore_in_drawer';

  @override
  bool build() {
    SharedPreferences.getInstance().then((p) => state = p.getBool(_key) ?? true).ignore();
    return true;
  }

  Future<void> set(bool v) async {
    state = v;
    await (await SharedPreferences.getInstance()).setBool(_key, v);
  }
}

final exploreEnabledProvider = NotifierProvider<ExploreEnabled, bool>(ExploreEnabled.new);

/// One input in a [showFieldsSheet].
class SheetField {
  const SheetField(this.key, {required this.label, this.hint, this.initial = '', this.maxLines = 1, this.number = false, this.suggestions = const [], this.help});
  final String key;
  final String label;
  final String? hint;
  final String initial;
  final int maxLines;
  final bool number;

  /// Tapping one fills the field.
  final List<String> suggestions;
  final String? help;
}

/// A bottom sheet that asks for one or more things, with room to explain:
/// an icon and title, an optional preview of what it's about, labelled
/// fields with quick picks, and the action. Null if dismissed. With
/// [destructive] (a label), that button returns `{'_destructive': 'yes'}`.
Future<Map<String, String>?> showFieldsSheet(
  BuildContext context, {
  required IconData icon,
  required String title,
  String? subtitle,
  Widget? preview,
  required List<SheetField> fields,
  String action = 'Save',
  Color? color,
  String? destructive,
}) {
  final controllers = {for (final f in fields) f.key: TextEditingController(text: f.initial)};
  Map<String, String> values() => {for (final e in controllers.entries) e.key: e.value.text.trim()};
  return showModalBottomSheet<Map<String, String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (context) => Padding(
      padding: EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, MediaQuery.viewInsetsOf(context).bottom + Space.l),
      child: SingleChildScrollView(
        child: StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: (color ?? AppColors.accent).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(Radii.m)),
                    child: Icon(icon, color: color ?? AppColors.accent),
                  ),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                        if (subtitle != null) Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
              if (preview != null) ...[const SizedBox(height: Space.l), preview],
              for (final (i, f) in fields.indexed) ...[
                const SizedBox(height: Space.l),
                TextField(
                  controller: controllers[f.key],
                  autofocus: i == 0,
                  maxLines: f.maxLines,
                  minLines: 1,
                  keyboardType: f.number ? TextInputType.number : (f.maxLines > 1 ? TextInputType.multiline : TextInputType.text),
                  textCapitalization: f.number ? TextCapitalization.none : TextCapitalization.sentences,
                  decoration: InputDecoration(labelText: f.label, hintText: f.hint, helperText: f.help, helperMaxLines: 2),
                  onSubmitted: fields.length == 1 && f.maxLines == 1 ? (_) => Navigator.pop(context, values()) : null,
                ),
                if (f.suggestions.isNotEmpty) ...[
                  const SizedBox(height: Space.s),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final sug in f.suggestions)
                        ActionChip(
                          label: Text(sug),
                          onPressed: () => setState(() {
                            final c = controllers[f.key]!;
                            c.text = sug;
                            c.selection = TextSelection.collapsed(offset: sug.length);
                          }),
                        ),
                    ],
                  ),
                ],
              ],
              const SizedBox(height: Space.xl),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: color),
                onPressed: () => Navigator.pop(context, values()),
                child: Text(action),
              ),
              if (destructive != null) ...[
                const SizedBox(height: Space.s),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                  onPressed: () => Navigator.pop(context, {'_destructive': 'yes'}),
                  child: Text(destructive),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
