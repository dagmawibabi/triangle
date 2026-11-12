import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/widgets/app_sheet.dart';
import 'spend_limits.dart';
import 'usage.dart';

/// Daily, monthly and per-watch caps on AI spending.
class SpendLimitsScreen extends ConsumerWidget {
  const SpendLimitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final limits = ref.watch(spendLimitsProvider);
    final events = ref.watch(usageProvider);
    final ctl = ref.read(spendLimitsProvider.notifier);
    final now = DateTime.now();
    final today = spentSince(events, DateTime(now.year, now.month, now.day));
    final month = spentSince(events, DateTime(now.year, now.month));

    return Scaffold(
      appBar: AppBar(title: const Text('Spending limits')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.x4),
        children: [
          Text(
            'Caps on what the assistant spends on AI models, in US dollars, from the costs your providers report '
            '(or estimates from their prices). A run stops when it reaches the cap; new runs wait until it resets. '
            'Leave a cap empty for none.',
            style: context.text.bodySmall?.copyWith(height: 1.4),
          ),
          const SizedBox(height: Space.l),
          Container(
            decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.l)),
            child: Column(
              children: [
                _LimitTile(
                  icon: Icons.today_outlined,
                  title: 'Per day',
                  spent: today,
                  limit: limits.daily,
                  resets: 'Resets at midnight',
                  onSet: ctl.setDaily,
                ),
                const Divider(height: 1, indent: Space.l, endIndent: Space.l),
                _LimitTile(
                  icon: Icons.calendar_month_outlined,
                  title: 'Per month',
                  spent: month,
                  limit: limits.monthly,
                  resets: 'Resets on the 1st',
                  onSet: ctl.setMonthly,
                ),
                const Divider(height: 1, indent: Space.l, endIndent: Space.l),
                _LimitTile(
                  icon: Icons.visibility_outlined,
                  title: 'Each watch, per day',
                  spent: null,
                  limit: limits.perWatchDaily,
                  resets: 'Watches and scheduled jobs: stops one that runs away without touching the others',
                  onSet: ctl.setPerWatchDaily,
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.l),
          Text(
            'Image, video and audio generation count toward the totals, but only chat runs are stopped by them.',
            style: context.text.bodySmall?.copyWith(color: AppColors.text3),
          ),
        ],
      ),
    );
  }
}

class _LimitTile extends StatelessWidget {
  const _LimitTile({
    required this.icon,
    required this.title,
    required this.spent,
    required this.limit,
    required this.resets,
    required this.onSet,
  });
  final IconData icon;
  final String title;
  final double? spent;
  final double? limit;
  final String resets;
  final Future<void> Function(double?) onSet;

  @override
  Widget build(BuildContext context) {
    final cap = limit;
    final used = spent;
    final over = cap != null && used != null && used >= cap;
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.l),
      onTap: () => showFormSheet<void>(
        context,
        builder: (_) => _LimitSheet(title: title, limit: cap, spent: used, resets: resets, onSet: onSet),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.m, Space.m),
        child: Row(
          // Icons sit in the middle of the row, however tall its text is.
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ...leadRow(Icon(icon, color: AppColors.text2), Space.l),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.text.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    [
                      cap == null ? 'No limit' : 'Limit ${formatUsd(cap)}',
                      if (used != null) '${formatUsd(used)} spent',
                    ].join(' · '),
                    style: context.text.bodySmall?.copyWith(color: over ? AppColors.danger : null),
                  ),
                  if (cap != null && used != null) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: (used / cap).clamp(0, 1).toDouble(),
                        minHeight: 4,
                        color: over ? AppColors.danger : AppColors.accent,
                        backgroundColor: AppColors.surface3,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(resets, style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
                ],
              ),
            ),
            const SizedBox(width: Space.s),
            Icon(Icons.chevron_right_rounded, color: AppColors.text3),
          ],
        ),
      ),
    );
  }
}

/// Sets or changes one limit: a few common amounts, or any amount.
class _LimitSheet extends StatefulWidget {
  const _LimitSheet({required this.title, required this.limit, required this.spent, required this.resets, required this.onSet});
  final String title;
  final double? limit;
  final double? spent;
  final String resets;
  final Future<void> Function(double?) onSet;

  @override
  State<_LimitSheet> createState() => _LimitSheetState();
}

class _LimitSheetState extends State<_LimitSheet> {
  late final _text = TextEditingController(text: widget.limit == null ? '' : _plain(widget.limit!));

  static String _plain(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save(double? v) async {
    await widget.onSet(v == null || v <= 0 ? null : v);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final typed = double.tryParse(_text.text.trim());
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: context.text.titleMedium),
        const SizedBox(height: 2),
        Text(
          [if (widget.spent != null) '${formatUsd(widget.spent!)} spent so far', widget.resets].join(' · '),
          style: context.text.bodySmall,
        ),
        const SizedBox(height: Space.l),
        TextField(
          controller: _text,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          decoration: const InputDecoration(labelText: 'Limit', prefixText: '\$ ', hintText: 'No limit'),
          onSubmitted: (_) => _save(typed),
        ),
        const SizedBox(height: Space.m),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final v in const [0.5, 1.0, 2.0, 5.0, 10.0, 25.0, 50.0])
              ChoiceChip(
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                label: Text(formatUsd(v)),
                selected: typed == v,
                onSelected: (_) => setState(() => _text.text = _plain(v)),
              ),
          ],
        ),
        const SizedBox(height: Space.l),
        Row(
          children: [
            if (widget.limit != null)
              TextButton(onPressed: () => _save(null), child: const Text('Remove limit')),
            const Spacer(),
            FilledButton(onPressed: () => _save(typed), child: const Text('Save')),
          ],
        ),
      ],
    );
  }
}
