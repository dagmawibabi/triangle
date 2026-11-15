import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme.dart';
import '../../core/widgets/app_sheet.dart';
import '../media/audio_center.dart';
import '../telegram/data/file_loader.dart' show formatDuration;
import 'playlists.dart';

/// A cached image of the file at [path], decoded once at a fixed size so
/// every cover of it (grid, list, header, drawer) shares one decode.
ImageProvider coverImage(String path, {int width = 600}) => ResizeImage(FileImage(File(path)), width: width, policy: ResizeImagePolicy.fit);

/// Decodes [p]'s cover ahead of time, so it's there the moment it shows.
void precachePlaylist(BuildContext context, Playlist p) {
  final paths = [if (p.coverPath != null && fileExists(p.coverPath!)) p.coverPath! else if (p.collage) ...p.arts];
  for (final path in paths) {
    precacheImage(coverImage(path, width: paths.length > 1 ? 300 : 600), context).ignore();
  }
}

/// A playlist's cover: its picture, a collage of its tracks' album art, or
/// its gradient with soft rings and its mark.
class PlaylistCover extends StatelessWidget {
  const PlaylistCover({super.key, required this.playlist, this.size, this.radius = Radii.l, this.emojiScale = 0.38});
  final Playlist playlist;

  /// Square side; fills its box when null.
  final double? size;
  final double radius;
  final double emojiScale;

  @override
  Widget build(BuildContext context) {
    final p = playlist;
    final cover = p.coverPath;
    Widget child = LayoutBuilder(
      builder: (context, box) {
        final side = size ?? math.min(box.maxWidth, box.maxHeight.isFinite ? box.maxHeight : box.maxWidth);
        if (cover != null && fileExists(cover)) {
          return Image(image: coverImage(cover), fit: BoxFit.cover, width: side, height: side, gaplessPlayback: true);
        }
        final arts = p.collage ? p.arts : const <String>[];
        if (arts.isNotEmpty) return ArtCollage(paths: arts, side: side, fill: p.colors);
        return GradientArt(colors: p.colors, mark: playlistMark(p, side * emojiScale), side: side);
      },
    );
    child = ClipRRect(borderRadius: BorderRadius.circular(radius), child: child);
    return size == null ? AspectRatio(aspectRatio: 1, child: child) : SizedBox.square(dimension: size, child: child);
  }
}

/// A playlist's mark at [size]: its icon, its emoji, or nothing.
Widget? playlistMark(Playlist p, double size, {Color color = Colors.white}) {
  final icon = playlistIcons[p.icon];
  if (icon != null) return Icon(icon, size: size * 1.05, color: color, shadows: const [Shadow(color: Color(0x40000000), blurRadius: 18, offset: Offset(0, 6))]);
  if (p.emoji.isEmpty) return null;
  return Text(p.emoji, style: TextStyle(fontSize: size, height: 1, shadows: const [Shadow(color: Color(0x40000000), blurRadius: 18, offset: Offset(0, 6))]));
}

/// Album covers in a square: one alone, two side by side, three with one
/// big, or four in a grid.
class ArtCollage extends StatelessWidget {
  const ArtCollage({super.key, required this.paths, required this.side, required this.fill});
  final List<String> paths;
  final double side;
  final List<Color> fill;

  @override
  Widget build(BuildContext context) {
    // Flexible cells, so odd sizes (and a cover mid-flight between pages)
    // never overflow by a pixel.
    Widget img(String path) => Image(
      image: coverImage(path, width: paths.length == 1 ? 600 : 300),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: fill))),
    );
    Widget cell(String path) => Expanded(child: img(path));
    return SizedBox.square(
      dimension: side,
      child: ClipRect(
        child: switch (paths.length) {
          1 => img(paths[0]),
          2 => Row(children: [cell(paths[0]), cell(paths[1])]),
          3 => Row(children: [cell(paths[0]), Expanded(child: Column(children: [cell(paths[1]), cell(paths[2])]))]),
          _ => Column(
            children: [
              Expanded(child: Row(children: [cell(paths[0]), cell(paths[1])])),
              Expanded(child: Row(children: [cell(paths[2]), cell(paths[3])])),
            ],
          ),
        },
      ),
    );
  }
}

