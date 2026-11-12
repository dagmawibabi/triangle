import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../settings/data/settings.dart';
import '../settings/presentation/cloud_settings.dart' show KeyField;
import 'verify_et.dart';

/// Money → Tools: the Verify.ET key that payment checks use first, the
/// credits left, and the banks and wallets it covers.
class VerifyEtSettings extends ConsumerStatefulWidget {
  const VerifyEtSettings({super.key});

  @override
  ConsumerState<VerifyEtSettings> createState() => _VerifyEtSettingsState();
}

class _VerifyEtSettingsState extends ConsumerState<VerifyEtSettings> {
  Future<Map<String, dynamic>>? _balance;
  String? _forKey;

  Future<Map<String, dynamic>>? _balanceFor(String key) {
    if (key.isEmpty) return null;
    if (_forKey != key) {
      _forKey = key;
      _balance = VerifyEt(key).balance();
    }
    return _balance;
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final key = s.verifyEtKey.trim();
    return Padding(
      padding: const EdgeInsets.only(top: Space.l),
      child: Container(
        padding: const EdgeInsets.all(Space.l),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.xl), border: Border.all(color: AppColors.line)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.verified_outlined, size: 19, color: AppColors.success),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Payment verification', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      Text(
                        key.isEmpty ? 'Checking banks directly' : 'Verify.ET first, banks directly as a fallback',
                        style: context.text.bodySmall?.copyWith(color: AppColors.text3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.m),
            Text(
              'With a Verify.ET key, "is this receipt real?" checks go through verify.et: more banks and wallets, whether the money '
              'went to your account, and whether the same receipt was already used before. It sends the reference (and the '
              'receiving account, when known) to Verify.ET. Without a key, Triangle asks the bank\'s own receipt page from this phone.',
              style: context.text.bodySmall?.copyWith(color: AppColors.text2, height: 1.45),
            ),
            const SizedBox(height: Space.m),
            KeyField(
              label: 'Verify.ET API key',
              hint: 'verify.et → sign in → API Keys → create a key with verification read and write',
              value: s.verifyEtKey,
              secret: true,
              onSave: ref.read(settingsProvider.notifier).setVerifyEtKey,
              verify: (k) async {
                try {
                  await VerifyEt(k.trim()).balance();
                  return null;
                } catch (e) {
                  return '$e';
                }
              },
              help: Uri.parse('https://verify.et/docs/get-started'),
            ),
            if (key.isNotEmpty) ...[
              const SizedBox(height: Space.s),
              FutureBuilder<Map<String, dynamic>>(
                future: _balanceFor(key),
                builder: (context, snap) {
                  if (snap.hasError) return Text('${snap.error}', style: context.text.bodySmall?.copyWith(color: AppColors.danger));
                  final b = snap.data;
                  if (b == null) return const LinearProgressIndicator(minHeight: 2);
                  final left = (b['balance'] as num?)?.toInt() ?? 0;
                  final total = (b['lifetimeCredits'] as num?)?.toInt() ?? left;
                  final reset = DateTime.tryParse('${b['nextResetAt'] ?? ''}')?.toLocal();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text('Checks left', style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700))),
                          Text('$left${total > 0 ? ' of $total' : ''}', style: context.text.labelMedium?.copyWith(fontFeatures: tabularFigures)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: total == 0 ? 0 : (left / total).clamp(0.0, 1.0),
                          minHeight: 7,
                          backgroundColor: AppColors.surface3,
                          color: b['isLowBalance'] == true ? AppColors.warning : AppColors.text,
                        ),
                      ),
                      if (reset != null) ...[
                        const SizedBox(height: 4),
                        Text('Refills ${reset.day}/${reset.month}/${reset.year}', style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
                      ],
                    ],
                  );
                },
              ),
            ],
            const SizedBox(height: Space.l),
            Text('BANKS AND WALLETS', style: context.text.labelSmall?.copyWith(color: AppColors.text3, letterSpacing: 0.8, fontWeight: FontWeight.w600)),
            const SizedBox(height: Space.s),
            for (final e in VerifyEt.banks.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      key.isNotEmpty || const {'cbe', 'telebirr', 'boa', 'dashen'}.contains(e.key) ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      size: 15,
                      color: key.isNotEmpty || const {'cbe', 'telebirr', 'boa', 'dashen'}.contains(e.key) ? AppColors.success : AppColors.text3,
                    ),
                    const SizedBox(width: Space.s),
                    Expanded(child: Text(e.value, style: context.text.bodySmall?.copyWith(height: 1.3))),
                  ],
                ),
              ),
            Text(
              key.isEmpty ? 'Ticked: checked directly with the bank. The rest need a Verify.ET key.' : 'Zemen and banks not listed are checked directly, through the receipt link in their SMS.',
              style: context.text.labelSmall?.copyWith(color: AppColors.text3),
            ),
            const SizedBox(height: Space.s),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => launchUrl(Uri.parse('https://verify.et/pricing'), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('Plans: 200 free checks a month'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
