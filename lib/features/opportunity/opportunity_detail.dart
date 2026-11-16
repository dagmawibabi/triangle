import 'dart:async';

import '../account/account_router.dart' show openChatInAccount;

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/widgets/app_sheet.dart';
import '../ai/data/ai.dart' show aiErrorText;
import '../assistant/reminders.dart';
import '../sections/section_kit.dart';
import '../telegram/presentation/forward_sheet.dart';
import '../telegram/presentation/link_opener.dart' show openHashtag, openUrl;
import '../telegram/presentation/tg_avatar.dart';
import 'opportunity.dart';
import '../marketplace/market_screen.dart' show LegitBadge;
import '../sections/skeletons.dart';
import 'opportunity_screen.dart';

Future<void> _open(BuildContext context, String url) => _launch(context, url);

Future<void> _launch(BuildContext context, String url) async {
  final u = Uri.tryParse(url.contains('://') || url.startsWith('mailto:') || url.startsWith('tel:') ? url : 'https://$url');
  if (u == null || !await launchUrl(u, mode: LaunchMode.externalApplication)) {
    if (context.mounted) showSnack(context, 'Couldn\'t open that link', icon: Icons.link_off_rounded);
  }
}

void _openPost(BuildContext context, OppPost p) => openChatInAccount(context, p.chatId, hint: p.account, openAt: p.messageId);

/// Opens a saved event by key, reading its post when it isn't loaded.
Future<void> openEvent(BuildContext context, WidgetRef ref, String key) async {
  final post = await withSnack(context, 'Opening…', () => ref.read(oppFeedProvider(OppKind.event).notifier).fetch(key));
  if (!context.mounted) return;
  if (post == null) return showSnack(context, 'That post is gone', icon: Icons.info_outline_rounded);
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EventScreen(event: EventView(post, ref.read(opportunityProvider).events[post.key]))));
}

Future<void> openJob(BuildContext context, WidgetRef ref, String key) async {
  final post = await withSnack(context, 'Opening…', () => ref.read(oppFeedProvider(OppKind.job).notifier).fetch(key));
  if (!context.mounted) return;
  if (post == null) return showSnack(context, 'That post is gone', icon: Icons.info_outline_rounded);
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => JobScreen(job: JobView(post, ref.read(opportunityProvider).jobs[post.key]))));
}

/// A round, see-through button over a picture.
class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.icon, required this.onTap, this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(6),
    child: Material(
      color: AppColors.text.withValues(alpha: 0.08),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, color: AppColors.text),
        onPressed: onTap,
      ),
    ),
  );
}

/// One of the three big buttons under an event's title.
class _BigAction extends StatelessWidget {
  const _BigAction({required this.icon, required this.label, required this.onTap, this.primary = false, this.active = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final bg = primary ? AppColors.text : (active ? oppColor.withValues(alpha: 0.22) : AppColors.text.withValues(alpha: 0.07));
    final fg = primary ? AppColors.bg : (active ? oppColor : AppColors.text);
    return Expanded(
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.l),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.l),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              children: [
                Icon(icon, color: fg, size: 22),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.xl, Space.xl, Space.xl, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(color: AppColors.text3, fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 6),
        Divider(height: 1, color: AppColors.line),
        const SizedBox(height: Space.m),
        child,
      ],
    ),
  );
}

/// Text that folds after [lines], with links in it tappable.
class _Folding extends StatefulWidget {
  const _Folding(this.text, {this.lines = 8});
  final String text;
  final int lines;

  @override
  State<_Folding> createState() => _FoldingState();
}

/// Links, @usernames, emails, phone numbers and #hashtags in plain text.
final _linkable = RegExp(
  r'(https?://[^\s<>"]+|www\.[^\s<>"]+|(?:t|telegram)\.me/[^\s<>"]+)'
  r'|([\w.+-]+@[\w-]+\.[\w.-]*[A-Za-z])'
  r'|((?<![\w@/])@[A-Za-z][\w]{3,31})'
  r'|((?<![\w&/])#[\p{L}\p{N}_]{2,})'
  r'|(\+\d[\d\s-]{7,14}\d|\b0[79]\d{8}\b)',
  unicode: true,
);

class _FoldingState extends State<_Folding> {
  bool _open = false;
  final List<TapGestureRecognizer> _taps = [];

  @override
  void dispose() {
    for (final t in _taps) {
      t.dispose();
    }
    super.dispose();
  }

  /// [text] with its links styled and tappable: web links open (Telegram
  /// ones inside the app), @usernames open the chat or profile, emails and
  /// numbers start a message or a call, #hashtags search your chats.
  List<InlineSpan> _spans(String text, TextStyle link) {
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
    final out = <InlineSpan>[];
    var at = 0;
    for (final m in _linkable.allMatches(text)) {
      var raw = m[0]!;
      // Sentence punctuation after a link isn't part of it.
      final trail = RegExp(r'[.,;:!?)\]»”’]+$').firstMatch(raw)?[0] ?? '';
      if (m[1] != null && trail.isNotEmpty) raw = raw.substring(0, raw.length - trail.length);
      if (m.start > at) out.add(TextSpan(text: text.substring(at, m.start)));
      final String target;
      if (m[1] != null) {
        target = raw.startsWith('http') ? raw : 'https://$raw';
      } else if (m[2] != null) {
        target = 'mailto:$raw';
      } else if (m[3] != null) {
        target = 'https://t.me/${raw.substring(1)}';
      } else if (m[4] != null) {
        target = raw;
      } else {
        target = 'tel:${raw.replaceAll(RegExp(r'[\s-]'), '')}';
      }
      final tap = TapGestureRecognizer()
        ..onTap = () {
          HapticFeedback.selectionClick();
          if (m[4] != null) {
            openHashtag(target);
          } else if (target.startsWith('mailto:') || target.startsWith('tel:')) {
            _launch(context, target);
          } else {
            openUrl(target, context: context);
          }
        };
      _taps.add(tap);
      out.add(TextSpan(text: raw, style: link, recognizer: tap));
      at = m.start + raw.length;
    }
    if (at < text.length) out.add(TextSpan(text: text.substring(at)));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: AppColors.text.withValues(alpha: 0.88), height: 1.5, fontSize: 15);
    final link = TextStyle(
      color: AppLook.minimalExplore ? AppColors.text : oppColor,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: (AppLook.minimalExplore ? AppColors.text : oppColor).withValues(alpha: 0.45),
    );
    final long = widget.text.split('\n').length > widget.lines || widget.text.length > 420;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: SelectableText.rich(
            TextSpan(style: style, children: _spans(widget.text, link)),
            maxLines: _open || !long ? null : widget.lines,
          ),
        ),
        if (long)
          TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
            onPressed: () => setState(() => _open = !_open),
            child: Text(
              _open ? 'Show less' : 'Read more',
              style: TextStyle(color: oppColor, fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }
}

