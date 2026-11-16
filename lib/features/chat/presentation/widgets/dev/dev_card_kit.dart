import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../../app/theme.dart';
import '../../../../../core/widgets/code_highlight.dart' show codeTextStyle;
import '../../../../settings/data/settings.dart';
import '../../../../telegram/data/telegram_tools.dart';
import '../../../../telegram/presentation/chat_actions.dart' show confirmAction;

// Shared pieces of the Vercel, Resend and MongoDB cards: the panel and its
// header with the service's mark, status pills, live timers, a JSON tree,
// copyable rows, bars, the sheet scaffold, and running a tool from a card
// (with the read-only rule and a confirmation for anything that changes).

enum DevBrand {
  vercel('Vercel', Color(0xFFEDEDED)),
  resend('Resend', Color(0xFFEDEDED)),
  mongodb('MongoDB', Color(0xFF00ED64)),
  cloudflare('Cloudflare', Color(0xFFF38020)),
  parcels('Packages', Color(0xFFF59E0B)),
  github('GitHub', Color(0xFF8B949E)),
  gmail('Gmail', Color(0xFFEA4335)),
  calendar('Google Calendar', Color(0xFF4285F4)),
  notion('Notion', Color(0xFFEDEDED)),
  e2b('E2B', Color(0xFFFF8800));

  const DevBrand(this.label, this.color);
  final String label;
  final Color color;

  /// The brand colour, readable on the current background.
  Color get tint => AppColors.isLight && (this == vercel || this == resend || this == notion) ? const Color(0xFF111111) : color;
}

/// The service's mark: Vercel's triangle, Resend's R, MongoDB's leaf.
class DevMark extends StatelessWidget {
  const DevMark(this.brand, {super.key, this.size = 18});
  final DevBrand brand;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fg = AppColors.isLight ? Colors.white : Colors.black;
    final bg = AppColors.isLight ? const Color(0xFF111111) : Colors.white;
    return switch (brand) {
      DevBrand.vercel => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * 0.25)),
        padding: EdgeInsets.all(size * 0.22),
        child: CustomPaint(painter: _Triangle(fg)),
      ),
      DevBrand.resend => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * 0.25)),
        child: Text('R', style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: size * 0.62, height: 1)),
      ),
      DevBrand.mongodb => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: const Color(0xFF001E2B), borderRadius: BorderRadius.circular(size * 0.25)),
        child: Icon(Icons.eco_rounded, size: size * 0.72, color: const Color(0xFF00ED64)),
      ),
      DevBrand.cloudflare => Icon(Icons.cloud_rounded, size: size, color: brand.color),
      DevBrand.github => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Icon(Icons.code_rounded, size: size * 0.62, color: fg),
      ),
      DevBrand.gmail => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(size * 0.25)),
        child: Icon(Icons.mail_rounded, size: size * 0.7, color: brand.color),
      ),
      DevBrand.calendar => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(size * 0.25), border: Border.all(color: brand.color, width: size * 0.06)),
        child: Text('${DateTime.now().day}', style: TextStyle(color: brand.color, fontWeight: FontWeight.w800, fontSize: size * 0.48, height: 1)),
      ),
      DevBrand.notion => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(size * 0.2), border: Border.all(color: Colors.black, width: size * 0.07)),
        child: Text('N', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: size * 0.6, height: 1, fontFamily: 'serif')),
      ),
      DevBrand.e2b => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: brand.color, borderRadius: BorderRadius.circular(size * 0.25)),
        child: Icon(Icons.terminal_rounded, size: size * 0.66, color: Colors.black),
      ),
      DevBrand.parcels => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: brand.color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(size * 0.25)),
        child: Icon(Icons.local_shipping_rounded, size: size * 0.68, color: brand.color),
      ),
    };
  }
}

class _Triangle extends CustomPainter {
  _Triangle(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size s) => canvas.drawPath(
    Path()
      ..moveTo(s.width / 2, s.height * 0.08)
      ..lineTo(s.width, s.height * 0.92)
      ..lineTo(0, s.height * 0.92)
      ..close(),
    Paint()..color = color,
  );
  @override
  bool shouldRepaint(_Triangle old) => old.color != color;
}

class DevPanel extends StatelessWidget {
  const DevPanel({super.key, required this.children, this.danger = false, this.glow, this.onTap});
  final List<Widget> children;
  final bool danger;

