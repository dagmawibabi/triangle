import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import '../../../app/theme.dart';
import '../../chat/presentation/widgets/markets_result_cards.dart' show PriceChart;
import '../finance_privacy.dart';

export '../finance_privacy.dart';
export 'account_card.dart';

// The finance look, shared by the Finance screen and the chat cards:
// colours (income green, spending coral, one colour per category), money
// set large with small decimals, cards, pills, account cards, transaction
// tiles grouped by day, budget tiles and charts.

// ---- colours -------------------------------------------------------------------

Color get finIn => AppColors.success;
Color get finOut => AppColors.isLight ? const Color(0xFFE5484D) : const Color(0xFFFF8473);
Color get finNeutral => AppColors.text2;

const _categoryColors = <String, int>{
  'rent': 0xFF60A5FA,
  'utilities': 0xFFFACC15,
  'groceries': 0xFF34D399,
  'transport': 0xFFFB923C,
  'eating_out': 0xFFF472B6,
  'clothing': 0xFFA78BFA,
  'health': 0xFFF87171,
  'airtime': 0xFF22D3EE,
  'loan': 0xFF94A3B8,
  'repayment_out': 0xFF94A3B8,
  'beauty': 0xFFE879F9,
  'gifts_given': 0xFFF59E0B,
  'education': 0xFF818CF8,
  'entertainment': 0xFFC084FC,
  'shopping': 0xFF2DD4BF,
  'transfer': 0xFF9CA3AF,
  'misc': 0xFFA1A1AA,
  'salary': 0xFF4ADE80,
  'business': 0xFF34D399,
  'side_hustle': 0xFFA3E635,
  'bonus': 0xFFFACC15,
  'refund': 0xFF38BDF8,
  'reimbursement': 0xFF22D3EE,
  'gifts_received': 0xFFF472B6,
  'debt': 0xFF94A3B8,
  'repayment_in': 0xFF94A3B8,
  'income_misc': 0xFFA1A1AA,
};

const _spare = [0xFF60A5FA, 0xFFF59E0B, 0xFF34D399, 0xFFF472B6, 0xFFA78BFA, 0xFFFB923C, 0xFF2DD4BF, 0xFFFACC15];

/// The colour of category [key]; grey for none, a steady pick for custom ones.
Color categoryColor(String? key) {
  if (key == null || key == 'uncategorized' || key == 'income_uncategorized' || key == 'other') return const Color(0xFF8B8B95);
  final v = _categoryColors[key] ?? _spare[key.codeUnits.fold(0, (a, b) => a + b) % _spare.length];
  final c = Color(v);
  // Deeper on paper-white so it still reads.
  return AppColors.isLight ? HSLColor.fromColor(c).withLightness((HSLColor.fromColor(c).lightness * 0.72).clamp(0.0, 1.0)).toColor() : c;
}

IconData categoryIcon(Object? key) => switch ('$key') {
  'home' => Icons.home_rounded,
  'bolt' => Icons.bolt_rounded,
  'cart' => Icons.shopping_cart_rounded,
  'car' => Icons.directions_car_rounded,
  'food' => Icons.restaurant_rounded,
  'shirt' => Icons.checkroom_rounded,
  'health' => Icons.local_hospital_rounded,
  'phone' => Icons.smartphone_rounded,
  'loan' => Icons.request_quote_rounded,
  'gift' => Icons.card_giftcard_rounded,
  'spa' => Icons.spa_rounded,
  'pay' => Icons.payments_rounded,
  'transfer' => Icons.swap_horiz_rounded,
  'school' => Icons.school_rounded,
  'movie' => Icons.movie_rounded,
  'bag' => Icons.shopping_bag_rounded,
  'wallet' => Icons.account_balance_wallet_rounded,
  'in' => Icons.south_west_rounded,
  'out' => Icons.north_east_rounded,
  _ => Icons.more_horiz_rounded,
};

Color hexColor(Object? hex, [Color? fallback]) {
  final s = '${hex ?? ''}'.replaceAll('#', '');
  final v = int.tryParse(s.length == 6 ? 'FF$s' : s, radix: 16);
  return v == null ? (fallback ?? AppColors.surface3) : Color(v);
}

// ---- numbers ------------------------------------------------------------------------

