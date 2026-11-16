import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../app/theme.dart';
import '../../core/widgets/app_sheet.dart';
import '../assistant/device_events.dart';
import '../assistant/places.dart';
import 'routines.dart';

/// Edits a routine's "At a place" trigger: the place (from where you are, an
/// address search, your saved places or a pasted link), what happens there
/// (arrive, leave, stay a while), and when it may run.
class LocationTriggerEditor extends ConsumerStatefulWidget {
  const LocationTriggerEditor({super.key, required this.trigger, required this.onChanged});
  final RoutineTrigger trigger;
  final ValueChanged<RoutineTrigger> onChanged;

  @override
  ConsumerState<LocationTriggerEditor> createState() => _LocationTriggerEditorState();
}

class _LocationTriggerEditorState extends ConsumerState<LocationTriggerEditor> with WidgetsBindingObserver {
  late final _name = TextEditingController(text: _place.placeName);
  bool _locating = false;
  Position? _here;
  LocationPermission? _permission;
  bool _servicesOn = true;
  String? _address;

  RoutineTrigger get t => widget.trigger;
  DeviceCondition get _place => t.place ?? const DeviceCondition(kind: DeviceTriggerKind.arrive);

  void _set(DeviceCondition c) => widget.onChanged(t.copyWith(place: c));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_checkPermission());
    if (_place.hasPlace) unawaited(_lookUpAddress());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from Android's settings: look again.
    if (state == AppLifecycleState.resumed) unawaited(_checkPermission());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _name.dispose();
    super.dispose();
  }

  Future<void> _checkPermission() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      final on = await Geolocator.isLocationServiceEnabled();
      final p = await Geolocator.checkPermission();
      Position? last;
      if (p == LocationPermission.always || p == LocationPermission.whileInUse) last = await Geolocator.getLastKnownPosition();
      if (mounted) {
        setState(() {
          _servicesOn = on;
          _permission = p;
          _here ??= last;
        });
      }
    } catch (_) {}
  }

  Future<void> _lookUpAddress() async {
    final p = _place;
    if (!p.hasPlace) return;
    final a = await addressAt(p.lat!, p.lng!);
    if (mounted && a != null) setState(() => _address = a);
  }

  void _usePoint(double lat, double lng, {String? name, String? address, int? radius}) {
    if (name != null && name.isNotEmpty && _name.text.trim().isEmpty) _name.text = name;
    _set(_place.copyWith(lat: lat, lng: lng, placeName: _name.text.trim().isEmpty ? (name ?? '') : _name.text.trim(), radius: radius));
    setState(() => _address = address);
    if (address == null) unawaited(_lookUpAddress());
  }

  Future<void> _useHere() async {
    setState(() => _locating = true);
    try {
      final pos = await currentPosition();
      setState(() => _here = pos);
      _usePoint(pos.latitude, pos.longitude);
      if (mounted) showSnack(context, 'Place set to where you are (±${pos.accuracy.round()} m)', icon: Icons.my_location_rounded);
    } catch (e) {
      if (mounted) showSnack(context, '$e', icon: Icons.location_off_outlined);
    } finally {
      if (mounted) setState(() => _locating = false);
      unawaited(_checkPermission());
    }
  }

  Future<void> _search() async {
    final hit = await showAppSheet<GeoHit>(
      context,
      initialSize: 0.8,
      builder: (context, scroll) => _AddressSearch(scroll: scroll, near: _here == null ? null : (lat: _here!.latitude, lng: _here!.longitude)),
    );
    if (hit != null) _usePoint(hit.lat, hit.lng, name: hit.name, address: hit.address);
  }

  Future<void> _paste() async {
    final clip = (await Clipboard.getData('text/plain'))?.text ?? '';
    if (!mounted) return;
    final c = TextEditingController(text: parseLatLng(clip) != null ? clip : '');
    final text = await showFormSheet<String>(
      context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Paste a location', style: context.text.titleMedium),
          const SizedBox(height: Space.xs),
          Text('Coordinates like "9.0301, 38.7469", or a Google Maps or OpenStreetMap link.', style: context.text.bodySmall),
          const SizedBox(height: Space.m),
          TextField(controller: c, autofocus: true, maxLines: 3, minLines: 1, decoration: const InputDecoration(hintText: 'Latitude, longitude or a map link')),
          const SizedBox(height: Space.l),
          FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Use it')),
        ],
      ),
    );
    if (text == null) return;
    final p = parseLatLng(text);
    if (p == null) {
      if (mounted) showSnack(context, 'No coordinates found in that', icon: Icons.info_outline_rounded);
      return;
    }
    _usePoint(p.lat, p.lng);
  }

  Future<void> _saved() async {
    final picked = await showAppSheet<SavedPlace>(context, initialSize: 0.6, builder: (context, scroll) => _SavedPlaces(scroll: scroll));
    if (picked != null) {
      _name.text = picked.name;
      _usePoint(picked.lat, picked.lng, name: picked.name, address: picked.address.isEmpty ? null : picked.address, radius: picked.radius);
    }
  }

  Future<void> _saveToPlaces() async {
    final p = _place;
    if (!p.hasPlace) return;
    final name = _name.text.trim().isEmpty ? 'Place' : _name.text.trim();
    await ref.read(savedPlacesProvider.notifier).put(SavedPlace(id: SavedPlacesStore.newId(), name: name, lat: p.lat!, lng: p.lng!, radius: p.radius, address: _address ?? ''));
    if (mounted) showSnack(context, 'Saved "$name" to your places');
  }

  Future<void> _pickTime(bool start) async {
    final cur = start ? (t.from.isEmpty ? '08:00' : t.from) : (t.until.isEmpty ? '20:00' : t.until);
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: int.parse(cur.substring(0, 2)), minute: int.parse(cur.substring(3))));
    if (picked == null) return;
    final v = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    widget.onChanged(start ? t.copyWith(from: v, until: t.until.isEmpty ? '20:00' : null) : t.copyWith(until: v, from: t.from.isEmpty ? '08:00' : null));
  }

  @override
  Widget build(BuildContext context) {
    final p = _place;
    final saved = ref.watch(savedPlacesProvider);
    final distance = (_here != null && p.hasPlace) ? Geolocator.distanceBetween(_here!.latitude, _here!.longitude, p.lat!, p.lng!) : null;
    final inside = distance != null && distance <= p.radius;
    final window = t.from.isNotEmpty && t.until.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<DeviceTriggerKind>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: DeviceTriggerKind.arrive, icon: Icon(Icons.login_rounded, size: 18), label: Text('Arrive')),
            ButtonSegment(value: DeviceTriggerKind.leave, icon: Icon(Icons.logout_rounded, size: 18), label: Text('Leave')),
            ButtonSegment(value: DeviceTriggerKind.stay, icon: Icon(Icons.hourglass_bottom_rounded, size: 18), label: Text('Stay')),
          ],
          selected: {p.kind.needsPlace ? p.kind : DeviceTriggerKind.arrive},
          onSelectionChanged: (s) => _set(p.copyWith(kind: s.first)),
        ),
        const SizedBox(height: Space.s),
        Text(
          switch (p.kind) {
            DeviceTriggerKind.leave => 'Runs when the phone moves out of the circle.',
            DeviceTriggerKind.stay => 'Runs once you have been inside the circle for ${p.dwellMinutes} minutes.',
            _ => 'Runs when the phone comes into the circle.',
          },
          style: context.text.bodySmall,
        ),
        const SizedBox(height: Space.m),
        // ---- the place ----
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: AppColors.line)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 172,
                child: p.hasPlace
                    ? PlaceMap(lat: p.lat!, lng: p.lng!, radius: p.radius, here: _here == null ? null : (lat: _here!.latitude, lng: _here!.longitude))
                    : _NoPlace(onHere: _locating ? null : _useHere),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.xs),
                child: TextField(
                  controller: _name,
                  onChanged: (x) => _set(p.copyWith(placeName: x.trim())),
                  decoration: const InputDecoration(labelText: 'Place name', hintText: 'Home, Work, Gym…', isDense: true, prefixIcon: Icon(Icons.label_outline_rounded, size: 20)),
                ),
              ),
              if (p.hasPlace)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _address ?? '${p.lat!.toStringAsFixed(5)}, ${p.lng!.toStringAsFixed(5)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall,
                        ),
                      ),
                      if (distance != null)
                        Container(
                          margin: const EdgeInsets.only(left: Space.s),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (inside ? AppColors.success : AppColors.text3).withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            inside ? 'You\'re here' : '${distanceText(distance)} away',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: inside ? AppColors.success : AppColors.text2),
                          ),
                        ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(Space.s),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _Action(icon: Icons.my_location_rounded, label: 'Where I am', busy: _locating, onTap: _locating ? null : _useHere),
                    _Action(icon: Icons.search_rounded, label: 'Search', onTap: _search),
                    _Action(icon: Icons.bookmarks_outlined, label: saved.isEmpty ? 'Saved' : 'Saved · ${saved.length}', onTap: _saved),
                    _Action(icon: Icons.content_paste_rounded, label: 'Paste', onTap: _paste),
                    if (p.hasPlace) _Action(icon: Icons.bookmark_add_outlined, label: 'Save place', onTap: _saveToPlaces),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (saved.isNotEmpty) ...[
          const SizedBox(height: Space.s),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final s in saved)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: const VisualDensity(horizontal: -1, vertical: -3),
                      avatar: Text(s.emoji),
                      label: Text(s.name),
                      selected: p.hasPlace && (p.lat! - s.lat).abs() < 1e-6 && (p.lng! - s.lng).abs() < 1e-6,
                      onSelected: (_) {
                        _name.text = s.name;
                        _usePoint(s.lat, s.lng, name: s.name, address: s.address.isEmpty ? null : s.address, radius: s.radius);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: Space.l),
        Row(
          children: [
            Expanded(child: Text('Counts as there within ${distanceText(p.radius.toDouble())}', style: context.text.titleSmall)),
          ],
        ),
        Slider(
          min: 50,
          max: 2000,
          divisions: 39,
          value: p.radius.clamp(50, 2000).toDouble(),
          label: distanceText(p.radius.toDouble()),
          onChanged: (x) => _set(p.copyWith(radius: (x / 50).round() * 50)),
        ),
        Text('Under 100 m can miss: GPS indoors is often off by 30–80 m.', style: context.text.bodySmall),
        if (p.kind == DeviceTriggerKind.stay) ...[
          const SizedBox(height: Space.l),
          Text('Stay for', style: context.text.titleSmall),
          const SizedBox(height: Space.s),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final m in const [5, 10, 15, 30, 45, 60, 120, 240])
                ChoiceChip(
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: const VisualDensity(horizontal: -1, vertical: -3),
                  label: Text(m < 60 ? '$m min' : '${m ~/ 60} h'),
                  selected: p.dwellMinutes == m,
                  onSelected: (_) => _set(p.copyWith(dwellMinutes: m)),
                ),
            ],
          ),
        ],
        const SizedBox(height: Space.l),
        Text('On', style: context.text.titleSmall),
        const SizedBox(height: Space.s),
        Wrap(
          spacing: 4,
          children: [
            for (final (i, d) in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'].indexed)
              FilterChip(
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: const VisualDensity(horizontal: -1, vertical: -3),
                showCheckmark: false,
                label: Text(d),
                selected: t.days.contains(i + 1),
                onSelected: (on) {
                  final days = {...t.days};
                  on ? days.add(i + 1) : days.remove(i + 1);
                  if (days.isNotEmpty) widget.onChanged(t.copyWith(days: days));
                },
              ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Only at certain hours'),
          subtitle: Text(window ? 'Between ${t.from} and ${t.until}' : 'Any time of day', style: context.text.bodySmall),
          value: window,
          onChanged: (v) => widget.onChanged(v ? t.copyWith(from: '08:00', until: '20:00') : RoutineTrigger.fromJson({...t.toJson()..remove('from')..remove('until')})),
        ),
        if (window)
          Row(
            children: [
              Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.wb_twilight_rounded, size: 18), label: Text('From ${t.from}'), onPressed: () => _pickTime(true))),
              const SizedBox(width: Space.s),
              Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.nights_stay_outlined, size: 18), label: Text('Until ${t.until}'), onPressed: () => _pickTime(false))),
            ],
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('At most once a day'),
          subtitle: Text('Coming and going all day won\'t run it again', style: context.text.bodySmall),
          value: t.oncePerDay,
          onChanged: (v) => widget.onChanged(t.copyWith(oncePerDay: v)),
        ),
        const SizedBox(height: Space.s),
        _PermissionNote(servicesOn: _servicesOn, permission: _permission, onFix: () async {
          if (!_servicesOn) {
            await Geolocator.openLocationSettings();
          } else if (_permission == LocationPermission.denied) {
            await Geolocator.requestPermission();
            await _checkPermission();
          } else {
            await Geolocator.openAppSettings();
          }
        }),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, this.onTap, this.busy = false});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) => ActionChip(
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: const VisualDensity(horizontal: -1, vertical: -2),
    avatar: busy ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(icon, size: 16, color: AppColors.text),
    label: Text(label),
    onPressed: onTap,
  );
}

