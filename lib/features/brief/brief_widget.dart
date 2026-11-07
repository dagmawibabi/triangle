import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../voice/speaker.dart';
import 'brief_store.dart';

/// Colours the home-screen widget comes in.
enum WidgetTheme {
  dark('Dark', 0xFF131316, 0xFFEDEDF0, 0xFFC9C9D1),
  black('Black', 0xFF000000, 0xFFFFFFFF, 0xFFBDBDC4),
  light('Light', 0xFFFFFFFF, 0xFF111114, 0xFF44444C),
  accent('Accent', 0xFF8AB4FF, 0xFF0B0B0D, 0xFF1A1A1E);

  const WidgetTheme(this.label, this.background, this.title, this.body);
  final String label;
  final int background;
  final int title;
  final int body;
}

/// How much of the brief the widget shows.
enum WidgetContent {
  tldr('TL;DR', 'Just the summary at the top'),
  needs('Needs you', 'The summary and what is waiting on you'),
  full('Everything', 'The whole brief, as far as it fits');

  const WidgetContent(this.label, this.explanation);
  final String label;
  final String explanation;
}

/// The widget's look, set in Settings → Home-screen widget.
@immutable
class WidgetLook {
  const WidgetLook({
    this.fontSize = 12.5,
    this.titleSize = 14,
    this.theme = WidgetTheme.dark,
    this.accent,
    this.opacity = 95,
    this.maxLines = 14,
    this.content = WidgetContent.needs,
    this.showTime = true,
    this.showTitle = true,
    this.showFooter = true,
    this.showImages = true,
  });

  /// Pictures in custom widgets' rows.
  final bool showImages;
  final double fontSize;
  final double titleSize;
  final WidgetTheme theme;

  /// The accent theme's colour, the app's accent unless set.
  final int? accent;

  /// Background opacity, 0-100.
  final int opacity;
  final int maxLines;
  final WidgetContent content;
  final bool showTime;
  final bool showTitle;
  final bool showFooter;

  int get background => theme == WidgetTheme.accent ? (accent ?? theme.background) : theme.background;

  WidgetLook copyWith({
    double? fontSize,
    double? titleSize,
    WidgetTheme? theme,
    int? accent,
    int? opacity,
    int? maxLines,
    WidgetContent? content,
    bool? showTime,
    bool? showTitle,
    bool? showFooter,
    bool? showImages,
  }) => WidgetLook(
    fontSize: fontSize ?? this.fontSize,
    titleSize: titleSize ?? this.titleSize,
    theme: theme ?? this.theme,
    accent: accent ?? this.accent,
    opacity: opacity ?? this.opacity,
    maxLines: maxLines ?? this.maxLines,
    content: content ?? this.content,
    showTime: showTime ?? this.showTime,
    showTitle: showTitle ?? this.showTitle,
    showFooter: showFooter ?? this.showFooter,
    showImages: showImages ?? this.showImages,
  );

  // Ints, strings and booleans only: the Kotlin side reads Flutter's
  // shared preferences, which store doubles in a form it can't.
  Future<void> save(SharedPreferences p) async {
    await p.setInt('widget_font_x10', (fontSize * 10).round());
    await p.setInt('widget_title_x10', (titleSize * 10).round());
    await p.setString('widget_theme', theme.name);
    await p.setInt('widget_background', background);
    await p.setInt('widget_title_color', theme.title);
    await p.setInt('widget_body_color', theme.body);
    await p.setInt('widget_opacity', opacity);
    await p.setInt('widget_max_lines', maxLines);
    await p.setString('widget_content', content.name);
    await p.setBool('widget_show_time', showTime);
    await p.setBool('widget_show_title', showTitle);
    await p.setBool('widget_show_footer', showFooter);
    await p.setBool('widget_show_images', showImages);
    if (accent != null) await p.setInt('widget_accent', accent!);
  }

  static WidgetLook load(SharedPreferences p) {
    const d = WidgetLook();
    return WidgetLook(
      fontSize: (p.getInt('widget_font_x10') ?? 125) / 10,
      titleSize: (p.getInt('widget_title_x10') ?? 140) / 10,
      theme: WidgetTheme.values.asNameMap()[p.getString('widget_theme')] ?? d.theme,
      accent: p.getInt('widget_accent'),
      opacity: p.getInt('widget_opacity') ?? d.opacity,
      maxLines: p.getInt('widget_max_lines') ?? d.maxLines,
      content: WidgetContent.values.asNameMap()[p.getString('widget_content')] ?? d.content,
      showTime: p.getBool('widget_show_time') ?? d.showTime,
      showTitle: p.getBool('widget_show_title') ?? d.showTitle,
      showFooter: p.getBool('widget_show_footer') ?? d.showFooter,
      showImages: p.getBool('widget_show_images') ?? d.showImages,
    );
  }
}

