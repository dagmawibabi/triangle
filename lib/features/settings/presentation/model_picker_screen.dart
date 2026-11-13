import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../ai/data/ai.dart';
import '../data/settings.dart';

enum _Sort { recommended, cheapest, newest, context, name }

/// Browse chat models from the Vercel AI Gateway and OpenRouter, with
/// models.dev details, the way the dnd app does it.
class ModelPickerScreen extends ConsumerStatefulWidget {
  const ModelPickerScreen({
    super.key,
    required this.current,
    this.kind = ModelType.text,
  });
  final String current;
  final ModelType kind;

  @override
  ConsumerState<ModelPickerScreen> createState() => _ModelPickerScreenState();
}

class _ModelPickerScreenState extends ConsumerState<ModelPickerScreen> {
  String _q = '';
  String? _provider;
  AiRouter? _router;
  late bool _tools = widget.kind == ModelType.text;
  bool _free = false;
  bool _reasoning = false;
  bool _vision = false;
  bool _openWeights = false;
  _Sort _sort = _Sort.recommended;

  static const _favored = [
    'anthropic',
    'openai',
    'google',
    'xai',
    'x-ai',
    'mistral',
    'mistralai',
    'deepseek',
    'moonshotai',
    'alibaba',
    'qwen',
    'meta',
    'meta-llama',
    'zai',
    'z-ai',
  ];
  static const _sortLabels = {
    _Sort.recommended: 'Recommended',
    _Sort.cheapest: 'Cheapest',
    _Sort.newest: 'Newest',
    _Sort.context: 'Largest context',
    _Sort.name: 'Name',
  };

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    // Start on the one service there is a key for; with several, on All.
    final keyed = AiRouter.values.where((r) => hasKeyFor(s, r)).toList();
    if (keyed.length == 1) _router = keyed.single;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(modelCatalogProvider.notifier).ensureLoaded(),
    );
  }

  Future<void> _manual() async {
    final ctrl = TextEditingController(text: widget.current);
    final id = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Model ID'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'gateway:openai/gpt-5',
              ),
            ),
            const SizedBox(height: Space.s),
            Text(
              'provider:model, where provider is gateway (Vercel AI Gateway), openrouter, google (AI Studio), opencode (OpenCode Zen) or lmstudio.',
              style: context.text.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Use'),
          ),
        ],
      ),
    );
    if (id != null && id.isNotEmpty && mounted) Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    final cat = ref.watch(modelCatalogProvider);
    final settings = ref.watch(settingsProvider);
    // Only the services with a key, unless there is none yet (then every
    // list, to browse).
    final keyed = AiRouter.values.where((r) => hasKeyFor(settings, r)).toList();
    final all = cat.ofKind(widget.kind).where((m) => keyed.isEmpty || keyed.contains(m.router)).toList();
    final textKind =
        widget.kind == ModelType.text || widget.kind == ModelType.transcription;
    final counts = {
      for (final r in AiRouter.values)
        r: all.where((m) => m.router == r).length,
    };
    final providers =
        all
            .where((m) => _router == null || m.router == _router)
            .map((m) => m.maker)
            .toSet()
            .toList()
          ..sort();
    final q = _q.toLowerCase().trim();
    final list = all.where((m) {
      if (_router != null && m.router != _router) return false;
      if (_provider != null && m.maker != _provider) return false;
      if (_tools && !m.toolCall) return false;
      if (_free && !m.isFree) return false;
      if (_reasoning && !m.reasoning) return false;
      if (_vision && !m.vision) return false;
      if (_openWeights && !m.openWeights) return false;
      return q.isEmpty ||
          m.id.toLowerCase().contains(q) ||
          m.name.toLowerCase().contains(q) ||
          (m.family?.toLowerCase().contains(q) ?? false);
    }).toList();
    switch (_sort) {
      case _Sort.recommended:
        int rank(ModelInfo m) {
          final i = _favored.indexOf(m.maker);
          return i < 0 ? 99 : i;
        }
        list.sort(
          (a, b) => rank(a) != rank(b)
              ? rank(a).compareTo(rank(b))
              : (b.releaseDate ?? '').compareTo(a.releaseDate ?? ''),
        );
      case _Sort.cheapest:
        list.sort((a, b) {
          final c = a.blendedPrice.compareTo(b.blendedPrice);
          return c != 0
              ? c
              : (b.releaseDate ?? '').compareTo(a.releaseDate ?? '');
        });
      case _Sort.newest:
        list.sort(
          (a, b) => (b.releaseDate ?? '').compareTo(a.releaseDate ?? ''),
        );
      case _Sort.context:
        list.sort(
          (a, b) => (b.contextWindow ?? 0).compareTo(a.contextWindow ?? 0),
        );
      case _Sort.name:
        list.sort((a, b) => a.name.compareTo(b.name));
    }
    final missingKey =
        _router != null &&
        !hasKeyFor(settings, _router!);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.kind.pickerTitle),
        actions: [
          IconButton(
            tooltip: 'Enter an ID',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _manual,
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: cat.loading
                ? null
                : () => ref.read(modelCatalogProvider.notifier).refresh(),
            icon: cat.loading
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.l,
                  Space.xs,
                  Space.l,
                  Space.s,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<AiRouter?>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: null,
                        label: Text('All · ${all.length}', maxLines: 1),
                      ),
                      for (final r in keyed)
                        ButtonSegment(
                          value: r,
                          label: Text(
                            '${r.short} · ${counts[r]}',
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                          ),
                        ),
                    ],
                    selected: {_router},
                    onSelectionChanged: (v) => setState(() {
                      _router = v.first;
                      _provider = null;
                    }),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.l,
                  0,
                  Space.l,
                  Space.m,
                ),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search models',
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: AppColors.text3,
                    ),
                  ),
                  onChanged: (v) => setState(() => _q = v),
                ),
              ),
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: Space.l),
                  children: [
                    // Free first: the filter people reach for most.
                    _filter(
                      'Free',
                      _free,
                      (v) => _free = v,
                      icon: Icons.money_off_rounded,
                    ),
                    _menuChip<_Sort>(Icons.sort_rounded, _sortLabels[_sort]!, [
                      for (final s in _Sort.values) (s, _sortLabels[s]!),
                    ], (s) => setState(() => _sort = s)),
                    const SizedBox(width: 6),
                    _menuChip<String>(
                      Icons.business_outlined,
                      _provider ?? 'All providers',
                      [
                        ('', 'All providers'),
                        for (final p in providers) (p, p),
                      ],
                      (p) => setState(() => _provider = p.isEmpty ? null : p),
                    ),
                    const SizedBox(width: 6),
                    if (textKind) ...[
                      _filter(
                        'Tool use',
                        _tools,
                        (v) => _tools = v,
                        icon: Icons.build_outlined,
                      ),
                      _filter(
                        'Reasoning',
                        _reasoning,
                        (v) => _reasoning = v,
                        icon: Icons.psychology_alt_outlined,
                      ),
                      _filter(
                        'Vision',
                        _vision,
                        (v) => _vision = v,
                        icon: Icons.image_outlined,
                      ),
                    ],
                    _filter(
                      'Open weights',
                      _openWeights,
                      (v) => _openWeights = v,
                      icon: Icons.lock_open_rounded,
                    ),
                  ],
                ),
              ),
              if (missingKey)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.l,
                    Space.m,
                    Space.l,
                    0,
                  ),
                  child: Text(
                    switch (_router) {
                      AiRouter.lmStudio => 'Add your LM Studio server address in Settings to use these models.',
                      AiRouter.openRouter => 'Add your OpenRouter key in Settings to use these models.',
                      AiRouter.openCode => 'Add your OpenCode Zen key in Settings to use these models.',
                      AiRouter.gemini => 'Add your Google AI Studio Gemini key in Settings to use these models.',
                      _ => 'Add your Vercel AI Gateway key in Settings to use these models.',
                    },
                    style: context.text.bodySmall?.copyWith(
                      color: AppColors.warning,
                    ),
                  ),
                ),
              // A router whose list failed says why, rather than looking empty.
              for (final r in _router == null ? AiRouter.values : [_router!])
                if (!missingKey && counts[r] == 0 && cat.providerErrors[r.providerId] != null && hasKeyFor(settings, r))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
                    child: Text(
                      'Couldn\'t list ${r.title} models: ${cat.providerErrors[r.providerId]}',
                      style: context.text.bodySmall?.copyWith(color: AppColors.danger),
                    ),
                  ),
              if (_tools || widget.kind != ModelType.text)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.l,
                    Space.m,
                    Space.l,
                    0,
                  ),
                  child: Text(
                    switch (widget.kind) {
                      ModelType.text => 'Showing models that can call tools, which Triangle needs to read your Telegram.',
                      ModelType.image => 'Models that create images, used by the generate_image tool.',
                      ModelType.speech => 'Voices that read answers aloud.',
                      ModelType.transcription => 'Chat models that accept audio, used to turn speech into text.',
                      _ => '',
                    },
                    style: context.text.bodySmall?.copyWith(
                      color: AppColors.text3,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.xl,
                  Space.m,
                  Space.xl,
                  Space.xs + 2,
                ),
                child: Row(
                  children: [
                    Text(
                      '${list.length} models',
                      style: context.text.labelSmall,
                    ),
                    const Spacer(),
                    Text(
                      widget.kind == ModelType.image
                          ? 'Price per image'
                          : 'Input / output per 1M tokens',
                      style: context.text.labelSmall,
                    ),
                  ],
                ),
              ),
              if (cat.error != null && all.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(Space.xl),
                  child: Text(
                    'Couldn\'t load models: ${cat.error}',
                    style: context.text.bodySmall?.copyWith(
                      color: AppColors.danger,
                    ),
                  ),
                ),
              Expanded(
                child: cat.loading && all.isEmpty
                    ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : RefreshIndicator(
                        onRefresh: () =>
                            ref.read(modelCatalogProvider.notifier).refresh(),
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(
                            Space.l,
                            Space.xs,
                            Space.l,
                            Space.x4,
                          ),
                          itemCount: list.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: Space.s),
                          itemBuilder: (ctx, i) => _ModelTile(
                            model: list[i],
                            selected: list[i].id == widget.current,
                            onTap: () => Navigator.pop(context, list[i].id),
                            onInfo: () => showModelDetails(
                              context,
                              list[i],
                              onUse: () => Navigator.pop(context, list[i].id),
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filter(
    String label,
    bool value,
    void Function(bool) set, {
    IconData? icon,
  }) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: FilterChip(
      avatar: icon == null
          ? null
          : Icon(
              icon,
              size: 15,
              color: value ? AppColors.accent : AppColors.text3,
            ),
      label: Text(label),
      selected: value,
      onSelected: (v) => setState(() => set(v)),
    ),
  );

  Widget _menuChip<V>(
    IconData icon,
    String label,
    List<(V, String)> items,
    ValueChanged<V> onSelect,
  ) {
    return PopupMenuButton<V>(
      onSelected: onSelect,
      itemBuilder: (_) => [
        for (final i in items) PopupMenuItem(value: i.$1, child: Text(i.$2)),
      ],
      child: Chip(
        avatar: Icon(icon, size: 15, color: AppColors.text3),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 18,
              color: AppColors.text3,
            ),
          ],
        ),
      ),
    );
  }
}