  /// A coloured edge for live or finished states.
  final Color? glow;

  /// Opens the card's details sheet; rows and buttons inside keep their own taps.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final edge = danger ? AppColors.danger.withValues(alpha: 0.5) : (glow?.withValues(alpha: 0.55) ?? AppColors.line);
    return Container(
      margin: const EdgeInsets.only(bottom: Space.s),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.l),
        border: Border.all(color: edge),
        // A faint wash of the state colour along the top.
        gradient: glow == null
            ? null
            : LinearGradient(
                begin: Alignment.topCenter,
                end: const Alignment(0, -0.2),
                colors: [glow!.withValues(alpha: 0.07), AppColors.surface],
              ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ),
    );
  }
}

class DevHead extends StatelessWidget {
  const DevHead({super.key, required this.brand, required this.title, this.subtitle, this.trailing, this.onTap});
  final DevBrand brand;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.s + 2, Space.s, Space.xs),
      child: Row(
        children: [
          DevMark(brand),
          const SizedBox(width: Space.s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelMedium?.copyWith(color: AppColors.text2)),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    ),
  );
}

class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, required this.color, this.icon, this.pulse = false});
  final String label;
  final Color color;
  final IconData? icon;

  /// A live dot in front, for something still running.
  final bool pulse;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(99)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (pulse) ...[_Pulse(color: color), const SizedBox(width: 5)],
        if (icon != null && !pulse) ...[Icon(icon, size: 12, color: color), const SizedBox(width: 4)],
        Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

class _Pulse extends StatefulWidget {
  const _Pulse({required this.color});
  final Color color;
  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: 0.3, end: 1.0).animate(_c),
    child: Container(width: 7, height: 7, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
  );
}

/// Seconds since [from], ticking while shown.
class Elapsed extends StatefulWidget {
  const Elapsed({super.key, required this.from, this.until, this.style});
  final DateTime from;
  final DateTime? until;
  final TextStyle? style;
  @override
  State<Elapsed> createState() => _ElapsedState();
}

class _ElapsedState extends State<Elapsed> {
  Timer? _t;
  @override
  void initState() {
    super.initState();
    if (widget.until == null) _t = Timer.periodic(const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(span((widget.until ?? DateTime.now()).difference(widget.from)), style: widget.style ?? context.text.labelSmall);
}

String span(Duration d) {
  if (d.isNegative) return '0s';
  if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
  if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds % 60}s';
  return '${d.inSeconds}s';
}

DateTime? parseWhen(Object? v) {
  if (v == null) return null;
  if (v is num) return DateTime.fromMillisecondsSinceEpoch(v > 1e12 ? v.toInt() : v.toInt() * 1000);
  return DateTime.tryParse('$v')?.toLocal();
}

/// "3 min ago", "yesterday 14:05", "12 Mar".
String ago(Object? v) {
  final d = parseWhen(v);
  if (d == null) return '';
  final diff = DateTime.now().difference(d);
  if (diff.isNegative) {
    final ahead = -diff.inMinutes;
    return ahead < 60 ? 'in $ahead min' : (ahead < 60 * 24 ? 'in ${(ahead / 60).round()} h' : DateFormat('d MMM, HH:mm').format(d));
  }
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays < 7) return '${diff.inDays} d ago';
  return d.year == DateTime.now().year ? DateFormat('d MMM').format(d) : DateFormat('d MMM y').format(d);
}

String bytes(Object? v) {
  final n = v is num ? v.toDouble() : double.tryParse('$v');
  if (n == null) return '';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var x = n;
  var i = 0;
  while (x >= 1024 && i < units.length - 1) {
    x /= 1024;
    i++;
  }
  return '${x < 10 && i > 0 ? x.toStringAsFixed(1) : x.round()} ${units[i]}';
}

String compact(Object? v) {
  final n = v is num ? v : num.tryParse('$v');
  if (n == null) return '${v ?? ''}';
  return NumberFormat.compact().format(n);
}

/// A thin bar for a share of a whole.
class ShareBar extends StatelessWidget {
  const ShareBar({super.key, required this.value, this.color, this.height = 5});
  final double value;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(99),
    child: SizedBox(
      height: height,
      child: Stack(
        children: [
          Container(color: AppColors.surface2),
          FractionallySizedBox(widthFactor: value.clamp(0.0, 1.0), child: Container(color: color ?? AppColors.accent)),
        ],
      ),
    ),
  );
}