double numOf(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

/// A random but steady 5-digit stand-in for [x] while amounts are hidden:
/// the same amount gets the same stand-in all session (so nothing jumps
/// around as the screen rebuilds), and a new set each time the app starts.
final _decoySalt = math.Random().nextInt(1 << 30);
double _decoy(double x) {
  final h = Object.hash(x.abs().toStringAsFixed(2), _decoySalt) & 0x7fffffff;
  return 10000 + (h % 9000000) / 100; // 10,000.00 – 99,999.99
}

/// "12,345.50", without a currency; whole numbers past 100k. A random
/// 5-digit stand-in while amounts are hidden.
String fmtAmount(Object? v, {int? decimals}) {
  final x = FinPrivacy.hidden ? _decoy(numOf(v)) : numOf(v).abs();
  return NumberFormat.decimalPatternDigits(decimalDigits: decimals ?? (x >= 100000 ? 0 : 2)).format(x);
}

/// "12.3K"; a stand-in while amounts are hidden.
String fmtCompact(Object? v) => NumberFormat.compact().format(FinPrivacy.hidden ? _decoy(numOf(v)) : numOf(v));

/// "ETB 12,345.50" with an optional sign. While hidden there's no sign
/// either, so a total doesn't give away which way it went.
String money(Object? v, String cur, {bool sign = false}) {
  final x = numOf(v);
  if (FinPrivacy.hidden) return '$cur ${fmtAmount(x)}';
  return '${sign ? (x < 0 ? '−' : '+') : (x < 0 ? '−' : '')}$cur ${fmtAmount(x)}';
}

String dayLabel(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(t.year, t.month, t.day);
  if (d == today) return 'Today';
  if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
  if (today.difference(d).inDays < 7) return DateFormat('EEEE').format(t);
  return DateFormat(t.year == now.year ? 'EEE, d MMM' : 'd MMM y').format(t);
}

String whenLabel(Object? iso) {
  final t = DateTime.tryParse('${iso ?? ''}');
  if (t == null) return '';
  final d = dayLabel(t);
  return d == 'Today' || d == 'Yesterday' ? '$d, ${DateFormat('HH:mm').format(t)}' : '$d · ${DateFormat('HH:mm').format(t)}';
}

String timeLabel(Object? iso) {
  final t = DateTime.tryParse('${iso ?? ''}');
  return t == null ? '' : DateFormat('HH:mm').format(t);
}

Map<String, dynamic> mapOf(Object? v) => v is Map ? Map<String, dynamic>.from(v) : const {};
List<Map<String, dynamic>> listOf(Object? v) => [
  for (final x in (v as List? ?? const []))
    if (x is Map) Map<String, dynamic>.from(x),
];

// ---- text -------------------------------------------------------------------------------

/// An amount set the way finance apps do: the whole part large, the
/// decimals and currency small.
class MoneyText extends StatelessWidget {
  const MoneyText(this.value, {super.key, this.cur, this.size = 28, this.color, this.sign = false, this.weight = FontWeight.w700, this.currencyFirst = true});
  final Object? value;
  final String? cur;
  final double size;
  final Color? color;
  final bool sign;
  final FontWeight weight;
  final bool currencyFirst;

  @override
  Widget build(BuildContext context) {
    final x = numOf(value);
    final s = fmtAmount(x);
    final dot = s.lastIndexOf('.');
    final whole = dot < 0 ? s : s.substring(0, dot);
    final frac = dot < 0 ? '' : s.substring(dot);
    final c = color ?? AppColors.text;
    final small = TextStyle(fontSize: size * 0.5, fontWeight: FontWeight.w500, color: c.withValues(alpha: 0.6), letterSpacing: 0);
    final pre = FinPrivacy.hidden ? '' : (sign ? (x < 0 ? '−' : '+') : (x < 0 ? '−' : ''));
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text.rich(
        TextSpan(
          style: TextStyle(fontSize: size, fontWeight: weight, color: c, height: 1.1, letterSpacing: -0.5, fontFeatures: tabularFigures),
          children: [
            if (cur != null && currencyFirst) TextSpan(text: '$cur ', style: small),
            TextSpan(text: '$pre$whole'),
            if (frac.isNotEmpty) TextSpan(text: frac, style: small.copyWith(fontSize: size * 0.55)),
            if (cur != null && !currencyFirst) TextSpan(text: ' $cur', style: small),
          ],
        ),
        maxLines: 1,
      ),
    );
  }
}

/// A small caption in the muted tone.
class Caption extends StatelessWidget {
  const Caption(this.text, {super.key, this.color, this.maxLines = 1});
  final String text;
  final Color? color;
  final int maxLines;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: context.text.bodySmall?.copyWith(color: color ?? AppColors.text3, height: 1.3), maxLines: maxLines, overflow: TextOverflow.ellipsis);
}

// ---- containers ------------------------------------------------------------------------------

/// A rounded panel on the surface colour.
class FinCard extends StatelessWidget {
  const FinCard({super.key, required this.child, this.padding = const EdgeInsets.all(Space.l), this.onTap, this.margin = const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.m), this.color});
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: margin,
    child: Material(
      color: color ?? AppColors.surface,
      borderRadius: BorderRadius.circular(Radii.xl),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.xl),
            border: Border.all(color: AppColors.line.withValues(alpha: 0.7)),
          ),
          padding: padding,
          child: child,
        ),
      ),
    ),
  );
}

