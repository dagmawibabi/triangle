import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../device/device.dart';
import '../../../telegram/data/telegram_tools.dart';
import '../../domain/chat_models.dart';
import '../../../../infrastructure/telegram/accounts.dart';
import '../../../telegram/data/account_tools.dart';

/// Tools whose sheet gets hands-on controls: what the assistant did, you can
/// change yourself (flip the flashlight, drag the volume, mute the chat).
const _deviceControls = {
  'flashlight',
  'keep_screen_on',
  'device_volume',
  'ringer_mode',
  'media_control',
  'vibrate',
  'open_app',
  'open_device_settings',
  'write_clipboard',
};
const _telegramControls = {'set_chat_notifications', 'archive_chat', 'pin_message'};

bool hasToolControls(ToolPart part) =>
    (part.status == ToolStatus.done || part.status == ToolStatus.error) &&
    ((_deviceControls.contains(part.name) && Device.supported) || _telegramControls.contains(part.name));

/// Controls for [part]'s tool. They run the same tool code the assistant
/// uses, as you: your tap is the approval.
class ToolControls extends ConsumerStatefulWidget {
  const ToolControls({super.key, required this.part, required this.result});
  final ToolPart part;
  final Map<String, dynamic>? result;

  @override
  ConsumerState<ToolControls> createState() => _ToolControlsState();
}

class _ToolControlsState extends ConsumerState<ToolControls> {
  late final Map<String, dynamic> _args = widget.part.args;
  late Map<String, dynamic> _state = {...?widget.result};
  bool _busy = false;
  bool? _pinned;

  @override
  void initState() {
    super.initState();
    // Volume is read fresh: it may have changed since the assistant set it.
    if (widget.part.name == 'device_volume') _run({}, quiet: true);
  }

  /// Runs the tool with [args] on top of the original call's; true when it worked.
  Future<bool> _run(Map<String, dynamic> args, {bool quiet = false, String? done}) async {
    setState(() => _busy = true);
    // A Telegram control acts in the account the call did.
    final account = accountOfCall(ref.read(accountsProvider), widget.part.name, _args);
    final out = await ref
        .read(account == null ? toolRunnerProvider : toolRunnerFamily(account))
        .run(widget.part.name, withoutAccount({..._args, ...args}));
    if (!mounted) return false;
    setState(() {
      _busy = false;
      if (out.json['error'] == null) _state = {..._state, ...out.json};
    });
    if (out.json['error'] case final error?) {
      showSnack(context, '$error', icon: Icons.error_outline_rounded);
    } else if (!quiet && done != null) {
      showSnack(context, done);
    }
    return out.json['error'] == null;
  }

