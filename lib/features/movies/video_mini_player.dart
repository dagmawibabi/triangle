import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../app/theme.dart';
import '../sections/section_kit.dart';
import '../telegram/data/file_loader.dart';
import '../telegram/presentation/link_opener.dart' show appNavigatorKey;
import 'movies_screen.dart' show WatchScreen, moviesColor;
import 'pip.dart';
import 'video_session.dart';

/// The video that keeps playing after its watch page closes, floating over
/// every screen: tap or swipe up to open it again, swipe it sideways to
/// close it, drag it up or down out of the way.
class VideoMiniPlayerHost extends ConsumerStatefulWidget {
  const VideoMiniPlayerHost({super.key});

  @override
  ConsumerState<VideoMiniPlayerHost> createState() => _VideoMiniPlayerHostState();
}

class _VideoMiniPlayerHostState extends ConsumerState<VideoMiniPlayerHost> {
  /// Distance from the bottom of the safe area.
  double _lift = 12;
  double _dx = 0;
  bool _dragging = false;

  void _expand() {
    final v = ref.read(videoSessionProvider).video;
    if (v == null) return;
    appNavigatorKey.currentState?.push(MaterialPageRoute<void>(builder: (_) => WatchScreen(videoKey: v.key, video: v)));
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: Pip.inPip,
    builder: (context, pip, _) {
      final s = ref.watch(videoSessionProvider);
      final c = s.controller;
      // In the picture-in-picture window: only the video, edge to edge.
      if (pip && c != null && c.value.isInitialized) {
        return Positioned.fill(
          child: ColoredBox(
            color: Colors.black,
            child: Center(child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c))),
          ),
        );
      }
      return _mini(context, s);
    },
  );

  Widget _mini(BuildContext context, VideoSessionState s) {
    final mq = MediaQuery.of(context);
    final maxLift = (mq.size.height - mq.padding.top - mq.padding.bottom - 120).clamp(12.0, double.infinity);
    final lift = _lift.clamp(12.0, maxLift);
    final width = mq.size.width;
    return AnimatedPositioned(
      duration: _dragging ? Duration.zero : const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      left: Space.s + _dx,
      right: Space.s - _dx,
      bottom: s.showMini ? mq.padding.bottom + mq.viewInsets.bottom + lift : -160,
      child: IgnorePointer(
        ignoring: !s.showMini,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: s.showMini ? (1 - (_dx.abs() / (width * 0.6))).clamp(0.0, 1.0) : 0,
          child: GestureDetector(
            onTap: _expand,
            onVerticalDragStart: (_) => setState(() => _dragging = true),
            onVerticalDragUpdate: (d) => setState(() => _lift = (_lift - d.delta.dy).clamp(12.0, maxLift)),
            onVerticalDragEnd: (d) {
              setState(() => _dragging = false);
              // A quick flick up opens it.
              if (d.velocity.pixelsPerSecond.dy < -1400) _expand();
            },
            onHorizontalDragStart: (_) => setState(() => _dragging = true),
            onHorizontalDragUpdate: (d) => setState(() => _dx += d.delta.dx),
            onHorizontalDragEnd: (d) {
              final gone = _dx.abs() > width * 0.3 || d.velocity.pixelsPerSecond.dx.abs() > 900;
              setState(() {
                _dragging = false;
                _dx = 0;
              });
              if (gone) ref.read(videoSessionProvider.notifier).stop();
            },
            child: s.video == null ? const SizedBox(height: 72) : _MiniCard(state: s),
          ),
        ),
      ),
    );
  }
}

class _MiniCard extends ConsumerWidget {
  const _MiniCard({required this.state});
  final VideoSessionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = state.video!;
    final c = state.controller;
    final session = ref.read(videoSessionProvider.notifier);
    return Material(
      color: AppColors.surface,
      elevation: 14,
      shadowColor: Colors.black,
      borderRadius: BorderRadius.circular(Radii.l),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.l),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 68,
              child: Row(
                children: [
                  SizedBox(
                    width: 121,
                    child: ColoredBox(
                      color: Colors.black,
                      child: c != null && c.value.isInitialized
                          ? Center(child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)))
                          : Stack(
                              fit: StackFit.expand,
                              children: [
                                TgPicture(file: v.thumb, mini: v.mini, account: v.account, cacheWidth: 300, placeholder: const SizedBox()),
                                const ColoredBox(color: Colors.black45),
                                Center(
                                  child: state.paused
                                      ? const Icon(Icons.pause_circle_outline_rounded, color: Colors.white)
                                      : (v.file == null
                                            ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                            : ValueListenableBuilder<double>(
                                                valueListenable: ref.read(fileLoaderFamily(v.account)).progress(v.file!),
                                                builder: (_, p, _) => SizedBox.square(dimension: 20, child: CircularProgressIndicator(value: p > 0 ? p : null, strokeWidth: 2, color: Colors.white)),
                                              )),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(v.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.text)),
                        const SizedBox(height: 2),
                        Text(
                          state.paused ? 'Download paused' : (c == null ? 'Loading…' : v.channel),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall?.copyWith(color: AppColors.text3),
                        ),
                      ],
                    ),
                  ),
                  if (c != null)
                    ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: c,
                      builder: (_, value, _) => IconButton(
                        icon: Icon(value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 30, color: AppColors.text),
                        onPressed: session.toggle,
                      ),
                    )
                  else if (state.paused)
                    IconButton(icon: Icon(Icons.play_arrow_rounded, size: 30, color: AppColors.text), onPressed: session.resumeDownload),
                  IconButton(icon: Icon(Icons.close_rounded, color: AppColors.text2), onPressed: session.stop),
                  const SizedBox(width: 2),
                ],
              ),
            ),
            if (c != null)
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: c,
                builder: (_, value, _) {
                  final total = value.duration.inMilliseconds;
                  final f = total <= 0 ? 0.0 : (value.position.inMilliseconds / total).clamp(0.0, 1.0);
                  return LinearProgressIndicator(value: f, minHeight: 2.5, color: moviesColor, backgroundColor: AppColors.line);
                },
              )
            else
              SizedBox(height: 2.5, child: ColoredBox(color: AppColors.line)),
          ],
        ),
      ),
    );
  }
}