class Tag extends StatelessWidget {
  const Tag(
    this.text, {
    super.key,
    this.icon,
    Color? color,
    this.filled = false,
  }) : _color = color;
  final String text;
  final IconData? icon;
  final Color? _color;
  Color get color => _color ?? AppColors.text2;
  final bool filled;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: filled ? color.withValues(alpha: 0.14) : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: filled ? Colors.transparent : AppColors.line),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
        ],
        Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({
    required this.model,
    required this.selected,
    required this.onTap,
    required this.onInfo,
  });
  final ModelInfo model;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    final m = model;
    final router = m.router;
    return Material(
      color: selected ? AppColors.accentDim : AppColors.surface,
      borderRadius: BorderRadius.circular(Radii.l),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.l),
        onTap: onTap,
        onLongPress: onInfo,
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            Space.l,
            Space.m,
            Space.xs,
            Space.m,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.l),
            border: Border.all(
              color: selected
                  ? AppColors.accent.withValues(alpha: 0.6)
                  : AppColors.line,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            m.name,
                            style: context.text.titleSmall?.copyWith(
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (selected) ...[
                          const SizedBox(width: Space.s),
                          Icon(
                            Icons.check_circle_rounded,
                            size: 16,
                            color: AppColors.accent,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      m.modelId,
                      style: context.text.bodySmall?.copyWith(
                        color: AppColors.text3,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: Space.s + 2),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        Tag(
                          router?.short ?? m.provider,
                          color: switch (router) {
                            AiRouter.openRouter => const Color(0xFF7FB2FF),
                            AiRouter.gemini => const Color(0xFF8AB4F8),
                            AiRouter.openCode => const Color(0xFFB49CFF),
                            _ => AppColors.text2,
                          },
                        ),
                        if (m.isFree)
                          Tag(
                            'Free',
                            icon: Icons.money_off_rounded,
                            color: AppColors.success,
                            filled: true,
                          )
                        else
                          Tag(m.priceLabel, icon: Icons.payments_outlined),
                        if (m.contextWindow != null)
                          Tag('${m.contextLabel} ctx'),
                        if (m.toolCall)
                          const Tag('Tools', icon: Icons.build_outlined),
                        if (m.reasoning)
                          Tag(
                            'Reasoning',
                            color: AppColors.accent,
                            filled: true,
                          ),
                        if (m.vision) const Tag('Vision'),
                        if (m.audioIn) const Tag('Audio in'),
                        if (m.makesImages) const Tag('Makes images'),
                        if (m.voices.isNotEmpty)
                          Tag('${m.voices.length} voices'),
                        if (m.openWeights) const Tag('Open weights'),
                        if (m.releaseDate != null) Tag(m.releaseDate!),
                      ],
                    ),
                    if (m.description.isNotEmpty) ...[
                      const SizedBox(height: Space.s),
                      Text(
                        m.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall?.copyWith(height: 1.4),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Details',
                icon: Icon(
                  Icons.info_outline_rounded,
                  size: 20,
                  color: AppColors.text3,
                ),
                onPressed: onInfo,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Everything the catalogs and models.dev know about a model.
Future<void> showModelDetails(
  BuildContext context,
  ModelInfo m, {
  VoidCallback? onUse,
  String useLabel = 'Use this model',
}) {
  String price(double? v) =>
      v == null ? '—' : (v == 0 ? 'Free' : '${ModelInfo.usd(v)} / 1M');
  final rows = <(String, String)>[
    ('Router', AiRouter.nameOf(m.id)),
    ('Type', m.kindLabel),
    if (m.imagePrice != null) ('Per image', ModelInfo.usd(m.imagePrice!)),
    if (m.voices.isNotEmpty) ('Voices', m.voices.join(', ')),
    ('Provider', m.maker),
    if (m.family != null) ('Family', m.family!),
    (
      'Context window',
      m.contextWindow == null
          ? '—'
          : '${ModelInfo.tokens(m.contextWindow)} tokens',
    ),
    (
      'Max output',
      m.maxOutput == null ? '—' : '${ModelInfo.tokens(m.maxOutput)} tokens',
    ),
    ('Input price', price(m.inputPrice)),
    ('Output price', price(m.outputPrice)),
    if (m.cacheReadPrice != null) ('Cached input', price(m.cacheReadPrice)),
    ('Input', m.inputModalities.join(', ')),
    ('Output', m.outputModalities.join(', ')),
    if (m.releaseDate != null) ('Released', m.releaseDate!),
    if (m.lastUpdated != null) ('Updated', m.lastUpdated!),
    if (m.knowledge != null) ('Knowledge cutoff', m.knowledge!),
  ];
  final caps = <(String, bool)>[
    ('Tool calling', m.toolCall),
    ('Reasoning', m.reasoning),
    ('Vision', m.vision),
    ('Audio input', m.audioIn),
    ('Makes images', m.makesImages),
    ('Structured output', m.structuredOutput),
    ('Attachments', m.attachment),
    ('Temperature', m.temperature),
    ('Open weights', m.openWeights),
  ];
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 1,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.x4),
        children: [
          Text(m.name, style: context.text.headlineSmall),
          const SizedBox(height: Space.xs),
          SelectableText(
            m.modelId,
            style: context.text.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
          if (m.description.isNotEmpty) ...[
            const SizedBox(height: Space.l),
            Text(
              m.description,
              style: context.text.bodyMedium?.copyWith(color: AppColors.text2),
            ),
          ],
          const SizedBox(height: Space.xl),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(Radii.m),
            ),
            child: Column(
              children: [
                for (final (i, (k, v)) in rows.indexed) ...[
                  if (i > 0) const Divider(indent: Space.l, endIndent: Space.l),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.l,
                      vertical: Space.m,
                    ),
                    child: Row(
                      children: [
                        Text(
                          k,
                          style: context.text.bodyMedium?.copyWith(
                            color: AppColors.text2,
                          ),
                        ),
                        const SizedBox(width: Space.l),
                        Expanded(
                          child: Text(
                            v,
                            textAlign: TextAlign.right,
                            style: context.text.bodyMedium?.copyWith(
                              fontFeatures: tabularFigures,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: Space.xl),
          Text('CAPABILITIES', style: context.text.labelSmall),
          const SizedBox(height: Space.s),
          Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            children: [
              for (final (k, on) in caps)
                Tag(
                  k,
                  icon: on ? Icons.check_rounded : Icons.close_rounded,
                  color: on ? AppColors.success : AppColors.text3,
                  filled: on,
                ),
            ],
          ),
          if (!m.toolCall && m.isText) ...[
            const SizedBox(height: Space.l),
            Text(
              'This model can\'t call tools, so it can\'t look at your Telegram.',
              style: context.text.bodySmall?.copyWith(color: AppColors.warning),
            ),
          ],
          if (onUse != null) ...[
            const SizedBox(height: Space.xxl),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                onUse();
              },
              child: Text(useLabel),
            ),
          ],
        ],
      ),
    ),
  );
}

/// Whether [s] has the key (or, for LM Studio, the address) [r] needs.
bool hasKeyFor(AppSettings s, AiRouter r) => switch (r) {
  AiRouter.vercel => s.hasVercelKey,
  AiRouter.openRouter => s.hasOpenRouterKey,
  AiRouter.gemini => s.hasGeminiKey,
  AiRouter.openCode => s.hasOpenCodeKey,
  AiRouter.lmStudio => s.hasLmStudio,
};