/// A blurred copy of the post's picture behind the page, as on Luma, fading
/// into the page colour. The plain page colour in the monochrome look.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.post});
  final OppPost post;

  @override
  Widget build(BuildContext context) {
    final pic = post.pictures.firstOrNull;
    if (pic == null || AppLook.minimalExplore) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppLook.minimalExplore ? AppColors.surface : Color.lerp(AppColors.bg, oppColor, 0.22)!, AppColors.bg],
            stops: const [0, 0.55],
          ),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 60, sigmaY: 60, tileMode: TileMode.clamp),
          child: Transform.scale(
            scale: 1.3,
            child: TgPicture(file: pic.file, mini: pic.mini, cacheWidth: 120, account: post.account),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.bg.withValues(alpha: AppColors.isLight ? 0.35 : 0.45),
                AppColors.bg.withValues(alpha: 0.85),
                AppColors.bg,
              ],
              stops: const [0, 0.5, 0.85],
            ),
          ),
        ),
      ],
    );
  }
}

// ---- an event -------------------------------------------------------------------------

class EventScreen extends ConsumerStatefulWidget {
  const EventScreen({super.key, required this.event});
  final EventView event;

  @override
  ConsumerState<EventScreen> createState() => _EventScreenState();
}

class _EventScreenState extends ConsumerState<EventScreen> {
  final _scroll = ScrollController();
  final _titleShown = ValueNotifier(false);