/// A gradient square with rings and an optional mark: the cover of a
/// playlist without a picture or album art.
class GradientArt extends StatelessWidget {
  const GradientArt({super.key, required this.colors, required this.side, this.mark, this.emoji, this.emojiScale = 0.38});
  final List<Color> colors;
  final double side;
  final Widget? mark;

  /// Shorthand for an emoji [mark].
  final String? emoji;
  final double emojiScale;

  @override
  Widget build(BuildContext context) => Container(
    width: side,
    height: side,
    decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors)),
    child: CustomPaint(
      painter: _RingsPainter(),
      child: Center(
        child: mark ??
            (emoji == null || emoji!.isEmpty
                ? null
                : Text(emoji!, style: TextStyle(fontSize: side * emojiScale, height: 1, shadows: const [Shadow(color: Color(0x40000000), blurRadius: 18, offset: Offset(0, 6))]))),
      ),
    ),
  );
}

class _RingsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width * 0.82, size.height * 0.16);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0x22FFFFFF)
      ..strokeWidth = size.width * 0.018;
    for (var i = 1; i <= 5; i++) {
      canvas.drawCircle(c, size.width * 0.17 * i, paint);
    }
    canvas.drawCircle(
      Offset(size.width * 0.1, size.height * 0.95),
      size.width * 0.32,
      Paint()..color = const Color(0x16000000),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Three bouncing bars: this is what's playing.
class EqualizerBars extends StatefulWidget {
  const EqualizerBars({super.key, required this.playing, this.color, this.size = 16});
  final bool playing;
  final Color? color;
  final double size;

  @override
  State<EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<EqualizerBars> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    if (widget.playing) _c.repeat();
  }

  @override
  void didUpdateWidget(EqualizerBars old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_c.isAnimating) _c.repeat();
    if (!widget.playing && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? AppColors.tint;
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < 3; i++)
              Container(
                width: widget.size / 4.5,
                height: widget.size * (widget.playing ? 0.3 + 0.7 * (0.5 + 0.5 * math.sin((_c.value * 2 * math.pi) + i * 2.1)).abs() : 0.35),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
              ),
          ],
        ),
      ),
    );
  }
}

/// A track's small square: album art, or its kind's icon on a tint.
class TrackArt extends StatelessWidget {
  const TrackArt({super.key, required this.track, this.size = 48});
  final PlaylistTrack track;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = track;
    Widget? img;
    if (t.artPath != null && fileExists(t.artPath!)) {
      img = Image(image: coverImage(t.artPath!, width: 200), fit: BoxFit.cover, width: size, height: size, gaplessPlayback: true);
    } else if (t.thumb != null) {
      try {
        img = Image.memory(base64Decode(t.thumb!), fit: BoxFit.cover, width: size, height: size, gaplessPlayback: true);
      } catch (_) {}
    } else if (t.artUrl != null) {
      img = Image.network(t.artUrl!, fit: BoxFit.cover, width: size, height: size, errorBuilder: (_, _, _) => const SizedBox());
    }
    final hue = (t.title.hashCode % 360).abs().toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              HSLColor.fromAHSL(1, hue, 0.45, AppColors.isLight ? 0.82 : 0.32).toColor(),
              HSLColor.fromAHSL(1, (hue + 40) % 360, 0.5, AppColors.isLight ? 0.72 : 0.22).toColor(),
            ],
          ),
        ),
        child: img ?? Icon(t.kind.icon, size: size * 0.46, color: AppColors.isLight ? const Color(0xCC000000) : const Color(0xE6FFFFFF)),
      ),
    );
  }
}

/// Where a track came from, as a small icon and label.
Widget trackSourceLine(BuildContext context, PlaylistTrack t, {int maxLines = 1}) {
  final icon = switch (t.source) {
    TrackSource.telegram => Icons.send_rounded,
    TrackSource.file => Icons.folder_outlined,
    TrackSource.stream => Icons.wifi_tethering_rounded,
  };
  final sub = t.subtitle;
  return Row(
    children: [
      Icon(icon, size: 12, color: t.source == TrackSource.telegram ? const Color(0xFF2AABEE) : AppColors.text3),
      const SizedBox(width: 4),
      if (t.kind == TrackKind.voice || t.kind == TrackKind.podcast || t.kind == TrackKind.audiobook) ...[
        Icon(t.kind.icon, size: 12, color: AppColors.text3),
        const SizedBox(width: 4),
      ],
      Expanded(
        child: Text(
          sub.isEmpty ? t.kind.label : sub,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: context.text.bodySmall?.copyWith(color: AppColors.text2),
        ),
      ),
    ],
  );
}

