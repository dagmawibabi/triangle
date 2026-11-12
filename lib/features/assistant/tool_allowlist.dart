import '../telegram/data/telegram_tools.dart';

/// The big groups of tools, as the Tools page shows them.
enum ToolArea {
  telegram('Telegram'),
  apps('Apps & web'),
  device('Device');

  const ToolArea(this.label);
  final String label;

  static ToolArea of(TelegramTool t) => t.category.onAppsScreen
      ? ToolArea.apps
      : (t.category == ToolCategory.device || t.category == ToolCategory.code)
      ? ToolArea.device
      : ToolArea.telegram;
}

/// Which tools a watch or routine may use. Null (see [ToolAllowlist.all])
/// means every tool the assistant has; otherwise only tools picked by name,
/// by category ("Messages", "Gmail") or by area ("Device").
///
/// Entries are `tool:<name>`, `cat:<category>` or `area:<area>`, so the
/// list keeps working when tools are added to a picked category.
class ToolAllowlist {
  const ToolAllowlist(this.entries);

  final Set<String> entries;

  static String tool(String name) => 'tool:$name';
  static String category(ToolCategory c) => 'cat:${c.name}';
  static String area(ToolArea a) => 'area:${a.name}';

  bool allows(TelegramTool t) =>
      entries.contains(tool(t.name)) || entries.contains(category(t.category)) || entries.contains(area(ToolArea.of(t)));

  bool get isEmpty => entries.isEmpty;

  /// The tools of [all] this allows.
  List<TelegramTool> pick(Iterable<TelegramTool> all) => [for (final t in all) if (allows(t)) t];

  /// Reads what the assistant (or a saved watch) gave: tool names, category
  /// names or labels, area names, or the prefixed forms. Unknown words are
  /// reported in [unknown].
  static ToolAllowlist parse(Iterable<Object?> raw, {List<String>? unknown}) {
    final out = <String>{};
    for (final v in raw) {
      final s = '$v'.trim();
      if (s.isEmpty) continue;
      if (s.startsWith('tool:') || s.startsWith('cat:') || s.startsWith('area:')) {
        out.add(s);
        continue;
      }
      final lower = s.toLowerCase();
      if (toolNamed(s) != null) {
        out.add(tool(s));
        continue;
      }
      final cat = ToolCategory.values.where((c) => c.name.toLowerCase() == lower || c.label.toLowerCase() == lower).firstOrNull;
      if (cat != null) {
        out.add(category(cat));
        continue;
      }
      final a = ToolArea.values.where((x) => x.name == lower || x.label.toLowerCase() == lower).firstOrNull;
      if (a != null) {
        out.add(area(a));
        continue;
      }
      unknown?.add(s);
    }
    return ToolAllowlist(out);
  }

  /// "3 tools · Messages · Device", for lists.
  String describe() {
    final parts = <String>[];
    for (final e in entries) {
      final (kind, name) = (e.split(':').first, e.substring(e.indexOf(':') + 1));
      switch (kind) {
        case 'area':
          parts.add(ToolArea.values.asNameMap()[name]?.label ?? name);
        case 'cat':
          parts.add(ToolCategory.values.asNameMap()[name]?.label ?? name);
        case 'tool':
          parts.add(toolNamed(name)?.label ?? name);
      }
    }
    parts.sort();
    if (parts.length > 3) return '${parts.take(3).join(', ')} +${parts.length - 3}';
    return parts.join(', ');
  }

  /// For the assistant: the readable names.
  List<String> toModel() => [
    for (final e in entries) e.startsWith('tool:') ? e.substring(5) : e,
  ];
}
