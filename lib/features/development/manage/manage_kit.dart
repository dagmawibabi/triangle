import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../chat/presentation/widgets/dev/dev_card_kit.dart';

// The frame of the Vercel, Resend, MongoDB and Cloudflare manager pages: a
// branded header that collapses as you scroll, with a summary loaded behind
// a skeleton; sticky tabs; and lists that load with skeleton rows, refresh
// by pulling, filter by search, and say clearly when empty or failing.

class ManageTab {
  const ManageTab(this.label, this.icon, this.builder);
  final String label;
  final IconData icon;
  final Widget Function(BuildContext context) builder;
}

class ManageScaffold extends StatelessWidget {
  const ManageScaffold({
    super.key,
    required this.brand,
    required this.title,
    required this.hero,
    required this.tabs,
    this.colors,
    this.fab,
    this.actions = const [],
  });
  final DevBrand brand;
  final String title;

  /// The summary under the title: who, what and how many.
  final Widget hero;
  final List<ManageTab> tabs;

  /// The header's gradient; defaults to the brand's colour.
  final List<Color>? colors;
  final Widget? fab;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = colors ?? [Color.lerp(brand.color, Colors.black, 0.55)!, Color.lerp(brand.color, Colors.black, 0.85)!];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        floatingActionButton: fab,
        body: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverAppBar(
              pinned: true,
              expandedHeight: 256,
              backgroundColor: c.last,
              foregroundColor: Colors.white,
              actions: actions,
              title: Row(
                children: [
                  DevMark(brand, size: 22),
                  const SizedBox(width: Space.s),
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ],
              ),
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.parallax,
                background: Container(
                  decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: c)),
                  child: Stack(
                    children: [
                      // A large faint mark in the corner.
                      Positioned(right: -30, bottom: -20, child: Opacity(opacity: 0.08, child: DevMark(brand, size: 190))),
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(Space.l, kToolbarHeight + Space.s, Space.l, Space.l + 46),
                          child: hero,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              bottom: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white60,
                indicatorColor: Colors.white,
                dividerColor: Colors.transparent,
                tabs: [for (final t in tabs) Tab(height: 46, icon: null, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(t.icon, size: 16), const SizedBox(width: 6), Text(t.label)]))],
              ),
            ),
          ],
          body: TabBarView(children: [for (final t in tabs) Builder(builder: t.builder)]),
        ),
      ),
    );
  }
}

/// White text on the header: a big value and a small label.
class HeroStat extends StatelessWidget {
  const HeroStat(this.value, this.label, {super.key, this.color});
  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: Space.s, horizontal: Space.m),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(Radii.m)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color ?? Colors.white, fontSize: 19, fontWeight: FontWeight.w800, fontFeatures: tabularFigures)),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
        ],
      ),
    ),
  );
}

/// The header's summary: loads [load] behind white skeleton bones.
class HeroLoader extends ConsumerStatefulWidget {
  const HeroLoader({super.key, required this.load, required this.builder});
  final Future<Map<String, dynamic>> Function(BuildContext context, WidgetRef ref) load;
  final Widget Function(BuildContext context, Map<String, dynamic> data) builder;
  @override
  ConsumerState<HeroLoader> createState() => _HeroLoaderState();
}

class _HeroLoaderState extends ConsumerState<HeroLoader> {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      try {
        // ignore: use_build_context_synchronously
        final d = await widget.load(context, ref);
        if (mounted) setState(() => _data = d);
      } catch (e) {
        if (mounted) setState(() => _error = '$e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_data != null) return widget.builder(context, _data!);
    if (_error != null) return Align(alignment: Alignment.bottomLeft, child: Text(_error!, maxLines: 3, style: const TextStyle(color: Colors.white70)));
    Widget bone(double w, double h) => Container(width: w, height: h, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)));
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [bone(44, 44), const SizedBox(width: Space.m), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [bone(140, 14), const SizedBox(height: 6), bone(90, 10)])]),
        const SizedBox(height: Space.m),
        Row(children: [for (var i = 0; i < 3; i++) ...[if (i > 0) const SizedBox(width: Space.s), Expanded(child: bone(double.infinity, 50))]]),
      ],
    );
  }
}