/// A track row: art (or the bars while it plays), title, where it's from,
/// length, and an optional checkbox or menu.
class TrackRow extends ConsumerWidget {
  const TrackRow({
    super.key,
    required this.track,
    this.index,
    this.onTap,
    this.onLongPress,
    this.trailing,
    this.selected,
    this.dense = false,
  });
  final PlaylistTrack track;
  final int? index;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  /// A checkbox state when picking; null when not.
  final bool? selected;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(audioCenterProvider);
    final isCurrent = a.current?.key == track.key;
    final title = Text(
      track.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.text.bodyLarge?.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: dense ? 14.5 : 15.5,
        color: isCurrent ? AppColors.tint : AppColors.text,
      ),
    );
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(Radii.m),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: Space.m, vertical: dense ? 6 : 8),
        child: Row(
          children: [
            if (selected != null) ...[
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected! ? AppColors.tint : Colors.transparent,
                  border: Border.all(color: selected! ? AppColors.tint : AppColors.text3, width: 1.6),
                ),
                child: selected! ? Icon(Icons.check_rounded, size: 15, color: AppColors.isLight ? Colors.white : AppColors.bg) : null,
              ),
              const SizedBox(width: Space.m),
            ] else if (index != null) ...[
              SizedBox(
                width: 24,
                child: Center(
                  child: isCurrent
                      ? EqualizerBars(playing: a.playing && !a.loading, size: 14)
                      : Text('${index! + 1}', style: context.text.bodySmall?.copyWith(color: AppColors.text3, fontFeatures: tabularFigures)),
                ),
              ),
              const SizedBox(width: Space.s),
            ],
            Stack(
              children: [
                TrackArt(track: track, size: dense ? 42 : 48),
                if (isCurrent && index == null)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular((dense ? 42 : 48) * 0.22)),
                      alignment: Alignment.center,
                      child: a.loading
                          ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : EqualizerBars(playing: a.playing, size: 16, color: Colors.white),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, const SizedBox(height: 2), trackSourceLine(context, track)],
              ),
            ),
            if (track.seconds > 0)
              Padding(
                padding: const EdgeInsets.only(left: Space.s),
                child: Text(formatDuration(track.seconds), style: context.text.bodySmall?.copyWith(color: AppColors.text3, fontFeatures: tabularFigures)),
              ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

// ---- editor ------------------------------------------------------------------

const _emojis = ['🎵', '🎧', '🎸', '🎹', '🥁', '🎤', '🎷', '🎻', '💿', '📻', '🌙', '☀️', '🔥', '💜', '🌊', '🌿', '🚗', '🏋️', '📚', '🙏', '😴', '☕', '🎉', '💭'];

/// Name, words and cover for a new or existing playlist; it, or null if
/// cancelled.
Future<Playlist?> showPlaylistEditor(BuildContext context, WidgetRef ref, {Playlist? playlist}) async {
  final out = await showFormSheet<_EditorResult>(context, builder: (_) => _PlaylistEditor(playlist: playlist));
  if (out == null || out.name.trim().isEmpty) return null;
  final store = ref.read(playlistsProvider.notifier);
  if (playlist == null) {
    final p = await store.create(out.name, description: out.description, emoji: out.emoji, icon: out.icon, collage: out.collage, palette: out.palette);
    if (out.coverPick != null) await store.setCover(p.id, out.coverPick!);
    return store.byId(p.id);
  }
  await store.update(
    playlist.id,
    (p) => p.copyWith(
      name: out.name.trim(),
      description: out.description.trim(),
      emoji: out.emoji,
      icon: out.icon,
      clearIcon: out.icon == null,
      collage: out.collage,
      palette: out.palette,
    ),
  );
  if (out.coverPick != null) {
    await store.setCover(playlist.id, out.coverPick!);
  } else if (out.removeCover) {
    await store.clearCover(playlist.id);
  }
  return store.byId(playlist.id);
}

typedef _EditorResult = ({
  String name,
  String description,
  String emoji,
  String? icon,
  bool collage,
  int palette,
  String? coverPick,
  bool removeCover,
});

enum _Mark { emoji, icon, none }

enum _Look { picture, collage, colour }

class _PlaylistEditor extends StatefulWidget {
  const _PlaylistEditor({this.playlist});
  final Playlist? playlist;

  @override
  State<_PlaylistEditor> createState() => _PlaylistEditorState();
}

class _PlaylistEditorState extends State<_PlaylistEditor> {
  late final _name = TextEditingController(text: widget.playlist?.name ?? '');
  late final _desc = TextEditingController(text: widget.playlist?.description ?? '');
  late final _custom = TextEditingController();
  late _Mark _mark = playlistIcons.containsKey(widget.playlist?.icon)
      ? _Mark.icon
      : (widget.playlist != null && widget.playlist!.emoji.isEmpty ? _Mark.none : _Mark.emoji);
  late String _emoji = widget.playlist?.emoji.isNotEmpty == true ? widget.playlist!.emoji : '🎵';
  late String _icon = playlistIcons.containsKey(widget.playlist?.icon) ? widget.playlist!.icon! : 'music';
  late int _palette = widget.playlist?.palette ?? math.Random().nextInt(playlistPalettes.length);
  late _Look _look = widget.playlist?.coverPath != null
      ? _Look.picture
      : (widget.playlist?.collage ?? true) && (widget.playlist?.arts.isNotEmpty ?? false)
      ? _Look.collage
      : _Look.colour;
  late bool _collage = widget.playlist?.collage ?? true;
  String? _pick;
  bool _removeCover = false;

  @override
  void initState() {
    super.initState();
    if (!_emojis.contains(_emoji)) _custom.text = _emoji;
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _custom.dispose();
    super.dispose();
  }

  String? get _cover => _pick ?? (_removeCover ? null : widget.playlist?.coverPath);
  List<String> get _arts => widget.playlist?.arts ?? const [];

  Future<void> _pickImage() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 88, maxWidth: 1400);
    if (x != null && mounted) {
      setState(() {
        _pick = x.path;
        _look = _Look.picture;
      });
    }
  }

  void _setLook(_Look v) {
    if (v == _Look.picture && _cover == null) {
      _pickImage();
      return;
    }
    setState(() {
      _look = v;
      _collage = v == _Look.collage;
      if (v != _Look.picture) {
        _pick = null;
        _removeCover = widget.playlist?.coverPath != null;
      } else {
        _removeCover = false;
      }
    });
  }

  void _done() {
    if (_name.text.trim().isEmpty) return;
    Navigator.pop<_EditorResult>(context, (
      name: _name.text.trim(),
      description: _desc.text.trim(),
      emoji: _mark == _Mark.emoji ? _emoji : '',
      icon: _mark == _Mark.icon ? _icon : null,
      collage: _look == _Look.picture ? _collage : _look == _Look.collage,
      palette: _palette,
      coverPick: _look == _Look.picture ? _pick : null,
      removeCover: _look != _Look.picture && widget.playlist?.coverPath != null,
    ));
  }

  Widget _cell({required bool selected, required VoidCallback onTap, required Widget child}) => InkWell(
    borderRadius: BorderRadius.circular(Radii.s),
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? AppColors.tint.withValues(alpha: 0.16) : AppColors.surface2,
        borderRadius: BorderRadius.circular(Radii.s),
        border: Border.all(color: selected ? AppColors.tint : Colors.transparent),
      ),
      child: child,
    ),
  );

  Widget _preview() {
    const side = 150.0;
    final colors = playlistPalettes[_palette % playlistPalettes.length];
    final cover = _cover;
    if (_look == _Look.picture && cover != null && File(cover).existsSync()) {
      return Image.file(File(cover), key: ValueKey(cover), width: side, height: side, fit: BoxFit.cover);
    }
    if (_look == _Look.collage && _arts.isNotEmpty) {
      return ArtCollage(key: const ValueKey('collage'), paths: _arts, side: side, fill: colors);
    }
    final Widget? mark = switch (_mark) {
      _Mark.emoji => Text(_emoji, style: const TextStyle(fontSize: side * 0.38, height: 1)),
      _Mark.icon => Icon(playlistIcons[_icon], size: side * 0.4, color: Colors.white),
      _Mark.none => null,
    };
    return GradientArt(key: ValueKey('$_palette$_mark$_emoji$_icon'), colors: colors, mark: mark, side: side);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.playlist != null;
    final colors = playlistPalettes[_palette % playlistPalettes.length];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(editing ? 'Edit playlist' : 'New playlist', style: context.text.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: Space.l),
        Center(
          child: GestureDetector(
            onTap: _pickImage,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.xl),
                    boxShadow: [BoxShadow(color: colors.last.withValues(alpha: 0.45), blurRadius: 30, offset: const Offset(0, 12))],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.xl),
                    child: AnimatedSwitcher(duration: const Duration(milliseconds: 220), child: _preview()),
                  ),
                ),
                Positioned(
                  right: -8,
                  bottom: -8,
                  child: Material(
                    color: AppColors.surface3,
                    shape: CircleBorder(side: BorderSide(color: AppColors.surface, width: 3)),
                    child: Padding(
                      padding: const EdgeInsets.all(9),
                      child: Icon(Icons.add_photo_alternate_outlined, size: 20, color: AppColors.text),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.l),
        Text('Cover', style: context.text.labelSmall),
        const SizedBox(height: Space.s),
        SegmentedButton<_Look>(
          showSelectedIcon: false,
          segments: [
            const ButtonSegment(value: _Look.picture, icon: Icon(Icons.image_outlined, size: 18), label: Text('Picture')),
            ButtonSegment(
              value: _Look.collage,
              enabled: _arts.isNotEmpty || !editing,
              icon: const Icon(Icons.grid_view_rounded, size: 18),
              label: const Text('Album art'),
            ),
            const ButtonSegment(value: _Look.colour, icon: Icon(Icons.palette_outlined, size: 18), label: Text('Colour')),
          ],
          selected: {_look},
          onSelectionChanged: (v) => _setLook(v.first),
        ),
        const SizedBox(height: Space.xs),
        Text(
          switch (_look) {
            _Look.picture => 'Your own picture. Tap the cover to change it.',
            _Look.collage => _arts.isEmpty
                ? 'Made from the songs\' album covers once you add some; until then, the colour below.'
                : 'Made from the album covers of the songs in it.',
            _Look.colour => 'A gradient with an emoji, an icon, or nothing.',
          },
          style: context.text.bodySmall,
        ),
        const SizedBox(height: Space.l),
        TextField(
          controller: _name,
          autofocus: !editing,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Name', hintText: 'Late night, Sermons, Road trip…'),
          onSubmitted: (_) => _done(),
        ),
        const SizedBox(height: Space.m),
        TextField(
          controller: _desc,
          maxLines: 2,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Description (optional)'),
        ),
        const SizedBox(height: Space.l),
        Text('Colour', style: context.text.labelSmall),
        const SizedBox(height: Space.s),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: playlistPalettes.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.s),
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => setState(() => _palette = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: playlistPalettes[i]),
                  border: Border.all(color: _palette == i ? AppColors.text : Colors.transparent, width: 2.5),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: Space.l),
        Text('Mark', style: context.text.labelSmall),
        const SizedBox(height: Space.s),
        SegmentedButton<_Mark>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: _Mark.emoji, icon: Icon(Icons.emoji_emotions_outlined, size: 18), label: Text('Emoji')),
            ButtonSegment(value: _Mark.icon, icon: Icon(Icons.category_outlined, size: 18), label: Text('Icon')),
            ButtonSegment(value: _Mark.none, icon: Icon(Icons.block_rounded, size: 18), label: Text('None')),
          ],
          selected: {_mark},
          onSelectionChanged: (v) => setState(() => _mark = v.first),
        ),
        const SizedBox(height: Space.m),
        if (_mark == _Mark.emoji) ...[
          TextField(
            controller: _custom,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Your own emoji',
              hintText: 'Type or paste any emoji',
              prefixIcon: Icon(Icons.edit_outlined, size: 18),
            ),
            onChanged: (v) {
              final first = v.trim().characters.take(1).toString();
              if (first.isNotEmpty) setState(() => _emoji = first);
            },
          ),
          const SizedBox(height: Space.m),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in _emojis)
                _cell(
                  selected: _emoji == e,
                  onTap: () => setState(() {
                    _emoji = e;
                    _custom.clear();
                  }),
                  child: Text(e, style: const TextStyle(fontSize: 20)),
                ),
            ],
          ),
        ] else if (_mark == _Mark.icon)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final MapEntry(:key, :value) in playlistIcons.entries)
                _cell(
                  selected: key == _icon,
                  onTap: () => setState(() => _icon = key),
                  child: Icon(value, size: 21, color: key == _icon ? AppColors.tint : AppColors.text2),
                ),
            ],
          )
        else
          Text('Just the colour, with no mark on it.', style: context.text.bodySmall),
        const SizedBox(height: Space.xl),
        FilledButton(onPressed: _name.text.trim().isEmpty ? null : _done, child: Text(editing ? 'Save' : 'Create playlist')),
      ],
    );
  }
}

