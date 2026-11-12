import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Keys for the lookup and sports tools that take one: metals.dev for gold
// and other metals, an optional LibreTranslate server, football-data.org
// for top scorers and an optional TheSportsDB key. Kept in the phone's
// secure storage, like the app's other keys.

class InfoKeys {
  const InfoKeys({
    this.metalsKey = '',
    this.libreUrl = '',
    this.libreKey = '',
    this.useLibre = false,
    this.footballDataKey = '',
    this.sportsDbKey = '',
  });
  final String metalsKey;
  final String libreUrl;
  final String libreKey;

  /// Translate with LibreTranslate instead of MyMemory.
  final bool useLibre;

  /// football-data.org (free tier) for top scorers.
  final String footballDataKey;

  /// TheSportsDB; empty uses the shared free key.
  final String sportsDbKey;

  bool get hasMetalsKey => metalsKey.trim().isNotEmpty;
  bool get libreReady => useLibre && libreUrl.trim().isNotEmpty;
  bool get hasFootballDataKey => footballDataKey.trim().isNotEmpty;

  InfoKeys copyWith({String? metalsKey, String? libreUrl, String? libreKey, bool? useLibre, String? footballDataKey, String? sportsDbKey}) => InfoKeys(
    metalsKey: metalsKey ?? this.metalsKey,
    libreUrl: libreUrl ?? this.libreUrl,
    libreKey: libreKey ?? this.libreKey,
    useLibre: useLibre ?? this.useLibre,
    footballDataKey: footballDataKey ?? this.footballDataKey,
    sportsDbKey: sportsDbKey ?? this.sportsDbKey,
  );
}

class InfoKeysNotifier extends Notifier<InfoKeys> {
  static const _storage = FlutterSecureStorage();
  static const _metals = 'info_metals_key',
      _libreUrl = 'info_libre_url',
      _libreKey = 'info_libre_key',
      _useLibre = 'info_use_libre',
      _footballData = 'sports_football_data_key',
      _sportsDb = 'sports_thesportsdb_key';

  /// Loaded once; until then the tools see empty keys.
  static InfoKeys current = const InfoKeys();
  static Future<InfoKeys>? _loading;

  static Future<InfoKeys> load() => _loading ??= () async {
    try {
      current = InfoKeys(
        metalsKey: await _storage.read(key: _metals) ?? '',
        libreUrl: await _storage.read(key: _libreUrl) ?? '',
        libreKey: await _storage.read(key: _libreKey) ?? '',
        useLibre: await _storage.read(key: _useLibre) == 'true',
        footballDataKey: await _storage.read(key: _footballData) ?? '',
        sportsDbKey: await _storage.read(key: _sportsDb) ?? '',
      );
    } catch (_) {}
    return current;
  }();

  @override
  InfoKeys build() {
    load().then((k) => state = k);
    return current;
  }

  Future<void> _save(InfoKeys k, String key, String value) async {
    state = current = k;
    await _storage.write(key: key, value: value);
  }

  Future<void> setMetalsKey(String v) => _save(state.copyWith(metalsKey: v.trim()), _metals, v.trim());
  Future<void> setLibreUrl(String v) => _save(state.copyWith(libreUrl: v.trim()), _libreUrl, v.trim());
  Future<void> setLibreKey(String v) => _save(state.copyWith(libreKey: v.trim()), _libreKey, v.trim());
  Future<void> setUseLibre(bool v) => _save(state.copyWith(useLibre: v), _useLibre, '$v');
  Future<void> setFootballDataKey(String v) => _save(state.copyWith(footballDataKey: v.trim()), _footballData, v.trim());
  Future<void> setSportsDbKey(String v) => _save(state.copyWith(sportsDbKey: v.trim()), _sportsDb, v.trim());
}

final infoKeysProvider = NotifierProvider<InfoKeysNotifier, InfoKeys>(InfoKeysNotifier.new);