/// A card's title row: title, an optional caption, and an action.
class CardTitle extends StatelessWidget {
  const CardTitle(this.title, {super.key, this.caption, this.action, this.onAction, this.trailing});
  final String title;
  final String? caption;
  final String? action;
  final VoidCallback? onAction;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.1)),
            if (caption != null) ...[const SizedBox(height: 2), Caption(caption!)],
          ],
        ),
      ),
      ?trailing,
      if (action != null)
        GestureDetector(
          onTap: onAction,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.only(left: Space.s),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(action!, style: context.text.labelMedium?.copyWith(color: AppColors.text2)),
                Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.text3),
              ],
            ),
          ),
        ),
    ],
  );
}

/// A section title outside a card.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action, this.onAction, this.padding = const EdgeInsets.fromLTRB(Space.xl, Space.xl, Space.l, Space.s)});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: CardTitle(title, action: action, onAction: onAction),
  );
}

// ---- small pieces ------------------------------------------------------------------------------

/// A category's icon on a tinted rounded square.
class CategoryIconTile extends StatelessWidget {
  const CategoryIconTile({super.key, this.icon, this.category, this.size = 40, this.color});
  final Object? icon;
  final String? category;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? categoryColor(category);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.withValues(alpha: AppColors.isLight ? 0.13 : 0.16), borderRadius: BorderRadius.circular(size * 0.32)),
      child: Icon(categoryIcon(icon), size: size * 0.5, color: c),
    );
  }
}

/// A compact selectable pill, for categories, filters and periods.
class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, required this.selected, required this.onTap, this.icon, this.color, this.dense = false});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? color;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.text;
    return Material(
      color: selected ? (color == null ? AppColors.text : c.withValues(alpha: 0.18)) : AppColors.surface2,
      shape: StadiumBorder(side: BorderSide(color: selected ? (color == null ? AppColors.text : c.withValues(alpha: 0.7)) : AppColors.line)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 12, vertical: dense ? 5 : 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: dense ? 14 : 16, color: selected && color == null ? AppColors.bg : (color ?? AppColors.text2)),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: (dense ? context.text.labelMedium : context.text.labelLarge)?.copyWith(
                  color: selected && color == null ? AppColors.bg : AppColors.text,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One choice out of a few, as a single rounded track.
class PillTabs<T> extends StatelessWidget {
  const PillTabs({super.key, required this.options, required this.value, required this.onChanged});
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    height: 38,
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(12)),
    child: Row(
      children: [
        for (final (v, label) in options)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(v),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: v == value ? AppColors.surface3 : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: v == value ? [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 4, offset: const Offset(0, 1))] : null,
                ),
                // Shrinks rather than clips when the tabs are many.
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: context.text.labelMedium?.copyWith(color: v == value ? AppColors.text : AppColors.text3, fontWeight: v == value ? FontWeight.w600 : FontWeight.w500),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// "▲ 12%" against the period before; green when it moved the good way.
class DeltaBadge extends StatelessWidget {
  const DeltaBadge({super.key, required this.pct, this.upIsGood = false, this.suffix});
  final double pct;
  final bool upIsGood;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final up = pct >= 0;
    final good = up == upIsGood;
    final c = pct.abs() < 0.5 ? AppColors.text3 : (good ? finIn : finOut);
    final v = pct.abs() >= 1000 ? '${(pct.abs() / 100).toStringAsFixed(0)}×' : '${pct.abs().toStringAsFixed(0)}%';
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 2, 7, 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(up ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded, size: 18, color: c),
          Text('$v${suffix == null ? '' : ' $suffix'}', style: context.text.labelSmall?.copyWith(color: c, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// A bank's initials on its colour.
class BankBadge extends StatelessWidget {
  const BankBadge({super.key, required this.name, this.colors = const [], this.size = 36});
  final String name;
  final List<Object?> colors;
  final double size;

  @override
  Widget build(BuildContext context) {
    final a = colors.isEmpty ? AppColors.surface3 : hexColor(colors.first);
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final initials = name.length <= 4 ? name.toUpperCase() : (words.length > 1 ? words.take(2).map((w) => w[0]).join() : name.substring(0, 2)).toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [a, Color.lerp(a, Colors.black, 0.3)!], begin: Alignment.topLeft, end: Alignment.bottomRight),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: EdgeInsets.all(size * 0.14),
        child: FittedBox(child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 0.3))),
      ),
    );
  }
}

// ---- accounts --------------------------------------------------------------------------------------

/// An account as a list row: badge, name, balance.
class AccountRow extends StatelessWidget {
  const AccountRow({super.key, required this.account, required this.cur, this.onTap});
  final Map<String, dynamic> account;
  final String cur;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ending = account['number_ending'];
    final name = '${account['nickname'] ?? ''}'.isNotEmpty ? '${account['nickname']}' : '${account['bank_name'] ?? account['bank']}';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s + 2),
        child: Row(
          children: [
            BankBadge(name: '${account['bank'] ?? ''}', colors: account['colors'] as List? ?? const [], size: 40),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Caption([account['bank'], if (ending != null) '•••• $ending', if (account['detected'] == true) 'found in texts'].join(' · ')),
                ],
              ),
            ),
            Text(fmtAmount(account['balance']), style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w700, fontFeatures: tabularFigures)),
          ],
        ),
      ),
    );
  }
}

