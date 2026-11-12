import 'package:flutter/material.dart';

import '../../../app/theme.dart';

/// The band over a search panel's list: "Recent" and a Clear All.
class RecentHeader extends StatelessWidget {
  const RecentHeader({super.key, this.title = 'Recent', this.onClear});
  final String title;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => Container(
    color: AppColors.surface2,
    padding: const EdgeInsets.fromLTRB(Space.l, 2, Space.xs, 2),
    child: Row(
      children: [
        Expanded(child: Text(title, style: context.text.titleSmall?.copyWith(color: AppColors.text2))),
        if (onClear != null)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.text2),
            onPressed: onClear,
            child: const Text('Clear All'),
          ),
      ],
    ),
  );
}

/// Recent search terms as one row of chips: tap to search again, × to forget.
class RecentTermChips extends StatelessWidget {
  const RecentTermChips({super.key, required this.terms, required this.onPick, required this.onRemove});
  final List<String> terms;
  final ValueChanged<String> onPick;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 6),
      itemCount: terms.length,
      separatorBuilder: (_, _) => const SizedBox(width: Space.s),
      itemBuilder: (_, i) => InputChip(
        avatar: Icon(Icons.history_rounded, size: 16, color: AppColors.text3),
        label: Text(terms[i]),
        visualDensity: VisualDensity.compact,
        onPressed: () => onPick(terms[i]),
        onDeleted: () => onRemove(terms[i]),
        deleteIcon: const Icon(Icons.close_rounded, size: 16),
        deleteButtonTooltipMessage: 'Remove',
      ),
    ),
  );
}

/// The message search's recent terms, shown while its box is empty, under
/// a "Recent" band.
class RecentSearches extends StatelessWidget {
  const RecentSearches({
    super.key,
    required this.history,
    required this.onPick,
    required this.onRemove,
    required this.onClear,
  });
  final List<String> history;
  final ValueChanged<String> onPick;
  final ValueChanged<String> onRemove;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        RecentHeader(onClear: onClear),
        for (final q in history)
          ListTile(
            leading: Icon(Icons.history_rounded, color: AppColors.text3),
            title: Text(q, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              icon: Icon(Icons.close_rounded, size: 18, color: AppColors.text3),
              tooltip: 'Remove',
              onPressed: () => onRemove(q),
            ),
            onTap: () => onPick(q),
          ),
      ],
    );
  }
}
