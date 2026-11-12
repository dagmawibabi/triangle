import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme.dart';
import '../../../settings/data/system_check.dart';
import '../../../settings/presentation/system_check_screen.dart';
import '../../../telegram/presentation/block_mute_screen.dart';
import '../../domain/chat_models.dart';
import 'info_card_kit.dart';

/// Cards for system_check and the Block & mute tools. Null for other tools.
Widget? safetyResultFor(ToolPart part, Map<String, dynamic> j) => switch (part.name) {
  'system_check' when j['areas'] is List => _SystemCheckCard(j: j),
  'list_hidden' || 'block_chat' || 'unblock_chat' || 'mute_words' || 'unmute_words' || 'block_mute_settings'
      when j['muted_words'] is List =>
    _HiddenCard(name: part.name, j: j),
  _ => null,
};

CheckStatus _status(Object? name) => CheckStatus.values.asNameMap()['$name'] ?? CheckStatus.info;

List<Map<String, dynamic>> _maps(Object? v) => [
  for (final x in (v as List? ?? const []))
    if (x is Map) Map<String, dynamic>.from(x),
];

String _plural(int n, CheckStatus s) => '$n ${s.word}${n == 1 || s == CheckStatus.ok || s == CheckStatus.fail ? '' : 's'}';

/// The colour of the whole check: red with anything broken, amber with
/// warnings, green otherwise.
Color _tone(Map<String, dynamic> counts) => (counts['broken'] as num? ?? 0) > 0
    ? CheckStatus.fail.color
    : (counts['warnings'] as num? ?? 0) > 0
    ? CheckStatus.warn.color
    : CheckStatus.ok.color;

/// The health score as a ring with the number inside.
class _Ring extends StatelessWidget {
  const _Ring({required this.score, required this.color, this.size = 56});
  final int? score;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Stack(
      fit: StackFit.expand,
      children: [
        CircularProgressIndicator(
          value: (score ?? 0) / 100,
          strokeWidth: size / 11,
          strokeCap: StrokeCap.round,
          backgroundColor: AppColors.surface3,
          valueColor: AlwaysStoppedAnimation(color),
        ),
        Center(
          child: Text(
            score == null ? '–' : '$score',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: size * 0.3, fontFeatures: tabularFigures),
          ),
        ),
      ],
    ),
  );
}

/// "2 broken · 3 warnings" as coloured pills.
Widget _countPills(Map<String, dynamic> counts) {
  final pairs = [
    (CheckStatus.fail, counts['broken']),
    (CheckStatus.warn, counts['warnings']),
    (CheckStatus.improve, counts['suggestions']),
    (CheckStatus.ok, counts['passed']),
  ];
  return Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final (s, n) in pairs)
        if (n is num && n > 0) InfoPill(_plural(n.toInt(), s), color: s.color, icon: s.icon),
    ],
  );
}

class _SystemCheckCard extends StatelessWidget {
  const _SystemCheckCard({required this.j});
  final Map<String, dynamic> j;

  @override
  Widget build(BuildContext context) {
    final counts = Map<String, dynamic>.from(j['counts'] as Map? ?? const {});
    final areas = _maps(j['areas']);
    final score = (j['score'] as num?)?.toInt();
    final attention = [
      for (final a in areas)
        for (final r in _maps(a['results']))
          if (_status(r['status']).rank <= CheckStatus.warn.rank) (a, r),
    ];
    final total = areas.fold<int>(0, (n, a) => n + _maps(a['results']).length);
    final broken = (counts['broken'] as num? ?? 0) + (counts['warnings'] as num? ?? 0);
    return InfoFrame(
      onTap: () => showSystemCheckSheet(context, j),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoHeader(
            Icons.health_and_safety_outlined,
            'System check',
            trailing: Text('${areas.length} areas', style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
            child: Row(
              children: [
                _Ring(score: score, color: _tone(counts)),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        broken == 0 ? 'All good' : '$broken thing${broken == 1 ? '' : 's'} need${broken == 1 ? 's' : ''} attention',
                        style: context.text.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      _countPills(counts),
                    ],
                  ),
                ),
              ],
            ),
          ),
          for (final (a, r) in attention.take(3))
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(_status(r['status']).icon, size: 16, color: _status(r['status']).color),
                  const SizedBox(width: Space.s),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: '${a['title']}: ', style: TextStyle(color: AppColors.text3)),
                          TextSpan(text: '${r['title']}'),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall?.copyWith(color: AppColors.text),
                    ),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    attention.length > 3 ? '${attention.length - 3} more to look at · $total findings' : 'All $total findings',
                    style: context.text.labelSmall?.copyWith(color: AppColors.text2),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.text3),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Every finding of a system check, area by area, most serious first.