// ---- transactions -----------------------------------------------------------------------------------

/// One transaction: category tile, who, category and account, amount and
/// time. Income is green; spending stays in the text colour.
class TxTile extends StatelessWidget {
  const TxTile({super.key, required this.tx, required this.cur, this.onTap, this.showDay = false, this.dense = false});
  final Map<String, dynamic> tx;
  final String cur;
  final VoidCallback? onTap;
  final bool showDay;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final income = tx['type'] == 'income';
    final transfer = tx['own_transfer'] == true || tx['category'] == 'transfer';
    final title = '${tx['counterparty'] ?? tx['note'] ?? tx['category_name'] ?? (income ? 'Money in' : 'Money out')}';
    final sub = [
      tx['category_name'] ?? (transfer ? 'Own transfer' : 'Uncategorized'),
      tx['account'] ?? tx['bank'],
    ].whereType<Object>().join(' · ');
    final color = transfer ? AppColors.text2 : (income ? finIn : AppColors.text);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: Space.l, vertical: dense ? 7 : Space.s + 2),
        child: Row(
          children: [
            CategoryIconTile(
              icon: transfer ? 'transfer' : (tx['icon'] ?? (income ? 'in' : 'out')),
              category: tx['category'],
              color: tx['category'] == null && !transfer ? (income ? finIn : AppColors.text2) : null,
              size: dense ? 36 : 42,
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 1),
                  Caption(sub, color: tx['category'] == null && !transfer && !income ? AppColors.warning.withValues(alpha: 0.85) : null),
                ],
              ),
            ),
            const SizedBox(width: Space.s),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${income ? '+' : '−'}${fmtAmount(tx['amount'])}',
                  style: context.text.bodyMedium?.copyWith(color: color, fontWeight: FontWeight.w700, fontFeatures: tabularFigures),
                ),
                const SizedBox(height: 1),
                Caption(showDay ? whenLabel(tx['date']) : timeLabel(tx['date'])),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// [txs] (newest first) under day headings, each with the day's net.
List<Widget> groupedByDay(List<Map<String, dynamic>> txs, String cur, {void Function(Map<String, dynamic> tx, int index)? onTap, bool dense = false, EdgeInsets headerPadding = const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, 2)}) {
  final out = <Widget>[];
  DateTime? day;
  for (var i = 0; i < txs.length; i++) {
    final t = DateTime.tryParse('${txs[i]['date']}');
    final d = t == null ? null : DateTime(t.year, t.month, t.day);
    if (d != null && d != day) {
      day = d;
      final same = txs.where((x) {
        final y = DateTime.tryParse('${x['date']}');
        return y != null && DateTime(y.year, y.month, y.day) == d;
      });
      final net = same.fold(0.0, (s, x) => s + (x['type'] == 'income' ? numOf(x['amount']) : -numOf(x['amount'])));
      out.add(_DayHeader(label: dayLabel(d), net: net, padding: headerPadding));
    }
    final tx = txs[i];
    out.add(TxTile(tx: tx, cur: cur, dense: dense, onTap: onTap == null ? null : () => onTap(tx, i)));
  }
  return out;
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label, required this.net, required this.padding});
  final String label;
  final double net;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      children: [
        Text(label.toUpperCase(), style: context.text.labelSmall?.copyWith(color: AppColors.text3, letterSpacing: 0.8, fontWeight: FontWeight.w600)),
        const Spacer(),
        Text(
          '${net >= 0 ? '+' : '−'}${fmtAmount(net)}',
          style: context.text.labelSmall?.copyWith(color: net >= 0 ? finIn.withValues(alpha: 0.8) : AppColors.text3, fontFeatures: tabularFigures),
        ),
      ],
    ),
  );
}

// ---- budgets --------------------------------------------------------------------------------------------

Color budgetColor(Map<String, dynamic> b) {
  final p = numOf(b['progress']);
  if (b['over'] == true) return finOut;
  if (p > 0.85) return AppColors.warning;
  return categoryColor(b['category'] as String?);
}

