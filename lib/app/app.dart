import '../features/telegram/presentation/chat_list_screen.dart' show clock24;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../core/widgets/brand_mark.dart';
import '../features/auth/data/auth_controller.dart';
import '../features/auth/presentation/code_screen.dart';
import '../features/auth/presentation/password_screen.dart';
import '../features/auth/presentation/phone_screen.dart';
import '../features/auth/presentation/qr_screen.dart';
import '../features/auth/presentation/unsupported_screen.dart';
import '../features/auth/presentation/welcome_screen.dart';
import '../features/brief/brief_screen.dart';
import '../features/brief/brief_store.dart';
import '../features/brief/brief_widget.dart';
import '../features/brief/home_widgets.dart';
import '../features/brief/widget_customizer_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import '../features/chat/presentation/chat_screen.dart';
import '../features/settings/data/settings.dart';
import '../infrastructure/telegram/accounts.dart';
import '../infrastructure/telegram/telegram_client.dart';
import 'theme.dart';
import '../features/telegram/presentation/link_opener.dart';

/// Lets screens know when another route covers them.
final appRouteObserver = RouteObserver<ModalRoute<void>>();

class TeleAiApp extends ConsumerStatefulWidget {
  const TeleAiApp({super.key});

  @override
  ConsumerState<TeleAiApp> createState() => _TeleAiAppState();
}

class _TeleAiAppState extends ConsumerState<TeleAiApp> with WidgetsBindingObserver {
  Palette? _shown;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The phone switched between light and dark.
  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  Widget build(BuildContext context) {
    clock24 = ref.watch(settingsProvider.select((s) => s.use24h));
    final settings = ref.watch(settingsProvider);
    final light = switch (settings.themeMode) {
      AppThemeMode.light => true,
      AppThemeMode.dark => false,
      AppThemeMode.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.light,
    };
    AppColors.palette = light ? Palette.light : Palette.dark;
    AppColors.applyAccent(Color(settings.accent.value));
    // Colours are read while building, so a new palette rebuilds every
    // screen in place (keeping where you are), not just the themed parts.
    final icons = AppLook.leadingIcons != settings.leadingIcons;
    AppLook.leadingIcons = settings.leadingIcons;
    if ((_shown != null && _shown != AppColors.palette) || icons) {
      WidgetsBinding.instance.addPostFrameCallback((_) => rebuildAllScreens(context));
    }
    _shown = AppColors.palette;
    final theme = buildTheme(
      accent: AppColors.accent,
      chatFontSize: settings.chatFontSize,
      chatFontFamily: settings.chatFont.family,
    );
    return MaterialApp(
      title: 'Triangle',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
      themeMode: light ? ThemeMode.light : ThemeMode.dark,
      navigatorKey: appNavigatorKey,
      navigatorObservers: [appRouteObserver],
      home: const AppGate(),
    );
  }
}

/// Marks every widget under [context] to build again.
void rebuildAllScreens(BuildContext context) {
  void mark(Element e) {
    e.markNeedsBuild();
    e.visitChildren(mark);
  }

  if (context is Element && context.mounted) context.visitChildren(mark);
}

/// Shows the screen TDLib's authorization state calls for, the way
/// telegrive's router does: the sign-in steps follow TDLib rather than being
/// pushed by hand.
class AppGate extends ConsumerStatefulWidget {
  const AppGate({super.key});

  @override
  ConsumerState<AppGate> createState() => _AppGateState();
}

class _AppGateState extends ConsumerState<AppGate> with WidgetsBindingObserver {
  /// Online while on screen and allowed; offline in the background.
  void _syncOnline() {
    final resumed = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    final allowed = ref.read(settingsProvider).appearOnline;
    ref.read(telegramClientProvider).setOnline(resumed && allowed);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _syncOnline();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.listenManual(settingsProvider, (_, _) => _syncOnline());
    // Only the account on screen appears online; the one switched away
    // from goes offline, as it would in the background.
    ref.listenManual(telegramClientProvider, (previous, _) {
      previous?.setOnline(false);
      _syncOnline();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncOnline());
    // Loads the briefs, which also refreshes the home-screen widget.
    ref.read(briefStoreProvider);
    BriefHomeWidget.listen(
      () => appNavigatorKey.currentState?.push(
        MaterialPageRoute<void>(builder: (_) => const BriefScreen()),
      ),
      // A custom widget: its row's link, or the widget in Settings.
      openWidget: (id, link) {
        final uri = link == null ? null : Uri.tryParse(link);
        if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
          launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
        appNavigatorKey.currentState?.push(
          MaterialPageRoute<void>(builder: (_) => WidgetCustomizerScreen(openWidget: id)),
        );
      },
    );
    // Writes every custom widget's rows where the launcher reads them.
    ref.read(homeWidgetsProvider.notifier).publishAll();
    // TDLib itself was started with the process (see startRuntime).
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider).value;
    final ui = ref.watch(authControllerProvider);

    final skipped = ref.watch(settingsProvider.select((s) => s.telegramSkipped));
    final loaded = ref.watch(settingsProvider.select((s) => s.loaded));

    // While another account is being added (its sign-in page is open on
    // top), the app underneath stays as it was.
    final adding = ref.watch(accountsProvider.select((s) => s.addingId != null));

    final Widget screen;
    if (auth is td.AuthorizationStateReady || adding) {
      screen = const ChatScreen(key: ValueKey('chat'));
    } else if (skipped && loaded) {
      // Using the app without Telegram: it can be connected later from
      // Settings → Apps & web → Telegram (TelegramSignInScreen).
      screen = const ChatScreen(key: ValueKey('chat'));
    } else if (!loaded || !asksToSignIn(auth)) {
      screen = const SplashScreen(key: ValueKey('splash'));
    } else if (!ui.startedSignIn &&
        auth is td.AuthorizationStateWaitPhoneNumber) {
      screen = const WelcomeScreen(key: ValueKey('welcome'));
    } else if (ui.editingPhone ||
        auth is td.AuthorizationStateWaitPhoneNumber) {
      screen = const PhoneScreen(key: ValueKey('phone'));
    } else {
      screen = switch (auth) {
        td.AuthorizationStateWaitCode() => const CodeScreen(
          key: ValueKey('code'),
        ),
        td.AuthorizationStateWaitPassword() => const PasswordScreen(
          key: ValueKey('password'),
        ),
        td.AuthorizationStateWaitOtherDeviceConfirmation() => const QrScreen(
          key: ValueKey('qr'),
        ),
        _ => const UnsupportedAuthScreen(key: ValueKey('unsupported')),
      };
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: screen,
    );
  }
}

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(telegramClientProvider);
    // Pure black with the bare triangle, like the native splash before it.
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.xxl),
          child: ValueListenableBuilder<String?>(
            valueListenable: client.fatalError,
            builder: (context, error, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BrandMark(size: 160, background: null),
                const SizedBox(height: Space.l),
                if (error == null)
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: Colors.white54,
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Text(
                      error,
                      textAlign: TextAlign.center,
                      style: context.text.bodyMedium?.copyWith(
                        color: AppColors.danger,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