Future<void> showSystemCheckSheet(BuildContext context, Map<String, dynamic> j) {
  final counts = Map<String, dynamic>.from(j['counts'] as Map? ?? const {});
  final areas = _maps(j['areas'])..sort((a, b) => _status(a['worst']).rank.compareTo(_status(b['worst']).rank));
  final score = (j['score'] as num?)?.toInt();
  String report() => [
    'Triangle system check · ${j['checked_at'] ?? ''} · health ${score ?? '–'}/100',
    for (final a in areas) ...[
      '',
      '${a['title']} (${a['ms']} ms)',
      for (final r in _maps(a['results'])) '  [${_status(r['status']).word}] ${r['title']}${r['detail'] == null ? '' : ': ${r['detail']}'}',
    ],
  ].join('\n');
  return showInfoSheet(context, (context) {
    return [
      SheetTitle(
        'System check',
        subtitle: 'Health ${score ?? '–'} of 100 · ${'${j['checked_at'] ?? ''}'.replaceFirst('T', ' ')}',
        leading: _Ring(score: score, color: _tone(counts), size: 52),
      ),
      const SizedBox(height: Space.m),
      _countPills(counts),
      for (final a in areas) ...[
        _AreaHeader(area: a),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(Radii.l),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            children: [
              for (final (i, r) in _maps(a['results']).indexed) ...[
                if (i > 0) Divider(height: 1, color: AppColors.line),
                _FindingRow(r: r),
              ],
              if (_maps(a['results']).isEmpty)
                Padding(
                  padding: const EdgeInsets.all(Space.m),
                  child: Text('Nothing to check here.', style: context.text.bodySmall),
                ),
            ],
          ),
        ),
      ],
      sheetButtons([
        FilledButton.icon(
          onPressed: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SystemCheckScreen()));
          },
          icon: const Icon(Icons.radar_rounded, size: 18),
          label: const Text('Open System check'),
        ),
        OutlinedButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: report()));
            showSnack(context, 'Report copied');
          },
          icon: const Icon(Icons.copy_all_rounded, size: 18),
          label: const Text('Copy report'),
        ),
      ]),
    ];
  });
}

class _AreaHeader extends StatelessWidget {
  const _AreaHeader({required this.area});
  final Map<String, dynamic> area;

  @override
  Widget build(BuildContext context) {
    final worst = _status(area['worst']);
    final icon = systemCheckAreas['${area['id']}']?.$2 ?? Icons.check_circle_outline_rounded;
    final ms = (area['ms'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.only(top: Space.l, bottom: Space.s),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: worst.color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(Radii.s)),
            child: Icon(icon, size: 16, color: worst.color),
          ),
          const SizedBox(width: Space.s),
          Expanded(child: Text('${area['title']}', style: context.text.titleSmall)),
          Text(ms < 1000 ? '$ms ms' : '${(ms / 1000).toStringAsFixed(1)} s', style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
          const SizedBox(width: Space.s),
          Icon(worst.icon, size: 16, color: worst.color),
        ],
      ),
    );
  }
}

class _FindingRow extends StatelessWidget {
  const _FindingRow({required this.r});
  final Map<String, dynamic> r;