/// A list a manager tab shows: skeleton rows while loading, pull to
/// refresh, an optional search box, and an empty or error message.
class ManagedList extends ConsumerStatefulWidget {
  const ManagedList({
    super.key,
    required this.load,
    required this.itemBuilder,
    this.empty = 'Nothing here yet.',
    this.searchHint,
    this.matches,
    this.header,
  });
  final Future<List<Map<String, dynamic>>> Function(BuildContext context, WidgetRef ref) load;
  final Widget Function(BuildContext context, Map<String, dynamic> item, VoidCallback reload) itemBuilder;
  final String empty;

  /// Shows a search box filtering items with [matches].
  final String? searchHint;
  final bool Function(Map<String, dynamic> item, String query)? matches;

  /// Shown above the items once loaded, e.g. totals or a chart.
  final Widget Function(BuildContext context, List<Map<String, dynamic>> items)? header;

  @override
  ConsumerState<ManagedList> createState() => _ManagedListState();
}

class _ManagedListState extends ConsumerState<ManagedList> with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>>? _items;
  String? _error;
  String _q = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final items = await widget.load(context, ref);
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    }
  }

  void _reload() {
    setState(() => _items = null);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final items = _items;
    final shown = items == null || _q.isEmpty || widget.matches == null ? items : [for (final i in items) if (widget.matches!(i, _q.toLowerCase())) i];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(top: Space.m, bottom: 96),
        children: [
          if (widget.searchHint != null && (items?.length ?? 0) > 4)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.m),
              child: TextField(
                onChanged: (v) => setState(() => _q = v.trim()),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: widget.searchHint,
                  prefixIcon: Icon(Icons.search_rounded, size: 20, color: AppColors.text3),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide.none),
                ),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: Column(
                children: [
                  Icon(Icons.cloud_off_rounded, size: 40, color: AppColors.text3),
                  const SizedBox(height: Space.s),
                  Text(_error!, textAlign: TextAlign.center, style: context.text.bodySmall?.copyWith(color: AppColors.danger)),
                  const SizedBox(height: Space.s),
                  OutlinedButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Try again')),
                ],
              ),
            )
          else if (shown == null)
            const SkeletonRows(count: 7)
          else ...[
            if (widget.header != null && items!.isNotEmpty) widget.header!(context, items),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.all(Space.x4),
                child: Column(
                  children: [
                    Icon(Icons.inbox_outlined, size: 40, color: AppColors.text3),
                    const SizedBox(height: Space.s),
                    Text(_q.isEmpty ? widget.empty : 'Nothing matches "$_q".', textAlign: TextAlign.center, style: context.text.bodySmall),
                  ],
                ),
              ),
            for (final i in shown) widget.itemBuilder(context, i, _reload),
          ],
        ],
      ),
    );
  }
}

/// A row in a manager list: a rounded surface with an icon, two lines and
/// something on the right.
class ManageTile extends StatelessWidget {
  const ManageTile({super.key, required this.leading, required this.title, this.subtitle, this.trailing, this.onTap});
  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
    child: Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.l), side: BorderSide(color: AppColors.line)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Space.m),
          child: Row(
            children: [
              leading,
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: Space.s), trailing!],
            ],
          ),
        ),
      ),
    ),
  );
}

/// A rounded icon on a tinted square, for tile leads.
class TileIcon extends StatelessWidget {
  const TileIcon(this.icon, {super.key, required this.color, this.size = 42});
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(size * 0.28)),
    child: Icon(icon, color: color, size: size * 0.52),
  );
}

/// Runs a reading tool and returns its list at [key].
Future<List<Map<String, dynamic>>> loadList(BuildContext context, WidgetRef ref, String tool, Map<String, dynamic> args, String key) async {
  final r = await devRun(context, ref, tool, args);
  return [for (final x in (r[key] as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];
}