/// A budget: its category, a thick bar, what's spent and what's left.
class BudgetTile extends StatelessWidget {
  const BudgetTile({super.key, required this.budget, required this.cur, this.onTap, this.padding = const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m)});
  final Map<String, dynamic> budget;
  final String cur;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final p = numOf(budget['progress']);
    final over = budget['over'] == true;
    final c = budgetColor(budget);
    final cat = budget['category'] as String?;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: padding,
        child: Column(
          children: [
            Row(
              children: [
                CategoryIconTile(icon: budget['icon'], category: cat, color: cat == null ? AppColors.text2 : null, size: 38),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${budget['name']}', style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                      Caption(
                        over
                            ? 'Over by ${fmtAmount(-numOf(budget['remaining']))}'
                            : '${fmtAmount(budget['remaining'])} left · ${budget['days_left']} ${budget['days_left'] == 1 ? 'day' : 'days'}${budget['per_day_left'] != null ? ' · ${fmtCompact(budget['per_day_left'])}/day' : ''}',
                        color: over ? finOut : null,
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${(p * 100).round()}%', style: context.text.titleSmall?.copyWith(color: c, fontWeight: FontWeight.w700)),
                    Caption(budget['period'] == 'week' ? 'weekly' : 'monthly'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: Space.s + 2),
            ThickBar(value: p, color: c),
            const SizedBox(height: 6),
            Row(
              children: [
                Caption('${fmtAmount(budget['spent'])} spent'),
                const Spacer(),
                Caption('of ${fmtAmount(budget['limit'])} $cur'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A rounded progress bar.
class ThickBar extends StatelessWidget {
  const ThickBar({super.key, required this.value, required this.color, this.height = 8});
  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => Container(
      height: height,
      decoration: BoxDecoration(color: AppColors.surface3, borderRadius: BorderRadius.circular(height)),
      alignment: Alignment.centerLeft,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        width: c.maxWidth * value.clamp(0.0, 1.0),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(height)),
      ),
    ),
  );
}

// ---- cash flow & categories -------------------------------------------------------------------------------

/// Money in and out side by side, with the split as one bar and the net.
class CashFlow extends StatelessWidget {
  const CashFlow({super.key, required this.income, required this.expense, required this.cur, this.previous, this.savingsRate});
  final double income;
  final double expense;
  final String cur;
  final Map<String, dynamic>? previous;
  final Object? savingsRate;

  @override
  Widget build(BuildContext context) {
    final total = income + expense;
    final net = income - expense;
    final exChange = previous?['expense_change_pct'];
    final inChange = previous?['income_change_pct'];
    Widget side(String label, double v, Color c, IconData icon, Object? change, bool upGood) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(color: c.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: Icon(icon, size: 13, color: c),
              ),
              const SizedBox(width: 6),
              Text(label, style: context.text.labelMedium?.copyWith(color: AppColors.text2)),
            ],
          ),
          const SizedBox(height: Space.s),
          MoneyText(v, size: 22),
          const SizedBox(height: 4),
          // A change of more than 5× means the period before had hardly any
          // data, so it says nothing.
          if (change is num && change.abs() <= 500) DeltaBadge(pct: change.toDouble(), upIsGood: upGood) else const SizedBox(height: 22),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            side('Money in', income, finIn, Icons.south_west_rounded, inChange, true),
            Container(width: 1, height: 70, color: AppColors.line, margin: const EdgeInsets.symmetric(horizontal: Space.m)),
            side('Spent', expense, finOut, Icons.north_east_rounded, exChange, false),
          ],
        ),
        const SizedBox(height: Space.m),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 6,
            child: total <= 0
                ? Container(color: AppColors.surface3)
                : Row(
                    children: [
                      Expanded(flex: math.max(1, (income / total * 1000).round()), child: Container(color: finIn)),
                      const SizedBox(width: 2),
                      Expanded(flex: math.max(1, (expense / total * 1000).round()), child: Container(color: finOut)),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: Space.s),
        Row(
          children: [
            Text('Net ', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
            Text(money(net, cur, sign: true), style: context.text.bodySmall?.copyWith(color: net >= 0 ? finIn : finOut, fontWeight: FontWeight.w600, fontFeatures: tabularFigures)),
            const SizedBox(width: Space.s),
            if (savingsRate is num) Expanded(child: Text('Saved ${((savingsRate as num) * 100).round()}%', textAlign: TextAlign.end, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: AppColors.text3))),
          ],
        ),
      ],
    );
  }
}

/// Spending by category: the shares as one stacked bar, then a row for
/// each with its icon, count, amount and share.
class CategoryBreakdown extends StatelessWidget {
  const CategoryBreakdown({super.key, required this.items, required this.cur, this.limit = 6, this.onTap, this.total});