class _NoPlace extends StatelessWidget {
  const _NoPlace({this.onHere});
  final VoidCallback? onHere;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.surface2, AppColors.surface]),
    ),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.travel_explore_rounded, size: 38, color: AppColors.text3),
          const SizedBox(height: Space.s),
          Text('No place yet', style: context.text.titleSmall),
          const SizedBox(height: 2),
          Text('Use where you are, or search an address', style: context.text.bodySmall),
          const SizedBox(height: Space.m),
          FilledButton.icon(
            style: FilledButton.styleFrom(shape: const StadiumBorder(), visualDensity: VisualDensity.compact),
            onPressed: onHere,
            icon: const Icon(Icons.my_location_rounded, size: 18),
            label: const Text('Where I am'),
          ),
        ],
      ),
    ),
  );
}

class _PermissionNote extends StatelessWidget {
  const _PermissionNote({required this.servicesOn, required this.permission, required this.onFix});
  final bool servicesOn;
  final LocationPermission? permission;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return Text('Place triggers work on Android.', style: context.text.bodySmall?.copyWith(color: AppColors.warning));
    }
    final (ok, text, action) = switch ((servicesOn, permission)) {
      (false, _) => (false, 'Location is turned off on this phone.', 'Turn on'),
      (_, LocationPermission.always) => (true, 'Location is allowed all the time: this works with the screen off.', null),
      (_, LocationPermission.whileInUse) => (false, 'Allowed only while the app is open. Choose "Allow all the time" so it works in your pocket.', 'Allow all the time'),
      (_, LocationPermission.deniedForever) => (false, 'Location is blocked for Triangle.', 'Open settings'),
      (_, LocationPermission.denied) => (false, 'Triangle can\'t see where the phone is yet.', 'Allow'),
      _ => (true, 'Checks where the phone is every couple of minutes while Triangle runs in the background.', null),
    };
    final color = ok ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.xs, Space.s),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(Radii.m)),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle_outline_rounded : Icons.location_disabled_outlined, size: 20, color: color),
          const SizedBox(width: Space.s),
          Expanded(child: Text(text, style: context.text.bodySmall)),
          if (action != null) TextButton(onPressed: onFix, child: Text(action)),
        ],
      ),
    );
  }
}

