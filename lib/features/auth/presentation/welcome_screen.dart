import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../settings/data/settings.dart';
import '../data/auth_controller.dart';

class _Page {
  const _Page({required this.title, required this.body, required this.art});
  final String title;
  final String body;
  final Widget art;
}

/// A few quiet pages on what the app is, then sign-in.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key, this.replay = false});

  /// Opened again from Settings: the last page closes it instead of
  /// starting sign-in.
  final bool replay;

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _pager = PageController();
  int _page = 0;

  static final _pages = [
    const _Page(
      title: 'Ask your Telegram anything.',
      body: 'How many channels you\'re in, what\'s new today, who\'s waiting on a reply. It reads your chats and shows its sources as chips you can open.',
      art: _Bubbles(
        lines: [
          'What did my channels post today?',
          'Do I have unread DMs?',
          'Catch me up on my work groups',
        ],
      ),
    ),
    const _Page(
      title: 'Your email, calendar and work apps.',
      body: 'Connect Gmail, Outlook, Google Calendar, Drive, Docs, Sheets, Slack, Notion, GitHub, Linear and Todoist, or any of '
          '500+ apps, through Composio. Read and triage your inbox, find a free slot, post to Slack, add a task. Emails open '
          'as they were designed.',
      art: _FeatureGrid(
        items: [
          (Icons.mail_outline_rounded, 'Gmail'),
          (Icons.event_outlined, 'Calendar'),
          (Icons.tag_rounded, 'Slack'),
          (Icons.sticky_note_2_outlined, 'Notion'),
          (Icons.add_to_drive_outlined, 'Drive'),
          (Icons.task_alt_rounded, 'Todoist'),
        ],
      ),
    ),
    const _Page(
      title: 'Knows your phone.',
      body: 'Find a verification code in your texts, check missed calls, call or text a contact, see battery, storage and '
          'Wi-Fi, turn on the flashlight, set an alarm or a timer, control what is playing. Each action asks you first.',
      art: _Bubbles(
        showMark: false,
        lines: [
          'What\'s my bank\'s latest SMS code?',
          'Call Mom',
          'Set an alarm for 6:30',
        ],
      ),
    ),
    const _Page(
      title: 'It browses the web for you.',
      body: 'Reads blogs and docs, fills in forms on real sites, calls APIs, downloads files, and shows you screenshots of what it sees. Watch it live, or take over whenever you like.',
      art: _Bubbles(
        showMark: false,
        lines: [
          'What\'s on Wikipedia about the Moon?',
          'Open the article and summarise it',
          'Screenshot the page for me',
        ],
      ),
    ),
    const _Page(
      title: 'Your PC, from your phone.',
      body: 'Run Triangle Companion on Windows and the assistant can see your screen, move the mouse, type, open apps and find your files. '
          'You can watch and take over live too. You choose what it may do on the PC, and can have it ask there first.',
      art: _PcControl(),
    ),
    const _Page(
      title: 'Find what interests you.',
      body: 'Search YouTube and read its transcripts, catch up on X, Reddit and Hacker News, find research papers, and '
          'discover books, free audiobooks, podcasts and radio. Films, shows, music and public GitHub projects too.',
      art: _FeatureGrid(
        items: [
          (Icons.ondemand_video_rounded, 'YouTube'),
          (Icons.alternate_email_rounded, 'X'),
          (Icons.forum_outlined, 'Reddit'),
          (Icons.newspaper_rounded, 'News'),
          (Icons.science_outlined, 'Papers'),
          (Icons.menu_book_rounded, 'Books'),
          (Icons.podcasts_rounded, 'Podcasts'),
          (Icons.radio_rounded, 'Radio'),
          (Icons.code_rounded, 'GitHub'),
        ],
      ),
    ),
    const _Page(
      title: 'Handy, every day.',
      body: 'Track spending and budgets from your bank texts. See your screen time and call history. Make and scan QR '
          'codes, resize or cut out a picture. Check scores, the weather, your flight, a recipe or a word, read the '
          'verse of the day, and see the Ethiopian date.',
      art: _FeatureGrid(
        items: [
          (Icons.account_balance_wallet_outlined, 'Money'),
          (Icons.hourglass_bottom_rounded, 'Screen time'),
          (Icons.call_outlined, 'Calls'),
          (Icons.qr_code_2_rounded, 'QR codes'),
          (Icons.crop_rounded, 'Pictures'),
          (Icons.sports_soccer_outlined, 'Scores'),
          (Icons.wb_sunny_outlined, 'Weather'),
          (Icons.restaurant_menu_rounded, 'Recipes'),
          (Icons.translate_rounded, 'Words'),
        ],
      ),
    ),
    const _Page(
      title: 'Briefed, morning and night.',
      body: 'A detailed rundown of everything that happened across your DMs, groups and channels, sorted by what needs you first. On a schedule or whenever you ask.',
      art: _Glyph(icon: Icons.wb_twilight_rounded),
    ),
    const _Page(
      title: 'Watches while you\'re away.',
      body: 'Tell it to keep an eye on a person, a group or a channel. It notifies you, sums things up, or replies the way you asked.',
      art: _Glyph(icon: Icons.visibility_outlined),
    ),
    const _Page(
      title: 'Routines that run themselves.',
      body: '"Every weekday at 9, catch me up on my channels." "Each Friday, sum up my spending." Describe a job and when '
          'to do it, and the assistant carries it out on schedule. Run one now, change it or pause it anytime.',
      art: _Glyph(icon: Icons.event_repeat_rounded),
    ),
    const _Page(
      title: 'Runs code, privately.',
      body: 'A private sandbox on your phone runs Python and JavaScript to crunch numbers, make charts and files.',
      art: _FeatureGrid(
        items: [
          (Icons.terminal_rounded, 'Python'),
          (Icons.javascript_rounded, 'JavaScript'),
          (Icons.bar_chart_rounded, 'Charts'),
          (Icons.functions_rounded, 'Scripts'),
          (Icons.folder_zip_outlined, 'Zip files'),
          (Icons.download_rounded, 'Downloads'),
        ],
      ),
    ),
    const _Page(
      title: 'Your cloud, by asking.',
      body: 'Manage Cloudflare: sites, DNS, cache, Workers, Pages and R2 storage you can browse, download and share. Run real '
          'Python, Node, R or bash in an E2B cloud sandbox, or write and run code yourself in the built-in editor.',
      art: _FeatureGrid(
        items: [
          (Icons.language_rounded, 'DNS'),
          (Icons.inventory_2_outlined, 'R2 files'),
          (Icons.bolt_rounded, 'Workers'),
          (Icons.terminal_rounded, 'E2B'),
          (Icons.code_rounded, 'Editor'),
          (Icons.bar_chart_rounded, 'Charts'),
        ],
      ),
    ),
    const _Page(
      title: 'Careful by design.',
      body: 'Reading never marks messages as read. Sending, replying and reacting wait for your OK. Deleting and leaving are off until you turn them on, and read-only mode locks everything else.',
      art: _Glyph(icon: Icons.verified_user_outlined),
    ),
  ];

  bool get _last => _page == _pages.length - 1;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void _next() {
    if (_last) {
      widget.replay
          ? Navigator.of(context).pop()
          : ref.read(authControllerProvider.notifier).startSignIn();
    } else {
      _pager.nextPage(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.xxl,
                    Space.l,
                    Space.m,
                    0,
                  ),
                  child: Row(
                    children: [
                      const BrandLockup(markSize: 28),
                      const Spacer(),
                      AnimatedOpacity(
                        opacity: _last ? 0 : 1,
                        duration: const Duration(milliseconds: 200),
                        child: TextButton(
                          onPressed: _last
                              ? null
                              : () => _pager.animateToPage(
                                  _pages.length - 1,
                                  duration: const Duration(milliseconds: 420),
                                  curve: Curves.easeOutCubic,
                                ),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.text2,
                          ),
                          child: const Text('Skip'),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pager,
                    itemCount: _pages.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (context, i) {
                      final p = _pages[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.xxl,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Spacer(flex: 2),
                            Center(child: p.art),
                            const Spacer(flex: 2),
                            Text(
                              p.title,
                              style: context.text.headlineMedium?.copyWith(
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: Space.l),
                            Text(
                              p.body,
                              style: context.text.bodyLarge?.copyWith(
                                color: AppColors.text2,
                              ),
                            ),
                            const Spacer(),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.xxl,
                    0,
                    Space.xxl,
                    Space.l,
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          for (var i = 0; i < _pages.length; i++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              margin: const EdgeInsets.only(right: 6),
                              width: i == _page ? 22 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: i == _page
                                    ? AppColors.text
                                    : AppColors.text3.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: Space.xl),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _next,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Text(
                              _last
                                  ? (widget.replay
                                        ? 'Done'
                                        : 'Sign in with Telegram')
                                  : 'Next',
                              key: ValueKey(_last),
                            ),
                          ),
                        ),
                      ),
                      if (_last && !widget.replay) ...[
                        const SizedBox(height: Space.s),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: () => ref.read(settingsProvider.notifier).setTelegramSkipped(true),
                            child: const Text('Continue without Telegram'),
                          ),
                        ),
                      ],
                      const SizedBox(height: Space.m),
                      Text(
                        'Independent app, not affiliated with Telegram.',
                        style: context.text.bodySmall?.copyWith(
                          color: AppColors.text3,
                        ),
                      ),
                    ],
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

/// A large outlined glyph in a soft ring.
class _Glyph extends StatelessWidget {
  const _Glyph({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      height: 180,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        gradient: RadialGradient(
          colors: [Colors.white.withValues(alpha: 0.06), Colors.transparent],
        ),
      ),
      child: Center(
        child: Container(
          width: 104,
          height: 104,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.surface2,
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Icon(icon, size: 46, color: AppColors.text),
        ),
      ),
    );
  }
}

/// A PC screen with the pointer gliding across it to a button and clicking.
class _PcControl extends StatefulWidget {
  const _PcControl();

  @override
  State<_PcControl> createState() => _PcControlState();
}

class _PcControlState extends State<_PcControl>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion
        ..stop()
        ..value = 0.7;
    } else if (!_motion.isAnimating) {
      _motion.repeat();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 264,
          height: 164,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(Radii.m),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.m),
              child: AnimatedBuilder(
                animation: _motion,
                builder: (_, _) => CustomPaint(
                  painter: _PcControlPainter(
                    _motion.value,
                    line: AppColors.surface3,
                    ink: AppColors.text,
                    accent: AppColors.accent,
                  ),
                ),
              ),
            ),
          ),
        ),
        Container(
          width: 36,
          height: 14,
          color: AppColors.surface3,
        ),
        Container(
          width: 88,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.surface3,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ],
    );
  }
}