  @override
  Widget build(BuildContext context) {
    final s = _status(r['status']);
    final serious = s.rank <= CheckStatus.warn.rank;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s + 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: Icon(s.icon, size: 17, color: s.color)),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${r['title']}', style: context.text.bodyMedium?.copyWith(fontWeight: serious ? FontWeight.w600 : null)),
                if (r['detail'] != null)
                  Padding(padding: const EdgeInsets.only(top: 2), child: Text('${r['detail']}', style: context.text.bodySmall)),
              ],
            ),
          ),
          if (r['fixable_in_settings'] == true) ...[
            const SizedBox(width: Space.s),
            Tooltip(message: 'Fixable in System check', child: Icon(Icons.build_circle_outlined, size: 16, color: AppColors.text3)),
          ],
        ],
      ),
    );
  }
}

/// What Block & mute hides after a Block & mute tool, with what changed.
class _HiddenCard extends StatelessWidget {
  const _HiddenCard({required this.name, required this.j});
  final String name;
  final Map<String, dynamic> j;

  @override
  Widget build(BuildContext context) {
    final chats = _maps(j['blocked_chats']);
    final words = [for (final w in (j['muted_words'] as List? ?? const [])) '$w'];
    final notices = Map<String, dynamic>.from(j['notices'] as Map? ?? const {});
    final accounts = (j['blocked_accounts'] as num?)?.toInt() ?? 0;
    List<String> strs(String k) => [for (final w in (j[k] as List? ?? const [])) '$w'];
    final (IconData icon, String headline) = switch (name) {
      'block_chat' => (Icons.block_rounded, 'Blocked ${(j['blocked'] as Map?)?['title'] ?? 'the chat'}'),
      'unblock_chat' => (Icons.check_circle_outline_rounded, 'Unblocked ${(j['unblocked'] as Map?)?['title'] ?? 'the chat'}'),
      'mute_words' => (
        Icons.volume_off_outlined,
        strs('muted').isEmpty ? 'Those words were already muted' : 'Muted ${strs('muted').map((w) => '“$w”').join(', ')}',
      ),
      'unmute_words' => (
        Icons.volume_up_outlined,
        strs('unmuted').isEmpty ? 'Nothing to unmute' : 'Unmuted ${strs('unmuted').map((w) => '“$w”').join(', ')}',
      ),
      'block_mute_settings' => (Icons.tune_rounded, 'Changed how hidden messages show'),
      _ => (Icons.shield_outlined, chats.isEmpty && words.isEmpty ? 'Nothing is hidden' : 'What\'s hidden'),
    };
    String onOff(Object? v) => v == false ? 'hidden' : 'notice';
    return InfoFrame(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BlockMuteScreen())),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InfoHeader(Icons.shield_outlined, 'Block & mute', padding: const EdgeInsets.fromLTRB(0, Space.m, 0, Space.s)),
            Row(
              children: [
                Icon(icon, size: 20, color: AppColors.text),
                const SizedBox(width: Space.s),
                Expanded(child: Text(headline, style: context.text.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis)),
              ],
            ),
            if (chats.isNotEmpty) ...[
              const SectionLabel('Blocked channels & groups', top: Space.m),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in chats)
                    InfoPill('${c['title']}', icon: c['kind'] == 'channel' ? Icons.campaign_outlined : Icons.groups_outlined),
                ],
              ),
            ],
            if (words.isNotEmpty) ...[
              const SectionLabel('Muted words', top: Space.m),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final w in words) InfoPill(w, icon: Icons.volume_off_outlined)],
              ),
            ],
            const SizedBox(height: Space.m),
            Text(
              [
                '$accounts blocked account${accounts == 1 ? '' : 's'}',
                'accounts: ${onOff(notices['accounts'])}',
                'chats: ${onOff(notices['chats'])}',
                'words: ${onOff(notices['words'])}',
                j['in_archived'] == true ? 'archived too' : 'not in archived',
              ].join(' · '),
              style: context.text.labelSmall?.copyWith(color: AppColors.text3),
            ),
          ],
        ),
      ),
    );
  }
}