// ---- add to a playlist ---------------------------------------------------------

/// Asks which playlist [tracks] go in (or makes a new one) and adds them.
/// Returns the playlist, or null if cancelled.
Future<Playlist?> showAddToPlaylist(BuildContext context, WidgetRef ref, List<PlaylistTrack> tracks) async {
  if (tracks.isEmpty) return null;
  final store = ref.read(playlistsProvider.notifier);
  await store.ready;
  if (!context.mounted) return null;
  final picked = await showAppSheet<String>(
    context,
    initialSize: 0.6,
    builder: (context, scroll) => _PickPlaylist(tracks: tracks, scroll: scroll),
  );
  if (picked == null || !context.mounted) return null;
  Playlist? target;
  if (picked == '+new') {
    target = await showPlaylistEditor(context, ref);
  } else {
    target = store.byId(picked);
  }
  if (target == null) return null;
  final added = await store.addTracks(target.id, tracks);
  if (context.mounted) {
    final skipped = tracks.length - added;
    showSnack(
      context,
      added == 0
          ? 'Already in ${target.name}'
          : 'Added ${added == 1 ? '“${tracks.first.title}”' : '$added tracks'} to ${target.name}${skipped > 0 ? ' · $skipped already there' : ''}',
      icon: Icons.playlist_add_check_rounded,
    );
  }
  return store.byId(target.id);
}