class _PcControlPainter extends CustomPainter {
  const _PcControlPainter(
    this.t, {
    required this.line,
    required this.ink,
    required this.accent,
  });

  /// 0 to 1 through one loop: glide, click, rest.
  final double t;
  final Color line, ink, accent;

  /// Where the pointer is when it has gone [p] of the way, 0 to 1.
  static Offset _at(double p, Size s) {
    final a = Offset(s.width * 0.14, s.height * 0.3);
    final c = Offset(s.width * 0.42, s.height * 0.95);
    final b = Offset(s.width * 0.76, s.height * 0.74);
    return a * ((1 - p) * (1 - p)) + c * (2 * p * (1 - p)) + b * (p * p);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = line;
    // The window: a title bar and a few lines of content.
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 20), fill);
    for (final (i, w) in const [0.62, 0.48, 0.55].indexed) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(16, 36.0 + i * 16, size.width * w, 6),
          const Radius.circular(3),
        ),
        fill,
      );
    }

    final glide = Curves.easeInOut.transform((t / 0.55).clamp(0.0, 1.0));
    final click = ((t - 0.55) / 0.12).clamp(0.0, 1.0);
    final clicked = t >= 0.55;

    // The button it is heading for.
    final target = _at(1, size);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: target, width: 66, height: 26),
        const Radius.circular(8),
      ),
      Paint()..color = clicked ? accent : line,
    );

    // The way it came, fading out behind the pointer.
    final fade = 1 - ((t - 0.7) / 0.3).clamp(0.0, 1.0);
    final trail = Paint()
      ..color = ink.withValues(alpha: 0.35 * fade)
      ..style = PaintingStyle.fill;
    for (var p = 0.0; p < glide; p += 0.04) {
      canvas.drawCircle(_at(p, size), 1.5, trail);
    }

    // The ripple of the click.
    if (click > 0 && click < 1) {
      canvas.drawCircle(
        target,
        6 + 18 * click,
        Paint()
          ..color = ink.withValues(alpha: 0.5 * (1 - click))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // The pointer, tip at its position.
    final tip = _at(glide, size);
    final arrow = Path()
      ..moveTo(tip.dx, tip.dy)
      ..relativeLineTo(0, 17)
      ..relativeLineTo(4.4, -3.8)
      ..relativeLineTo(3, 6.6)
      ..relativeLineTo(2.8, -1.3)
      ..relativeLineTo(-3, -6.4)
      ..relativeLineTo(5.8, -0.5)
      ..close();
    canvas.drawPath(arrow, Paint()..color = ink);
    canvas.drawPath(
      arrow,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_PcControlPainter old) => old.t != t;
}

/// A few questions in bubbles, as the chat shows them.
class _Bubbles extends StatelessWidget {
  const _Bubbles({required this.lines, this.showMark = true});
  final List<String> lines;
  final bool showMark;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showMark) ...[
          const BrandMark(size: 64),
          const SizedBox(height: Space.xxl),
        ],
        for (final (i, line) in lines.indexed)
          Align(
            alignment: i.isOdd ? Alignment.centerLeft : Alignment.centerRight,
            child: Container(
              margin: const EdgeInsets.only(bottom: Space.s),
              padding: const EdgeInsets.symmetric(
                horizontal: Space.l,
                vertical: Space.m,
              ),
              decoration: BoxDecoration(
                color: i.isOdd ? AppColors.surface2 : AppColors.surface3,
                borderRadius: BorderRadius.circular(Radii.xl),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Text(
                line,
                style: context.text.bodyMedium?.copyWith(
                  color: AppColors.text2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A small grid of what the assistant can do.
class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid({required this.items});
  final List<(IconData, String)> items;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      child: Wrap(
        spacing: Space.m,
        runSpacing: Space.m,
        alignment: WrapAlignment.center,
        children: [
          for (final (icon, label) in items)
            Container(
              width: 80,
              padding: const EdgeInsets.symmetric(vertical: Space.m),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(Radii.l),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                children: [
                  Icon(icon, color: AppColors.text, size: 24),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: context.text.labelSmall?.copyWith(
                      color: AppColors.text2,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