/// A label and value side by side, the value copyable.
class CopyRow extends StatelessWidget {
  const CopyRow({super.key, required this.label, required this.value, this.mono = true});
  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () {
      Clipboard.setData(ClipboardData(text: value));
      showSnack(context, '$label copied');
    },
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 74, child: Text(label, style: context.text.labelSmall?.copyWith(color: AppColors.text3))),
          Expanded(
            child: Text(
              value,
              style: mono ? codeTextStyle.copyWith(fontSize: 12.5) : context.text.bodySmall,
            ),
          ),
          Icon(Icons.copy_rounded, size: 14, color: AppColors.text3),
        ],
      ),
    ),
  );
}

/// Small number tiles in a wrap.
class StatTiles extends StatelessWidget {
  const StatTiles(this.items, {super.key});
  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.m),
    child: LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth > 420 ? 4 : (c.maxWidth > 260 ? 3 : 2);
        final w = (c.maxWidth - (cols - 1) * Space.s) / cols;
        return Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            for (final (label, value) in items)
              Container(
                width: w,
                padding: const EdgeInsets.all(Space.s + 2),
                decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.s)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontFeatures: tabularFigures)),
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
                  ],
                ),
              ),
          ],
        );
      },
    ),
  );
}

/// A "show N more" footer.
class MoreRow extends StatelessWidget {
  const MoreRow({super.key, required this.label, this.onTap, this.busy = false});
  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: busy ? null : onTap,
    child: Padding(
      padding: const EdgeInsets.all(Space.m),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (busy) const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)) else Icon(Icons.expand_more_rounded, size: 18, color: AppColors.accent),
          const SizedBox(width: Space.xs),
          Text(label, style: context.text.labelMedium?.copyWith(color: AppColors.accent)),
        ],
      ),
    ),
  );
}

/// Pads [child] as card content.
Widget pad(Widget child, {double top = 0, double bottom = Space.m}) => Padding(padding: EdgeInsets.fromLTRB(Space.m, top, Space.m, bottom), child: child);

void openUrl(String url) => launchUrl(Uri.parse(url.startsWith('http') ? url : 'https://$url'), mode: LaunchMode.externalApplication);

/// A bottom sheet that can grow to full height, with a title row.
Future<T?> showDevSheet<T>(
  BuildContext context, {
  required DevBrand brand,
  required String title,
  String? subtitle,
  List<Widget> actions = const [],
  required Widget Function(BuildContext context, ScrollController scroll) builder,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  backgroundColor: AppColors.surface,
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl))),
  builder: (sheet) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.72,
    minChildSize: 0.35,
    maxChildSize: 0.96,
    builder: (context, scroll) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.s, Space.s),
          child: Row(
            children: [
              DevMark(brand, size: 26),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    if (subtitle != null && subtitle.isNotEmpty) Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                  ],
                ),
              ),
              ...actions,
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: builder(context, scroll)),
      ],
    ),
  ),
);

/// A section heading inside a sheet.
class SheetLabel extends StatelessWidget {
  const SheetLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.l, Space.xl, Space.m, Space.s),
    child: Row(children: [Expanded(child: Text(text.toUpperCase(), style: context.text.labelSmall)), ?trailing]),
  );
}

/// A rounded group of rows inside a sheet.
class SheetGroup extends StatelessWidget {
  const SheetGroup({super.key, required this.children, this.danger = false});
  final List<Widget> children;
  final bool danger;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: Space.l),
    decoration: BoxDecoration(
      color: AppColors.surface2.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(Radii.l),
      border: Border.all(color: danger ? AppColors.danger.withValues(alpha: 0.4) : AppColors.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: Material(type: MaterialType.transparency, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)),
  );
}

/// Loads [load] once and shows a spinner, the error, or [builder].
class Loaded<T> extends StatefulWidget {
  const Loaded({super.key, required this.load, required this.builder});
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T value, VoidCallback reload) builder;

  @override
  State<Loaded<T>> createState() => _LoadedState<T>();
}

class _LoadedState<T> extends State<Loaded<T>> {
  late Future<T> _f = widget.load();

