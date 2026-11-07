import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/assistant/watch_engine.dart';
import '../features/telegram/data/telegram_store.dart';
import '../infrastructure/telegram/accounts.dart';
import '../infrastructure/telegram/telegram_client.dart';

/// What runs whether or not a screen is showing: TDLib, the store that
/// mirrors it, and (once signed in) the watches, reminders and briefs.
///
/// Android may start the app's process with no screen at all (after a
/// reboot, or to restart the background service), so none of this may wait
/// for a widget to be built.
void startRuntime(ProviderContainer container) {
  // The store listens from the first update, so nothing TDLib reports
  // before a screen opens is missed.
  container.read(telegramStoreProvider);
  container.read(telegramClientProvider).start().catchError((_) {});
  // Every other signed-in account runs too, so switching is instant and
  // the assistant can reach them. Each is its own TDLib instance, sharing
  // the one receive loop.
  final accounts = container.read(accountsProvider);
  for (final a in accounts.accounts) {
    if (a.id != accounts.activeId) container.read(telegramStoreFamily(a.id));
  }
  container.read(accountsProvider.notifier).cleanUpLeftovers();
  // Reminders, scheduled jobs, schedule and app watches, and briefs run
  // without Telegram too; Telegram watches start hearing messages once an
  // account is signed in (the engine listens to TDLib's updates throughout).
  container.read(watchEngineProvider).start();
}
