import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import 'finance_ui.dart';

// The account card: bank-card proportions, the bank's colours as a rich
// gradient with a soft glow, fine engraved lines and a glass edge, a
// coloured shadow, and the balance set large.

/// The account's two colours, deepened so white text always reads.
(Color, Color) accountColors(Map<String, dynamic> account) {
  final cs = [for (final c in (account['colors'] as List? ?? const [])) hexColor(c)];
  var a = cs.isNotEmpty ? cs.first : const Color(0xFF3F3F46);
  var b = cs.length > 1 ? cs[1] : Color.lerp(a, Colors.black, 0.45)!;
  // Light brand colours (white, yellow) become a deeper shade of the main one.
  if (a.computeLuminance() > 0.4) a = HSLColor.fromColor(a).withLightness(0.32).toColor();
  if (b.computeLuminance() > 0.4 || (b.r - a.r).abs() + (b.g - a.g).abs() + (b.b - a.b).abs() < 0.08) b = Color.lerp(a, Colors.black, 0.5)!;
  return (a, b);
}

String _initials(String name) {
  final n = name.trim();
  if (n.isEmpty) return '?';
  if (n.length <= 4 && !n.contains(' ')) return n.toUpperCase();
  final w = n.split(RegExp(r'\s+'));
  return (w.length > 1 ? '${w[0][0]}${w[1][0]}' : n.substring(0, 2)).toUpperCase();
}

/// An account as a card. [compact] is the carousel size: no flows strip.
class AccountCard extends StatelessWidget {
  const AccountCard({super.key, required this.account, required this.cur, this.compact = false, this.onTap, this.shadow = true});
  final Map<String, dynamic> account;
  final String cur;
  final bool compact;
  final VoidCallback? onTap;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final (a, b) = accountColors(account);
    final radius = BorderRadius.circular(compact ? 20 : 24);
    final dim = Colors.white.withValues(alpha: 0.68);
    final faint = Colors.white.withValues(alpha: 0.5);
    final ending = account['number_ending'];
    final bank = '${account['bank'] ?? ''}';
    final title = '${account['nickname'] ?? ''}'.isNotEmpty ? '${account['nickname']}' : '${account['bank_name'] ?? bank}';
    final wallet = account['wallet'] == true;
    final cash = account['bank_id'] == 100;
    final tags = [
      if (account['default'] == true) 'Default',
      if (account['detected'] == true) 'New',
      if (account['dormant'] == true) 'Not in use',
      if (account['include_in_totals'] == false) 'Not in total',
    ];
    final pad = compact ? 14.0 : 18.0;

    final content = Padding(
      padding: EdgeInsets.all(pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Mark(text: cash ? null : _initials(bank), icon: cash ? Icons.payments_rounded : null, size: compact ? 30 : 36),
              SizedBox(width: compact ? 8 : 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(bank, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: compact ? 13 : 15, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
                    Text(
                      title == bank ? (wallet ? 'Mobile wallet' : (cash ? 'Cash' : 'Bank account')) : title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: dim, fontSize: compact ? 11 : 12),
                    ),
                  ],
                ),
              ),
              for (final t in tags.take(compact ? 1 : 2)) _Tag(t),
              if (tags.isEmpty || !compact) ...[
                const SizedBox(width: 6),
                Icon(cash ? Icons.account_balance_wallet_outlined : (wallet ? Icons.smartphone_rounded : Icons.contactless_outlined), size: compact ? 18 : 22, color: faint),
              ],
            ],
          ),
          const Spacer(),
          Text('Balance', style: TextStyle(color: faint, fontSize: compact ? 10 : 11, letterSpacing: 0.6, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: MoneyText(account['balance'], cur: cur, size: compact ? 23 : 30, color: Colors.white, weight: FontWeight.w800)),
              if (ending != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 3),
                  child: Text('•••• $ending', style: TextStyle(color: dim, fontSize: compact ? 11 : 13, letterSpacing: 1.6, fontWeight: FontWeight.w600, fontFeatures: tabularFigures)),
                ),
            ],
          ),
          if (!compact) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Row(
                children: [
                  _Flow(icon: Icons.south_west_rounded, label: 'In', value: account['month_in']),
                  Container(width: 1, height: 14, margin: const EdgeInsets.symmetric(horizontal: 12), color: Colors.white.withValues(alpha: 0.18)),
                  _Flow(icon: Icons.north_east_rounded, label: 'Out', value: account['month_out']),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      account['balance_as_of'] != null ? 'Updated ${dayLabel(DateTime.parse('${account['balance_as_of']}')).toLowerCase()}' : 'This month',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: faint, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    return AspectRatio(
      aspectRatio: compact ? 1.72 : 1.586,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: shadow ? [BoxShadow(color: a.withValues(alpha: AppColors.isLight ? 0.35 : 0.3), blurRadius: compact ? 16 : 26, spreadRadius: -4, offset: Offset(0, compact ? 6 : 12))] : null,
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(painter: _CardArt(a, b)),
              content,
              // The glass edge: brighter at the top, as if lit from above.
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.white.withValues(alpha: 0.06), Colors.transparent],
                      stops: const [0, 0.35],
                    ),
                  ),
                ),
              ),
              Material(type: MaterialType.transparency, child: InkWell(onTap: onTap, splashColor: Colors.white.withValues(alpha: 0.08))),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardArt extends CustomPainter {
  _CardArt(this.a, this.b);
  final Color a;
  final Color b;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Base: the brand colour sweeping into the deeper one.
    canvas.drawRect(
      rect,
      Paint()..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.lerp(a, Colors.white, 0.06)!, a, b], stops: const [0, 0.45, 1]).createShader(rect),
    );
    // A soft light from the top right.
    final glow = Color.lerp(a, Colors.white, 0.45)!;
    canvas.drawRect(rect, Paint()..shader = RadialGradient(center: const Alignment(0.9, -1.2), radius: 1.15, colors: [glow.withValues(alpha: 0.55), glow.withValues(alpha: 0)]).createShader(rect));
    // Depth in the bottom left.
    canvas.drawRect(rect, Paint()..shader = RadialGradient(center: const Alignment(-1.1, 1.3), radius: 1.0, colors: [Colors.black.withValues(alpha: 0.38), Colors.transparent]).createShader(rect));
    // Fine engraved rings from beyond the right edge.
    final c = Offset(size.width * 1.08, size.height * 0.95);
    for (var i = 0; i < 14; i++) {
      final r = size.width * (0.28 + i * 0.055);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = Colors.white.withValues(alpha: math.max(0.012, 0.075 - i * 0.0045)),
      );
    }
    // A faint diagonal sheen.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: const Alignment(-1, -1),
          end: const Alignment(1, 1),
          colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0.07), Colors.white.withValues(alpha: 0)],
          stops: const [0.28, 0.4, 0.52],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_CardArt old) => old.a != a || old.b != b;
}

