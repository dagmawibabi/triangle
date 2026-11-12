import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../domain/chat_models.dart';
import 'info_card_kit.dart';

/// Cards for screen_read and screen_screenshot. Null for other tools.
Widget? screenResultFor(ToolPart part, Map<String, dynamic> j) => switch (part.name) {
  'screen_read' when j['elements'] is List => _ScreenReadCard(j: j),
  'screen_screenshot' when j['image_path'] is String => _ScreenshotCard(j: j),
  _ => null,
};

List<Map<String, dynamic>> _elements(Map<String, dynamic> j) => [
  for (final x in (j['elements'] as List? ?? const []))
    if (x is Map) Map<String, dynamic>.from(x),
];

IconData _roleIcon(Object? role) => switch ('$role') {
  'button' => Icons.smart_button_outlined,
  'field' => Icons.edit_note_rounded,
  'switch' => Icons.toggle_on_outlined,
  'checkbox' => Icons.check_box_outlined,
  'image' => Icons.image_outlined,
  'list' => Icons.view_list_outlined,
  'web' => Icons.language_rounded,
  'text' => Icons.notes_rounded,
  _ => Icons.crop_square_rounded,
};

/// What an element shows: its text, else its label or hint.
String _caption(Map<String, dynamic> e) {
  for (final k in const ['text', 'label', 'hint', 'view']) {
    final v = '${e[k] ?? ''}'.trim();
    if (v.isNotEmpty) return v;
  }
  return '(${e['role'] ?? 'element'})';
}

class _ScreenReadCard extends StatelessWidget {
  const _ScreenReadCard({required this.j});
  final Map<String, dynamic> j;

  @override
  Widget build(BuildContext context) {
    final all = _elements(j);
    final actions = all.where((e) => e['clickable'] == true || e['editable'] == true || e['checked'] != null).length;
    final preview = all.where((e) => '${e['text'] ?? e['label'] ?? ''}'.trim().isNotEmpty).take(6).toList();
    return InfoFrame(
      onTap: () => _showElements(context, j),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InfoHeader(
              Icons.view_quilt_outlined,
              'Screen · ${j['app'] ?? j['package'] ?? 'app'}',
              padding: const EdgeInsets.fromLTRB(0, Space.m, 0, Space.s),
              trailing: Text('${all.length} elements · $actions actions', style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
            ),
            for (final e in preview)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(_roleIcon(e['role']), size: 15, color: AppColors.text3),
                    const SizedBox(width: Space.s),
                    Expanded(child: Text(_caption(e), maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: AppColors.text))),
                  ],
                ),
              ),
            if ((j['password_fields'] as num? ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: InfoPill('Passwords hidden', icon: Icons.password_rounded, color: AppColors.success),
              ),
          ],
        ),
      ),
    );
  }
}

/// Every element of a screen read, with its id, role and state.
Future<void> _showElements(BuildContext context, Map<String, dynamic> j) => showInfoSheet(
  context,
  (context) => [
    SheetTitle(
      '${j['app'] ?? 'Screen'}',
      subtitle: [
        if (j['package'] != null) '${j['package']}',
        if (j['screen'] != null) '${j['screen']}',
        '${j['count'] ?? _elements(j).length} elements${j['truncated'] == true ? ' (more not shown)' : ''}',
      ].join(' · '),
      leading: Icon(Icons.view_quilt_outlined, color: AppColors.text2),
    ),
    const SizedBox(height: Space.m),
    for (final e in _elements(j))
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 34,
              child: Text('#${e['id']}', style: context.text.labelSmall?.copyWith(color: AppColors.text3, fontFeatures: tabularFigures)),
            ),
            Icon(_roleIcon(e['role']), size: 16, color: AppColors.text2),
            const SizedBox(width: Space.s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_caption(e), style: context.text.bodyMedium),
                  Text(
                    [
                      '${e['role'] ?? ''}',
                      if (e['clickable'] == true) 'tappable',
                      if (e['editable'] == true) 'editable',
                      if (e['scrollable'] == true) 'scrolls',
                      if (e['checked'] == true) 'on',
                      if (e['checked'] == false) 'off',
                      if (e['focused'] == true) 'focused',
                      if (e['disabled'] == true) 'disabled',
                      if (e['password'] == true) 'password',
                    ].where((x) => x.isNotEmpty).join(' · '),
                    style: context.text.labelSmall?.copyWith(color: AppColors.text3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
  ],
);

class _ScreenshotCard extends StatelessWidget {
  const _ScreenshotCard({required this.j});
  final Map<String, dynamic> j;

  @override
  Widget build(BuildContext context) {
    final file = File('${j['image_path']}');
    if (!file.existsSync()) return const SizedBox.shrink();
    return InfoFrame(
      onTap: () => showInfoSheet(
        context,
        (context) => [
          SheetTitle('Screenshot', subtitle: '${j['app'] ?? ''} · ${j['width']}×${j['height']}'),
          const SizedBox(height: Space.m),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.l),
            child: InteractiveViewer(maxScale: 5, child: Image.file(file)),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            height: 128,
            child: Image.file(file, fit: BoxFit.cover, cacheWidth: 216),
          ),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InfoHeader(Icons.screenshot_monitor_rounded, 'Screenshot', padding: EdgeInsets.zero),
                const SizedBox(height: Space.xs),
                Text('${j['app'] ?? 'The screen'}', style: context.text.titleSmall),
                Text('${j['width']}×${j['height']} · tap to look closer', style: context.text.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
