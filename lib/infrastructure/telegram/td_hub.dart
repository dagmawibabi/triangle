import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:handy_tdlib/handy_tdlib.dart' show TdPlugin;

import 'td_library.dart';
import 'td_receiver.dart';

/// The process's one TDLib receive loop, shared by every account.
///
/// TDLib's JSON interface hands out updates for all client ids through a
/// single `td_receive`, which must never run on two threads at once
/// (td_json_client.h). So each account's [TelegramClient] has its own client
/// id, but they all hear from this one receiver; each keeps only the payloads
/// whose `@client_id` is its own.
class TdHub {
  late final _receiver = TdReceiver(onPayload: _dispatch);
  final Set<void Function(Map<String, dynamic>)> _listeners = {};
  Future<void>? _starting;

  /// Loads TDLib and starts the receive loop, once per process.
  Future<void> start() => _starting ??= () async {
    await openTdLibrary();
    TdPlugin.instance.tdExecute(
      jsonEncode(const td.SetLogVerbosityLevel(newVerbosityLevel: 1).toJson()),
    );
    await _receiver.start();
  }().catchError((Object e) {
    _starting = null;
    throw e;
  });

  void _dispatch(Map<String, dynamic> payload) {
    for (final l in List.of(_listeners)) {
      l(payload);
    }
  }

  void Function() listen(void Function(Map<String, dynamic>) onPayload) {
    _listeners.add(onPayload);
    return () => _listeners.remove(onPayload);
  }

  Future<void> stop() async {
    _starting = null;
    await _receiver.stop();
  }
}

final tdHubProvider = Provider<TdHub>((ref) {
  final hub = TdHub();
  ref.onDispose(hub.stop);
  return hub;
});
