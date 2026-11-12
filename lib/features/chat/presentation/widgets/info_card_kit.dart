import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/app_sheet.dart';

// Small shared pieces for the screen time, image, lookup, world and food
// cards: a framed card, a header line, stats, pills, a bar chart and the
// detail sheet's scaffold.

List<Map<String, dynamic>> maps(Object? v) => [
  for (final x in (v as List? ?? const []))
    if (x is Map) Map<String, dynamic>.from(x),
];

List<String> strs(Object? v) => [for (final x in (v as List? ?? const [])) '$x'];

Map<String, dynamic> mapOf(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

num? numOf(Object? v) => v is num ? v : num.tryParse('${v ?? ''}');

String? textOf(Object? v) {
  final s = '${v ?? ''}'.trim();
  return s.isEmpty || s == 'null' ? null : s;
}

Future<void> openLink(String? url) async {
  if (url == null || url.isEmpty) return;
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
}

void copyText(BuildContext context, String text, [String what = 'Copied']) {
  Clipboard.setData(ClipboardData(text: text));
  showSnack(context, what);
}

/// "1.2 MB", "340 KB".
String fileSize(num? bytes) {
  if (bytes == null) return '—';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(bytes < 10 * 1024 * 1024 ? 2 : 1)} MB';
}

class InfoFrame extends StatelessWidget {
  const InfoFrame({super.key, required this.child, this.onTap, this.color});
  final Widget child;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: Space.s),
    decoration: BoxDecoration(
      color: color ?? AppColors.surface,
      borderRadius: BorderRadius.circular(Radii.l),
      border: Border.all(color: AppColors.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: onTap == null ? child : InkWell(onTap: onTap, child: child),
  );
}

/// The small caps line at the top of a card.
class InfoHeader extends StatelessWidget {
  const InfoHeader(this.icon, this.label, {super.key, this.color, this.trailing, this.padding = const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.s)});
  final IconData icon;
  final String label;
  final Color? color;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      children: [
        Icon(icon, size: 16, color: color ?? AppColors.text2),
        const SizedBox(width: Space.s),
        Expanded(child: Text(label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall)),
        ?trailing,
      ],
    ),
  );
}

class InfoStat extends StatelessWidget {
  const InfoStat(this.label, this.value, {super.key, this.icon, this.valueColor});
  final String label;
  final String value;
  final IconData? icon;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (icon != null) ...[Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 16, color: AppColors.text3)), const SizedBox(width: 6)],
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: AppColors.text3, fontSize: 11)),
            const SizedBox(height: 1),
            Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: valueColor, fontFeatures: tabularFigures)),
          ],
        ),
      ),
    ],
  );
}

/// [stats] two to a row (three when [columns] says so).
Widget infoGrid(List<Widget> stats, {int columns = 2}) => LayoutBuilder(
  builder: (context, c) {
    final w = (c.maxWidth - Space.m * (columns - 1)) / columns;
    return Wrap(spacing: Space.m, runSpacing: Space.m, children: [for (final s in stats) SizedBox(width: w, child: s)]);
  },
);

class InfoPill extends StatelessWidget {
  const InfoPill(this.text, {super.key, this.color, this.onTap, this.icon});
  final String text;
  final Color? color;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = color;
    return Material(
      color: c == null ? AppColors.surface2 : c.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), border: Border.all(color: c == null ? AppColors.line : c.withValues(alpha: 0.4))),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 13, color: c ?? AppColors.text2), const SizedBox(width: 4)],
              Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c ?? AppColors.text2, fontWeight: c == null ? null : FontWeight.w600))),
            ],
          ),
        ),
      ),
    );
  }
}

/// A rising or falling change, coloured: up is red when [upIsBad].
class ChangeChip extends StatelessWidget {
  const ChangeChip(this.percent, {super.key, this.upIsBad = true, this.suffix = ''});
  final num percent;
  final bool upIsBad;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final up = percent > 0;
    final flat = percent == 0;
    final c = flat ? AppColors.text3 : (up == upIsBad ? AppColors.danger : AppColors.success);
    return InfoPill('${up ? '+' : ''}$percent%$suffix', color: c, icon: flat ? Icons.remove_rounded : (up ? Icons.trending_up_rounded : Icons.trending_down_rounded));
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing, this.top = Space.xl});
  final String text;
  final String? trailing;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: top, bottom: Space.s),
    child: Row(
      children: [
        Expanded(child: Text(text.toUpperCase(), style: context.text.labelSmall)),
        if (trailing != null) Text(trailing!, style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
      ],
    ),
  );
}