  EventView get e => widget.event;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() => _titleShown.value = _scroll.offset > 360);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _titleShown.dispose();
    super.dispose();
  }

  String get _whenText {
    final s = e.start;
    if (s == null) return 'Date to be announced';
    final day = dayName(s);
    final date = (day == 'Today' || day == 'Tomorrow') ? day : DateFormat('EEEE, d MMMM').format(s);
    if (!e.hasTime) return '$date · All day';
    final end = e.end;
    if (end == null) return '$date, ${timeText(s)}';
    if (DateUtils.isSameDay(s, end)) return '$date, ${timeText(s)} – ${timeText(end)}';
    return '$date, ${timeText(s)} – ${DateFormat('d MMM').format(end)}, ${timeText(end)}';
  }

  String get _shareText => [e.title, _whenText, if (e.online) 'Online' else if (e.place.isNotEmpty) e.place, if (e.link.isNotEmpty) e.link].join('\n');

  Future<void> _calendar() async {
    final s = e.start;
    if (s == null) return showSnack(context, 'This event has no date yet', icon: Icons.info_outline_rounded);
    final f = await eventCalendarFile(
      title: e.title,
      start: s,
      end: e.end,
      allDay: !e.hasTime,
      place: e.online ? 'Online' : e.place,
      details: e.summary.isEmpty ? e.post.text : e.summary,
      link: e.link,
    );
    final r = await OpenFilex.open(f.path, type: 'text/calendar');
    if (r.type != ResultType.done && mounted) {
      await _open(context, googleCalendarLink(title: e.title, start: s, end: e.end, allDay: !e.hasTime, place: e.place, details: e.summary).toString());
    }
  }

  Future<void> _remind() async {
    final s = e.start;
    if (s == null) return showSnack(context, 'This event has no date yet', icon: Icons.info_outline_rounded);
    final options = [
      (const Duration(days: 1), 'A day before'),
      (const Duration(hours: 3), '3 hours before'),
      (const Duration(hours: 1), 'An hour before'),
      (const Duration(minutes: 15), '15 minutes before'),
      (Duration.zero, 'When it starts'),
    ].where((o) => s.subtract(o.$1).isAfter(DateTime.now())).toList();
    if (options.isEmpty) return showSnack(context, 'It\'s too close to the start for a reminder', icon: Icons.info_outline_rounded);
    final picked = await showFormSheet<Duration>(
      context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Remind me', style: context.text.titleMedium),
          const SizedBox(height: Space.s),
          for (final (d, label) in options)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: lead(const Icon(Icons.notifications_active_outlined)),
              title: Text(label),
              subtitle: Text(DateFormat('EEE d MMM, HH:mm').format(s.subtract(d)), style: context.text.bodySmall),
              onTap: () => Navigator.pop(context, d),
            ),
        ],
      ),
    );
    if (picked == null) return;
    try {
      final r = await ref
          .read(reminderStoreProvider.notifier)
          .add(
            text:
                '📅 ${e.title} · ${picked == Duration.zero ? 'starting now' : 'starts ${timeText(s)}'}${e.online
                    ? ' (online)'
                    : e.place.isEmpty
                    ? ''
                    : ' at ${e.place}'}',
            at: s.subtract(picked),
          );
      final store = ref.read(opportunityProvider.notifier);
      if (ref.read(opportunityProvider).savedEvent(e.key) == null) await store.saveEvent(e, EventStatus.interested);
      await store.updateSavedEvent(e.key, (x) => x.copyWith(reminders: [...x.reminders, r.id]));
      if (mounted) showSnack(context, 'I\'ll remind you ${DateFormat('EEE HH:mm').format(s.subtract(picked))}', icon: Icons.notifications_active_outlined);
    } catch (err) {
      if (mounted) showSnack(context, '$err', icon: Icons.error_outline_rounded);
    }
  }

  Future<void> _more() async {
    final saved = ref.read(opportunityProvider).savedEvent(e.key);
    final store = ref.read(opportunityProvider.notifier);
    final pick = await showFormSheet<String>(
      context,
      builder: (context) {
        Widget row(String v, IconData icon, String label, {Color? color}) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: lead(Icon(icon, color: color)),
          title: Text(label, style: TextStyle(color: color)),
          onTap: () => Navigator.pop(context, v),
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (saved?.status != EventStatus.interested) row('interested', Icons.star_outline_rounded, 'Interested'),
            row('calendar', Icons.event_available_outlined, 'Add to calendar'),
            row('gcal', Icons.calendar_month_outlined, 'Open in Google Calendar'),
            row('remind', Icons.notifications_none_rounded, 'Remind me…'),
            row('post', Icons.forum_outlined, 'Open the post'),
            row('forward', Icons.shortcut_rounded, 'Forward in Telegram'),
            row('copy', Icons.copy_rounded, 'Copy details'),
            if (saved != null) row('went', Icons.task_alt_rounded, 'I went'),
            if (saved != null) row('unsave', Icons.bookmark_remove_outlined, 'Remove from my events'),
            row('hide', Icons.visibility_off_outlined, 'Hide this event', color: AppColors.danger),
          ],
        );
      },
    );
    if (!mounted || pick == null) return;
    switch (pick) {
      case 'interested':
        await store.saveEvent(e, EventStatus.interested);
      case 'calendar':
        await _calendar();
      case 'gcal':
        if (e.start != null) await _open(context, googleCalendarLink(title: e.title, start: e.start!, end: e.end, allDay: !e.hasTime, place: e.place, details: e.summary).toString());
      case 'remind':
        await _remind();
      case 'post':
        _openPost(context, e.post);
      case 'forward':
        await showForwardSheet(context, e.post.chatId, e.post.messageIds);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: _shareText));
        if (mounted) showSnack(context, 'Copied');
      case 'went':
        await store.saveEvent(e, EventStatus.went);
      case 'unsave':
        for (final id in saved?.reminders ?? const <String>[]) {
          await ref.read(reminderStoreProvider.notifier).remove(id);
        }
        await store.unsaveEvent(e.key);
      case 'hide':
        await store.setHidden(e.key, true);
        if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(opportunityProvider.select((o) => o.savedEvent(e.key)));
    final going = saved?.status == EventStatus.going;
    final s = e.start;
    final pic = e.post.pictures.firstOrNull;
    final reminders = {for (final r in ref.watch(reminderStoreProvider)) r.id: r};
    final mine = [for (final id in saved?.reminders ?? const <String>[]) ?reminders[id]].where((r) => r.next != null).toList();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          Positioned.fill(child: _Backdrop(post: e.post)),
          CustomScrollView(
            controller: _scroll,
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                foregroundColor: AppColors.text,
                elevation: 0,
                scrolledUnderElevation: 0,
                automaticallyImplyLeading: false,
                flexibleSpace: ValueListenableBuilder<bool>(
                  valueListenable: _titleShown,
                  builder: (context, shown, _) => AnimatedContainer(duration: const Duration(milliseconds: 200), color: shown ? AppColors.bg.withValues(alpha: 0.92) : Colors.transparent),
                ),
                leading: _GlassButton(icon: Icons.arrow_back_rounded, tooltip: 'Back', onTap: () => Navigator.maybePop(context)),
                title: ValueListenableBuilder<bool>(
                  valueListenable: _titleShown,
                  builder: (context, shown, _) => AnimatedOpacity(
                    opacity: shown ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Text(
                      e.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 17),
                    ),
                  ),
                ),
                actions: [_GlassButton(icon: Icons.ios_share_rounded, tooltip: 'Share', onTap: () => showForwardSheet(context, e.post.chatId, e.post.messageIds))],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.xl, Space.s, Space.xl, 0),
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: AppColors.isLight ? 0.12 : 0.4),
                          blurRadius: 30,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Only the picture flies from the list: the strip under it
                        // would be squeezed into the thumbnail's square on the way.
                        Hero(
                          tag: 'event-${e.key}',
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: pic == null
                                ? _BigDate(start: s, icon: e.online ? Icons.videocam_rounded : Icons.celebration_rounded)
                                : GestureDetector(
                                    onTap: () => _openPost(context, e.post),
                                    child: TgPicture(file: pic.file, mini: pic.mini, cacheWidth: 1100, account: e.post.account),
                                  ),
                          ),
                        ),
                        Container(
                          width: double.infinity,
                          color: Colors.black.withValues(alpha: 0.86),
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.auto_awesome_outlined, size: 13, color: Colors.white70),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'From ${e.post.source}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.xl, Space.xl, Space.xl, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.title,
                        style: TextStyle(fontSize: 28, height: 1.15, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: AppColors.text),
                      ),
                      const SizedBox(height: Space.m),
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => openChatInAccount(context, e.post.chatId, hint: e.post.account),
                        child: Row(
                          children: [
                            TgAvatar(chatId: e.post.chatId, title: e.post.source, size: 22, accountId: e.post.account),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                e.organizer,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: AppColors.text2, fontSize: 15.5, fontWeight: FontWeight.w500),
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, color: AppColors.text3, size: 20),
                          ],
                        ),
                      ),
                      const SizedBox(height: Space.m),
                      Row(
                        children: [
                          Flexible(
                            child: Text(_whenText, style: TextStyle(color: AppColors.text2, fontSize: 15.5)),
                          ),
                          if (s != null && !e.past) ...[const SizedBox(width: 8), _CountPill(start: s)],
                        ],
                      ),
                      const SizedBox(height: Space.l),
                      Row(
                        children: [
                          _BigAction(
                            icon: e.link.isNotEmpty ? Icons.confirmation_number_outlined : Icons.forum_outlined,
                            label: e.link.isNotEmpty ? (e.online ? 'Join' : 'Register') : 'Open post',
                            primary: true,
                            onTap: () => e.link.isNotEmpty ? _open(context, e.link) : _openPost(context, e.post),
                          ),
                          const SizedBox(width: Space.s),
                          _BigAction(
                            icon: going ? Icons.check_circle_rounded : Icons.add_task_rounded,
                            label: going ? 'Going' : 'I\'m going',
                            active: going,
                            onTap: () async {
                              final store = ref.read(opportunityProvider.notifier);
                              await store.saveEvent(e, going ? EventStatus.interested : EventStatus.going);
                              if (!going && context.mounted) showSnack(context, 'Added to your events', icon: Icons.celebration_outlined);
                            },
                          ),
                          const SizedBox(width: Space.s),
                          _BigAction(icon: Icons.more_horiz_rounded, label: 'More', onTap: _more),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _Section(
                  title: 'Location',
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.online ? 'Online' : (e.venue.isNotEmpty ? e.venue : (e.city.isNotEmpty ? e.city : 'See the post for where')),
                              style: TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.w700),
                            ),
                            if (!e.online && e.city.isNotEmpty && e.venue.isNotEmpty) Text(e.city, style: TextStyle(color: AppColors.text3, fontSize: 14.5)),
                            if (e.online) Text(e.link.isNotEmpty ? Uri.tryParse(e.link)?.host ?? e.link : 'The link is in the post', style: TextStyle(color: AppColors.text3, fontSize: 14.5)),
                          ],
                        ),
                      ),
                      if (!e.online && e.place.isNotEmpty)
                        IconButton.filledTonal(
                          tooltip: 'Open in maps',
                          onPressed: () => _open(context, 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(e.place)}'),
                          icon: const Icon(Icons.map_outlined),
                        ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _Section(
                  title: 'Hosts',
                  trailing: e.info?.contact.isNotEmpty ?? false
                      ? GestureDetector(
                          onTap: () {
                            final c = e.info!.contact;
                            if (c.startsWith('@')) {
                              _open(context, 'https://t.me/${c.substring(1)}');
                            } else if (c.contains('@')) {
                              _open(context, 'mailto:$c');
                            } else {
                              _open(context, 'tel:${c.replaceAll(RegExp(r'[^\d+]'), '')}');
                            }
                          },
                          child: Text(
                            'Contact',
                            style: TextStyle(color: AppColors.text3, fontWeight: FontWeight.w600),
                          ),
                        )
                      : null,
                  child: Column(
                    children: [
                      if (e.organizer != e.post.source)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: LetterAvatar(e.organizer, size: 40),
                          title: Text(
                            e.organizer,
                            style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: TgAvatar(chatId: e.post.chatId, title: e.post.source, size: 40, accountId: e.post.account),
                        title: Text(
                          e.post.source,
                          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text('Posted ${agoText(e.post.date)}${e.post.views > 0 ? ' · ${NumberFormat.compact().format(e.post.views)} views' : ''}', style: context.text.bodySmall),
                        trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
                        onTap: () => _openPost(context, e.post),
                      ),
                    ],
                  ),
                ),
              ),
              if (e.price.isNotEmpty || e.free != null || e.category.isNotEmpty || (e.info?.tags.isNotEmpty ?? false))
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Space.xl, Space.l, Space.xl, 0),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (e.price.isNotEmpty || e.free == true) Chip(avatar: const Icon(Icons.sell_outlined, size: 16), label: Text(e.free == true && e.price.isEmpty ? 'Free' : e.price)),
                        if (e.category.isNotEmpty) Chip(avatar: const Icon(Icons.category_outlined, size: 16), label: Text(e.category)),
                        for (final t in e.info?.tags ?? const <String>[]) Chip(label: Text('#$t')),
                      ],
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: _Section(
                  title: 'About event',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (e.summary.isNotEmpty) ...[
                        Text(
                          e.summary,
                          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 16, height: 1.4),
                        ),
                        const SizedBox(height: Space.m),
                      ],
                      _Folding(e.post.text),
                      if (e.post.links.isNotEmpty) ...[
                        const SizedBox(height: Space.s),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final l in e.post.links.take(6))
                              ActionChip(
                                avatar: const Icon(Icons.link_rounded, size: 16),
                                label: Text(Uri.tryParse(l)?.host ?? l, overflow: TextOverflow.ellipsis),
                                onPressed: () => _open(context, l),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (s != null && !e.past)
                SliverToBoxAdapter(
                  child: _Section(
                    title: 'Reminders',
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final r in mine)
                          InputChip(
                            avatar: const Icon(Icons.notifications_active_outlined, size: 16),
                            label: Text(DateFormat('EEE d MMM, HH:mm').format(r.next!)),
                            onDeleted: () async {
                              await ref.read(reminderStoreProvider.notifier).remove(r.id);
                              await ref
                                  .read(opportunityProvider.notifier)
                                  .updateSavedEvent(
                                    e.key,
                                    (x) => x.copyWith(
                                      reminders: [
                                        for (final id in x.reminders)
                                          if (id != r.id) id,
                                      ],
                                    ),
                                  );
                            },
                          ),
                        ActionChip(avatar: const Icon(Icons.add_alert_outlined, size: 16), label: const Text('Remind me'), onPressed: _remind),
                        ActionChip(avatar: const Icon(Icons.event_available_outlined, size: 16), label: const Text('Add to calendar'), onPressed: _calendar),
                      ],
                    ),
                  ),
                ),
              if (saved != null)
                SliverToBoxAdapter(
                  child: _Section(
                    title: 'Your note',
                    child: TextFormField(
                      initialValue: saved.note,
                      maxLines: 4,
                      minLines: 1,
                      decoration: const InputDecoration(hintText: 'Who you\'re going with, what to bring…'),
                      onChanged: (v) => ref.read(opportunityProvider.notifier).updateSavedEvent(e.key, (x) => x.copyWith(note: v)),
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
        ],
      ),
      bottomNavigationBar: const BottomAudioBar(),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.start});
  final DateTime start;

  @override
  Widget build(BuildContext context) {
    final soon = start.difference(DateTime.now()).inHours < 24;
    final c = soon ? AppColors.warning : AppColors.text2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(99)),
      child: Text(
        countdown(start),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c),
      ),
    );
  }
}

