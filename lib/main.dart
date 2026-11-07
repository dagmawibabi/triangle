import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/runtime.dart';
import 'app/theme.dart';
import 'infrastructure/telegram/accounts.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.bg,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  // TDLib and the watches start here rather than with a screen: after a
  // reboot or a background restart there is no screen to start them.
  // Which Telegram accounts there are, and which one was open, so TDLib
  // starts with that one rather than switching after the first frame.
  final accounts = await AccountRegistry.load();
  final container = ProviderContainer(
    overrides: [initialAccountsProvider.overrideWithValue(accounts)],
  );
  startRuntime(container);
  runApp(UncontrolledProviderScope(container: container, child: const TeleAiApp()));
}
