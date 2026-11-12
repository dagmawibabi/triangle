import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../default_assistant.dart';
import 'automation_widgets.dart';

/// Settings → Default assistant: make Triangle the phone's assistant app,
/// so long-pressing home (or the assistant gesture) opens it.
class DefaultAssistantScreen extends ConsumerStatefulWidget {
  const DefaultAssistantScreen({super.key});

  @override
  ConsumerState<DefaultAssistantScreen> createState() => _DefaultAssistantScreenState();
}

class _DefaultAssistantScreenState extends ConsumerState<DefaultAssistantScreen> with WidgetsBindingObserver {
  bool? _isDefault;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from Android's settings: look again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final v = await DefaultAssistant.isDefault();
    if (mounted) setState(() => _isDefault = v);
  }

  @override
  Widget build(BuildContext context) {
    final opens = ref.watch(assistOpensProvider);
    final on = _isDefault == true;
    return Scaffold(
      appBar: AppBar(title: const Text('Default assistant')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.x4),
        children: [
          Container(
            padding: const EdgeInsets.all(Space.l),
            decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.l)),
            child: Row(
              children: [
                Icon(
                  !DefaultAssistant.supported ? Icons.phone_android_rounded : (on ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded),
                  color: on ? AppColors.success : AppColors.text3,
                  size: 28,
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        !DefaultAssistant.supported
                            ? 'Android only'
                            : _isDefault == null
                            ? 'Checking…'
                            : on
                            ? 'Triangle is your assistant'
                            : 'Another app is your assistant',
                        style: context.text.titleSmall,
                      ),
                      Text(
                        on
                            ? 'Long-press the home button, or swipe up from a bottom corner, to call Triangle up from anywhere.'
                            : 'Pick Triangle as the "Digital assistant app" in Android settings to call it up from anywhere.',
                        style: context.text.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.m),
          if (DefaultAssistant.supported)
            FilledButton.icon(
              onPressed: () async {
                if (!await DefaultAssistant.openSettings() && context.mounted) {
                  showSnack(context, 'Couldn\'t open Android settings', icon: Icons.error_outline_rounded);
                }
              },
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(on ? 'Change in Android settings' : 'Open Android settings'),
            ),
          const SizedBox(height: Space.s),
          if (DefaultAssistant.supported && !on)
            Text(
              'In the screen that opens: Default digital assistant app (or Assist & voice input) → Triangle. '
              'Android asks apps to send you there; it can\'t be switched from inside the app.',
              style: context.text.bodySmall,
            ),
          const SizedBox(height: Space.xl),
          Text('WHEN YOU CALL IT UP', style: context.text.labelSmall),
          const SizedBox(height: Space.s),
          automationCard(context, [
            RadioGroup<AssistOpens>(
              groupValue: opens,
              onChanged: (v) {
                if (v != null) ref.read(assistOpensProvider.notifier).set(v);
              },
              child: Column(
                children: [
                  for (final o in AssistOpens.values)
                    RadioListTile<AssistOpens>(
                      value: o,
                      secondary: lead(Icon(o == AssistOpens.voice ? Icons.graphic_eq_rounded : Icons.keyboard_alt_outlined)),
                      title: Text(o.label),
                      subtitle: Text(o.explanation, style: context.text.bodySmall),
                    ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: Space.m),
          Text('A headset\'s voice button always opens voice mode.', style: context.text.bodySmall),
        ],
      ),
    );
  }
}
