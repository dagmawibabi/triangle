import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../data/content_filters.dart';

/// Stands in for a message hidden by a block or a muted word. Always the
/// same size, whatever the message holds, so nothing about it shows through.
class HiddenMessageNotice extends StatelessWidget {
  const HiddenMessageNotice({super.key, required this.verdict, required this.onReveal});
  final HiddenVerdict verdict;
  final VoidCallback onReveal;

  static const height = 52.0;

  @override
  Widget build(BuildContext context) {
    final icon = switch (verdict.reason) {
      HideReason.blockedAccount => Icons.person_off_outlined,
      HideReason.blockedChat => Icons.block_rounded,
      HideReason.mutedWord => Icons.volume_off_outlined,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Material(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.l),
              side: BorderSide(color: AppColors.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onReveal,
              child: SizedBox(
                height: height,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.m),
                  child: Row(
                    children: [
                      Icon(icon, size: 18, color: AppColors.text3),
                      const SizedBox(width: Space.s),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              verdict.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.bodySmall?.copyWith(color: AppColors.text2),
                            ),
                            Text('Tap to view', style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The thin line over a hidden message you chose to see, to hide it again.
class RevealedMessageBar extends StatelessWidget {
  const RevealedMessageBar({super.key, required this.verdict, required this.onHide});
  final HiddenVerdict verdict;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.m),
        onTap: onHide,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.visibility_off_outlined, size: 14, color: AppColors.text3),
              const SizedBox(width: Space.xs),
              Flexible(
                child: Text(
                  '${verdict.label} · Hide',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelSmall?.copyWith(color: AppColors.text3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
