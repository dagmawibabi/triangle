import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omni_ai/omni_ai.dart' show BrowserView;

import '../../app/theme.dart';
import '../ai/data/ai.dart';
import 'browser_mode.dart';

/// The assistant's browser, live (omni_ai's [BrowserView]): watch what it
/// does, or take over (log in, solve a check it can't) and hand back. It is
/// the same page the browser tools drive. "Desktop site" switches between
/// sites' mobile and PC layouts, for you and the assistant alike.
class BrowserScreen extends ConsumerStatefulWidget {
  const BrowserScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BrowserScreen()));

  @override
  ConsumerState<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends ConsumerState<BrowserScreen> {
  bool _desktop = false;

  @override
  void initState() {
    super.initState();
    BrowserMode.desktop.then((v) {
      if (mounted) setState(() => _desktop = v);
    });
  }

  Future<void> _setDesktop(bool on) async {
    setState(() => _desktop = on);
    await BrowserMode.setDesktop(on);
    final session = ref.read(aiProvider).browser.session;
    final c = session.controller;
    if (c == null) return;
    await BrowserMode.apply(session);
    await c.reload();
    // Give the page a moment to load before laying it out wide.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    await BrowserMode.fit(session);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(
      title: const Text('Browser'),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: Space.s),
          child: FilterChip(
            // The chip theme sets no icon colour; without one it vanishes
            // on the dark chip.
            avatar: Icon(
              _desktop ? Icons.desktop_windows_outlined : Icons.smartphone_rounded,
              size: 16,
              color: AppColors.text,
            ),
            label: const Text('Desktop site'),
            selected: _desktop,
            showCheckmark: false,
            onSelected: _setDesktop,
          ),
        ),
      ],
    ),
    body: BrowserView(session: ref.watch(aiProvider).browser.session),
  );
}