class _PickPlaylist extends ConsumerWidget {
  const _PickPlaylist({required this.tracks, required this.scroll});
  final List<PlaylistTrack> tracks;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lists = ref.watch(playlistsProvider).sorted;
    final one = tracks.length == 1 ? tracks.first : null;
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.xl),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.s, 0, Space.s, Space.m),
          child: Column(
            children: [
              Text('Add to playlist', style: context.text.titleLarge),
              const SizedBox(height: 2),
              Text(
                one != null ? one.title : '${tracks.length} tracks',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodySmall,
              ),
            ],
          ),
        ),
        ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.m)),
          leading: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m), border: Border.all(color: AppColors.line)),
            child: Icon(Icons.add_rounded, color: AppColors.text),
          ),
          title: const Text('New playlist', style: TextStyle(fontWeight: FontWeight.w600)),
          onTap: () => Navigator.pop(context, '+new'),
        ),
        for (final p in lists)
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.m)),
            leading: PlaylistCover(playlist: p, size: 52, radius: Radii.m),
            title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(p.summary, style: context.text.bodySmall),
            trailing: one != null && p.has(one)
                ? Icon(Icons.check_circle_rounded, color: AppColors.tint)
                : Icon(Icons.add_circle_outline_rounded, color: AppColors.text3),
            onTap: () => Navigator.pop(context, p.id),
          ),
      ],
    );
  }
}

/// A cover in flight between pages: the destination cover, scaled to the
/// flight's box (it never lays out at an in-between size).
Widget coverFlight(BuildContext flight, Animation<double> animation, HeroFlightDirection direction, BuildContext from, BuildContext to) {
  final hero = (direction == HeroFlightDirection.push ? to.widget : from.widget) as Hero;
  return FittedBox(fit: BoxFit.cover, child: SizedBox.square(dimension: 240, child: hero.child));
}