  @override
  Widget build(BuildContext context) {
    final control = _control(context);
    return Container(
      margin: const EdgeInsets.only(top: Space.l),
      padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.xs),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(Radii.m),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: Space.s),
            child: Row(
              children: [
                Text('CONTROLS', style: context.text.labelSmall),
                const Spacer(),
                if (_busy) const SizedBox.square(dimension: 12, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
          ),
          control,
        ],
      ),
    );
  }

  Widget _switch(String title, bool value, void Function(bool) onChanged, {IconData? icon}) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    secondary: icon == null ? null : Icon(icon, color: value ? AppColors.accent : AppColors.text2),
    title: Text(title),
    value: value,
    onChanged: _busy ? null : onChanged,
  );

  Widget _button(IconData icon, String label, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.s),
    child: OutlinedButton.icon(onPressed: _busy ? null : onTap, icon: Icon(icon, size: 18), label: Text(label)),
  );

  Widget _control(BuildContext context) {
    bool flag(String k, {bool fallback = false}) =>
        _state[k] is bool ? _state[k] as bool : (_args[k] is bool ? _args[k] as bool : fallback);
    return switch (widget.part.name) {
      'flashlight' => _switch(
        'Flashlight',
        flag('on'),
        (v) => _run({'on': v}),
        icon: flag('on') ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
      ),
      'keep_screen_on' => _switch(
        'Keep the screen on',
        flag('on', fallback: true),
        (v) => _run({'on': v}),
        icon: Icons.light_mode_outlined,
      ),
      'device_volume' => _Volume(
        levels: _state['levels'] is Map ? Map<String, dynamic>.from(_state['levels'] as Map) : const {},
        busy: _busy,
        onSet: (stream, percent) => _run({'stream': stream, 'percent': percent, 'mute': false, 'unmute': false}),
      ),
      'ringer_mode' => Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.s),
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'normal', icon: Icon(Icons.notifications_active_outlined), label: Text('Ring')),
            ButtonSegment(value: 'vibrate', icon: Icon(Icons.vibration_rounded), label: Text('Vibrate')),
            ButtonSegment(value: 'silent', icon: Icon(Icons.notifications_off_outlined), label: Text('Silent')),
          ],
          selected: {'${_state['mode'] ?? _args['mode'] ?? 'normal'}'},
          onSelectionChanged: _busy ? null : (v) => _run({'mode': v.first}),
        ),
      ),
      'media_control' => Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.s),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final (action, icon, tip) in const [
              ('previous', Icons.skip_previous_rounded, 'Previous'),
              ('toggle', Icons.play_arrow_rounded, 'Play / pause'),
              ('next', Icons.skip_next_rounded, 'Next'),
              ('stop', Icons.stop_rounded, 'Stop'),
            ])
              IconButton.filledTonal(
                tooltip: tip,
                onPressed: _busy ? null : () => _run({'action': action}),
                icon: Icon(icon),
              ),
          ],
        ),
      ),
      'vibrate' => _button(Icons.vibration_rounded, 'Vibrate again', () => _run(const {}, done: 'Vibrated')),
      'open_app' => _button(Icons.open_in_new_rounded, 'Open ${_args['name'] ?? 'the app'} again', () => _run(const {})),
      'open_device_settings' => _button(Icons.settings_outlined, 'Open these settings again', () => _run(const {})),
      'write_clipboard' => _button(Icons.copy_rounded, 'Copy to the clipboard again', () => _run(const {}, done: 'Copied')),
      'set_chat_notifications' => _switch(
        'Muted',
        flag('muted'),
        (v) => _run({'muted': v}),
        icon: Icons.notifications_off_outlined,
      ),
      'archive_chat' => _switch(
        'Archived',
        flag('archived', fallback: true),
        (v) => _run({'archived': v}),
        icon: Icons.archive_outlined,
      ),
      'pin_message' => _switch(
        'Pinned',
        _pinned ?? _args['unpin'] != true,
        (v) async {
          if (await _run({'unpin': !v}) && mounted) setState(() => _pinned = v);
        },
        icon: Icons.push_pin_outlined,
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

/// One slider per sound stream; the change is made when you let go.
class _Volume extends StatefulWidget {
  const _Volume({required this.levels, required this.busy, required this.onSet});
  final Map<String, dynamic> levels;
  final bool busy;
  final void Function(String stream, int percent) onSet;

  @override
  State<_Volume> createState() => _VolumeState();
}

class _VolumeState extends State<_Volume> {
  final _drag = <String, double>{};

  static const _icons = {
    'media': Icons.music_note_rounded,
    'ring': Icons.ring_volume_rounded,
    'alarm': Icons.alarm_rounded,
    'notification': Icons.notifications_none_rounded,
    'call': Icons.call_rounded,
  };

  @override
  Widget build(BuildContext context) {
    if (widget.levels.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: Space.m),
        child: LinearProgressIndicator(),
      );
    }
    return Column(
      children: [
        for (final e in widget.levels.entries)
          Row(
            children: [
              Icon(_icons[e.key] ?? Icons.volume_up_rounded, size: 20, color: AppColors.text2),
              Expanded(
                child: Slider(
                  value: (_drag[e.key] ?? (e.value as num).toDouble()).clamp(0, 100),
                  max: 100,
                  divisions: 20,
                  label: '${(_drag[e.key] ?? (e.value as num)).round()}%',
                  onChanged: widget.busy ? null : (v) => setState(() => _drag[e.key] = v),
                  onChangeEnd: (v) {
                    _drag.remove(e.key);
                    widget.onSet(e.key, v.round());
                  },
                ),
              ),
              SizedBox(
                width: 40,
                child: Text('${(_drag[e.key] ?? (e.value as num)).round()}%', style: context.text.bodySmall, textAlign: TextAlign.end),
              ),
            ],
          ),
      ],
    );
  }
}
