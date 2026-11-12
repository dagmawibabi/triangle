import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether money amounts are hidden, in the Finance screen and the chat's
/// money cards: each shows a random 5-digit stand-in instead (see
/// fmtAmount). One setting for both, kept across restarts.
///
/// The finance formatters read [hidden] directly, so toggling rebuilds the
/// whole widget tree in place (as a hot reload would): every amount on
/// screen changes at once and no state such as scroll or selection is lost.
abstract final class FinPrivacy {
  static bool hidden = false;
  static const _key = 'finance_hide_amounts';
  static bool _loaded = false;

  /// Reads the saved choice, once.
  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final v = (await SharedPreferences.getInstance()).getBool(_key) ?? false;
      if (v != hidden) {
        hidden = v;
        _rebuildAll();
      }
    } catch (_) {
      // No preferences (tests): amounts stay shown.
    }
  }

  static Future<void> set(bool value) async {
    if (value == hidden) return;
    hidden = value;
    _rebuildAll();
    try {
      await (await SharedPreferences.getInstance()).setBool(_key, value);
    } catch (_) {}
  }

  static Future<void> toggle() => set(!hidden);

  static void _rebuildAll() {
    void mark(Element e) {
      e.markNeedsBuild();
      e.visitChildren(mark);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(mark);
  }
}