/// A small map of a place: OpenStreetMap tiles in the app's colours, the
/// circle that counts as "there", and where you are when known.
class PlaceMap extends StatelessWidget {
  const PlaceMap({super.key, required this.lat, required this.lng, required this.radius, this.here, this.color});
  final double lat;
  final double lng;
  final int radius;
  final ({double lat, double lng})? here;
  final Color? color;

  static const _tile = 256.0;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? AppLook.brand(AppColors.accent);
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth, h = c.maxHeight;
        // The closest zoom where the circle still fits with room around it.
        var zoom = 18;
        while (zoom > 3 && radius / metresPerPixel(lat, zoom) > h * 0.32) {
          zoom--;
        }
        final t = tileFor(lat, lng, zoom);
        final px = (t.x + t.fx) * _tile, py = (t.y + t.fy) * _tile;
        final left = px - w / 2, top = py - h / 2;
        final n = 1 << zoom;
        final tiles = <Widget>[
          for (var ty = (top / _tile).floor(); ty <= ((top + h) / _tile).floor(); ty++)
            for (var tx = (left / _tile).floor(); tx <= ((left + w) / _tile).floor(); tx++)
              if (ty >= 0 && ty < n)
                Positioned(
                  left: tx * _tile - left,
                  top: ty * _tile - top,
                  width: _tile,
                  height: _tile,
                  child: Image.network(
                    'https://tile.openstreetmap.org/$zoom/${tx % n}/$ty.png',
                    headers: const {'User-Agent': 'Triangle/1.0 (Flutter; routine place preview)'},
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => ColoredBox(color: AppColors.surface2),
                  ),
                ),
        ];
        final rPx = radius / metresPerPixel(lat, zoom);
        Offset? you;
        if (here != null) {
          final y = tileFor(here!.lat, here!.lng, zoom);
          you = Offset((y.x + y.fx) * _tile - left, (y.y + y.fy) * _tile - top);
          if (you.dx < -20 || you.dy < -20 || you.dx > w + 20 || you.dy > h + 20) you = null;
        }
        // Greyscale, and dimmed and flipped for the dark theme, so the map
        // sits quietly in the app's palette.
        final grey = <double>[0.2126, 0.7152, 0.0722, 0, 0, 0.2126, 0.7152, 0.0722, 0, 0, 0.2126, 0.7152, 0.0722, 0, 0, 0, 0, 0, 1, 0];
        final dark = <double>[-0.2126 * 0.85, -0.7152 * 0.85, -0.0722 * 0.85, 0, 235, -0.2126 * 0.85, -0.7152 * 0.85, -0.0722 * 0.85, 0, 235, -0.2126 * 0.85, -0.7152 * 0.85, -0.0722 * 0.85, 0, 240, 0, 0, 0, 1, 0];
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(child: ColoredBox(color: AppColors.surface2)),
            Positioned.fill(
              child: ColorFiltered(colorFilter: ColorFilter.matrix(AppColors.isLight ? grey : dark), child: Stack(children: tiles)),
            ),
            Positioned.fill(
              child: CustomPaint(painter: _CirclePainter(center: Offset(w / 2, h / 2), radius: rPx, color: accent, you: you)),
            ),
            Positioned(
              left: w / 2 - 14,
              top: h / 2 - 30,
              child: Icon(Icons.location_on_rounded, size: 28, color: accent, shadows: const [Shadow(color: Colors.black38, blurRadius: 6)]),
            ),
            Positioned(
              right: 6,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: AppColors.bg.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(4)),
                child: Text('© OpenStreetMap', style: TextStyle(fontSize: 9, color: AppColors.text2)),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CirclePainter extends CustomPainter {
  _CirclePainter({required this.center, required this.radius, required this.color, this.you});
  final Offset center;
  final double radius;
  final Color color;
  final Offset? you;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(center, radius, Paint()..color = color.withValues(alpha: 0.16));
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final y = you;
    if (y != null) {
      canvas.drawCircle(y, 11, Paint()..color = const Color(0xFF2F80ED).withValues(alpha: 0.22));
      canvas.drawCircle(y, 6.5, Paint()..color = Colors.white);
      canvas.drawCircle(y, 4.5, Paint()..color = const Color(0xFF2F80ED));
    }
  }