  void _reload() => setState(() => _f = widget.load());

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: _f,
    builder: (context, snap) {
      if (snap.connectionState != ConnectionState.done) return const SkeletonPage();
      if (snap.hasError) {
        return Padding(
          padding: const EdgeInsets.all(Space.l),
          child: Column(
            children: [
              Text('${snap.error}', style: context.text.bodySmall?.copyWith(color: AppColors.danger)),
              TextButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Try again')),
            ],
          ),
        );
      }
      return widget.builder(context, snap.data as T, _reload);
    },
  );
}

/// Runs [tool] from a card or sheet. Tools that change something ask
/// first and stay off in read-only mode; errors are thrown with the
/// service's message.
Future<Map<String, dynamic>> devRun(
  BuildContext context,
  WidgetRef ref,
  String tool,
  Map<String, dynamic> args, {
  String? confirmTitle,
  String? confirmMessage,
  String? confirmLabel,
}) async {
  final t = toolNamed(tool);
  final s = ref.read(settingsProvider);
  if (t != null && t.modifiesData) {
    if (s.readOnlyMode) throw 'Read-only mode is on: nothing can be changed.';
    final ok = await confirmAction(
      context,
      title: confirmTitle ?? '${t.label}?',
      message: confirmMessage ?? t.description,
      action: confirmLabel ?? 'Go ahead',
      danger: t.destructive,
    );
    if (!ok) throw const _Cancelled();
  }
  final reading = t == null || !t.modifiesData;
  final key = reading ? _devCacheKey(tool, args) : null;
  if (devCacheOnly) {
    final hit = key == null ? null : await _devCacheRead(key);
    if (hit == null) throw const DevNoCache();
    return hit;
  }
  final r = await ref.read(toolRunnerProvider).run(tool, args);
  if (r.json['error'] != null) throw '${r.json['error']}';
  if (key != null) unawaited(_devCacheWrite(key, r.json));
  return r.json;
}

// ---- what the manager pages saw last time ------------------------------------
//
// The manager pages (mail, Vercel, MongoDB, …) show what reading tools
// returned last time straight away, then refresh behind it: a first pass
// runs their loaders inside [devFromCache], where [devRun] answers from
// this cache (memory, then the phone) or throws [DevNoCache].