  /// [{key, name, amount, share, count, icon}], largest first.
  final List<Map<String, dynamic>> items;
  final String cur;
  final int limit;
  final double? total;
  final void Function(String key)? onTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final double sum = total ?? items.fold<double>(0.0, (s, x) => s + numOf(x['amount']));
    final top = items.take(limit).toList();
    final rest = items.skip(limit).toList();
    final restAmount = rest.fold(0.0, (s, x) => s + numOf(x['amount']));
    final rows = [
      ...top,
      if (restAmount > 0) {'key': 'other', 'name': '${rest.length} more', 'amount': restAmount, 'share': sum == 0 ? 0 : restAmount / sum, 'count': rest.fold(0, (s, x) => s + (x['count'] as num? ?? 0).toInt()), 'icon': 'more'},
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 10,
            child: Row(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Expanded(flex: math.max(1, (numOf(rows[i]['amount']) * 1000 / math.max(1, sum)).round()), child: Container(color: categoryColor('${rows[i]['key']}'))),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.s),
        for (final r in rows)
          InkWell(
            borderRadius: BorderRadius.circular(Radii.m),
            onTap: onTap == null || r['key'] == 'other' ? null : () => onTap!('${r['key']}'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  CategoryIconTile(icon: r['icon'], category: '${r['key']}', size: 34),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${r['name']}', style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Caption('${r['count']} ${r['count'] == 1 ? 'payment' : 'payments'}'),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(fmtAmount(r['amount']), style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600, fontFeatures: tabularFigures)),
                      Caption('${(numOf(r['share']) * 100).toStringAsFixed(numOf(r['share']) < 0.1 ? 1 : 0)}%'),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// People or sources with a letter avatar and a bar for the amount.
class RankList extends StatelessWidget {
  const RankList({super.key, required this.items, required this.color, this.limit = 5});
  final List<Map<String, dynamic>> items;
  final Color color;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final hi = items.fold(0.0, (s, x) => math.max(s, numOf(x['amount'])));
    return Column(
      children: [
        for (final x in items.take(limit))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: color.withValues(alpha: 0.14),
                  child: Text('${x['name']}'.trim().isEmpty ? '?' : '${x['name']}'.trim()[0].toUpperCase(), style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text('${x['name']}', style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis)),
                          Text(fmtAmount(x['amount']), style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600, fontFeatures: tabularFigures)),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Expanded(child: ThickBar(value: hi == 0 ? 0 : numOf(x['amount']) / hi, color: color.withValues(alpha: 0.75), height: 4)),
                          const SizedBox(width: Space.s),
                          Caption('${x['count']}×'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---- charts --------------------------------------------------------------------------------------------

/// Bars per day, week or month: spending, income or both, with the average
/// as a dashed line. Press or drag to read a bar.
class FlowChart extends StatefulWidget {
  const FlowChart({super.key, required this.points, this.height = 150, this.mode = 'expense', this.showAverage = true});

  /// [{label, income, expense}], oldest first.
  final List<Map<String, dynamic>> points;
  final double height;

  /// "expense", "income" or "both".
  final String mode;
  final bool showAverage;

  @override
  State<FlowChart> createState() => _FlowChartState();
}

class _FlowChartState extends State<FlowChart> {
  int? _at;

  void _pick(Offset p, double w) {
    if (widget.points.isEmpty) return;
    const left = 0.0;
    final i = ((p.dx - left) / (w - left) * widget.points.length).floor().clamp(0, widget.points.length - 1);
    if (i != _at) setState(() => _at = i);
  }

  @override
  Widget build(BuildContext context) {
    final pts = widget.points;
    if (pts.isEmpty) return SizedBox(height: widget.height);
    final inc = [for (final p in pts) numOf(p['income'])];
    final exp = [for (final p in pts) numOf(p['expense'])];
    final series = widget.mode == 'income' ? inc : exp;
    final avg = series.isEmpty ? 0.0 : series.reduce((a, b) => a + b) / series.length;
    final sel = _at == null ? null : pts[_at!];
    final label = context.text.labelSmall!.copyWith(color: AppColors.text3, fontSize: 10);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 22,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: sel == null
                ? Row(
                    key: const ValueKey('legend'),
                    children: [
                      if (widget.mode == 'both') ...[_legend(finIn, 'In'), const SizedBox(width: Space.m), _legend(finOut, 'Out')],
                      const Spacer(),
                      if (widget.showAverage) Text('avg ${fmtCompact(avg)}', style: label.copyWith(fontSize: 11)),
                    ],
                  )
                : Row(
                    key: ValueKey(_at),
                    children: [
                      Text('${sel['label']}', style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      if (widget.mode != 'expense') Text('+${fmtAmount(sel['income'])}', style: context.text.labelMedium?.copyWith(color: finIn, fontFeatures: tabularFigures)),
                      if (widget.mode == 'both') const SizedBox(width: Space.m),
                      if (widget.mode != 'income') Text('−${fmtAmount(sel['expense'])}', style: context.text.labelMedium?.copyWith(color: finOut, fontFeatures: tabularFigures)),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: Space.xs),
        LayoutBuilder(
          builder: (context, c) => GestureDetector(
            onTapDown: (d) => _pick(d.localPosition, c.maxWidth),
            onHorizontalDragUpdate: (d) => _pick(d.localPosition, c.maxWidth),
            onTapUp: (_) => Future.delayed(const Duration(seconds: 3), () {
              if (mounted) setState(() => _at = null);
            }),
            child: CustomPaint(
              size: Size(c.maxWidth, widget.height),
              painter: _FlowPainter(
                income: inc,
                expense: exp,
                labels: [for (final p in pts) '${p['label']}'],
                mode: widget.mode,
                at: _at,
                average: widget.showAverage ? avg : null,
                inColor: finIn,
                outColor: finOut,
                track: AppColors.surface2,
                grid: AppColors.line,
                label: label,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _legend(Color c, String t) => Row(
    children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 4),
      Text(t, style: context.text.labelSmall?.copyWith(color: AppColors.text2)),
    ],
  );
}

class _FlowPainter extends CustomPainter {
  _FlowPainter({
    required this.income,
    required this.expense,
    required this.labels,
    required this.mode,
    required this.at,
    required this.average,
    required this.inColor,
    required this.outColor,
    required this.track,
    required this.grid,
    required this.label,
  });
  final List<double> income;
  final List<double> expense;
  final List<String> labels;
  final String mode;
  final int? at;
  final double? average;
  final Color inColor;
  final Color outColor;
  final Color track;
  final Color grid;
  final TextStyle label;

  @override
  void paint(Canvas canvas, Size size) {
    const bottom = 18.0;
    final h = size.height - bottom;
    final w = size.width;
    final both = mode == 'both';
    final values = [if (mode != 'expense') ...income, if (mode != 'income') ...expense];
    final hi = values.fold(0.0, math.max);
    final top = hi <= 0 ? 1.0 : hi * 1.08;
    final n = income.length;
    final slot = w / n;
    final barW = both ? math.min(12.0, slot * 0.34) : math.min(22.0, math.max(2.0, slot * 0.62));

    // Baseline.
    canvas.drawLine(Offset(0, h + 0.5), Offset(w, h + 0.5), Paint()..color = grid);

    for (var i = 0; i < n; i++) {
      final cx = slot * i + slot / 2;
      final dim = at != null && at != i;
      void bar(double v, double x, Color c) {
        final bh = v <= 0 ? 0.0 : math.max(2.0, v / top * h);
        final r = Radius.circular(math.min(5, barW / 2));
        // A faint full-height track keeps sparse days readable.
        if (!both && n <= 40) {
          canvas.drawRRect(RRect.fromRectAndCorners(Rect.fromLTWH(x, 0, barW, h), topLeft: r, topRight: r), Paint()..color = track.withValues(alpha: 0.55));
        }
        if (bh > 0) canvas.drawRRect(RRect.fromRectAndCorners(Rect.fromLTWH(x, h - bh, barW, bh), topLeft: r, topRight: r), Paint()..color = c.withValues(alpha: dim ? 0.3 : 1));
      }

      if (both) {
        bar(income[i], cx - barW - 1, inColor);
        bar(expense[i], cx + 1, outColor);
      } else {
        bar(mode == 'income' ? income[i] : expense[i], cx - barW / 2, mode == 'income' ? inColor : outColor);
      }
    }

    // The average, dashed.
    if (average != null && average! > 0) {
      final y = h - average! / top * h;
      final p = Paint()
        ..color = label.color!.withValues(alpha: 0.8)
        ..strokeWidth = 1;
      for (var x = 0.0; x < w; x += 7) {
        canvas.drawLine(Offset(x, y), Offset(math.min(w, x + 3.5), y), p);
      }
    }

    // Labels: as many as fit.
    final every = math.max(1, (n / math.max(1, (w / 52).floor())).ceil());
    for (var i = 0; i < n; i += every) {
      final tp = TextPainter(text: TextSpan(text: labels[i], style: label), textDirection: TextDirection.ltr)..layout();
      final x = (slot * i + slot / 2 - tp.width / 2).clamp(0.0, w - tp.width);
      tp.paint(canvas, Offset(x, h + 5));
    }
  }

  @override
  bool shouldRepaint(_FlowPainter old) => old.at != at || old.mode != mode || old.income != income || old.expense != expense || old.inColor != inColor;
}

/// A half-circle gauge for the health score.
class ScoreGauge extends StatelessWidget {
  const ScoreGauge({super.key, required this.score, required this.color, this.size = 150, this.caption});
  final int score;
  final Color color;
  final double size;
  final String? caption;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size * 0.6,
    child: CustomPaint(
      painter: _GaugePainter(score / 100, color, AppColors.surface3),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$score', style: TextStyle(fontSize: size * 0.24, fontWeight: FontWeight.w800, color: AppColors.text, height: 1)),
            if (caption != null) Text(caption!, style: context.text.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    ),
  );
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.value, this.color, this.track);
  final double value;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.075;
    final r = size.width / 2 - stroke / 2;
    final rect = Rect.fromCircle(center: Offset(size.width / 2, size.height - stroke * 0.2), radius: r);
    Paint p(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi, math.pi, false, p(track));
    final sweep = math.pi * value.clamp(0.0, 1.0);
    if (sweep > 0) {
      canvas.drawArc(
        rect,
        math.pi,
        sweep,
        false,
        p(color)..shader = SweepGradient(startAngle: math.pi, endAngle: math.pi * 2, colors: [color.withValues(alpha: 0.55), color]).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.value != value || old.color != color;
}

Color scoreColor(int score) => score >= 75 ? finIn : score >= 55 ? const Color(0xFF60A5FA) : score >= 35 ? AppColors.warning : finOut;

/// A ring that fills to [value], with [child] in the middle.
class RingProgress extends StatelessWidget {
  const RingProgress({super.key, required this.value, required this.color, this.size = 96, this.stroke = 9, this.child});
  final double value;
  final Color color;
  final double size;
  final double stroke;
  final Widget? child;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _RingPainter(value, color, AppColors.surface3, stroke), child: Center(child: child)),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.color, this.track, this.stroke);
  final double value;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: size.shortestSide / 2 - stroke / 2);
    Paint p(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, p(track));
    final v = value.clamp(0.0, 1.0);
    if (v > 0) canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * v, false, p(color));
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.color != color;
}

/// A soft line of the balance, for a hero; no axes.
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, this.height = 48, this.color});
  final List<double> values;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) => values.length < 2
      ? SizedBox(height: height)
      : SizedBox(height: height, width: double.infinity, child: CustomPaint(painter: _SparkPainter(values, color ?? AppColors.text2)));
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color);
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final lo = values.reduce(math.min), hi = values.reduce(math.max);
    final span = hi - lo == 0 ? 1 : hi - lo;
    Offset at(int i) => Offset(size.width * i / (values.length - 1), size.height - 2 - (values[i] - lo) / span * (size.height - 4));
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      final a = at(i - 1), b = at(i);
      final mx = (a.dx + b.dx) / 2;
      path.cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
    }
    final area = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)]).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    final end = at(values.length - 1);
    canvas.drawCircle(end, 3.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.values != values || old.color != color;
}

// ---- category picker ----------------------------------------------------------------------------------------

/// Categories as compact pills that wrap tightly; tap again to clear.
class CategoryPills extends StatelessWidget {
  const CategoryPills({super.key, required this.categories, required this.selected, required this.onChanged});