/// An event with no picture: its day, big, over a gradient.
class _BigDate extends StatelessWidget {
  const _BigDate({required this.start, required this.icon});
  final DateTime? start;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final s = start;
    final minimal = AppLook.minimalExplore;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: minimal ? [AppColors.surface3, AppColors.surface] : [oppColor, Color.lerp(oppColor, const Color(0xFFFF6B9A), 0.6)!],
        ),
      ),
      child: Stack(
        children: [
          Positioned(right: -30, bottom: -30, child: Icon(icon, size: 220, color: (minimal ? AppColors.text : Colors.white).withValues(alpha: 0.08))),
          Center(
            child: s == null
                ? Icon(icon, size: 80, color: minimal ? AppColors.text2 : Colors.white)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        DateFormat.MMMM().format(s).toUpperCase(),
                        style: TextStyle(color: (minimal ? AppColors.text : Colors.white).withValues(alpha: 0.8), letterSpacing: 4, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${s.day}',
                        style: TextStyle(color: minimal ? AppColors.text : Colors.white, fontSize: 120, height: 1, fontWeight: FontWeight.w900, letterSpacing: -4),
                      ),
                      Text(
                        DateFormat.EEEE().format(s),
                        style: TextStyle(color: (minimal ? AppColors.text : Colors.white).withValues(alpha: 0.8), fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ---- a job ------------------------------------------------------------------------------

class JobScreen extends ConsumerStatefulWidget {
  const JobScreen({super.key, required this.job});
  final JobView job;

  @override
  ConsumerState<JobScreen> createState() => _JobScreenState();
}

class _JobScreenState extends ConsumerState<JobScreen> {
  JobView get j => widget.job;

  Future<void> _draft() async {
    final store = ref.read(opportunityProvider.notifier);
    final extra = TextEditingController();
    var future = store.draftApplication(j);
    await showAppSheet<void>(
      context,
      initialSize: 0.75,
      builder: (context, scroll) => StatefulBuilder(
        builder: (context, setSheet) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: oppColor),
                const SizedBox(width: Space.s),
                Expanded(child: Text('Your application', style: context.text.titleMedium)),
              ],
            ),
            if (ref.read(opportunityProvider).profile.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: Space.s),
                child: Text('Add your profile so this uses your real experience.', style: context.text.bodySmall?.copyWith(color: AppColors.warning)),
              ),
            const SizedBox(height: Space.m),
            FutureBuilder<String>(
              future: future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.l),
                    child: Shimmer(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final w in [0.4, 1.0, 0.95, 1.0, 0.7, 1.0, 0.9, 0.5]) Padding(padding: const EdgeInsets.only(bottom: 9), child: FractionallySizedBox(widthFactor: w, child: const Bone(height: 12)))])),
                  );
                }
                if (snap.hasError) return Text(aiErrorText(snap.error!), style: TextStyle(color: AppColors.danger));
                final text = snap.data ?? '';
                final subject = RegExp(r'^Subject:\s*(.+)$', multiLine: true).firstMatch(text)?[1]?.trim();
                final body = text.replaceFirst(RegExp(r'^Subject:.*\n+', multiLine: true), '').trim();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(Space.m),
                      decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m)),
                      child: SelectableText(text, style: const TextStyle(height: 1.5)),
                    ),
                    const SizedBox(height: Space.m),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: text));
                              if (context.mounted) showSnack(context, 'Copied');
                            },
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            label: const Text('Copy'),
                          ),
                        ),
                        if (j.applyEmail.isNotEmpty) ...[
                          const SizedBox(width: Space.s),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => _open(
                                context,
                                Uri(scheme: 'mailto', path: j.applyEmail, queryParameters: {'subject': subject ?? 'Application: ${j.title}', 'body': body}).toString().replaceAll('+', '%20'),
                              ),
                              icon: const Icon(Icons.mail_outline_rounded, size: 18),
                              label: const Text('Email it'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: Space.l),
            TextField(
              controller: extra,
              decoration: const InputDecoration(labelText: 'Change something', hintText: 'e.g. shorter, more formal, mention my portfolio'),
            ),
            const SizedBox(height: Space.s),
            TextButton.icon(
              onPressed: () => setSheet(() => future = store.draftApplication(j, extra: extra.text)),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Write it again'),
            ),
          ],
        ),
      ),
    );
    extra.dispose();
  }

  Future<void> _remindDeadline() async {
    final d = j.deadline;
    if (d == null) return;
    final at = DateTime(d.year, d.month, d.day - 1, 9);
    final when = at.isAfter(DateTime.now()) ? at : DateTime.now().add(const Duration(hours: 1));
    try {
      final r = await ref.read(reminderStoreProvider.notifier).add(text: '💼 Apply for ${j.title}${j.company.isEmpty ? '' : ' at ${j.company}'}: closes ${dayName(d)}', at: when);
      final store = ref.read(opportunityProvider.notifier);
      if (ref.read(opportunityProvider).trackedJob(j.key) == null) await store.track(j, JobStatus.saved);
      await store.updateTracked(j.key, (x) => x.copyWith(reminders: [...x.reminders, r.id]));
      if (mounted) showSnack(context, 'I\'ll remind you ${DateFormat('EEE d MMM, HH:mm').format(when)}', icon: Icons.notifications_active_outlined);
    } catch (e) {
      if (mounted) showSnack(context, '$e', icon: Icons.error_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tracked = ref.watch(opportunityProvider.select((o) => o.trackedJob(j.key)));
    final store = ref.read(opportunityProvider.notifier);
    final info = j.info;
    final left = j.daysLeft;
    final applyButtons = <Widget>[
      if (j.applyLink.isNotEmpty) FilledButton.icon(onPressed: () => _open(context, j.applyLink), icon: const Icon(Icons.open_in_new_rounded, size: 18), label: const Text('Apply')),
      if (j.applyEmail.isNotEmpty)
        FilledButton.tonalIcon(
          onPressed: () => _open(context, Uri(scheme: 'mailto', path: j.applyEmail, queryParameters: {'subject': 'Application: ${j.title}'}).toString().replaceAll('+', '%20')),
          icon: const Icon(Icons.mail_outline_rounded, size: 18),
          label: const Text('Email'),
        ),
      if (j.applyTelegram.isNotEmpty)
        FilledButton.tonalIcon(onPressed: () => _open(context, 'https://t.me/${j.applyTelegram.substring(1)}'), icon: const Icon(Icons.send_rounded, size: 18), label: Text(j.applyTelegram)),
      if (j.applyPhone.isNotEmpty)
        FilledButton.tonalIcon(onPressed: () => _open(context, 'tel:${j.applyPhone.replaceAll(' ', '')}'), icon: const Icon(Icons.call_outlined, size: 18), label: const Text('Call')),
    ];
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: tracked == null ? 'Save' : 'Saved',
            icon: Icon(tracked == null ? Icons.bookmark_border_rounded : Icons.bookmark_rounded, color: tracked == null ? null : oppColor),
            onPressed: () => tracked == null ? store.track(j, JobStatus.saved) : store.untrack(j.key),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'post':
                  _openPost(context, j.post);
                case 'forward':
                  await showForwardSheet(context, j.post.chatId, j.post.messageIds);
                case 'copy':
                  await Clipboard.setData(ClipboardData(text: [j.title, if (j.company.isNotEmpty) j.company, if (j.applyLink.isNotEmpty) j.applyLink, j.post.text].join('\n')));
                  if (context.mounted) showSnack(context, 'Copied');
                case 'hide':
                  await store.setHidden(j.key, true);
                  if (context.mounted) Navigator.pop(context);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'post', child: Text('Open the post')),
              PopupMenuItem(value: 'forward', child: Text('Forward in Telegram')),
              PopupMenuItem(value: 'copy', child: Text('Copy')),
              PopupMenuItem(value: 'hide', child: Text('Hide this job')),
            ],
          ),
        ],
      ),
      bottomNavigationBar: const BottomAudioBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, 120),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Hero(
                tag: 'job-${j.key}',
                child: j.post.pictures.isEmpty
                    ? LetterAvatar(j.company.isNotEmpty ? j.company : j.post.source, size: 64)
                    : GestureDetector(
                        onTap: () => _openPost(context, j.post),
                        child: OppThumb(post: j.post, size: 64, radius: 16, icon: Icons.work_outline_rounded, cacheWidth: 240),
                      ),
              ),
              const SizedBox(width: Space.l),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      j.title,
                      style: TextStyle(fontSize: 23, height: 1.18, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: AppColors.text),
                    ),
                    const SizedBox(height: 4),
                    Text([if (j.company.isNotEmpty) j.company, if (j.location.isNotEmpty) j.location].join(' · '), style: TextStyle(color: AppColors.text2, fontSize: 15)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.m),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (j.type.isNotEmpty) Chip(avatar: const Icon(Icons.schedule_rounded, size: 16), label: Text(j.type)),
              if (j.workplace.isNotEmpty) Chip(avatar: const Icon(Icons.home_work_outlined, size: 16), label: Text(j.workplace[0].toUpperCase() + j.workplace.substring(1))),
              if (j.level.isNotEmpty) Chip(avatar: const Icon(Icons.stairs_outlined, size: 16), label: Text(j.level)),
              if (j.salary.isNotEmpty)
                Chip(
                  avatar: Icon(Icons.payments_outlined, size: 16, color: AppColors.success),
                  label: Text(j.salary),
                ),
              if (info?.vacancies != null) Chip(avatar: const Icon(Icons.groups_outlined, size: 16), label: Text('${info!.vacancies} ${info.vacancies == 1 ? 'opening' : 'openings'}')),
              if ((info?.category ?? '').isNotEmpty) Chip(avatar: const Icon(Icons.category_outlined, size: 16), label: Text(info!.category)),
            ],
          ),
          const SizedBox(height: Space.m),
          if (j.deadline != null)
            Container(
              padding: const EdgeInsets.all(Space.m),
              decoration: BoxDecoration(
                color: (j.closed ? AppColors.text3 : (left != null && left <= 3 ? AppColors.danger : oppColor)).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(Radii.m),
              ),
              child: Row(
                children: [
                  Icon(Icons.timer_outlined, color: j.closed ? AppColors.text3 : (left != null && left <= 3 ? AppColors.danger : oppColor)),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Text(
                      j.closed
                          ? 'Closed on ${DateFormat('EEE d MMM').format(j.deadline!)}'
                          : 'Apply by ${DateFormat('EEEE d MMM').format(j.deadline!)} · ${left == 0 ? 'today' : '$left ${left == 1 ? 'day' : 'days'} left'}',
                      style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.text),
                    ),
                  ),
                  if (!j.closed) TextButton(onPressed: _remindDeadline, child: const Text('Remind me')),
                ],
              ),
            ),
          if (info?.legit != null) ...[
            const SizedBox(height: Space.m),
            Container(
              padding: const EdgeInsets.all(Space.m),
              decoration: BoxDecoration(
                color: LegitBadge.colorOf(info!.legit!).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(Radii.m),
                border: Border.all(color: LegitBadge.colorOf(info.legit!).withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  LegitBadge(score: info.legit!, big: true),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          info.legit! >= 70 ? 'Looks genuine' : (info.legit! >= 45 ? 'Check before you apply' : 'Be careful: this may be a scam'),
                          style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.text),
                        ),
                        if (info.legitNotes.isNotEmpty) Text(info.legitNotes, style: context.text.bodySmall),
                        if (info.legit! < 45) Text('Never pay to apply, train or get a job.', style: context.text.bodySmall?.copyWith(color: AppColors.danger)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (j.match != null) ...[
            const SizedBox(height: Space.m),
            Container(
              padding: const EdgeInsets.all(Space.m),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(Radii.m),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(
                children: [
                  MatchRing(value: j.match!, size: 52),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          j.match! >= 75 ? 'Strong fit' : (j.match! >= 50 ? 'Partial fit' : 'Weak fit'),
                          style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.text),
                        ),
                        if (info!.matchReason.isNotEmpty) Text(info.matchReason, style: context.text.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: Space.l),
          Text('YOUR APPLICATION', style: context.text.labelSmall),
          const SizedBox(height: Space.s),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final s in JobStatus.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(s.label),
                      selected: tracked?.status == s,
                      selectedColor: oppColor,
                      labelStyle: TextStyle(fontWeight: FontWeight.w600, color: tracked?.status == s ? AppLook.onBrand(oppColor) : AppColors.text),
                      onSelected: (_) async {
                        await store.track(j, s);
                        if (s == JobStatus.applied && context.mounted) showSnack(context, 'Good luck! Marked as applied', icon: Icons.send_outlined);
                      },
                    ),
                  ),
              ],
            ),
          ),
          if (tracked != null) ...[
            if (tracked.appliedAt != null)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Text('Applied ${DateFormat('EEE d MMM').format(tracked.appliedAt!)}', style: context.text.bodySmall),
              ),
            const SizedBox(height: Space.s),
            TextFormField(
              initialValue: tracked.note,
              maxLines: 4,
              minLines: 1,
              decoration: const InputDecoration(hintText: 'Notes: who you talked to, interview date…', isDense: true),
              onChanged: (v) => store.updateTracked(j.key, (x) => x.copyWith(note: v)),
            ),
          ],
          const SizedBox(height: Space.l),
          if (applyButtons.isNotEmpty) Wrap(spacing: Space.s, runSpacing: Space.s, children: applyButtons),
          if (info?.apply.isNotEmpty ?? false)
            Padding(
              padding: const EdgeInsets.only(top: Space.s),
              child: Text(info!.apply, style: context.text.bodySmall),
            ),
          const SizedBox(height: Space.s),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              foregroundColor: oppColor,
              side: BorderSide(color: oppColor.withValues(alpha: 0.5)),
            ),
            onPressed: _draft,
            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
            label: const Text('Draft my application'),
          ),
          if (info?.summary.isNotEmpty ?? false) ...[
            const SizedBox(height: Space.xl),
            Text('ABOUT THE ROLE', style: context.text.labelSmall),
            const SizedBox(height: Space.s),
            Text(
              info!.summary,
              style: TextStyle(color: AppColors.text, fontSize: 15.5, height: 1.45, fontWeight: FontWeight.w500),
            ),
          ],
          if (info?.requirements.isNotEmpty ?? false) ...[
            const SizedBox(height: Space.xl),
            Text('REQUIREMENTS', style: context.text.labelSmall),
            const SizedBox(height: Space.s),
            for (final r in info!.requirements)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(color: oppColor, shape: BoxShape.circle),
                      ),
                    ),
                    const SizedBox(width: Space.s),
                    Expanded(
                      child: Text(r, style: TextStyle(color: AppColors.text, height: 1.4)),
                    ),
                  ],
                ),
              ),
          ],
          if (info?.skills.isNotEmpty ?? false) ...[
            const SizedBox(height: Space.l),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final s in info!.skills) Chip(label: Text(s))]),
          ],
          const SizedBox(height: Space.xl),
          Row(
            children: [
              Expanded(child: Text('THE POST', style: context.text.labelSmall)),
              TextButton.icon(
                onPressed: () => _openPost(context, j.post),
                icon: const Icon(Icons.forum_outlined, size: 16),
                label: Text(j.post.source, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          _Folding(j.post.text, lines: 12),
        ],
      ),
    );
  }
}

