import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../../app/theme.dart';
import 'glass.dart';

/// One tab of a [GlassTabStrip]: its label and, optionally, a count.
class GlassTab {
  const GlassTab(this.label, {this.badge = 0, this.badgeMuted = false});
  final String label;

  /// Shown next to the label when above zero (unread chats, say).
  final int badge;

  /// The badge in grey rather than the accent (every unread chat muted).
  final bool badgeMuted;
}

/// Telegram's folder tabs: a glass pill of labels with a lit lozenge that
/// slides under them as [position] moves (a page index, fractional while
/// swiping between pages). Scrolls sideways when the tabs don't fit and
/// keeps the current one in view.
class GlassTabStrip extends StatefulWidget {
  const GlassTabStrip({
    super.key,
    required this.tabs,
    required this.position,
    required this.onTap,
    this.height = 44,
    this.onLongPress,
  });

  final List<GlassTab> tabs;
  final ValueListenable<double> position;
  final ValueChanged<int> onTap;
  final ValueChanged<int>? onLongPress;
  final double height;

  @override
  State<GlassTabStrip> createState() => _GlassTabStripState();
}

class _GlassTabStripState extends State<GlassTabStrip> {
  final _scroll = ScrollController();
  int _shown = -1;

  static const _labelStyle = TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.1);
  static const _badgeStyle = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700);
  static const _pad = 14.0;
  static const _inset = 4.0;

  @override
  void initState() {
    super.initState();
    widget.position.addListener(_follow);
  }

  @override
  void didUpdateWidget(GlassTabStrip old) {
    super.didUpdateWidget(old);
    if (old.position != widget.position) {
      old.position.removeListener(_follow);
      widget.position.addListener(_follow);
    }
  }

  @override
  void dispose() {
    widget.position.removeListener(_follow);
    _scroll.dispose();
    super.dispose();
  }

  List<double> _widths = const [];

  /// Brings the current tab to the middle of the strip when it changes.
  void _follow() {
    final i = widget.position.value.round();
    if (i == _shown || !_scroll.hasClients || i >= _widths.length) return;
    _shown = i;
    var left = 0.0;
    for (var k = 0; k < i; k++) {
      left += _widths[k];
    }
    final view = _scroll.position.viewportDimension;
    final target = (left + _widths[i] / 2 - view / 2).clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(target, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
  }

  static double _textWidth(String text, TextStyle style, TextScaler scaler) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      textScaler: scaler,
    )..layout();
    return tp.width;
  }

  String _badgeText(int n) => NumberFormat.compact().format(n);

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.2);
    final tabs = widget.tabs;
    return Glass(
      padding: const EdgeInsets.all(_inset),
      child: SizedBox(
        height: widget.height - _inset * 2,
        child: LayoutBuilder(
          builder: (context, box) {
            var widths = [
              for (final t in tabs)
                _pad * 2 +
                    _textWidth(t.label, _labelStyle, scaler) +
                    (t.badge > 0 ? 6 + math.max(20.0, _textWidth(_badgeText(t.badge), _badgeStyle, scaler) + 12) : 0),
            ];
            final total = widths.fold(0.0, (a, b) => a + b);
            if (total < box.maxWidth && tabs.isNotEmpty) {
              // Few tabs: share out the spare room so the pill is filled.
              final extra = (box.maxWidth - total) / tabs.length;
              widths = [for (final w in widths) w + extra];
            }
            _widths = widths;
            final lefts = <double>[];
            var x = 0.0;
            for (final w in widths) {
              lefts.add(x);
              x += w;
            }
            return SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: SizedBox(
                width: x,
                child: ValueListenableBuilder<double>(
                  valueListenable: widget.position,
                  builder: (context, p, _) {
                    final pos = p.clamp(0.0, math.max(0, tabs.length - 1).toDouble());
                    final i = pos.floor();
                    final j = math.min(i + 1, tabs.length - 1);
                    final f = pos - i;
                    final left = tabs.isEmpty ? 0.0 : lefts[i] + (lefts[j] - lefts[i]) * f;
                    final width = tabs.isEmpty ? 0.0 : widths[i] + (widths[j] - widths[i]) * f;
                    return Stack(
                      children: [
                        if (tabs.isNotEmpty)
                          Positioned(
                            left: left,
                            width: width,
                            top: 0,
                            bottom: 0,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: AppColors.tint.withValues(alpha: AppColors.isLight ? 0.12 : 0.16),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: CustomPaint(painter: const GlassRim(radius: 999, strength: 0.8)),
                            ),
                          ),
                        Row(
                          children: [
                            for (var k = 0; k < tabs.length; k++)
                              _TabLabel(
                                tab: tabs[k],
                                width: widths[k],
                                lit: (1 - (pos - k).abs()).clamp(0.0, 1.0),
                                badgeText: _badgeText(tabs[k].badge),
                                onTap: () => widget.onTap(k),
                                onLongPress: widget.onLongPress == null ? null : () => widget.onLongPress!(k),
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({
    required this.tab,
    required this.width,
    required this.lit,
    required this.badgeText,
    required this.onTap,
    this.onLongPress,
  });
  final GlassTab tab;
  final double width;
  final double lit;
  final String badgeText;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final on = AppColors.isLight || AppColors.tint.computeLuminance() > 0.6 ? AppColors.text : AppColors.tint;
    final color = Color.lerp(AppColors.text2, on, lit)!;
    final badgeBg = tab.badgeMuted
        ? AppColors.text3.withValues(alpha: 0.35)
        : Color.lerp(AppColors.text3.withValues(alpha: 0.5), AppColors.accent, lit)!;
    final badgeFg = tab.badgeMuted
        ? AppColors.text
        : Color.lerp(AppColors.bg, AppColors.accent.computeLuminance() > 0.5 ? const Color(0xFF0B0B0D) : Colors.white, lit)!;
    return SizedBox(
      width: width,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    tab.label,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: _GlassTabStripState._labelStyle.copyWith(color: color),
                  ),
                ),
                if (tab.badge > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    constraints: const BoxConstraints(minWidth: 20),
                    height: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(999)),
                    child: Text(badgeText, style: _GlassTabStripState._badgeStyle.copyWith(color: badgeFg)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
