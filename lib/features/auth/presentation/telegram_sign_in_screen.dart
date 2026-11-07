import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../../app/theme.dart';
import '../../../infrastructure/telegram/accounts.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../data/auth_controller.dart';
import 'code_screen.dart';
import 'password_screen.dart';
import 'phone_screen.dart';
import 'qr_screen.dart';
import 'unsupported_screen.dart';

/// Signing in to Telegram from Settings → Apps & web → Telegram, when the
/// app is already in use without it: the same phone, QR, code and password
/// screens the first run shows, as a page that closes once signed in.
class TelegramSignInScreen extends ConsumerStatefulWidget {
  const TelegramSignInScreen({super.key, this.addingAccount = false});

  /// Signing in another account (from "Add account"): closing the page
  /// cancels it and goes back to the account that was open.
  final bool addingAccount;

  /// Starts adding an account and opens its sign-in page.
  static Future<void> addAccount(BuildContext context, WidgetRef ref) async {
    try {
      ref.read(accountsProvider.notifier).beginAdd();
    } on StateError catch (e) {
      showSnack(context, e.message);
      return;
    }
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(builder: (_) => const TelegramSignInScreen(addingAccount: true)),
    );
  }

  @override
  ConsumerState<TelegramSignInScreen> createState() => _TelegramSignInScreenState();
}

class _TelegramSignInScreenState extends ConsumerState<TelegramSignInScreen> {
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _accounts; // Read now: ref can't be used in dispose.
    Future.microtask(() => ref.read(authControllerProvider.notifier).startSignIn());
  }

  void _closeAdded(String message) {
    if (_closing) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      // Before popping: ref can't be used once this page is on its way out.
      _accounts.clearNotice();
      Navigator.of(context).pop();
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    });
  }

  late final AccountsController _accounts = ref.read(accountsProvider.notifier);

  @override
  void dispose() {
    // Closed before the account finished signing in: drop it and go back.
    // After this frame: providers can't change while the tree is updating.
    if (widget.addingAccount) Future.microtask(_accounts.cancelAdd);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider).value;
    final ui = ref.watch(authControllerProvider);
    if (widget.addingAccount) {
      final accounts = ref.watch(accountsProvider);
      // Done once the registry has recorded who signed in (or found the
      // account was already here).
      if (accounts.addingId == null) {
        _closeAdded(accounts.notice ?? 'Signed in as ${accounts.active.label}');
      }
    } else if (auth is td.AuthorizationStateReady && !_closing) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pop();
        showSnack(context, 'Telegram connected');
      });
    }
    final Widget screen;
    if (auth is td.AuthorizationStateReady || !asksToSignIn(auth)) {
      screen = Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(strokeWidth: 2),
              const SizedBox(height: Space.l),
              Text(auth is td.AuthorizationStateReady ? 'Signed in' : 'Starting Telegram…', style: context.text.bodySmall),
            ],
          ),
        ),
      );
    } else if (ui.editingPhone || auth is td.AuthorizationStateWaitPhoneNumber) {
      screen = const PhoneScreen(key: ValueKey('phone'));
    } else {
      screen = switch (auth) {
        td.AuthorizationStateWaitCode() => const CodeScreen(key: ValueKey('code')),
        td.AuthorizationStateWaitPassword() => const PasswordScreen(key: ValueKey('password')),
        td.AuthorizationStateWaitOtherDeviceConfirmation() => const QrScreen(key: ValueKey('qr')),
        _ => const UnsupportedAuthScreen(key: ValueKey('unsupported')),
      };
    }
    return Stack(
      children: [
        AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: screen),
        // The sign-in screens are made for the first run and have no way
        // back; this one can be closed.
        SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(Space.xs),
              child: IconButton(
                tooltip: 'Not now',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