/// Inside a [devFromCache] pass: reading tools answer from the cache only.
bool get devCacheOnly => Zone.current[#devCacheOnly] == true;

/// Thrown in a [devFromCache] pass when there is nothing saved.
class DevNoCache implements Exception {
  const DevNoCache();
}

/// Runs [load] answering only from what was saved last time.
Future<T> devFromCache<T>(Future<T> Function() load) => runZoned(load, zoneValues: {#devCacheOnly: true});

final _devMem = <String, Map<String, dynamic>>{};
const _devPrefix = 'devcache.v1:';

String _devCacheKey(String tool, Map<String, dynamic> args) {
  // Times ("from two hours ago") change every call; the same view should
  // still find what it showed last time.
  final stable = jsonEncode(args, toEncodable: (o) => '$o').replaceAll(RegExp(r'\d{4}-\d{2}-\d{2}T[\d:.]+Z?'), 'T');
  return '$tool $stable';
}

Future<Map<String, dynamic>?> _devCacheRead(String key) async {
  final mem = _devMem[key];
  if (mem != null) return mem;
  try {
    final raw = (await SharedPreferences.getInstance()).getString('$_devPrefix$key');
    if (raw == null) return null;
    final j = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    _devMem[key] = j;
    return j;
  } catch (_) {
    return null;
  }
}

Future<void> _devCacheWrite(String key, Map<String, dynamic> value) async {
  _devMem[key] = value;
  try {
    final raw = jsonEncode(value);
    if (raw.length > 400 * 1024) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_devPrefix$key', raw);
    // Keeps the newest 120 views.
    final order = [...(prefs.getStringList('${_devPrefix}order') ?? const <String>[])]..remove(key)..add(key);
    while (order.length > 120) {
      await prefs.remove('$_devPrefix${order.removeAt(0)}');
    }
    await prefs.setStringList('${_devPrefix}order', order);
  } catch (_) {}
}

class _Cancelled implements Exception {
  const _Cancelled();
}

/// Whether [e] is the person backing out of a confirmation.
bool cancelled(Object e) => e is _Cancelled;

/// A button that runs an action, spinning while it does and showing its
/// error as a toast.
class ActionButton extends StatefulWidget {
  const ActionButton({super.key, required this.label, required this.icon, required this.onRun, this.danger = false, this.filled = false, this.done});
  final String label;
  final IconData icon;
  final Future<void> Function() onRun;
  final bool danger;
  final bool filled;

  /// The toast after it worked.
  final String? done;

  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton> {
  bool _busy = false;

  Future<void> _go() async {
    setState(() => _busy = true);
    try {
      await widget.onRun();
      if (mounted && widget.done != null) showSnack(context, widget.done!);
    } catch (e) {
      if (mounted && !cancelled(e)) showSnack(context, '$e'.replaceFirst('Exception: ', ''), icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = _busy ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(widget.icon, size: 18);
    final style = widget.danger ? OutlinedButton.styleFrom(foregroundColor: AppColors.danger, side: BorderSide(color: AppColors.danger.withValues(alpha: 0.5))) : null;
    return widget.filled
        ? FilledButton.tonalIcon(onPressed: _busy ? null : _go, icon: icon, label: Text(widget.label))
        : OutlinedButton.icon(style: style, onPressed: _busy ? null : _go, icon: icon, label: Text(widget.label));
  }
}

// ---- JSON ------------------------------------------------------------------------------

/// [dark] on a dark page, [light] on a light one.
Color adapt(Color dark, Color light) => AppColors.isLight ? light : dark;

/// MongoDB's green, deep enough to read on white.
Color get mongoGreen => adapt(const Color(0xFF00ED64), const Color(0xFF00A35C));

/// A soft accent-tinted button that reads in both themes.
ButtonStyle get tonalButton => FilledButton.styleFrom(backgroundColor: AppColors.accent.withValues(alpha: 0.14), foregroundColor: AppColors.accent);

/// A solid icon button: the page's text colour with the page behind it.
ButtonStyle get solidIconButton => IconButton.styleFrom(backgroundColor: AppColors.text, foregroundColor: AppColors.bg);

Color jsonColor(Object? v) {
  if (v == null) return AppColors.text3;
  if (v is bool) return adapt(const Color(0xFFC792EA), const Color(0xFF7C3AED));
  if (v is num) return adapt(const Color(0xFFF78C6C), const Color(0xFFC2410C));
  if (v is String) return adapt(const Color(0xFFC3E88D), const Color(0xFF15803D));
  if (v is Map && (v.containsKey(r'$oid'))) return adapt(const Color(0xFF82AAFF), const Color(0xFF1D4ED8));
  if (v is Map && (v.containsKey(r'$date'))) return adapt(const Color(0xFFFFCB6B), const Color(0xFFA16207));
  return AppColors.text2;
}

/// One value as a short line: strings quoted, ids and dates unwrapped.
String jsonInline(Object? v, {int max = 80}) {
  String s;
  if (v is Map && v.length == 1 && v.containsKey(r'$oid')) {
    s = 'ObjectId(${v[r'$oid']})';
  } else if (v is Map && v.length == 1 && v.containsKey(r'$date')) {
    final d = parseWhen(v[r'$date'] is Map ? (v[r'$date'] as Map)[r'$numberLong'] : v[r'$date']);
    s = d == null ? '${v[r'$date']}' : DateFormat('d MMM y, HH:mm').format(d);
  } else if (v is Map && v.length == 1 && (v.containsKey(r'$numberLong') || v.containsKey(r'$numberDecimal') || v.containsKey(r'$numberDouble'))) {
    s = '${v.values.first}';
  } else if (v is String) {
    s = '"$v"';
  } else if (v is Map) {
    s = '{${v.length} field${v.length == 1 ? '' : 's'}}';
  } else if (v is List) {
    s = '[${v.length} item${v.length == 1 ? '' : 's'}]';
  } else {
    s = '$v';
  }
  return s.length > max ? '${s.substring(0, max)}…' : s;
}

bool _leaf(Object? v) => !(v is Map || v is List) || (v is Map && v.length <= 2 && v.keys.every((k) => '$k'.startsWith(r'$')));

/// An expandable tree of a JSON value: tap a branch to open it, long-press
/// a value to copy it.
class JsonTree extends StatelessWidget {
  const JsonTree({super.key, required this.value, this.depth = 0, this.openDepth = 1});
  final Object? value;
  final int depth;
  final int openDepth;

  @override
  Widget build(BuildContext context) {
    final entries = value is Map
        ? [for (final e in (value as Map).entries) ('${e.key}', e.value)]
        : [for (final (i, x) in (value as List? ?? const []).indexed) ('$i', x)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final (k, v) in entries.take(300)) _JsonRow(name: k, value: v, depth: depth, open: depth < openDepth - 1)],
    );
  }
}

class _JsonRow extends StatefulWidget {
  const _JsonRow({required this.name, required this.value, required this.depth, required this.open});
  final String name;
  final Object? value;
  final int depth;
  final bool open;
  @override
  State<_JsonRow> createState() => _JsonRowState();
}

class _JsonRowState extends State<_JsonRow> {
  late bool _open = widget.open;

  @override
  Widget build(BuildContext context) {
    final leaf = _leaf(widget.value);
    final style = codeTextStyle.copyWith(fontSize: 12.5, height: 1.35);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: leaf ? null : () => setState(() => _open = !_open),
          onLongPress: () {
            Clipboard.setData(ClipboardData(text: widget.value is String ? widget.value as String : jsonEncode(widget.value)));
            showSnack(context, '${widget.name} copied');
          },
          child: Padding(
            padding: EdgeInsets.only(left: widget.depth * 14.0, top: 2, bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 16,
                  child: leaf ? null : Icon(_open ? Icons.arrow_drop_down_rounded : Icons.arrow_right_rounded, size: 18, color: AppColors.text3),
                ),
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      style: style,
                      children: [
                        TextSpan(text: widget.name, style: TextStyle(color: AppColors.text2, fontWeight: FontWeight.w600)),
                        const TextSpan(text: ': '),
                        TextSpan(text: jsonInline(widget.value, max: 140), style: TextStyle(color: jsonColor(widget.value))),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_open && !leaf) JsonTree(value: widget.value, depth: widget.depth + 1, openDepth: 0),
      ],
    );
  }
}

// ---- web previews ----------------------------------------------------------------------

/// Whether pages can be shown inside the app here.
bool get canPreviewWeb => Platform.isAndroid || Platform.isIOS;

/// One loaded page, kept so scrolling a card away and back (or rebuilding
/// it) shows the same page instead of loading it again.
class _Page {
  _Page(this.url, this.html) {
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => progress.value = p,
        onPageFinished: (_) {
          progress.value = 100;
          done.value = true;
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame ?? true) error.value = e.description;
        },
      ));
    load();
  }

  final String? url;
  final String? html;
  late final WebViewController controller;
  final progress = ValueNotifier<int>(0);
  final done = ValueNotifier<bool>(false);
  final error = ValueNotifier<String?>(null);

  void load() {
    done.value = false;
    error.value = null;
    progress.value = 0;
    if (html != null) {
      controller.loadHtmlString(html!);
    } else if (url != null) {
      controller.loadRequest(Uri.parse(url!.startsWith('http') ? url! : 'https://$url'));
    }
  }

  static final _cache = <String, _Page>{};

  /// The page for [key], made once; the oldest are dropped past eight.
  static _Page of(String key, String? url, String? html) {
    final hit = _cache.remove(key);
    final page = hit ?? _Page(url, html);
    _cache[key] = page;
    while (_cache.length > 8) {
      _cache.remove(_cache.keys.first);
    }
    return page;
  }
}