// ---- yours --------------------------------------------------------------------------------

/// A saved event or job drawn the way the lists draw it: its post is read
/// (once) to get there, with a skeleton meanwhile, and a plain row from
/// what was kept if the post is gone.
class _SavedPost extends ConsumerStatefulWidget {
  const _SavedPost({required this.kind, required this.postKey, required this.fallback, required this.builder});
  final OppKind kind;
  final String postKey;
  final Widget fallback;
  final Widget Function(OppPost post) builder;

  @override
  ConsumerState<_SavedPost> createState() => _SavedPostState();
}

class _SavedPostState extends ConsumerState<_SavedPost> {
  late final Future<OppPost?> _post = ref.read(oppFeedProvider(widget.kind).notifier).fetch(widget.postKey).catchError((Object _) => null);

  @override
  Widget build(BuildContext context) => FutureBuilder<OppPost?>(
    future: _post,
    initialData: ref.read(oppFeedProvider(widget.kind).notifier).byKey(widget.postKey),
    builder: (context, snap) {
      final p = snap.data;
      if (p != null) return widget.builder(p);
      if (snap.connectionState != ConnectionState.done) {
        return widget.kind == OppKind.job ? const SkeletonCards(count: 1, padding: EdgeInsets.zero) : const SkeletonRows(count: 1, art: 92, artRadius: 14, lines: 3);
      }
      return widget.fallback;
    },
  );
}

