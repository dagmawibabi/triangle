import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../chat/data/chat_controller.dart';
import '../../telegram/data/telegram_tools.dart';
import '../data/settings.dart';
import 'tools_screen.dart' show FeatureTools, ToolSwitches;

/// A feature page's Tools tab: what its tools let the assistant do, one
/// switch for all of them, questions to try (sent straight to the chat),
/// and each tool with its own switch and details.
class FeatureToolsTab extends ConsumerWidget {
  const FeatureToolsTab({super.key, required this.category, required this.intro, this.examples = const [], this.setup = const []});
  final ToolCategory category;
  final String intro;

  /// Keys and settings these tools use, under the intro.
  final List<Widget> setup;

  /// Questions that use these tools, for "Try it".
  final List<String> examples;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final tools = [for (final t in telegramTools) if (t.category == category) t];
    final on = tools.where((t) => s.toolChosen(t.name, destructive: t.destructive)).length;
    final all = on == tools.length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.x4),
      children: [
        Container(
          padding: const EdgeInsets.all(Space.l),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.xl), border: Border.all(color: AppColors.line)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
                    child: Icon(Icons.handyman_outlined, size: 19, color: AppColors.accent),
                  ),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Assistant tools', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        Text('$on of ${tools.length} on', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
                      ],
                    ),
                  ),
                  Switch(value: all, onChanged: (v) => ToolSwitches.of(ref).setAll(tools, v)),
                ],
              ),
              const SizedBox(height: Space.m),
              Text(intro, style: context.text.bodySmall?.copyWith(color: AppColors.text2, height: 1.45)),
              if (s.readOnlyMode && tools.any((t) => t.modifiesData)) ...[
                const SizedBox(height: Space.s),
                Text('Read-only mode is on, so tools that change things stay off whatever their switch says.', style: context.text.bodySmall?.copyWith(color: AppColors.warning)),
              ],
            ],
          ),
        ),
        ...setup,
        if (examples.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xs, Space.xl, 0, Space.s),
            child: Text('TRY IT', style: context.text.labelSmall?.copyWith(color: AppColors.text3, letterSpacing: 0.9, fontWeight: FontWeight.w600)),
          ),
          for (final q in examples)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s),
              child: Material(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(Radii.l),
                child: InkWell(
                  borderRadius: BorderRadius.circular(Radii.l),
                  onTap: () {
                    // Back to the chat, with the question asked.
                    Navigator.of(context).popUntil((r) => r.isFirst);
                    ref.read(chatControllerProvider.notifier).send(q);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
                    child: Row(
                      children: [
                        Icon(Icons.auto_awesome_outlined, size: 18, color: AppColors.text2),
                        const SizedBox(width: Space.m),
                        Expanded(child: Text(q, style: context.text.bodyMedium)),
                        Icon(Icons.arrow_forward_rounded, size: 18, color: AppColors.text3),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.xs, Space.xl, 0, Space.s),
          child: Text('TOOLS', style: context.text.labelSmall?.copyWith(color: AppColors.text3, letterSpacing: 0.9, fontWeight: FontWeight.w600)),
        ),
        FeatureTools(category: category),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.xs, Space.m, Space.xs, 0),
          child: Text('Tap a tool to see what it takes and returns. Turned off, the assistant can\'t use it.', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
        ),
      ],
    );
  }
}