  @override
  bool shouldRepaint(covariant _CirclePainter old) => old.center != center || old.radius != radius || old.color != color || old.you != you;
}

class _AddressSearch extends StatefulWidget {
  const _AddressSearch({required this.scroll, this.near});
  final ScrollController scroll;
  final ({double lat, double lng})? near;

  @override
  State<_AddressSearch> createState() => _AddressSearchState();
}

class _AddressSearchState extends State<_AddressSearch> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<GeoHit> _hits = const [];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _changed(String v) {
    _debounce?.cancel();
    if (v.trim().length < 3) return setState(() => _hits = const []);
    _debounce = Timer(const Duration(milliseconds: 600), () => _run(v));
  }

  Future<void> _run(String v) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final hits = await searchPlaces(v, near: widget.near);
      if (mounted && _q.text == v) setState(() => _hits = hits);
    } catch (e) {
      if (mounted) setState(() => _error = 'The address search isn\'t answering. Try again in a moment.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l),
        child: TextField(
          controller: _q,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _changed,
          onSubmitted: _run,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: 'An address, landmark or business',
            suffixIcon: _busy ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
          ),
        ),
      ),
      if (_error != null) Padding(padding: const EdgeInsets.all(Space.l), child: Text(_error!, style: context.text.bodySmall?.copyWith(color: AppColors.warning))),
      Expanded(
        child: ListView(
          controller: widget.scroll,
          children: [
            for (final h in _hits)
              ListTile(
                leading: lead(const Icon(Icons.place_outlined)),
                title: Text(h.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(h.address, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                onTap: () => Navigator.pop(context, h),
              ),
            if (_hits.isEmpty && !_busy && _q.text.trim().length >= 3 && _error == null)
              Padding(padding: const EdgeInsets.all(Space.xl), child: Text('No places found.', textAlign: TextAlign.center, style: context.text.bodySmall)),
            Padding(
              padding: const EdgeInsets.all(Space.l),
              child: Text('Search by OpenStreetMap. What you type is sent to it.', textAlign: TextAlign.center, style: context.text.labelSmall),
            ),
          ],
        ),
      ),
    ],
  );
}

class _SavedPlaces extends ConsumerWidget {
  const _SavedPlaces({required this.scroll});
  final ScrollController scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final places = ref.watch(savedPlacesProvider);
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
      children: [
        Text('Your places', style: context.text.titleMedium),
        const SizedBox(height: Space.xs),
        Text('Places you save here can be picked for any routine.', style: context.text.bodySmall),
        const SizedBox(height: Space.m),
        if (places.isEmpty)
          Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: Text('No saved places yet. Set a place, then tap "Save place".', textAlign: TextAlign.center, style: context.text.bodySmall),
          ),
        for (final p in places)
          Card(
            margin: const EdgeInsets.only(bottom: Space.s),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.pop(context, p),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: 96, child: IgnorePointer(child: PlaceMap(lat: p.lat, lng: p.lng, radius: p.radius))),
                  ListTile(
                    leading: Text(p.emoji, style: const TextStyle(fontSize: 22)),
                    title: Text(p.name),
                    subtitle: Text(p.address.isEmpty ? '${p.lat.toStringAsFixed(4)}, ${p.lng.toStringAsFixed(4)} · ${distanceText(p.radius.toDouble())}' : p.address, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                    trailing: IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () => ref.read(savedPlacesProvider.notifier).remove(p.id),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
