import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../settings/data/settings.dart';
import 'component_cards.dart';
import 'components.dart';

/// Settings → Components: whether the assistant may draw components, which
/// ones, and how they look, with a live preview of each.
class ComponentsScreen extends ConsumerWidget {
  const ComponentsScreen({super.key});

  static const _tool = 'show_component';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(componentPrefsProvider);
    final store = ref.read(componentPrefsProvider.notifier);
    final settings = ref.watch(settingsProvider);
    final on = settings.toolChosen(_tool);
    final count = ComponentKind.values.where(prefs.isOn).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Components')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.x4),
        children: [
          _card(context, [
            SwitchListTile(
              secondary: const Icon(Icons.widgets_outlined),
              title: const Text('Let the assistant use components'),
              subtitle: Text(
                on
                    ? '$count of ${ComponentKind.values.length} on. It draws one when a chart, table or tiles say it better than text.'
                    : 'Off: answers stay text and markdown tables.',
                style: context.text.bodySmall,
              ),
              value: on,
              onChanged: (v) => ref.read(settingsProvider.notifier).setToolEnabled(_tool, v),
            ),
          ]),
          _label(context, 'Look'),
          _card(context, [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Colours', style: context.text.titleSmall),
                  const SizedBox(height: Space.s),
                  Wrap(
                    spacing: Space.s,
                    runSpacing: Space.s,
                    children: [
                      for (final p in ComponentPalette.values)
                        _PaletteChip(palette: p, selected: prefs.palette == p, onTap: () => store.setPalette(p)),
                    ],
                  ),
                ],
              ),
            ),
            SwitchListTile(
              title: const Text('Smooth lines'),
              subtitle: Text('Line and area charts curve between points', style: context.text.bodySmall),
              value: prefs.curved,
              onChanged: store.setCurved,
            ),
            SwitchListTile(
              title: const Text('Show values'),
              subtitle: Text('Bars and the latest point carry their number', style: context.text.bodySmall),
              value: prefs.showValues,
              onChanged: store.setShowValues,
            ),
          ]),
          _label(context, 'Components'),
          Text(
            'Turn off any the assistant shouldn\'t use. Previews show sample data in your colours; tap a chart to read it.',
            style: context.text.bodySmall,
          ),
          const SizedBox(height: Space.m),
          for (final k in ComponentKind.values) _ComponentTile(kind: k, enabled: prefs.isOn(k), masterOn: on, onChanged: (v) => store.setEnabled(k, v)),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: Space.xl, bottom: Space.s, left: 4),
    child: Text(text.toUpperCase(), style: context.text.labelSmall?.copyWith(letterSpacing: 0.8)),
  );

  Widget _card(BuildContext context, List<Widget> children) => Container(
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: AppColors.line)),
    clipBehavior: Clip.antiAlias,
    child: Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, c) in children.indexed) ...[if (i > 0) Divider(height: 1, indent: Space.l, color: AppColors.line), c],
        ],
      ),
    ),
  );
}

class _PaletteChip extends StatelessWidget {
  const _PaletteChip({required this.palette, required this.selected, required this.onTap});
  final ComponentPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = palette.colors(AppColors.tint).take(5).toList();
    return Material(
      color: selected ? AppColors.tint.withValues(alpha: 0.12) : AppColors.surface2,
      borderRadius: BorderRadius.circular(Radii.m),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.m),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.m),
            border: Border.all(color: selected ? AppColors.tint : Colors.transparent, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final c in colors)
                Container(width: 12, height: 12, margin: const EdgeInsets.only(right: 3), decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text(palette.label, style: context.text.labelMedium?.copyWith(fontWeight: selected ? FontWeight.w700 : null)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A component: what it's for, its switch, and a preview that opens.
class _ComponentTile extends StatefulWidget {
  const _ComponentTile({required this.kind, required this.enabled, required this.masterOn, required this.onChanged});
  final ComponentKind kind;
  final bool enabled;
  final bool masterOn;
  final ValueChanged<bool> onChanged;

  @override
  State<_ComponentTile> createState() => _ComponentTileState();
}

class _ComponentTileState extends State<_ComponentTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final k = widget.kind;
    final active = widget.enabled && widget.masterOn;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: Container(
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: AppColors.line)),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: () => setState(() => _open = !_open),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.s, Space.m),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: (active ? AppColors.tint : AppColors.text3).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(Radii.m),
                        ),
                        child: Icon(k.icon, size: 20, color: active ? AppColors.tint : AppColors.text3),
                      ),
                      const SizedBox(width: Space.m),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(k.label, style: context.text.titleSmall),
                            Text(k.description, style: context.text.bodySmall),
                          ],
                        ),
                      ),
                      Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppColors.text3),
                      Switch(value: widget.enabled, onChanged: widget.onChanged),
                    ],
                  ),
                ),
              ),
              if (_open)
                Container(
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
                  child: Opacity(
                    opacity: active ? 1 : 0.5,
                    child: ComponentView(data: componentSamples[k]!, framed: false),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
