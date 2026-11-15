import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:omni_ai/omni_ai.dart' show OmniAI;

/// The Vapi phone-call settings, kept in secure storage: the key, whose
/// behalf calls are made on, and the country code for numbers written
/// without one. [apply] hands them to omni_ai's Vapi toolkit.
abstract final class VapiStore {
  static const _storage = FlutterSecureStorage();
  static const _key = 'triangle.vapi.v1';

  static String key = '';
  static String onBehalfOf = '';
  static String countryCode = '';
  static String voice = 'Elliot';
  static int maxMinutes = 10;

  /// The Vapi number calls are made from; empty uses the account's first.
  static String phoneNumberId = '';

  static Future<void>? _loading;

  static bool get ready => key.trim().isNotEmpty;

  static Future<void> load() => _loading ??= _read();

  /// Drops what was loaded, so the next [load] reads storage again (after
  /// a profile is restored or the data is cleared).
  static void forget() {
    _loading = null;
    key = onBehalfOf = countryCode = phoneNumberId = '';
    voice = 'Elliot';
    maxMinutes = 10;
  }

  static Future<void> _read() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map;
      key = '${j['key'] ?? ''}';
      onBehalfOf = '${j['on_behalf_of'] ?? ''}';
      countryCode = '${j['country'] ?? ''}';
      voice = '${j['voice'] ?? 'Elliot'}';
      maxMinutes = (j['max_minutes'] as num?)?.toInt() ?? 10;
      phoneNumberId = '${j['from_number'] ?? ''}';
    } catch (e) {
      debugPrint('[Vapi] $e');
    }
  }

  static Future<void> save({String? key, String? onBehalfOf, String? countryCode, String? voice, int? maxMinutes, String? phoneNumberId}) async {
    await load();
    if (key != null) VapiStore.key = key.trim();
    if (onBehalfOf != null) VapiStore.onBehalfOf = onBehalfOf.trim();
    if (countryCode != null) VapiStore.countryCode = countryCode.trim();
    if (voice != null) VapiStore.voice = voice;
    if (maxMinutes != null) VapiStore.maxMinutes = maxMinutes;
    if (phoneNumberId != null) VapiStore.phoneNumberId = phoneNumberId;
    await _storage.write(
      key: _key,
      value: jsonEncode({
        'key': VapiStore.key,
        'on_behalf_of': VapiStore.onBehalfOf,
        'country': VapiStore.countryCode,
        'voice': VapiStore.voice,
        'max_minutes': VapiStore.maxMinutes,
        'from_number': VapiStore.phoneNumberId,
      }),
    );
  }

  /// Gives omni_ai's Vapi toolkit the saved settings.
  static void apply(OmniAI ai) {
    final v = ai.vapi;
    v.apiKey = key.isEmpty ? null : key;
    v.onBehalfOf = onBehalfOf.isEmpty ? null : onBehalfOf;
    v.defaultCountryCode = countryCode.isEmpty ? null : countryCode;
    v.voiceId = voice;
    v.maxCallMinutes = maxMinutes;
    v.phoneNumberId = phoneNumberId.isEmpty ? null : phoneNumberId;
  }
}

/// The call tools omni_ai's Vapi toolkit offers.
const vapiToolNames = {
  'place_phone_call',
  'place_phone_calls',
  'get_phone_call',
  'list_phone_calls',
  'control_phone_call',
  'phone_call_recording',
  'list_phone_numbers',
};
