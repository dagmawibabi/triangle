import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../../infrastructure/telegram/accounts.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../../chat/data/chat_repository.dart';

/// Whether TDLib is asking for an account to sign in.
bool asksToSignIn(td.AuthorizationState? state) => switch (state) {
  td.AuthorizationStateWaitPhoneNumber() ||
  td.AuthorizationStateWaitOtherDeviceConfirmation() ||
  td.AuthorizationStateWaitCode() ||
  td.AuthorizationStateWaitPassword() ||
  td.AuthorizationStateWaitRegistration() ||
  td.AuthorizationStateWaitEmailAddress() ||
  td.AuthorizationStateWaitEmailCode() => true,
  _ => false,
};

/// Choices made on the sign-in screens that TDLib's state alone can't express.
@immutable
class AuthUiState {
  const AuthUiState({this.startedSignIn = false, this.editingPhone = false});

  /// Past the welcome screen in this run of the app.
  final bool startedSignIn;

  /// Wants to type a phone number even though TDLib is showing a QR code or
  /// waiting for a code (to fix a typo, say).
  final bool editingPhone;

  AuthUiState copyWith({bool? startedSignIn, bool? editingPhone}) =>
      AuthUiState(
        startedSignIn: startedSignIn ?? this.startedSignIn,
        editingPhone: editingPhone ?? this.editingPhone,
      );
}

/// Sign-in actions, as telegrive does them. Each throws a
/// `TelegramException` whose `friendlyMessage` the screen shows as-is.
class AuthController extends Notifier<AuthUiState> {
  TelegramClient get _client => ref.read(telegramClientProvider);

  @override
  AuthUiState build() => const AuthUiState();

  void startSignIn() => state = state.copyWith(startedSignIn: true);

  /// A QR confirmation is its own TDLib authorization branch. It must be
  /// closed before another phone number can be submitted; merely swapping the
  /// Flutter screen would leave TDLib in the QR state and yield `Unexpected`.
  void editPhone() {
    if (_client.authState is td.AuthorizationStateWaitOtherDeviceConfirmation) {
      state = state.copyWith(startedSignIn: true, editingPhone: false);
      unawaited(_client.restartAfterQrAuthentication());
      return;
    }
    state = state.copyWith(editingPhone: true);
  }

  void cancelEditPhone() => state = state.copyWith(editingPhone: false);

  Future<void> submitPhone(String phone) async {
    final normalized = phone.replaceAll(RegExp(r'[^\d+]'), '');
    await _client.send<td.Ok>(
      td.SetAuthenticationPhoneNumber(
        phoneNumber: normalized,
        settings: const td.PhoneNumberAuthenticationSettings(
          allowFlashCall: false,
          allowMissedCall: false,
          isCurrentPhoneNumber: false,
          hasUnknownPhoneNumber: false,
          allowSmsRetrieverApi: false,
          authenticationTokens: [],
        ),
      ),
    );
    state = state.copyWith(editingPhone: false);
  }

  Future<void> requestQrCode() async {
    await _client.send<td.Ok>(
      const td.RequestQrCodeAuthentication(otherUserIds: []),
    );
    state = state.copyWith(editingPhone: false);
  }

  Future<void> submitCode(String code) =>
      _client.send<td.Ok>(td.CheckAuthenticationCode(code: code.trim()));

  Future<void> resendCode() =>
      _client.send<td.Ok>(const td.ResendAuthenticationCode());

  Future<void> submitPassword(String password) =>
      _client.send<td.Ok>(td.CheckAuthenticationPassword(password: password));

  /// Signs the active account out. With other accounts still signed in it
  /// is removed and another one opens. Signing out the last account also
  /// forgets this app's conversations, which quote the account's messages.
  Future<void> signOut([String? accountId]) async {
    final String id = accountId ?? ref.read(activeAccountIdProvider);
    final removed = await ref.read(accountsProvider.notifier).signOut(id);
    if (!removed) await ref.read(chatRepositoryProvider).clearAll();
    state = const AuthUiState();
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthUiState>(
  AuthController.new,
);

/// Whether a Telegram account is signed in. Triangle works without one; the
/// drawer, settings, suggestions and tools follow this.
final telegramConnectedProvider = Provider<bool>(
  (ref) => ref.watch(authStateProvider).value is td.AuthorizationStateReady,
);
