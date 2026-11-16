import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../settings/data/settings.dart';
import '../../infrastructure/telegram/accounts.dart';
import '../telegram/data/telegram_store.dart';
import 'package:omni_ai/omni_ai.dart' show AiException, ComposioClient, ConnectedApp;

import '../ai/data/ai.dart';

class IntegrationsState {
  const IntegrationsState({this.accounts = const [], this.loading = false, this.error, this.checkedAt, this.connecting});

  /// Every account the user connected, active or not.
  final List<ConnectedApp> accounts;
  final bool loading;
  final String? error;
  final DateTime? checkedAt;

  /// The toolkit a connect link was just opened for.
  final String? connecting;

  /// Toolkit slugs with a working connection.
  Set<String> get connected => {for (final a in accounts) if (a.active) a.toolkit};

  ConnectedApp? accountFor(String toolkit) =>
      accounts.where((a) => a.toolkit == toolkit && a.active).firstOrNull ?? accounts.where((a) => a.toolkit == toolkit).firstOrNull;

  IntegrationsState copyWith({
    List<ConnectedApp>? accounts,
    bool? loading,
    String? error,
    bool clearError = false,
    DateTime? checkedAt,
    String? connecting,
    bool clearConnecting = false,
  }) => IntegrationsState(
    accounts: accounts ?? this.accounts,
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
    checkedAt: checkedAt ?? this.checkedAt,
    connecting: clearConnecting ? null : (connecting ?? this.connecting),
  );
}

/// The user's Composio connections: which apps are connected, connecting
/// a new one (Composio's sign-in page opens in the browser), and removing one.
class IntegrationsController extends Notifier<IntegrationsState> {
  String? _lastKey;

  @override
  IntegrationsState build() {
    final key = ref.watch(settingsProvider.select((s) => s.composioKey));
    final loaded = ref.watch(settingsProvider.select((s) => s.loaded));
    if (loaded && key.isNotEmpty && key != _lastKey) {
      _lastKey = key;
      Future.microtask(refresh);
    }
    if (key.isEmpty) _lastKey = null;
    return const IntegrationsState();
  }

  /// This person's Composio user id. Made once, from their Telegram id when
  /// it is known so the same key finds the same connections after a
  /// reinstall.
  Future<String> userId() async {
    final s = ref.read(settingsProvider);
    if (s.composioUserId.isNotEmpty) return s.composioUserId;
    // The first account signed in, not whichever is on screen, so the same
    // person gets the same id however many accounts they've added.
    final first = ref.read(accountsProvider).signedIn.firstOrNull;
    final me = first == null ? ref.read(telegramStoreProvider).me : ref.read(telegramStoreFamily(first.id)).me;
    final id = me != null ? 'teleai-tg-${me.id}' : 'teleai-${const Uuid().v4()}';
    await ref.read(settingsProvider.notifier).setComposioUserId(id);
    return id;
  }

  Future<ComposioClient?> client() async {
    final s = ref.read(settingsProvider);
    if (!s.hasComposioKey) return null;
    // omni_ai's Composio client, with the key from Settings.
    return ref.read(aiProvider).composio.client
      ..apiKey = s.composioKey
      ..userId = await userId();
  }

  Future<void> refresh() async {
    final c = await client();
    if (c == null) {
      state = const IntegrationsState();
      return;
    }
    state = state.copyWith(loading: true, clearError: true);
    try {
      final accounts = await c.connections();
      state = state.copyWith(accounts: accounts, loading: false, checkedAt: DateTime.now());
    } catch (e) {
      debugPrint('[Integrations] $e');
      state = state.copyWith(loading: false, error: '$e');
    }
  }

  /// Opens Composio's sign-in page for [toolkit]. Returns an error, or null.
  Future<String?> connect(String toolkit) async {
    final c = await client();
    if (c == null) return 'Add your Composio API key in Settings → AI & models first.';
    try {
      final url = await c.connectLink(toolkit);
      state = state.copyWith(connecting: toolkit);
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return ok ? null : 'Could not open the browser.';
    } catch (e) {
      return '$e';
    }
  }

  /// A connect link for the chat's connect card.
  Future<String> linkFor(String toolkit) async {
    final c = await client();
    if (c == null) throw const AiException('Add your Composio API key in Settings first.', provider: 'composio');
    return c.connectLink(toolkit);
  }

  /// Back from the browser: see whether the connection went through.
  Future<void> returned() async {
    if (state.connecting == null) return;
    await refresh();
    state = state.copyWith(clearConnecting: true);
  }

  Future<String?> disconnect(String toolkit) async {
    final c = await client();
    final account = state.accountFor(toolkit);
    if (c == null || account == null) return null;
    try {
      for (final a in state.accounts.where((a) => a.toolkit == toolkit)) {
        await c.disconnect(a.id);
      }
      state = state.copyWith(accounts: state.accounts.where((a) => a.toolkit != toolkit).toList());
      return null;
    } catch (e) {
      return '$e';
    }
  }
}

final integrationsProvider = NotifierProvider<IntegrationsController, IntegrationsState>(IntegrationsController.new);
