import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/net_image.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../library/library_api.dart';
import '../../domain/chat_models.dart';

/// Cards for the country tools and NASA's astronomy picture of the day. Null
/// for other tools.
Widget? exploreResultFor(ToolPart part, Map<String, dynamic> j) {
  List<Map<String, dynamic>> list(Object? v) => [
    for (final x in (v as List? ?? const []))
      if (x is Map) Map<String, dynamic>.from(x),
  ];
  return switch (part.name) {
    'country_info' when j['name'] != null => _CountryCard(c: j),
    'countries_list' when list(j['countries']).isNotEmpty => _CountryGrid(countries: list(j['countries'])),
    'nasa_apod' when list(j['pictures']).length == 1 => _ApodCard(p: list(j['pictures']).first),
    'nasa_apod' when list(j['pictures']).isNotEmpty => _ApodGallery(pictures: list(j['pictures'])),
    _ => null,
  };
}

const _space = Color(0xFF4F7BFF);

String _n(Object? v) => v is num ? NumberFormat.compact().format(v) : '—';
String _full(Object? v) => v is num ? NumberFormat.decimalPattern().format(v) : '—';

Future<void> _open(String? url) async {
  if (url == null || url.isEmpty) return;
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

class _Frame extends StatelessWidget {
  const _Frame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: Space.s),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: AppColors.line)),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

class _Stat extends StatelessWidget {
  const _Stat(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 16, color: AppColors.text3),
      const SizedBox(width: 6),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: context.text.bodySmall?.copyWith(color: AppColors.text3, fontSize: 11)),
            Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
          ],
        ),
      ),
    ],
  );
}

Widget _grid(BuildContext context, List<Widget> stats) => LayoutBuilder(
  builder: (context, c) {
    final w = (c.maxWidth - Space.m) / 2;
    return Wrap(spacing: Space.m, runSpacing: Space.m, children: [for (final s in stats) SizedBox(width: w, child: s)]);
  },
);

class _Pill extends StatelessWidget {
  const _Pill(this.text, {this.onTap});
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(99),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(99), border: Border.all(color: AppColors.line)),
      child: Text(text, style: TextStyle(fontSize: 12, color: AppColors.text2)),
    ),
  );
}

// ---- countries ----------------------------------------------------------------------------

class _CountryCard extends StatelessWidget {
  const _CountryCard({required this.c});
  final Map<String, dynamic> c;

