import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../app/theme.dart';
import '../../../domain/chat_models.dart';
import 'dev_card_kit.dart';
import 'mongo_cards.dart';
import 'resend_cards.dart';
import 'vercel_cards.dart';

/// Cards for the Development tools (Vercel, Resend, MongoDB): each
/// service's own cards, then one for any other change or deletion, and a
/// JSON tree for raw API answers.
Widget? devResultFor(ToolPart part, Map<String, dynamic> j) {
  final dev = j['dev'];
  if (dev is! String) return null;
  final own = vercelResultFor(part, j) ?? resendResultFor(part, j) ?? mongoResultFor(part, j);
  if (own != null) return own;
  final brand = switch (dev) {
    'vercel' => DevBrand.vercel,
    'resend' => DevBrand.resend,
    _ => DevBrand.mongodb,
  };
  if (j['result'] != null) return _RawCard(brand: brand, title: '${j['path'] ?? part.name}', value: j['result']);
  if (j['done'] == true || j['deleted'] != null) return _DoneCard(brand: brand, tool: part.name, j: j);
  return null;
}

class _DoneCard extends StatelessWidget {
  const _DoneCard({required this.brand, required this.tool, required this.j});
  final DevBrand brand;
  final String tool;
  final Map<String, dynamic> j;

  @override
  Widget build(BuildContext context) {
    final deleted = j['deleted'] != null;
    final facts = <String>[
      for (final e in j.entries)
        if (!const {'dev', 'done'}.contains(e.key) && e.value != null && e.value is! Map && e.value is! List) '${e.key.replaceAll('_', ' ')}: ${e.value}',
      for (final e in j.entries)
        if (e.value is List && (e.value as List).isNotEmpty && (e.value as List).first is! Map) '${e.key.replaceAll('_', ' ')}: ${(e.value as List).join(', ')}',
    ];
    final label = tool.replaceFirst(RegExp(r'^(vercel|resend|mongodb)_'), '').replaceAll('_', ' ');
    return DevPanel(
      onTap: () => showJsonSheet(context, brand: brand, title: '${brand.label}: $label', value: j),
      children: [
        ListTile(
          trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
          leading: DevMark(brand, size: 28),
          title: Row(
            children: [
              Icon(deleted ? Icons.delete_outline_rounded : Icons.check_circle_outline_rounded, size: 18, color: deleted ? AppColors.danger : AppColors.success),
              const SizedBox(width: Space.s),
              Expanded(child: Text('${brand.label}: ${label[0].toUpperCase()}${label.substring(1)}', style: const TextStyle(fontWeight: FontWeight.w600))),
            ],
          ),
          subtitle: facts.isEmpty ? null : Text(facts.take(4).join('\n'), style: context.text.bodySmall),
        ),
      ],
    );
  }
}

class _RawCard extends StatelessWidget {
  const _RawCard({required this.brand, required this.title, required this.value});
  final DevBrand brand;
  final String title;
  final Object? value;

  @override
  Widget build(BuildContext context) => DevPanel(
    onTap: () => showJsonSheet(context, brand: brand, title: title, value: value),
    children: [
      DevHead(
        brand: brand,
        title: '${brand.label} · $title',
        trailing: IconButton(
          icon: const Icon(Icons.copy_rounded, size: 16),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: value is String ? value as String : const JsonEncoder.withIndent('  ').convert(value)));
            showSnack(context, 'Copied');
          },
        ),
      ),
      pad(value is Map || value is List ? JsonTree(value: value, openDepth: 1) : Text('$value', maxLines: 30, overflow: TextOverflow.ellipsis, style: context.text.bodySmall)),
    ],
  );
}
