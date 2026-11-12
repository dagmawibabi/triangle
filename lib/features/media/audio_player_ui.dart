import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/widgets/glass.dart';
import '../telegram/data/file_loader.dart';
import 'audio_center.dart';

/// The bar that floats under a header while something plays.
class AudioMiniBar extends ConsumerWidget {
  const AudioMiniBar({super.key, this.margin = const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, 0)});
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(audioCenterProvider);
    final t = a.current;
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      alignment: Alignment.topCenter,
      child: t == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: margin,
              child: Glass(
                radius: Radii.l,
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: () => showAudioPlayer(context),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
                          child: Row(
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: a.loading
                                    ? const SizedBox.square(
                                        dimension: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : Icon(a.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: AppColors.accent),
                                onPressed: a.toggle,
                              ),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(text: t.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                                      if (t.subtitle.isNotEmpty)
                                        TextSpan(text: ' – ${t.subtitle}', style: TextStyle(color: AppColors.text2)),
                                    ],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 13.5, color: AppColors.text),
                                ),
                              ),
                              if (a.speed != 1)
                                Text('${a.speed}×', style: TextStyle(fontSize: 12, color: AppColors.accent)),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: Icon(Icons.close_rounded, size: 20, color: AppColors.text2),
                                onPressed: a.stop,
                              ),
                            ],
                          ),
                        ),
                        LinearProgressIndicator(
                          value: t.live && a.playing
                              ? null
                              : t.live
                              ? 0
                              : a.duration.inMilliseconds == 0
                              ? 0
                              : (a.position.inMilliseconds / a.duration.inMilliseconds).clamp(0, 1).toDouble(),
                          minHeight: 2,
                          backgroundColor: Colors.transparent,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

Future<void> showAudioPlayer(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => const _AudioSheet(),
);

class _AudioSheet extends ConsumerWidget {
  const _AudioSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(audioCenterProvider);
    final t = a.current;
    if (t == null) {
      return const SizedBox(height: 160, child: Center(child: Text('Nothing playing')));
    }
    final total = a.duration.inMilliseconds > 0 ? a.duration : Duration(seconds: t.seconds);
    final pos = a.position > total ? total : a.position;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.xl),
              child: SizedBox.square(
                dimension: 200,
                child: t.cover != null
                    ? Image.memory(base64Decode(t.cover!.data), fit: BoxFit.cover)
                    : t.artUrl != null
                    ? Image.network(t.artUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF151A26)))
                    : Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF2A3550), Color(0xFF151A26)],
                          ),
                        ),
                        child: Icon(t.live ? Icons.radio_rounded : (t.voice ? Icons.mic_rounded : Icons.music_note_rounded), size: 72, color: AppColors.accent),
                      ),
              ),
            ),
            const SizedBox(height: Space.xl),
            Text(t.title, style: context.text.titleLarge, textAlign: TextAlign.center, maxLines: 2),
            const SizedBox(height: 2),
            Text(t.subtitle, style: context.text.bodyMedium?.copyWith(color: AppColors.text2), textAlign: TextAlign.center),
            const SizedBox(height: Space.l),
            if (t.live)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(99)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 8, color: AppColors.danger),
                    const SizedBox(width: 6),
                    Text('LIVE · ${formatDuration(pos.inSeconds)}', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700, fontSize: 12)),
                  ],
                ),
              )
            else ...[
            Slider(
              value: pos.inMilliseconds.toDouble().clamp(0, total.inMilliseconds.toDouble().clamp(1, double.infinity)),
              max: total.inMilliseconds.toDouble().clamp(1, double.infinity),
              onChanged: (v) => a.seek(Duration(milliseconds: v.round())),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.l),
              child: Row(
                children: [
                  Text(formatDuration(pos.inSeconds), style: context.text.labelSmall),
                  const Spacer(),
                  Text(formatDuration(total.inSeconds), style: context.text.labelSmall),
                ],
              ),
            ),
            ],
            const SizedBox(height: Space.s),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(iconSize: 30, icon: const Icon(Icons.skip_previous_rounded), onPressed: a.previous),
                IconButton(iconSize: 28, icon: const Icon(Icons.replay_10_rounded), onPressed: t.live ? null : () => a.skip(-10)),
                const SizedBox(width: Space.s),
                Material(
                  color: AppColors.text,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: a.toggle,
                    child: SizedBox.square(
                      dimension: 66,
                      child: a.loading
                          ? Padding(
                              padding: EdgeInsets.all(22),
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.bg),
                            )
                          : Icon(a.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 36, color: AppColors.bg),
                    ),
                  ),
                ),
                const SizedBox(width: Space.s),
                IconButton(iconSize: 28, icon: const Icon(Icons.forward_10_rounded), onPressed: t.live ? null : () => a.skip(10)),
                IconButton(
                  iconSize: 30,
                  icon: const Icon(Icons.skip_next_rounded),
                  onPressed: a.hasNext ? a.next : null,
                ),
              ],
            ),
            const SizedBox(height: Space.l),
            if (!t.live)
            Wrap(
              spacing: 6,
              children: [
                for (final v in const [0.75, 1.0, 1.25, 1.5, 2.0])
                  ChoiceChip(label: Text('$v×'), selected: a.speed == v, onSelected: (_) => a.setSpeed(v)),
              ],
            ),
            if (a.queue.length > 1) ...[
              const SizedBox(height: Space.s),
              Text(
                '${a.queue.indexWhere((x) => x.key == t.key) + 1} of ${a.queue.length}${t.url != null ? '' : ' in this chat'}',
                style: context.text.labelSmall,
              ),
            ],
            if (a.error != null) ...[
              const SizedBox(height: Space.s),
              Text(a.error!, style: context.text.bodySmall?.copyWith(color: AppColors.danger)),
            ],
          ],
        ),
      ),
    );
  }
}