/// A live look at a page ([url]) or raw [html]. In a card it is a still
/// window ([interactive] false) that a tap passes through; in a sheet it
/// scrolls and clicks like a browser. Loaded once and kept: scrolling past
/// it doesn't load it again. A skeleton shows until the page is ready.
class WebPreview extends StatefulWidget {
  const WebPreview({super.key, this.url, this.html, this.height = 220, this.interactive = false, this.onTap});
  final String? url;
  final String? html;
  final double height;
  final bool interactive;
  final VoidCallback? onTap;

  @override
  State<WebPreview> createState() => _WebPreviewState();
}

class _WebPreviewState extends State<WebPreview> with AutomaticKeepAliveClientMixin {
  _Page? _page;

  // A card and a sheet may show the same page at once: each gets its own.
  String get _key => '${widget.interactive ? 'sheet' : 'card'}:${widget.url ?? 'html${widget.html.hashCode}'}';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (canPreviewWeb && (widget.url != null || widget.html != null)) _page = _Page.of(_key, widget.url, widget.html);
  }

  @override
  void didUpdateWidget(WebPreview old) {
    super.didUpdateWidget(old);
    if (canPreviewWeb && (old.url != widget.url || old.html != widget.html || old.interactive != widget.interactive)) {
      _page = _Page.of(_key, widget.url, widget.html);
    }
  }

  static String _full(String url) => url.startsWith('http') ? url : 'https://$url';

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final page = _page;
    final host = widget.url == null ? 'HTML preview' : (Uri.tryParse(_full(widget.url!))?.host ?? widget.url!);
    return Container(
      height: widget.height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(Radii.m), border: Border.all(color: AppColors.line), color: AppColors.surface2),
      child: Column(
        children: [
          // A small browser bar: the address, reload and open.
          Container(
            height: 30,
            color: AppColors.surface2,
            padding: const EdgeInsets.symmetric(horizontal: Space.s),
            child: Row(
              children: [
                for (final c in const [Color(0xFFFF5F57), Color(0xFFFEBC2E), Color(0xFF28C840)])
                  Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 4), decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                const SizedBox(width: Space.s),
                Icon(widget.url == null ? Icons.code_rounded : Icons.lock_outline_rounded, size: 12, color: AppColors.text3),
                const SizedBox(width: 4),
                Expanded(child: Text(host, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall)),
                if (page != null)
                  InkWell(onTap: page.load, child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.refresh_rounded, size: 15, color: AppColors.text3))),
                if (widget.url != null)
                  InkWell(onTap: () => openUrl(widget.url!), child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.open_in_new_rounded, size: 14, color: AppColors.text3))),
              ],
            ),
          ),
          if (page != null)
            ValueListenableBuilder<int>(
              valueListenable: page.progress,
              builder: (context, p, _) => p > 0 && p < 100 ? LinearProgressIndicator(value: p / 100, minHeight: 2) : const SizedBox(height: 2),
            ),
          Expanded(
            child: page == null
                ? InkWell(
                    onTap: widget.onTap ?? (widget.url == null ? null : () => openUrl(widget.url!)),
                    child: Stack(
                      children: [
                        const Positioned.fill(child: PageSkeleton(animate: false)),
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
                            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(99)),
                            child: Text(widget.url == null ? 'Preview on the phone app' : 'Tap to open the page', style: context.text.labelSmall),
                          ),
                        ),
                      ],
                    ),
                  )
                : Stack(
                    children: [
                      Positioned.fill(child: WebViewWidget(controller: page.controller)),
                      // The skeleton until the page has loaded, or the error.
                      Positioned.fill(
                        child: ValueListenableBuilder<String?>(
                          valueListenable: page.error,
                          builder: (context, error, _) => error != null
                              ? Container(
                                  color: AppColors.surface2,
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.all(Space.m),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.wifi_off_rounded, color: AppColors.text3),
                                      const SizedBox(height: 4),
                                      Text(error, textAlign: TextAlign.center, maxLines: 3, style: context.text.bodySmall),
                                      TextButton(onPressed: page.load, child: const Text('Try again')),
                                    ],
                                  ),
                                )
                              : ValueListenableBuilder<bool>(
                                  valueListenable: page.done,
                                  builder: (context, done, _) => IgnorePointer(
                                    ignoring: done,
                                    child: AnimatedOpacity(opacity: done ? 0 : 1, duration: const Duration(milliseconds: 300), child: const PageSkeleton()),
                                  ),
                                ),
                        ),
                      ),
                      // In a card the page is a picture: a tap opens the sheet.
                      if (!widget.interactive) Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onTap)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ---- skeletons -------------------------------------------------------------------------