  /// (key, name, icon).
  final List<(String, String, String)> categories;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final (key, name, icon) in categories)
        Pill(
          dense: true,
          label: name,
          icon: categoryIcon(icon),
          color: categoryColor(key),
          selected: selected == key,
          onTap: () => onChanged(selected == key ? null : key),
        ),
    ],
  );
}

/// Categories as a grid of icon tiles, for full pages.
class CategoryGrid extends StatelessWidget {
  const CategoryGrid({super.key, required this.categories, required this.selected, required this.onChanged, this.allLabel});

  /// (key, name, icon).
  final List<(String, String, String)> categories;
  final String? selected;
  final ValueChanged<String?> onChanged;

  /// When set, a first tile for "no category" (all spending).
  final String? allLabel;

  @override
  Widget build(BuildContext context) {
    final tiles = [if (allLabel != null) (null, allLabel!, 'wallet'), for (final c in categories) (c.$1, c.$2, c.$3)];
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: Space.s,
      crossAxisSpacing: Space.s,
      childAspectRatio: 0.92,
      children: [
        for (final (key, name, icon) in tiles)
          () {
            final on = selected == key;
            final c = key == null ? AppColors.text : categoryColor(key);
            return Material(
              color: on ? c.withValues(alpha: 0.16) : AppColors.surface,
              borderRadius: BorderRadius.circular(Radii.l),
              child: InkWell(
                borderRadius: BorderRadius.circular(Radii.l),
                onTap: () => onChanged(key),
                child: Container(
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: on ? c.withValues(alpha: 0.8) : AppColors.line, width: on ? 1.5 : 1)),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: Space.s),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CategoryIconTile(icon: icon, category: key, color: key == null ? AppColors.text2 : null, size: 34),
                      const SizedBox(height: 6),
                      Text(name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: on ? AppColors.text : AppColors.text2, height: 1.15)),
                    ],
                  ),
                ),
              ),
            );
          }(),
      ],
    );
  }
}