class WidgetLookController extends Notifier<WidgetLook> {
  @override
  WidgetLook build() {
    SharedPreferences.getInstance().then((p) => state = WidgetLook.load(p));
    return const WidgetLook();
  }

  Future<void> update(WidgetLook Function(WidgetLook) change) async {
    state = change(state);
    final p = await SharedPreferences.getInstance();
    await state.save(p);
    await BriefHomeWidget.publish(ref.read(briefStoreProvider).briefs, look: state);
  }
}

final widgetLookProvider = NotifierProvider<WidgetLookController, WidgetLook>(WidgetLookController.new);

/// The Android home-screen widget showing the latest brief (BriefWidget.kt).
/// The brief is written to shared preferences, where the widget reads it,
/// and the widget is told to redraw.
abstract final class BriefHomeWidget {
  static const _channel = MethodChannel('teleai/brief_widget');

  /// Taps on a widget: the brief opens the Brief screen, a custom widget
  /// [openWidget] (with the tapped row's link, if it has one).
  static void listen(VoidCallback openBriefs, {void Function(String id, String? link)? openWidget}) {
    if (kIsWeb || !Platform.isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openBrief') openBriefs();
      if (call.method == 'openWidget' && call.arguments is Map) {
        final a = call.arguments as Map;
        openWidget?.call('${a['id']}', a['link'] as String?);
      }
    });
    // A tap that launched the app arrives before anyone listened.
    _channel.invokeMethod<Object?>('takeLaunch').then((open) {
      if (open is! Map) return;
      if (open['brief'] == true) {
        openBriefs();
      } else if (open['id'] != null) {
        openWidget?.call('${open['id']}', open['link'] as String?);
      }
    }, onError: (_) {});
  }

  static Future<void> publish(List<Brief> briefs, {WidgetLook? look}) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final p = await SharedPreferences.getInstance();
      final l = look ?? WidgetLook.load(p);
      final b = briefs.where((b) => b.error == null && b.text.isNotEmpty).firstOrNull;
      if (b == null) {
        await p.remove('widget_brief_title');
        await p.remove('widget_brief_text');
        await p.remove('widget_brief_when');
      } else {
        await p.setString('widget_brief_title', '${b.kind.emoji} ${b.kind.label}');
        await p.setString('widget_brief_text', forWidget(b.text, l.content));
        await p.setString('widget_brief_when', DateFormat('EEE d MMM, HH:mm').format(b.at));
      }
      // The list the widget scrolls: one row per paragraph.
      await p.setString(
        'widget_payload.brief',
        jsonEncode({
          'title': b == null ? 'Brief' : '${b.kind.emoji} ${b.kind.label}',
          if (b != null) 'when': DateFormat('EEE d MMM, HH:mm').format(b.at),
          'empty': 'No brief yet. Tap to open Triangle and write one.',
          'brief': true,
          // The list scrolls, so the whole brief goes in and no row is cut
          // short: scrolling reaches the end.
          'full': true,
          'items': b == null
              ? const []
              : [
                  for (final para in forWidget(b.text, l.content, null).split(RegExp(r'\n\s*\n')))
                    if (para.trim().isNotEmpty) {'x': para.trim()},
                ],
        }),
      );
      await _channel.invokeMethod<void>('update');
    } catch (e) {
      debugPrint('[BriefWidget] $e');
    }
  }

  /// Plain text that fits a widget: the part of the brief [content] asks
  /// for, without Markdown or post links.
  /// [limit] cuts it for places that can't scroll; null keeps it all.
  static String forWidget(String markdown, [WidgetContent content = WidgetContent.full, int? limit = 1400]) {
    String section(RegExp start) {
      final m = start.firstMatch(markdown);
      if (m == null) return '';
      final rest = markdown.substring(m.end);
      // Up to the next heading or bold section title.
      final next = RegExp(r'\n\s*(#{1,6}\s|\*\*[^*\n]{2,40}\*\*\s*:?\s*\n|- \*\*[🔴🟠🟡⚪])').firstMatch(rest);
      return rest.substring(0, next?.start ?? rest.length).trim();
    }

    final tldr = section(RegExp(r'TL;?DR\**\s*:?\s*\**', caseSensitive: false));
    final needs = section(RegExp(r'Needs you now\**\s*:?\s*\**', caseSensitive: false));
    final picked = switch (content) {
      WidgetContent.tldr when tldr.isNotEmpty => tldr,
      WidgetContent.needs when tldr.isNotEmpty || needs.isNotEmpty => [tldr, if (needs.isNotEmpty) '🔴 $needs'].join('\n\n'),
      _ => markdown,
    };
    final text = Speaker.clean(
      picked.replaceAll(RegExp(r'https?://\S+'), '').replaceAll(RegExp(r'\(\s*\)'), ''),
    );
    return limit != null && text.length > limit ? '${text.substring(0, limit)}…' : text;
  }
}
