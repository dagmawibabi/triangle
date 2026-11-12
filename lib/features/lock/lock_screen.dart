import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/widgets/brand_mark.dart';
import 'app_lock.dart';

/// Covers the app while it is locked. The screens underneath keep their
/// state (and background work keeps running); they just can't be seen or
/// touched until the passcode or a fingerprint unlocks them.
class AppLockGate extends ConsumerWidget {
  const AppLockGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(appLockProvider);
    // Until the setting is read, nothing shows: a locked app mustn't flash.
    final covered = !lock.loaded || lock.locked;
    return Stack(
      fit: StackFit.expand,
      children: [
        TickerMode(
          enabled: !covered,
          child: ExcludeSemantics(excluding: covered, child: IgnorePointer(ignoring: covered, child: child)),
        ),
        if (!lock.loaded)
          ColoredBox(color: AppColors.bg)
        else if (lock.locked)
          // Its own overlay, so the passcode field's selection handles work
          // outside the app's navigator.
          Overlay(initialEntries: [OverlayEntry(builder: (_) => const LockScreen())]),
      ],
    );
  }
}

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  bool _checking = false;
  String? _error;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _biometrics());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _biometrics() async {
    final lock = ref.read(appLockProvider);
    if (!lock.biometrics || !lock.biometricsAvailable) {
      _focus.requestFocus();
      return;
    }
    final ok = await ref.read(appLockProvider.notifier).unlockWithBiometrics();
    if (!ok && mounted) _focus.requestFocus();
  }

  Future<void> _submit() async {
    final code = _code.text;
    if (code.isEmpty || _checking) return;
    final ctl = ref.read(appLockProvider.notifier);
    setState(() {
      _checking = true;
      _error = null;
    });
    final ok = await ctl.unlockWithPasscode(code);
    if (!mounted) return;
    setState(() {
      _checking = false;
      if (!ok) {
        _code.clear();
        final wait = ctl.waitSeconds;
        _error = wait > 0 ? 'Too many tries. Wait $wait s.' : 'Wrong passcode';
        if (wait > 0) _countDown();
      }
    });
    if (!ok) _focus.requestFocus();
  }

  void _countDown() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      final wait = ref.read(appLockProvider.notifier).waitSeconds;
      if (!mounted) return t.cancel();
      setState(() => _error = wait > 0 ? 'Too many tries. Wait $wait s.' : null);
      if (wait <= 0) t.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider);
    final waiting = ref.read(appLockProvider.notifier).waitSeconds > 0;
    return Material(
      color: AppColors.bg,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BrandMark(size: 56, color: AppColors.text, background: null),
                  const SizedBox(height: Space.l),
                  Text('Triangle is locked', style: context.text.titleLarge),
                  const SizedBox(height: Space.xs),
                  Text('Enter your passcode to continue', style: context.text.bodySmall),
                  const SizedBox(height: Space.xl),
                  TextField(
                    controller: _code,
                    focusNode: _focus,
                    obscureText: true,
                    enabled: !waiting,
                    autofillHints: const [],
                    enableSuggestions: false,
                    autocorrect: false,
                    textAlign: TextAlign.center,
                    style: context.text.titleMedium?.copyWith(letterSpacing: 6),
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      hintText: 'Passcode',
                      errorText: _error,
                      suffixIcon: _checking
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          : IconButton(
                              tooltip: 'Unlock',
                              icon: const Icon(Icons.arrow_forward_rounded),
                              onPressed: waiting ? null : _submit,
                            ),
                    ),
                  ),
                  if (lock.biometrics && lock.biometricsAvailable) ...[
                    const SizedBox(height: Space.l),
                    TextButton.icon(
                      icon: const Icon(Icons.fingerprint_rounded),
                      label: const Text('Use fingerprint or face'),
                      onPressed: _biometrics,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