  @override
  Widget build(BuildContext context) => _Frame(
    child: InkWell(
      onTap: () => showCountry(context, c),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 2.2,
                child: c['flag'] == null
                    ? ColoredBox(color: AppColors.surface2)
                    : NetImage('${c['flag']}', fit: BoxFit.cover, errorWidget: ColoredBox(color: AppColors.surface2)),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withValues(alpha: 0.65)]),
                  ),
                ),
              ),
              Positioned(
                left: Space.m,
                right: Space.m,
                bottom: Space.m,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${c['name']}', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                    Text('${c['official'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(Space.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _grid(context, [
                  _Stat(Icons.location_city_rounded, 'Capital', '${c['capital'] ?? '—'}'),
                  _Stat(Icons.public_rounded, 'Region', '${[c['subregion'], c['region']].where((x) => x != null).firstOrNull ?? '—'}'),
                  _Stat(Icons.groups_rounded, 'Population', _n(c['population'])),
                  _Stat(Icons.square_foot_rounded, 'Area', '${_n(c['area_km2'])} km²'),
                ]),
                const SizedBox(height: Space.m),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final l in (c['languages'] as List? ?? const []).take(4)) _Pill('$l'),
                    for (final cur in (c['currencies'] as List? ?? const []).whereType<Map>()) _Pill('${cur['symbol'] ?? ''} ${cur['code']}'.trim()),
                    if (c['calling_code'] != null) _Pill('${c['calling_code']}'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Everything about a country, with its neighbours a tap away.
Future<void> showCountry(BuildContext context, Map<String, dynamic> c) => showAppSheet<void>(
  context,
  builder: (context, scroll) {
    double? density() {
      final p = c['population'], a = c['area_km2'];
      return p is num && a is num && a > 0 ? p / a : null;
    }

    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.s),
              child: c['flag'] == null ? const SizedBox(width: 72, height: 48) : NetImage('${c['flag']}', width: 72, height: 48, fit: BoxFit.cover),
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${c['name']}', style: context.text.titleLarge),
                  Text([c['native'], c['code'], c['code3']].where((x) => x != null).join(' · '), style: context.text.bodySmall),
                ],
              ),
            ),
            if (c['coat_of_arms'] != null) NetImage('${c['coat_of_arms']}', width: 44, height: 44, errorWidget: const SizedBox.shrink()),
          ],
        ),
        if (c['flag_description'] != null) ...[
          const SizedBox(height: Space.s),
          Text('${c['flag_description']}', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
        ],
        const SizedBox(height: Space.l),
        _grid(context, [
          _Stat(Icons.badge_outlined, 'Official name', '${c['official'] ?? '—'}'),
          _Stat(Icons.location_city_rounded, 'Capital', '${c['capital'] ?? '—'}'),
          _Stat(Icons.groups_rounded, 'Population', _full(c['population'])),
          _Stat(Icons.square_foot_rounded, 'Area', '${_full(c['area_km2'])} km²'),
          _Stat(Icons.grid_on_rounded, 'People per km²', density() == null ? '—' : density()!.toStringAsFixed(1)),
          _Stat(Icons.public_rounded, 'Continent', (c['continents'] as List?)?.join(', ') ?? '${c['region'] ?? '—'}'),
          _Stat(Icons.person_outline_rounded, 'People are', '${c['demonym'] ?? '—'}'),
          _Stat(Icons.call_rounded, 'Calling code', '${c['calling_code'] ?? '—'}'),
          _Stat(Icons.language_rounded, 'Internet', '${c['tld'] ?? '—'}'),
          if (c['drives_on'] != null) _Stat(Icons.directions_car_outlined, 'Drives on the', '${c['drives_on']}'),
          if (c['week_starts'] != null) _Stat(Icons.calendar_view_week_rounded, 'Week starts', '${c['week_starts']}'),
          if (c['gini'] != null) _Stat(Icons.balance_rounded, 'Gini (inequality)', '${c['gini']}'),
        ]),
        const SizedBox(height: Space.l),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (c['independent'] == true) const _Pill('Independent'),
            if (c['un_member'] == true) const _Pill('UN member'),
            if (c['landlocked'] == true) const _Pill('Landlocked'),
          ],
        ),
        for (final (label, items) in [
          ('LANGUAGES', [for (final l in (c['languages'] as List? ?? const [])) '$l']),
          ('CURRENCIES', [for (final x in (c['currencies'] as List? ?? const []).whereType<Map>()) '${x['name']} (${x['code']}${x['symbol'] == null ? '' : ', ${x['symbol']}'})']),
          ('TIME ZONES', [for (final t in (c['timezones'] as List? ?? const [])) '$t']),
        ])
          if (items.isNotEmpty) ...[
            const SizedBox(height: Space.l),
            Text(label, style: context.text.labelSmall),
            const SizedBox(height: Space.xs),
            Wrap(spacing: 4, runSpacing: 4, children: [for (final i in items) _Pill(i)]),
          ],
        if ((c['borders'] as List?)?.isNotEmpty == true) ...[
          const SizedBox(height: Space.l),
          Text('NEIGHBOURS', style: context.text.labelSmall),
          const SizedBox(height: Space.xs),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final b in c['borders'] as List)
                _Pill(
                  '$b',
                  onTap: () async {
                    try {
                      final n = await LibraryApi.instance.countryInfo('$b');
                      if (context.mounted) await showCountry(context, n);
                    } catch (e) {
                      if (context.mounted) showSnack(context, 'Couldn\'t load $b: $e', icon: Icons.error_outline_rounded);
                    }
                  },
                ),
            ],
          ),
        ],
        const SizedBox(height: Space.l),
        Wrap(
          spacing: Space.s,
          children: [
            if (c['map'] != null) FilledButton.icon(onPressed: () => _open('${c['map']}'), icon: const Icon(Icons.map_outlined, size: 18), label: const Text('Map')),
            OutlinedButton.icon(
              onPressed: () => _open('https://en.wikipedia.org/wiki/${Uri.encodeComponent('${c['name']}')}'),
              icon: const Icon(Icons.travel_explore_rounded, size: 18),
              label: const Text('Wikipedia'),
            ),
          ],
        ),
      ],
    );
  },
);

class _CountryGrid extends StatelessWidget {
  const _CountryGrid({required this.countries});
  final List<Map<String, dynamic>> countries;

  @override
  Widget build(BuildContext context) => _Frame(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.s),
          child: Row(
            children: [
              const Icon(Icons.public_rounded, size: 16, color: _space),
              const SizedBox(width: Space.s),
              Text('COUNTRIES · ${countries.length}', style: context.text.labelSmall),
            ],
          ),
        ),
        for (final (i, c) in countries.take(15).indexed)
          InkWell(
            onTap: () async {
              try {
                final full = await LibraryApi.instance.countryInfo('${c['code']}');
                if (context.mounted) await showCountry(context, full);
              } catch (e) {
                if (context.mounted) showSnack(context, 'Couldn\'t load ${c['name']}: $e', icon: Icons.error_outline_rounded);
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: 6),
              child: Row(
                children: [
                  SizedBox(width: 22, child: Text('${i + 1}', style: context.text.labelSmall)),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: c['flag'] == null ? Text('${c['flag_emoji'] ?? ''}') : NetImage('${c['flag']}', width: 36, height: 24, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('${c['capital'] ?? ''}${c['subregion'] == null ? '' : ' · ${c['subregion']}'}', style: context.text.bodySmall),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_n(c['population']), style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('${_n(c['area_km2'])} km²', style: context.text.labelSmall),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: Space.xs),
      ],
    ),
  );
}