class MyEventsScreen extends ConsumerWidget {
  const MyEventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = ref.watch(opportunityProvider);
    final all = o.savedEvents;
    final now = DateTime.now().subtract(const Duration(hours: 6));
    final upcoming = [
      for (final e in all)
        if (e.status != EventStatus.went && (e.start == null || e.start!.isAfter(now))) e,
    ]..sort((a, b) => (a.start ?? DateTime(9999)).compareTo(b.start ?? DateTime(9999)));
    final past = [
      for (final e in all)
        if (!upcoming.contains(e)) e,
    ]..sort((a, b) => (b.start ?? b.savedAt).compareTo(a.start ?? a.savedAt));
    Widget fallback(SavedEvent e) => ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(width: 56, height: 56, child: e.mini == null ? ColoredBox(color: AppColors.surface2, child: Icon(Icons.event_rounded, color: AppColors.text3)) : Image.memory(base64Decode(e.mini!), fit: BoxFit.cover)),
      ),
      title: Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [e.start == null ? 'Date to be announced' : '${dayName(e.start!)}${e.hasTime ? ', ${timeText(e.start!)}' : ''}', if (e.place.isNotEmpty) e.place, 'post no longer available'].join(' · '),
        maxLines: 2,
        style: context.text.bodySmall,
      ),
    );
    Widget item(SavedEvent e) => Dismissible(
      key: ValueKey(e.key),
      direction: DismissDirection.endToStart,
      background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: Space.xl), color: AppColors.danger.withValues(alpha: 0.12), child: Icon(Icons.bookmark_remove_outlined, color: AppColors.danger)),
      onDismissed: (_) async {
        for (final id in e.reminders) {
          await ref.read(reminderStoreProvider.notifier).remove(id);
        }
        await ref.read(opportunityProvider.notifier).unsaveEvent(e.key);
      },
      child: _SavedPost(
        kind: OppKind.event,
        postKey: e.key,
        fallback: fallback(e),
        builder: (p) => EventRow(event: EventView(p, o.events[p.key])),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Your events')),
      body: all.isEmpty
          ? const SectionEmpty(icon: Icons.confirmation_number_outlined, title: 'No events yet', body: 'Tap "I\'m going" or "Interested" on an event to keep it here.')
          : ListView(
              padding: const EdgeInsets.only(bottom: Space.x4),
              children: [
                if (upcoming.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.xs), child: Text('UPCOMING · ${upcoming.length}', style: context.text.labelSmall)),
                for (final e in upcoming) item(e),
                if (past.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.xs), child: Text('PAST · ${past.length}', style: context.text.labelSmall)),
                for (final e in past) Opacity(opacity: 0.6, child: item(e)),
                Padding(padding: const EdgeInsets.all(Space.l), child: Text('Swipe left to remove one.', textAlign: TextAlign.center, style: context.text.labelSmall)),
              ],
            ),
    );
  }
}

