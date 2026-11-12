import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/widgets/app_sheet.dart';
import 'app_lock.dart';

/// Settings → App lock: passcode, fingerprint/face unlock and when to lock.
class AppLockSettingsScreen extends ConsumerWidget {
  const AppLockSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(appLockProvider);
    final ctl = ref.read(appLockProvider.notifier);

    Future<void> turnOn() async {
      final code = await _newPasscode(context);
      if (code == null) return;
      await ctl.setPasscode(code);
      if (context.mounted) showSnack(context, 'App lock is on', icon: Icons.lock_outline_rounded);
    }

    Future<void> turnOff() async {
      if (!await _checkPasscode(context, ref)) return;
      await ctl.disable();
      if (context.mounted) showSnack(context, 'App lock is off', icon: Icons.lock_open_rounded);
    }

    Future<void> change() async {
      if (!await _checkPasscode(context, ref) || !context.mounted) return;
      final code = await _newPasscode(context);
      if (code == null) return;
      await ctl.setPasscode(code);
      if (context.mounted) showSnack(context, 'Passcode changed', icon: Icons.lock_outline_rounded);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('App lock')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.x4),
        children: [
          Text(
            'Ask for a passcode (or your fingerprint or face) when Triangle opens, so someone holding your phone can\'t read '
            'your chats, email or texts, or use the assistant. Watches and briefs keep running while it is locked.',
            style: context.text.bodySmall?.copyWith(height: 1.4),
          ),
          const SizedBox(height: Space.l),
          Container(
            decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.l)),
            child: Column(
              children: [
                SwitchListTile(
                  secondary: lead(const Icon(Icons.lock_outline_rounded)),
                  title: const Text('App lock'),
                  subtitle: Text(lock.enabled ? 'On' : 'Off', style: context.text.bodySmall),
                  value: lock.enabled,
                  onChanged: !lock.loaded ? null : (on) => on ? turnOn() : turnOff(),
                ),
                if (lock.enabled) ...[
                  const Divider(height: 1, indent: Space.l, endIndent: Space.l),
                  ListTile(
                    leading: lead(const Icon(Icons.password_rounded)),
                    title: const Text('Change passcode'),
                    trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
                    onTap: change,
                  ),
                  const Divider(height: 1, indent: Space.l, endIndent: Space.l),
                  SwitchListTile(
                    secondary: lead(const Icon(Icons.fingerprint_rounded)),
                    title: const Text('Unlock with fingerprint or face'),
                    subtitle: Text(
                      lock.biometricsAvailable
                          ? 'The passcode still works as a backup'
                          : 'No fingerprint or face is set up on this phone',
                      style: context.text.bodySmall,
                    ),
                    value: lock.biometrics && lock.biometricsAvailable,
                    onChanged: !lock.biometricsAvailable
                        ? null
                        : (on) async {
                            final ok = await ctl.setBiometrics(on);
                            if (!ok && context.mounted) showSnack(context, 'Couldn\'t confirm your fingerprint or face');
                          },
                  ),
                  const Divider(height: 1, indent: Space.l, endIndent: Space.l),
                  ListTile(
                    leading: lead(const Icon(Icons.timer_outlined)),
                    title: const Text('Lock'),
                    subtitle: Text('${lockAfterLabel(lock.lockAfter)} away from the app', style: context.text.bodySmall),
                    trailing: Icon(Icons.chevron_right_rounded, color: AppColors.text3),
                    onTap: () async {
                      final d = await showModalBottomSheet<Duration>(
                        context: context,
                        showDragHandle: true,
                        backgroundColor: AppColors.surface,
                        builder: (context) => SafeArea(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final (d, label) in lockAfterChoices)
                                ListTile(
                                  title: Text(label),
                                  trailing: d == lock.lockAfter ? const Icon(Icons.check_rounded) : null,
                                  onTap: () => Navigator.of(context).pop(d),
                                ),
                            ],
                          ),
                        ),
                      );
                      if (d != null) await ctl.setLockAfter(d);
                    },
                  ),
                  const Divider(height: 1, indent: Space.l, endIndent: Space.l),
                  ListTile(
                    leading: lead(const Icon(Icons.lock_clock_outlined)),
                    title: const Text('Lock now'),
                    onTap: ctl.lockNow,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: Space.l),
          Text(
            'The passcode is stored only as a salted hash in your phone\'s keystore. If you forget it, the only way back in '
            'is to clear Triangle\'s data in Android settings, which signs you out.',
            style: context.text.bodySmall?.copyWith(color: AppColors.text3),
          ),
        ],
      ),
    );
  }
}

/// Asks for a new passcode twice, in a bottom sheet; null when cancelled.
Future<String?> _newPasscode(BuildContext context) async {
  final first = TextEditingController(), second = TextEditingController();
  String? error;
  var hidden = true;
  final result = await showFormSheet<String>(
    context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        void save() {
          if (first.text.length < 4) return setState(() => error = 'Use at least 4 characters');
          if (first.text != second.text) return setState(() => error = 'The two don\'t match');
          Navigator.of(context).pop(first.text);
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.lock_outline_rounded, color: AppColors.text2),
                const SizedBox(width: Space.s),
                Expanded(child: Text('Set a passcode', style: context.text.titleMedium)),
              ],
            ),
            const SizedBox(height: Space.xs),
            Text('4 or more characters. You\'ll need it if fingerprint or face unlock isn\'t available.', style: context.text.bodySmall),
            const SizedBox(height: Space.l),
            TextField(
              controller: first,
              autofocus: true,
              obscureText: hidden,
              enableSuggestions: false,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Passcode',
                suffixIcon: IconButton(
                  tooltip: hidden ? 'Show' : 'Hide',
                  icon: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => hidden = !hidden),
                ),
              ),
            ),
            const SizedBox(height: Space.m),
            TextField(
              controller: second,
              obscureText: hidden,
              enableSuggestions: false,
              autocorrect: false,
              onSubmitted: (_) => save(),
              decoration: InputDecoration(labelText: 'Again', errorText: error),
            ),
            const SizedBox(height: Space.l),
            Row(
              children: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                const Spacer(),
                FilledButton(onPressed: save, child: const Text('Save passcode')),
              ],
            ),
          ],
        );
      },
    ),
  );
  return result;
}

/// Asks for the current passcode in a bottom sheet; true when it is right.
Future<bool> _checkPasscode(BuildContext context, WidgetRef ref) async {
  final code = TextEditingController();
  String? error;
  var checking = false;
  final ok = await showFormSheet<bool>(
    context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        Future<void> check() async {
          setState(() => checking = true);
          final ctl = ref.read(appLockProvider.notifier);
          final right = await ctl.verify(code.text);
          if (!context.mounted) return;
          if (right) return Navigator.of(context).pop(true);
          final wait = ctl.waitSeconds;
          setState(() {
            checking = false;
            error = wait > 0 ? 'Too many tries. Wait $wait s.' : 'Wrong passcode';
          });
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.password_rounded, color: AppColors.text2),
                const SizedBox(width: Space.s),
                Expanded(child: Text('Enter your passcode', style: context.text.titleMedium)),
              ],
            ),
            const SizedBox(height: Space.l),
            TextField(
              controller: code,
              autofocus: true,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              onSubmitted: (_) => check(),
              decoration: InputDecoration(labelText: 'Passcode', errorText: error),
            ),
            const SizedBox(height: Space.l),
            Row(
              children: [
                TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                const Spacer(),
                FilledButton(onPressed: checking ? null : check, child: const Text('Continue')),
              ],
            ),
          ],
        );
      },
    ),
  );
  return ok ?? false;
}