/// A soft shimmer passing over its [child]'s shapes, for loading states.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child, this.animate = true});
  final Widget child;
  final bool animate;
  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (context, child) => ShaderMask(
      blendMode: BlendMode.srcATop,
      shaderCallback: (r) => LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [AppColors.surface2, AppColors.surface3, AppColors.surface2],
        stops: const [0.25, 0.5, 0.75],
        transform: _Slide(_c.value),
      ).createShader(r),
      child: child,
    ),
  );
}

class _Slide extends GradientTransform {
  const _Slide(this.t);
  final double t;
  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) => Matrix4.translationValues(bounds.width * (t * 2 - 1), 0, 0);
}

/// A grey block for skeletons.
class Bone extends StatelessWidget {
  const Bone({super.key, this.width, this.height = 12, this.radius = 6, this.circle = false});
  final double? width;
  final double height;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) => Container(
    width: circle ? height : width,
    height: height,
    decoration: BoxDecoration(color: AppColors.surface2, shape: circle ? BoxShape.circle : BoxShape.rectangle, borderRadius: circle ? null : BorderRadius.circular(radius)),
  );
}

/// The outline of a web page: a bar, a heading, a picture and text.
class PageSkeleton extends StatelessWidget {
  const PageSkeleton({super.key, this.animate = true});
  final bool animate;