/// Vertical bars with optional labels under them; [ghost] draws a faint
/// comparison bar behind each (last week, say).
class MiniBars extends StatelessWidget {
  const MiniBars({
    super.key,
    required this.values,
    this.labels = const [],
    this.ghost = const [],
    this.highlight,
    this.color,
    this.height = 80,
    this.labelEvery = 1,
    this.valueLabel,
  });
  final List<num> values;
  final List<String> labels;
  final List<num> ghost;
  final int? highlight;
  final Color? color;
  final double height;
  final int labelEvery;
  final String Function(num v)? valueLabel;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.text;
    final top = [...values, ...ghost].fold<num>(0, (m, v) => v > m ? v : m);
    return Column(
      children: [
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < values.length; i++)
                Expanded(
                  child: Tooltip(
                    message: valueLabel == null ? '' : '${labels.elementAtOrNull(i) ?? ''} ${valueLabel!(values[i])}'.trim(),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: values.length > 16 ? 1 : 3),
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          if (i < ghost.length)
                            FractionallySizedBox(
                              heightFactor: top == 0 ? 0 : (ghost[i] / top).clamp(0, 1).toDouble(),
                              child: Container(decoration: BoxDecoration(color: AppColors.surface3, borderRadius: BorderRadius.circular(3))),
                            ),
                          FractionallySizedBox(
                            widthFactor: i < ghost.length ? 0.6 : 1,
                            heightFactor: top == 0 ? 0 : (values[i] / top).clamp(0, 1).toDouble(),
                            child: Container(
                              constraints: const BoxConstraints(minHeight: 2),
                              decoration: BoxDecoration(
                                color: highlight == null || highlight == i ? c : c.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (labels.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              for (var i = 0; i < values.length; i++)
                Expanded(
                  child: Text(
                    i % labelEvery == 0 ? labels.elementAtOrNull(i) ?? '' : '',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: TextStyle(fontSize: 10, color: highlight == i ? AppColors.text : AppColors.text3, fontWeight: highlight == i ? FontWeight.w700 : null),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A horizontal share bar, for "this app took 34%".
class ShareBar extends StatelessWidget {
  const ShareBar(this.fraction, {super.key, this.color, this.height = 5});
  final double fraction;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(99),
    child: Stack(
      children: [
        Container(height: height, color: AppColors.surface3),
        FractionallySizedBox(widthFactor: fraction.clamp(0, 1), child: Container(height: height, color: color ?? AppColors.text)),
      ],
    ),
  );
}

/// The standard detail sheet: a scrolling list of [children].
Future<void> showInfoSheet(BuildContext context, List<Widget> Function(BuildContext context) children, {double initialSize = 0.86}) => showAppSheet<void>(
  context,
  initialSize: initialSize,
  builder: (context, scroll) => ListView(
    controller: scroll,
    padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
    children: children(context),
  ),
);

/// Loads, then shows, a sheet.
Future<void> showLoadingSheet(BuildContext context, Future<Map<String, dynamic>> Function() load, List<Widget> Function(BuildContext context, Map<String, dynamic> data) children, {double initialSize = 0.9}) =>
    showAppSheet<void>(
      context,
      initialSize: initialSize,
      builder: (context, scroll) => FutureBuilder<Map<String, dynamic>>(
        future: load(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(Space.xl),
                child: Text('${snap.error}', textAlign: TextAlign.center, style: TextStyle(color: AppColors.text2)),
              ),
            );
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          return ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4), children: children(context, snap.data!));
        },
      ),
    );

class SheetTitle extends StatelessWidget {
  const SheetTitle(this.title, {super.key, this.subtitle, this.leading, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (leading != null) ...[leading!, const SizedBox(width: Space.m)],
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(title, style: context.text.titleLarge),
            if (subtitle != null && subtitle!.isNotEmpty) Text(subtitle!, style: context.text.bodySmall),
          ],
        ),
      ),
      ?trailing,
    ],
  );
}

/// A label and value on one line, for detail lists.
class KeyValueRow extends StatelessWidget {
  const KeyValueRow(this.label, this.value, {super.key, this.onTap, this.mono = false, this.valueColor});
  final String label;
  final String value;
  final VoidCallback? onTap;
  final bool mono;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: TextStyle(color: AppColors.text3, fontSize: 13))),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 13.5, fontFamily: mono ? 'monospace' : null, color: valueColor ?? (onTap == null ? AppColors.text : AppColors.text), decoration: onTap == null ? null : TextDecoration.underline, decorationColor: AppColors.text3),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget sheetButtons(List<Widget> buttons) => Padding(
  padding: const EdgeInsets.only(top: Space.l),
  child: Wrap(spacing: Space.s, runSpacing: Space.s, children: buttons),
);

Widget linkButton(String label, String? url, {IconData icon = Icons.open_in_new_rounded, bool filled = false}) => url == null
    ? const SizedBox.shrink()
    : filled
    ? FilledButton.icon(onPressed: () => openLink(url), icon: Icon(icon, size: 18), label: Text(label))
    : OutlinedButton.icon(onPressed: () => openLink(url), icon: Icon(icon, size: 18), label: Text(label));