/// The bank's initials on frosted glass.
class _Mark extends StatelessWidget {
  const _Mark({this.text, this.icon, required this.size});
  final String? text;
  final IconData? icon;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withValues(alpha: 0.16),
      border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
    ),
    child: icon != null
        ? Icon(icon, size: size * 0.5, color: Colors.white)
        : Padding(
            padding: EdgeInsets.all(size * 0.17),
            child: FittedBox(child: Text(text ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 0.2))),
          ),
  );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(left: 5),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: 0.18))),
    child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
  );
}

class _Flow extends StatelessWidget {
  const _Flow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: Colors.white.withValues(alpha: 0.75)),
      const SizedBox(width: 4),
      Text(fmtCompact(value), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, fontFeatures: tabularFigures)),
      const SizedBox(width: 3),
      Text(label.toLowerCase(), style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11)),
    ],
  );
}

/// Accounts as a snapping carousel of cards with page dots.
class AccountCarousel extends StatefulWidget {
  const AccountCarousel({super.key, required this.accounts, required this.cur, this.onTap, this.compact = true});
  final List<Map<String, dynamic>> accounts;
  final String cur;
  final void Function(int index)? onTap;
  final bool compact;

  @override
  State<AccountCarousel> createState() => _AccountCarouselState();
}

class _AccountCarouselState extends State<AccountCarousel> {
  final _page = PageController(viewportFraction: 0.84);
  int _at = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.accounts.length;
    return LayoutBuilder(
      builder: (context, c) {
        final cardW = c.maxWidth * 0.84 - 10;
        final h = cardW / (widget.compact ? 1.72 : 1.586);
        return Column(
          children: [
            SizedBox(
              // Room under the card for its shadow.
              height: h + 22,
              child: PageView.builder(
                controller: _page,
                padEnds: n == 1,
                itemCount: n,
                onPageChanged: (i) => setState(() => _at = i),
                itemBuilder: (context, i) => AnimatedBuilder(
                  animation: _page,
                  builder: (context, child) {
                    final p = _page.hasClients && _page.position.haveDimensions ? (_page.page ?? 0) : 0.0;
                    final t = (1 - (p - i).abs()).clamp(0.0, 1.0);
                    return Transform.scale(scale: 0.94 + 0.06 * t, alignment: Alignment.topCenter, child: Opacity(opacity: 0.6 + 0.4 * t, child: child));
                  },
                  child: Padding(
                    padding: EdgeInsets.only(left: i == 0 && n > 1 ? 16 : 5, right: 5),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: AccountCard(account: widget.accounts[i], cur: widget.cur, compact: widget.compact, onTap: widget.onTap == null ? null : () => widget.onTap!(i)),
                    ),
                  ),
                ),
              ),
            ),
            if (n > 1)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < n; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: i == _at ? 18 : 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(color: i == _at ? AppColors.text : AppColors.surface3, borderRadius: BorderRadius.circular(3)),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}
