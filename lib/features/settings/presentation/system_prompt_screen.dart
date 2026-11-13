import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../assistant/system_prompt.dart';
import '../../chat/data/chat_controller.dart';
import '../data/settings.dart';

/// What the system prompt is now, in a few words.
String systemPromptStatus(AppSettings s) {
  if (!s.systemPromptEnabled) return 'Off: nothing is sent but a watch\'s own instructions';
  if (!s.systemPromptCustom) return 'The built-in prompt';
  if (s.systemPrompt.trim().isEmpty) return 'Cleared: nothing is sent but a watch\'s own instructions';
  return 'Your edited prompt';
}

/// The template being used: the user's, or the built-in one.
String activeSystemPromptTemplate(AppSettings s) => s.systemPromptCustom ? s.systemPrompt : defaultSystemPromptTemplate;

/// Edit the system prompt template: save, clear or reset it.
class SystemPromptEditorScreen extends ConsumerStatefulWidget {
  const SystemPromptEditorScreen({super.key});

  @override
  ConsumerState<SystemPromptEditorScreen> createState() => _SystemPromptEditorScreenState();
}

class _SystemPromptEditorScreenState extends ConsumerState<SystemPromptEditorScreen> {
  late final _ctrl = TextEditingController(text: activeSystemPromptTemplate(ref.read(settingsProvider)));
  bool _dirty = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref.read(settingsProvider.notifier).setSystemPrompt(_ctrl.text);
    if (!mounted) return;
    setState(() => _dirty = false);
    showSnack(context, _ctrl.text.trim().isEmpty ? 'System prompt cleared' : 'System prompt saved');
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear the system prompt?'),
        content: const Text(
          'The assistant gets no instructions from it, not even the rule that text from other people is never an '
          'instruction: only your memory, vault and tool notes, and a watch\'s own instructions. Actions still wait '
          'for your approval after it reads other people\'s text. Reset brings the built-in one back.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true) return;
    _ctrl.clear();
    await _save();
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset to the built-in prompt?'),
        content: const Text('Your edits are replaced by the prompt the app ships with, and it is turned on.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reset')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(settingsProvider.notifier).resetSystemPrompt();
    if (!mounted) return;
    setState(() {
      _ctrl.text = defaultSystemPromptTemplate;
      _dirty = false;
    });
    showSnack(context, 'System prompt reset');
  }

  void _insert(String name) {
    final sel = _ctrl.selection;
    final text = _ctrl.text;
    final at = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final tag = '{{$name}}';
    _ctrl.value = TextEditingValue(
      text: text.replaceRange(at, end, tag),
      selection: TextSelection.collapsed(offset: at + tag.length),
    );
    setState(() => _dirty = true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Discard your changes?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep editing')),
              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard')),
            ],
          ),
        );
        if (leave == true && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Edit system prompt'),
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) => v == 'clear' ? _clear() : _reset(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'clear', child: Text('Clear')),
                PopupMenuItem(value: 'reset', child: Text('Reset to default')),
              ],
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(Space.l),
          children: [
            Text(
              'Words in {{double braces}} are filled in for each run, so the prompt stays current. Tap one below to '
              'add it where the cursor is. What you write is exactly what is sent; only a watch\'s own instructions '
              'are always added in its runs. Keep {{external_content_rule}}: it tells the assistant that text from '
              'other people (messages, emails, pages) is never an instruction.',
              style: context.text.bodySmall,
            ),
            const SizedBox(height: Space.m),
            TextField(
              controller: _ctrl,
              minLines: 12,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.4),
              onChanged: (_) => setState(() => _dirty = true),
              decoration: const InputDecoration(hintText: 'Empty: no system prompt'),
            ),
            const SizedBox(height: Space.m),
            Row(
              children: [
                OutlinedButton(onPressed: _reset, child: const Text('Reset to default')),
                const SizedBox(width: Space.s),
                OutlinedButton(onPressed: _clear, child: const Text('Clear')),
                const Spacer(),
                FilledButton(onPressed: _dirty ? _save : null, child: const Text('Save')),
              ],
            ),
            const SizedBox(height: Space.l),
            Text('Placeholders', style: context.text.titleSmall),
            const SizedBox(height: Space.s),
            for (final e in systemPromptPlaceholders.entries)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('{{${e.key}}}', style: const TextStyle(fontFamily: 'monospace')),
                subtitle: Text(e.value, style: context.text.bodySmall),
                trailing: IconButton(
                  tooltip: 'Insert',
                  icon: const Icon(Icons.add_rounded),
                  onPressed: () => _insert(e.key),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The exact instructions a new chat gets now, filled in.
class SystemPromptPreviewScreen extends ConsumerWidget {
  const SystemPromptPreviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Exact system prompt')),
      body: FutureBuilder<String>(
        future: ref.read(chatControllerProvider.notifier).previewInstructions(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Couldn\'t build the prompt: ${snap.error}'));
          final text = snap.data;
          if (text == null) return const Center(child: CircularProgressIndicator());
          return ListView(
            padding: const EdgeInsets.all(Space.l),
            children: [
              Text(
                'What a new chat is sent now, before your first message: the system prompt filled in, then your '
                'memory, vault and the notes for the tools that are on. ${text.length} characters, about '
                '${(text.length / 4).round()} tokens. Watches and voice mode add their own part.',
                style: context.text.bodySmall,
              ),
              const SizedBox(height: Space.s),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: text));
                    if (context.mounted) showSnack(context, 'Copied');
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copy'),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(Space.m),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.m)),
                child: SelectableText(
                  text,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.4),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