  @override
  Widget build(BuildContext context) => Container(
    color: AppColors.surface,
    padding: const EdgeInsets.all(Space.m),
    child: Shimmer(
      animate: animate,
      child: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [const Bone(height: 18, circle: true), const SizedBox(width: 8), const Bone(width: 70), const Spacer(), for (var i = 0; i < 3; i++) const Padding(padding: EdgeInsets.only(left: 8), child: Bone(width: 32, height: 8))]),
              const SizedBox(height: 18),
              Bone(width: c.maxWidth * 0.7, height: 18),
              const SizedBox(height: 8),
              Bone(width: c.maxWidth * 0.45, height: 12),
              const SizedBox(height: 14),
              Bone(width: c.maxWidth, height: (c.maxHeight * 0.3).clamp(40, 160), radius: 10),
              const SizedBox(height: 14),
              for (final f in const [0.95, 0.85, 0.9, 0.6]) Padding(padding: const EdgeInsets.only(bottom: 7), child: Bone(width: c.maxWidth * f, height: 9)),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Placeholder rows while a list loads: an icon, two lines and a pill.
class SkeletonRows extends StatelessWidget {
  const SkeletonRows({super.key, this.count = 5, this.padding = const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s)});
  final int count;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Shimmer(
    child: Column(
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: padding,
            child: Row(
              children: [
                const Bone(width: 40, height: 40, radius: 10),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [Bone(width: 120.0 + (i * 37) % 90, height: 12), const SizedBox(height: 7), Bone(width: 180.0 - (i * 23) % 70, height: 9)],
                  ),
                ),
                const Bone(width: 54, height: 18, radius: 99),
              ],
            ),
          ),
      ],
    ),
  );
}

/// Placeholder for a sheet or page: a block, tiles and rows.
class SkeletonPage extends StatelessWidget {
  const SkeletonPage({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.m),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Shimmer(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Bone(height: 120, radius: 14),
                const SizedBox(height: Space.m),
                Row(children: [for (var i = 0; i < 3; i++) ...[if (i > 0) const SizedBox(width: Space.s), const Expanded(child: Bone(height: 54, radius: 10))]]),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.m),
        const SkeletonRows(count: 4),
      ],
    ),
  );
}

/// Full-screen preview of [html], e.g. a code block or a page about to be deployed.
Future<void> showHtmlPreview(BuildContext context, String html, {String title = 'HTML preview'}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (context) => Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Copy HTML',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: html));
              showSnack(context, 'HTML copied');
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(Space.s),
        child: LayoutBuilder(builder: (context, c) => WebPreview(html: html, height: c.maxHeight, interactive: true)),
      ),
    ),
  ),
);

/// Whether [code] in [language] is a page that can be previewed.
bool looksLikeHtml(String code, String language) {
  final l = language.toLowerCase();
  if (const {'html', 'htm', 'xhtml', 'svg'}.contains(l)) return true;
  final t = code.trimLeft().toLowerCase();
  return t.startsWith('<!doctype html') || t.startsWith('<html') || (l.isEmpty && t.startsWith('<svg'));
}

/// A details sheet for any result: every field as a tree, copyable.
Future<void> showJsonSheet(BuildContext context, {required DevBrand brand, required String title, String? subtitle, required Object? value, List<Widget> Function(BuildContext context)? header}) => showDevSheet(
  context,
  brand: brand,
  title: title,
  subtitle: subtitle,
  actions: [
    IconButton(
      tooltip: 'Copy all',
      icon: const Icon(Icons.copy_rounded, size: 18),
      onPressed: () {
        Clipboard.setData(ClipboardData(text: value is String ? value : const JsonEncoder.withIndent('  ').convert(value)));
        showSnack(context, 'Copied');
      },
    ),
  ],
  builder: (context, scroll) => ListView(
    controller: scroll,
    padding: const EdgeInsets.only(bottom: Space.x4),
    children: [
      ...?header?.call(context),
      const SheetLabel('Everything'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l),
        child: value is Map || value is List ? JsonTree(value: value, openDepth: 2) : SelectableText('$value'),
      ),
    ],
  ),
);