// ---- hiding amounts -------------------------------------------------------------------------------

/// The eye that hides or shows every amount, here and in the chat's cards.
class HideAmountsButton extends StatelessWidget {
  const HideAmountsButton({super.key, this.size = 22, this.color, this.compact = false});
  final double size;
  final Color? color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final hidden = FinPrivacy.hidden;
    return IconButton(
      tooltip: hidden ? 'Show amounts' : 'Hide amounts',
      visualDensity: compact ? VisualDensity.compact : null,
      iconSize: size,
      constraints: compact ? const BoxConstraints(minWidth: 32, minHeight: 32) : null,
      padding: compact ? EdgeInsets.zero : null,
      onPressed: FinPrivacy.toggle,
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
        child: Icon(hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined, key: ValueKey(hidden), color: color ?? AppColors.text2),
      ),
    );
  }
}

/// The balance over time: pressable with its values, or just its shape
/// while amounts are hidden.
class BalanceChart extends StatelessWidget {
  const BalanceChart({super.key, required this.values, required this.times, required this.cur, this.height = 150});
  final List<double> values;
  final List<int> times;
  final String cur;
  final double height;

  @override
  Widget build(BuildContext context) => FinPrivacy.hidden
      ? Sparkline(values: values, height: height * 0.8, color: AppColors.text2)
      : PriceChart(values: values, times: times, height: height, currency: cur.toLowerCase());
}
