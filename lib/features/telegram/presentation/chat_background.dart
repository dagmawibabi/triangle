import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../../app/theme.dart';
import '../data/telegram_tools.dart';
import 'td_image.dart';

Color _rgb(int c) => Color(0xFF000000 | (c & 0xFFFFFF));

/// The colours of a fill, for gradients and the picker swatches.
List<Color> fillColors(td.BackgroundFill fill) => switch (fill) {
  td.BackgroundFillSolid(:final color) => [_rgb(color), _rgb(color)],
  td.BackgroundFillGradient(:final topColor, :final bottomColor) => [_rgb(topColor), _rgb(bottomColor)],
  td.BackgroundFillFreeformGradient(:final colors) => [for (final c in colors) _rgb(c)],
};

Gradient _gradient(td.BackgroundFill fill) {
  final colors = fillColors(fill);
  if (fill is td.BackgroundFillGradient) {
    final a = fill.rotationAngle * math.pi / 180;
    return LinearGradient(
      begin: Alignment(-math.sin(a), -math.cos(a)),
      end: Alignment(math.sin(a), math.cos(a)),
      colors: colors,
    );
  }
  if (fill is td.BackgroundFillFreeformGradient && colors.length >= 3) {
    return SweepGradient(colors: [...colors, colors.first]);
  }
  return LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors);
}

/// What a [td.Background] looks like: a wallpaper image, a gradient or
/// solid fill, or a pattern's fill (the pattern itself is a vector Telegram
/// ships as TGV, drawn here as its fill only).
class BackgroundView extends StatelessWidget {
  const BackgroundView({super.key, required this.background, this.dimming = 0, this.thumbnail = false});
  final td.Background background;

  /// 0..100, Telegram's dark-theme dimming.
  final int dimming;
  final bool thumbnail;

  @override
  Widget build(BuildContext context) {
    final b = background;
    final Widget base = switch (b.type) {
      td.BackgroundTypeWallpaper(:final isBlurred) => _Wallpaper(document: b.document, blurred: isBlurred, thumb: thumbnail),
      td.BackgroundTypePattern(:final fill, :final intensity) => DecoratedBox(
        decoration: BoxDecoration(gradient: _gradient(fill)),
        child: Opacity(
          opacity: (intensity.abs() / 100).clamp(0.15, 0.6),
          child: b.document == null ? const SizedBox.expand() : _Wallpaper(document: b.document, blurred: false, thumb: true),
        ),
      ),
      td.BackgroundTypeFill(:final fill) => DecoratedBox(decoration: BoxDecoration(gradient: _gradient(fill))),
      td.BackgroundTypeChatTheme() => ColoredBox(color: AppColors.surface),
    };
    // Keep messages readable on bright wallpapers in the dark UI.
    final dim = (dimming > 0 ? dimming / 100 : 0.35).clamp(0.0, 0.85);
    return Stack(
      fit: StackFit.expand,
      children: [
        base,
        if (!thumbnail) ColoredBox(color: Colors.black.withValues(alpha: dim)),
      ],
    );
  }
}

class _Wallpaper extends StatelessWidget {
  const _Wallpaper({required this.document, required this.blurred, required this.thumb});
  final td.Document? document;
  final bool blurred;
  final bool thumb;

  @override
  Widget build(BuildContext context) {
    final d = document;
    if (d == null) return ColoredBox(color: AppColors.surface);
    final file = thumb ? (d.thumbnail?.file ?? d.document) : d.document;
    return TdFileImage(file: file, minithumbnail: d.minithumbnail, priority: thumb ? 2 : 6);
  }
}

/// The chat's own background behind [child], when it has one.
class ChatBackdrop extends StatelessWidget {
  const ChatBackdrop({super.key, required this.background, required this.child});
  final td.ChatBackground? background;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final b = background;
    if (b == null) {
      // No wallpaper set: a faint wash of the accent from the corners, so
      // the glass header and composer have something to catch.
      return DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.bg,
          gradient: RadialGradient(
            center: const Alignment(1.1, -1.1),
            radius: 1.5,
            colors: [AppColors.tint.withValues(alpha: AppColors.isLight ? 0.06 : 0.07), AppColors.bg.withValues(alpha: 0)],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-1.2, 1.1),
              radius: 1.3,
              colors: [AppColors.tint.withValues(alpha: AppColors.isLight ? 0.04 : 0.05), AppColors.bg.withValues(alpha: 0)],
            ),
          ),
          child: child,
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: BackgroundView(background: b.background, dimming: b.darkThemeDimming)),
        child,
      ],
    );
  }
}

const _swatches = <List<int>>[
  [0x1E2A3A, 0x0F1620],
  [0x2B1D3A, 0x120C1A],
  [0x13302A, 0x09161A],
  [0x3A2414, 0x170D07],
  [0x24324F, 0x4A2850],
  [0x0E3B43, 0x2A1544],
  [0x202020, 0x202020],
  [0x3A1420, 0x101A3A],
];