// ---- NASA APOD -----------------------------------------------------------------------------

class _ApodCard extends StatelessWidget {
  const _ApodCard({required this.p});
  final Map<String, dynamic> p;

  @override
  Widget build(BuildContext context) {
    final video = p['media_type'] == 'video';
    return _Frame(
      child: InkWell(
        onTap: () => showApod(context, p),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                AspectRatio(
                  aspectRatio: 4 / 3,
                  child: p['thumbnail'] == null
                      ? Container(color: Colors.black, child: const Icon(Icons.auto_awesome_rounded, color: Colors.white54, size: 48))
                      : NetImage('${p['thumbnail']}', fit: BoxFit.cover, errorWidget: const ColoredBox(color: Colors.black)),
                ),
                if (video) const Icon(Icons.play_circle_fill_rounded, size: 56, color: Colors.white),
                Positioned(
                  left: Space.s,
                  top: Space.s,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(99)),
                    child: Text('NASA · ${p['date']}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(Space.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${p['title']}', style: context.text.titleMedium),
                  if (p['copyright'] != null) Text('© ${p['copyright']}', style: context.text.bodySmall),
                  const SizedBox(height: Space.s),
                  Text('${p['explanation'] ?? ''}', maxLines: 4, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApodGallery extends StatelessWidget {
  const _ApodGallery({required this.pictures});
  final List<Map<String, dynamic>> pictures;

  @override
  Widget build(BuildContext context) => _Frame(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.s),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, size: 16, color: _space),
              const SizedBox(width: Space.s),
              Text('ASTRONOMY PICTURES · ${pictures.length}', style: context.text.labelSmall),
            ],
          ),
        ),
        SizedBox(
          height: 190,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
            scrollDirection: Axis.horizontal,
            itemCount: pictures.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.s),
            itemBuilder: (context, i) {
              final p = pictures[i];
              return InkWell(
                onTap: () => showApod(context, p),
                child: SizedBox(
                  width: 150,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(Radii.m),
                        child: p['thumbnail'] == null
                            ? Container(width: 150, height: 120, color: Colors.black)
                            : NetImage('${p['thumbnail']}', width: 150, height: 120, fit: BoxFit.cover, errorWidget: Container(width: 150, height: 120, color: Colors.black)),
                      ),
                      const SizedBox(height: 4),
                      Text('${p['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                      Text('${p['date']}', style: context.text.labelSmall),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

/// The picture full size (pinch to zoom) with the full explanation.
Future<void> showApod(BuildContext context, Map<String, dynamic> p) => showAppSheet<void>(
  context,
  initialSize: 0.92,
  builder: (context, scroll) => ListView(
    controller: scroll,
    padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
    children: [
      Text('${p['title']}', style: context.text.titleLarge),
      Text([p['date'], if (p['copyright'] != null) '© ${p['copyright']}'].join(' · '), style: context.text.bodySmall),
      const SizedBox(height: Space.m),
      ClipRRect(
        borderRadius: BorderRadius.circular(Radii.l),
        child: Container(
          color: Colors.black,
          child: p['media_type'] == 'video'
              ? Stack(
                  alignment: Alignment.center,
                  children: [
                    if (p['thumbnail'] != null) NetImage('${p['thumbnail']}', fit: BoxFit.cover),
                    IconButton(
                      iconSize: 64,
                      color: Colors.white,
                      icon: const Icon(Icons.play_circle_fill_rounded),
                      onPressed: () => _open('${p['url']}'),
                    ),
                  ],
                )
              : InteractiveViewer(
                  maxScale: 5,
                  child: Image.network(
                    '${p['url']}',
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, progress) =>
                        progress == null ? child : const SizedBox(height: 240, child: Center(child: CircularProgressIndicator())),
                  ),
                ),
        ),
      ),
      const SizedBox(height: Space.m),
      Wrap(
        spacing: Space.s,
        runSpacing: Space.s,
        children: [
          if (p['hd_url'] != null) FilledButton.icon(onPressed: () => _open('${p['hd_url']}'), icon: const Icon(Icons.hd_rounded, size: 18), label: const Text('Full resolution')),
          OutlinedButton.icon(onPressed: () => _open('${p['page']}'), icon: const Icon(Icons.open_in_new_rounded, size: 18), label: const Text('APOD page')),
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: '${p['title']}\n${p['hd_url'] ?? p['url']}'));
              showSnack(context, 'Copied the link');
            },
            icon: const Icon(Icons.link_rounded, size: 18),
            label: const Text('Copy link'),
          ),
        ],
      ),
      const SizedBox(height: Space.l),
      SelectableText('${p['explanation'] ?? ''}', style: context.text.bodyMedium?.copyWith(height: 1.55)),
    ],
  ),
);