/// Every job you saved or applied to, by where it stands, as job cards.
class ApplicationsScreen extends ConsumerWidget {
  const ApplicationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = ref.watch(opportunityProvider);
    final all = o.tracked;
    return DefaultTabController(
      length: JobStatus.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Your applications'),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: oppColor,
            tabs: [for (final s in JobStatus.values) Tab(text: '${s.label} · ${all.where((t) => t.status == s).length}')],
          ),
        ),
        body: TabBarView(
          children: [
            for (final s in JobStatus.values)
              Builder(
                builder: (context) {
                  final list = [
                    for (final t in all)
                      if (t.status == s) t,
                  ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
                  if (list.isEmpty) {
                    return Center(child: Padding(padding: const EdgeInsets.all(Space.x4), child: Text('Nothing ${s.label.toLowerCase()} yet.', style: context.text.bodySmall)));
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.x4),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final t = list[i];
                      final facts = [
                        if (t.appliedAt != null) 'Applied ${DateFormat('d MMM').format(t.appliedAt!)}' else 'Saved ${DateFormat('d MMM').format(t.savedAt)}',
                        if (t.note.isNotEmpty) t.note,
                      ].join(' · ');
                      return Padding(
                        padding: const EdgeInsets.only(bottom: Space.m),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _SavedPost(
                              kind: OppKind.job,
                              postKey: t.key,
                              fallback: Material(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(Radii.l),
                                child: ListTile(
                                  leading: LetterAvatar(t.company.isNotEmpty ? t.company : t.source, size: 46),
                                  title: Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                                  subtitle: Text([if (t.company.isNotEmpty) t.company, if (t.salary.isNotEmpty) t.salary, 'post no longer available'].join(' · '), style: context.text.bodySmall),
                                ),
                              ),
                              builder: (p) => JobCard(job: JobView(p, o.jobs[p.key])),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(left: Space.s),
                              child: Row(
                                children: [
                                  Icon(Icons.subdirectory_arrow_right_rounded, size: 16, color: AppColors.text3),
                                  const SizedBox(width: 4),
                                  Expanded(child: Text(facts, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall)),
                                  PopupMenuButton<JobStatus?>(
                                    tooltip: 'Move',
                                    padding: EdgeInsets.zero,
                                    onSelected: (v) async {
                                      final store = ref.read(opportunityProvider.notifier);
                                      if (v == null) {
                                        for (final id in t.reminders) {
                                          await ref.read(reminderStoreProvider.notifier).remove(id);
                                        }
                                        await store.untrack(t.key);
                                      } else {
                                        await store.updateTracked(t.key, (x) => x.copyWith(status: v, appliedAt: v == JobStatus.applied && x.appliedAt == null ? DateTime.now() : null));
                                      }
                                    },
                                    itemBuilder: (_) => [
                                      for (final x in JobStatus.values)
                                        if (x != s) PopupMenuItem(value: x, child: Text('Move to ${x.label}')),
                                      const PopupMenuItem(value: null, child: Text('Remove')),
                                    ],
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: 6),
                                      child: Row(mainAxisSize: MainAxisSize.min, children: [Text(s.label, style: TextStyle(color: oppColor, fontWeight: FontWeight.w700, fontSize: 12.5)), Icon(Icons.expand_more_rounded, size: 18, color: oppColor)]),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