/// Picks a background for a chat: Telegram's installed backgrounds, a
/// colour or gradient, or an image from the phone. Changes apply to this
/// chat (for both sides of a private chat unless "only for me").
Future<void> showBackgroundPicker(BuildContext context, WidgetRef ref, int chatId) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: AppColors.surface,
  showDragHandle: true,
  builder: (_) => _BackgroundPicker(chatId: chatId),
);

class _BackgroundPicker extends ConsumerStatefulWidget {
  const _BackgroundPicker({required this.chatId});
  final int chatId;

  @override
  ConsumerState<_BackgroundPicker> createState() => _BackgroundPickerState();
}

class _BackgroundPickerState extends ConsumerState<_BackgroundPicker> {
  List<td.Background>? _installed;
  bool _onlyForMe = true;
  bool _busy = false;
  int _dimming = 30;

  @override
  void initState() {
    super.initState();
    ref.read(toolRunnerProvider).installedBackgrounds().then((b) {
      if (mounted) setState(() => _installed = b);
    }, onError: (_) {
      if (mounted) setState(() => _installed = const []);
    });
  }

  Future<void> _apply(Future<void> Function(TelegramToolRunner r) f) async {
    setState(() => _busy = true);
    try {
      await f(ref.read(toolRunnerProvider));
      if (mounted) {
        Navigator.of(context).pop();
        showSnack(context, 'Background updated', icon: Icons.wallpaper_rounded);
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Couldn\'t change the background: $e', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final installed = _installed;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
          children: [
            Row(
              children: [
                Expanded(child: Text('Chat background', style: context.text.titleLarge)),
                if (_busy) const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            const SizedBox(height: Space.m),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('From gallery'),
                    onPressed: _busy
                        ? null
                        : () async {
                            final r = await FilePicker.pickFiles(type: FileType.image);
                            final path = r.firstOrNull?.path;
                            if (path == null) return;
                            await _apply(
                              (t) => t.setChatBackground(
                                widget.chatId,
                                localPath: path,
                                onlyForMe: _onlyForMe,
                                dimming: _dimming,
                              ),
                            );
                          },
                  ),
                ),
                const SizedBox(width: Space.s),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.format_color_reset_outlined),
                    label: const Text('Remove'),
                    onPressed: _busy ? null : () => _apply((t) => t.removeChatBackground(widget.chatId)),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Only for me'),
              subtitle: const Text('Off: the other person sees it too (private chats)'),
              value: _onlyForMe,
              onChanged: (v) => setState(() => _onlyForMe = v),
            ),
            Row(
              children: [
                const Text('Dimming'),
                Expanded(
                  child: Slider(
                    value: _dimming.toDouble(),
                    max: 80,
                    divisions: 16,
                    label: '$_dimming%',
                    onChanged: (v) => setState(() => _dimming = v.round()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.s),
            Text('Colours', style: context.text.titleSmall),
            const SizedBox(height: Space.s),
            Wrap(
              spacing: Space.s,
              runSpacing: Space.s,
              children: [
                for (final s in _swatches)
                  InkWell(
                    borderRadius: BorderRadius.circular(Radii.m),
                    onTap: _busy
                        ? null
                        : () => _apply(
                            (t) => t.setChatBackground(
                              widget.chatId,
                              fill: s[0] == s[1]
                                  ? td.BackgroundFillSolid(color: s[0])
                                  : td.BackgroundFillGradient(topColor: s[0], bottomColor: s[1], rotationAngle: 0),
                              onlyForMe: _onlyForMe,
                              dimming: _dimming,
                            ),
                          ),
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Radii.m),
                        border: Border.all(color: AppColors.line),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [_rgb(s[0]), _rgb(s[1])],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Space.l),
            Text('Telegram backgrounds', style: context.text.titleSmall),
            const SizedBox(height: Space.s),
            if (installed == null)
              const Padding(
                padding: EdgeInsets.all(Space.l),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (installed.isEmpty)
              Text('None installed.', style: context.text.bodySmall)
            else
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: Space.s,
                crossAxisSpacing: Space.s,
                childAspectRatio: 0.62,
                children: [
                  for (final b in installed)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.m),
                      child: Material(
                        type: MaterialType.transparency,
                        child: InkWell(
                          onTap: _busy
                              ? null
                              : () => _apply(
                                  (t) => t.setChatBackground(
                                    widget.chatId,
                                    backgroundId: b.id,
                                    type: b.type,
                                    onlyForMe: _onlyForMe,
                                    dimming: _dimming,
                                  ),
                                ),
                          child: BackgroundView(background: b, thumbnail: true),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
