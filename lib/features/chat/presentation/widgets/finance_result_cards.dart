import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme.dart';
import '../../../finance/finance_screen.dart';
import '../../../finance/ui/finance_sheets.dart';
import '../../../finance/ui/finance_ui.dart';
import '../../domain/chat_models.dart';

/// Cards for the finance tools, drawn with the Finance screen's pieces: the
/// money dashboard, accounts, transactions grouped by day, income and
/// spending charts, categories, balance history, budgets, the health
/// score, SMS syncs and parsed messages. A transaction opens its sheet
/// (categorize it there); "Open" goes to the Finance screen. Null for
/// other tools.
Widget? financeResultFor(ToolPart part, Map<String, dynamic> j) {
  if (!part.name.startsWith('finance_') || j['error'] != null) return null;
  final cur = '${j['currency'] ?? 'ETB'}';
  return switch (part.name) {
    'finance_overview' => _OverviewCard(data: j, cur: cur),
    'finance_accounts' => _AccountsCard(data: j, cur: cur),
    'finance_add_account' || 'finance_update_account' when j['account'] is Map => _Frame(
      icon: Icons.account_balance_rounded,
      title: part.name == 'finance_add_account' ? 'Account added' : 'Account updated',
      tab: 1,
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m), child: AccountCard(account: mapOf(j['account']), cur: cur)),
        if (j['moved_transactions'] != null) _Note('${j['moved_transactions']} earlier transactions moved onto it.'),
      ],
    ),
    'finance_delete_account' when j['account'] is Map => _Frame(
      icon: Icons.delete_outline_rounded,
      title: 'Account removed',
      children: [
        AccountRow(account: mapOf(j['account']), cur: cur),
        _Note(j['transactions_deleted'] != null ? '${j['transactions_deleted']} transactions deleted with it.' : '${j['transactions_kept'] ?? 0} transactions kept, without an account.'),
      ],
    ),
    'finance_transactions' => _TransactionsCard(data: j, cur: cur),
    'finance_add_transaction' || 'finance_update_transaction' || 'finance_delete_transaction' when j['transaction'] is Map => _Frame(
      icon: switch (part.name) {
        'finance_add_transaction' => Icons.add_card_rounded,
        'finance_delete_transaction' => Icons.delete_outline_rounded,
        _ => Icons.edit_rounded,
      },
      title: switch (part.name) {
        'finance_add_transaction' => 'Recorded',
        'finance_delete_transaction' => 'Deleted',
        _ => 'Updated',
      },
      tab: 2,
      children: [
        _Tx(tx: mapOf(j['transaction']), cur: cur, showDay: true),
        if (j['rule_saved'] != null) _Note('From now on: ${j['rule_saved']}${j['also_categorized'] != null ? ' · ${j['also_categorized']} more filed' : ''}'),
        if (mapOf(j['account'])['balance'] != null) _Note('${mapOf(j['account'])['name']} is now at ${money(mapOf(j['account'])['balance'], cur)}.'),
        const SizedBox(height: Space.xs),
      ],
    ),
    'finance_summary' when j['period'] is Map => _SummaryCard(data: j, cur: cur),
    'finance_insights' when j['view'] != null || j['health_score'] != null => _InsightsCard(data: j, cur: cur),
    'finance_budgets' || 'finance_set_budget' => _BudgetsCard(budgets: listOf(j['budgets']), cur: cur, removed: j['removed'] == true),
    'finance_sync_sms' when j['scanned'] != null => _SyncCard(data: j, cur: cur),
    'finance_parse_sms' => _ParsedCard(data: j, cur: cur),
    'finance_categories' when j['categories'] is List => _CategoriesCard(data: j),
    'finance_categorize' => _CategorizedCard(data: j),
    'finance_banks' when j['banks'] is List => _BanksCard(data: j),
    'finance_update_patterns' when j['patterns'] is Map => _Frame(
      icon: j['updated'] == true ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
      title: j['updated'] != true ? 'Patterns not updated' : (j['changed'] == true ? 'Bank patterns updated' : 'Bank patterns up to date'),
      children: [
        _Note(
          [
            mapOf(j['patterns'])['source'] == 'downloaded' ? 'From Totals' : 'Shipped with the app',
            '${mapOf(j['patterns'])['patterns']} patterns · ${mapOf(j['patterns'])['banks']} banks',
            if (j['error'] != null) '${j['error']}',
          ].join(' · '),
        ),
      ],
    ),
    _ => null,
  };
}

class _CategorizedCard extends StatelessWidget {
  const _CategorizedCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final c = mapOf(data['category']);
    return _Frame(
      icon: Icons.sell_rounded,
      title: data['forgotten'] == true ? 'Rule removed' : 'Categorized',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
          child: data['forgotten'] == true
              ? Caption('${data['counterparty']} will no longer be filed automatically.', color: AppColors.text2, maxLines: 2)
              : Row(
                  children: [
                    CategoryIconTile(icon: c['icon'], category: '${c['key']}', size: 40),
                    const SizedBox(width: Space.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${data['counterparty']} → ${c['name']}', style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                          Caption('${data['categorized'] ?? 0} transactions filed${data['created_category'] == true ? ' · new category' : ''}'),
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

void _openFinance(BuildContext context, [int tab = 0]) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FinanceScreen(initialTab: tab)));

/// The chat card: an icon, a title and caption, "Open", then the body.
class _Frame extends StatelessWidget {
  const _Frame({required this.icon, required this.title, required this.children, this.subtitle, this.tab});
  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Widget> children;

  /// The Finance tab "Open" goes to; no button when null.
  final int? tab;

  @override
  Widget build(BuildContext context) {
    FinPrivacy.load();
    return _frame(context);
  }

  Widget _frame(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: Space.s),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.xl), border: Border.all(color: AppColors.line)),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.s, Space.m),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(9)),
                child: Icon(icon, size: 16, color: AppColors.text2),
              ),
              const SizedBox(width: Space.s + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (subtitle != null && subtitle!.isNotEmpty) Caption(subtitle!),
                  ],
                ),
              ),
              HideAmountsButton(size: 18, compact: true, color: AppColors.text3),
              if (tab != null)
                TextButton(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: AppColors.text2, padding: const EdgeInsets.symmetric(horizontal: Space.s)),
                  onPressed: () => _openFinance(context, tab!),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [Text('Open'), Icon(Icons.chevron_right_rounded, size: 18)]),
                ),
            ],
          ),
        ),
        ...children,
      ],
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
    child: Caption(text, color: AppColors.text2, maxLines: 4),
  );
}

/// A block inside a card with a little title.
class _Block extends StatelessWidget {
  const _Block({required this.title, required this.child, this.caption, this.padding = const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.m)});
  final String title;
  final String? caption;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(title.toUpperCase(), style: context.text.labelSmall?.copyWith(color: AppColors.text3, letterSpacing: 0.9, fontWeight: FontWeight.w600)),
            const Spacer(),
            if (caption != null) Caption(caption!),
          ],
        ),
        const SizedBox(height: Space.s),
        child,
      ],
    ),
  );
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Divider(height: 1, color: AppColors.line, indent: Space.m, endIndent: Space.m);
}

/// A transaction row that opens its sheet.
class _Tx extends StatelessWidget {
  const _Tx({required this.tx, required this.cur, this.showDay = false});
  final Map<String, dynamic> tx;
  final String cur;
  final bool showDay;

  @override
  Widget build(BuildContext context) => TxTile(tx: tx, cur: cur, dense: true, showDay: showDay, onTap: () => showTransactionSheet(context, tx, cur));
}

List<Widget> _days(BuildContext context, List<Map<String, dynamic>> txs, String cur) =>
    groupedByDay(txs, cur, dense: true, onTap: (t, _) => showTransactionSheet(context, t, cur), headerPadding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0));

// ---- dashboards ---------------------------------------------------------------------------

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.data, required this.cur});
  final Map<String, dynamic> data;
  final String cur;

  @override
  Widget build(BuildContext context) {
    final accounts = listOf(data['accounts']);
    final s = mapOf(data['summary']);
    final points = listOf(mapOf(s['series'])['points']);
    final budgets = listOf(data['budgets']);
    final recent = listOf(data['recent']);
    final cats = listOf(s['categories']);
    return _Frame(
      icon: Icons.account_balance_wallet_rounded,
      title: 'Your money',
      subtitle: [mapOf(s['period'])['label'], if (data['last_sync'] != null) 'synced ${whenLabel(data['last_sync']).toLowerCase()}'].whereType<Object>().join(' · '),
      tab: 0,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Caption('Total balance', color: AppColors.text2),
              MoneyText(data['total_balance'], cur: cur, size: 34),
            ],
          ),
        ),
        if (accounts.isNotEmpty)
          AccountCarousel(accounts: accounts, cur: cur, onTap: (_) => _openFinance(context, 1)),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.l, Space.m, Space.m),
          child: CashFlow(income: numOf(s['income']), expense: numOf(s['expense']), cur: cur, previous: s['previous'] is Map ? mapOf(s['previous']) : null, savingsRate: s['savings_rate']),
        ),
        if (points.any((p) => numOf(p['expense']) > 0)) ...[
          const _Divider(),
          _Block(title: 'Spending', caption: '${fmtAmount(s['avg_daily_spend'])} a day', child: FlowChart(points: points, height: 110)),
        ],
        if (cats.isNotEmpty) ...[const _Divider(), _Block(title: 'Where it went', child: CategoryBreakdown(items: cats, cur: cur, total: numOf(s['expense']), limit: 4))],
        if (budgets.isNotEmpty) ...[
          const _Divider(),
          _Block(
            title: 'Budgets',
            padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, 0),
            child: Column(children: [for (final b in budgets.take(3)) BudgetTile(budget: b, cur: cur, padding: const EdgeInsets.only(bottom: Space.m))]),
          ),
        ],
        if (recent.isNotEmpty) ...[const _Divider(), ..._days(context, recent.take(5).toList(), cur), const SizedBox(height: Space.s)],
        if (numOf(data['uncategorized']) > 0) _Note('${data['uncategorized']} transactions this period have no category. Tap one to file it.'),
        if (data['note'] != null) _Note('${data['note']}'),
      ],
    );
  }
}

class _SummaryCard extends StatefulWidget {
  const _SummaryCard({required this.data, required this.cur});
  final Map<String, dynamic> data;
  final String cur;

  @override
  State<_SummaryCard> createState() => _SummaryCardState();
}

class _SummaryCardState extends State<_SummaryCard> {
  String _mode = 'both';

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final cur = widget.cur;
    // Older cards have no view: they showed everything.
    final view = '${data['view'] ?? 'all'}';
    final period = '${mapOf(data['period'])['label'] ?? ''}';
    final points = listOf(mapOf(data['series'])['points']);
    final trend = mapOf(data['balance_trend']);
    final values = [for (final v in (trend['values'] as List? ?? const [])) numOf(v)];
    final times = [for (final v in (trend['times'] as List? ?? const [])) (v as num).toInt()];
    final cats = listOf(data['categories']);
    final sources = listOf(data['income_sources']);
    final payees = listOf(data['top_payees']);
    final who = data['account'] != null ? ' · ${data['account']}' : '';
    final hasFlow = points.any((p) => numOf(p['income']) + numOf(p['expense']) > 0);

    Widget headline(String label, Object? v, {Color? color, Widget? badge}) => Padding(
      padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Caption(label, color: AppColors.text2),
          const SizedBox(height: 2),
          Row(children: [Flexible(child: MoneyText(v, cur: cur, size: 30, color: color)), if (badge != null) ...[const SizedBox(width: Space.s), badge]]),
        ],
      ),
    );
    Widget? change(String key, bool upGood) {
      final c = mapOf(data['previous'])[key];
      return c is num && c.abs() <= 500 ? DeltaBadge(pct: c.toDouble(), upIsGood: upGood, suffix: 'vs ${mapOf(data['previous'])['label'] ?? 'before'}') : null;
    }

    return switch (view) {
      'spending' => _Frame(
        icon: Icons.north_east_rounded,
        title: 'Spending$who',
        subtitle: '$period · ${fmtAmount(data['avg_daily_spend'])} a day',
        tab: 0,
        children: [
          headline('Spent', data['expense'], badge: change('expense_change_pct', false)),
          if (hasFlow) Padding(padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m), child: FlowChart(points: points, height: 140)),
          if (data['biggest_expense'] is Map) ...[const _Divider(), _Tx(tx: mapOf(data['biggest_expense']), cur: cur, showDay: true), const _Note('Biggest expense in this period.')],
          if (numOf(data['fees']) > 0) _Note('Including ${money(data['fees'], cur)} in bank fees and VAT.'),
        ],
      ),
      'categories' => _Frame(
        icon: Icons.donut_large_rounded,
        title: 'Spending by category$who',
        subtitle: '$period · ${money(data['expense'], cur)}',
        tab: 0,
        children: [
          if (cats.isEmpty) const _Note('No spending in this period.') else Padding(padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s), child: CategoryBreakdown(items: cats, cur: cur, total: numOf(data['expense']), limit: 8)),
        ],
      ),
      'payees' => _Frame(
        icon: Icons.people_alt_rounded,
        title: 'Paid most to$who',
        subtitle: period,
        tab: 2,
        children: [
          if (payees.isEmpty) const _Note('No payments to named people or places in this period.') else Padding(padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s), child: RankList(items: payees, color: finOut, limit: 8)),
        ],
      ),
      'income' => _Frame(
        icon: Icons.south_west_rounded,
        title: 'Income$who',
        subtitle: period,
        tab: 0,
        children: [
          headline('Money in', data['income'], color: finIn, badge: change('income_change_pct', true)),
          if (sources.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s), child: CategoryBreakdown(items: sources, cur: cur, total: numOf(data['income']), limit: 5)),
          if (listOf(data['top_payers']).isNotEmpty) ...[
            const _Divider(),
            _Block(title: 'From', child: RankList(items: listOf(data['top_payers']), color: finIn)),
          ],
        ],
      ),
      'balance' => _Frame(
        icon: Icons.show_chart_rounded,
        title: 'Balance$who',
        subtitle: period,
        tab: 1,
        children: [
          if (values.length >= 2) ...[
            headline('Now', values.last),
            Padding(padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m), child: BalanceChart(values: values, times: times, height: 150, cur: cur)),
          ] else
            _Note('${data['note'] ?? 'Not enough reported balances to chart.'}'),
        ],
      ),
      'cashflow' => _Frame(
        icon: Icons.swap_vert_rounded,
        title: 'Money in and out$who',
        subtitle: '$period · ${data['transactions']} transactions',
        tab: 0,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
            child: CashFlow(income: numOf(data['income']), expense: numOf(data['expense']), cur: cur, previous: data['previous'] is Map ? mapOf(data['previous']) : null, savingsRate: data['savings_rate']),
          ),
          if (hasFlow) Padding(padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m), child: FlowChart(points: points, mode: 'both', height: 120, showAverage: false)),
          if (numOf(data['own_transfers']) > 0) _Note('${data['own_transfers']} transfers between your own accounts aren\'t counted.'),
        ],
      ),
      _ => _Frame(
        icon: Icons.insights_rounded,
        title: data['account'] != null ? '${data['account']}' : 'Full report',
        subtitle: '$period · ${data['transactions']} transactions',
        tab: 0,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
            child: CashFlow(income: numOf(data['income']), expense: numOf(data['expense']), cur: cur, previous: data['previous'] is Map ? mapOf(data['previous']) : null, savingsRate: data['savings_rate']),
          ),
          if (hasFlow) ...[
            const _Divider(),
            _Block(
              title: 'By ${mapOf(data['series'])['bucket'] ?? 'day'}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 190, child: PillTabs<String>(options: const [('both', 'Both'), ('expense', 'Out'), ('income', 'In')], value: _mode, onChanged: (v) => setState(() => _mode = v))),
                  const SizedBox(height: Space.m),
                  FlowChart(points: points, mode: _mode, height: 130),
                ],
              ),
            ),
          ],
          if (values.length >= 2) ...[const _Divider(), _Block(title: 'Balance', child: BalanceChart(values: values, times: times, height: 120, cur: cur))],
          if (cats.isNotEmpty) ...[const _Divider(), _Block(title: 'Spending by category', child: CategoryBreakdown(items: cats, cur: cur, total: numOf(data['expense']), limit: 5))],
          if (payees.isNotEmpty) ...[const _Divider(), _Block(title: 'Paid most to', child: RankList(items: payees, color: finOut, limit: 4))],
          if (sources.isNotEmpty) ...[const _Divider(), _Block(title: 'Income from', child: CategoryBreakdown(items: sources, cur: cur, total: numOf(data['income']), limit: 3))],
        ],
      ),
    };
  }
}

class _Mini extends StatelessWidget {
  const _Mini(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s + 2),
    decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Caption(label),
        const SizedBox(height: 2),
        FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700, fontFeatures: tabularFigures))),
      ],
    ),
  );
}

class _AccountsCard extends StatelessWidget {
  const _AccountsCard({required this.data, required this.cur});
  final Map<String, dynamic> data;
  final String cur;

  @override
  Widget build(BuildContext context) {
    final accounts = listOf(data['accounts']);
    // One account asked for: just its card.
    if (data['filtered'] == true && accounts.length == 1) {
      final a = accounts.first;
      return _Frame(
        icon: Icons.account_balance_rounded,
        title: '${a['name'] ?? a['bank']}',
        subtitle: [a['bank_name'], if (a['balance_as_of'] != null) 'updated ${whenLabel(a['balance_as_of']).toLowerCase()}'].whereType<Object>().join(' · '),
        tab: 1,
        children: [Padding(padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.l), child: AccountCard(account: a, cur: cur, onTap: () => _openFinance(context, 1)))],
      );
    }
    return _Frame(
      icon: Icons.account_balance_rounded,
      title: data['filtered'] == true ? '${accounts.isEmpty ? 'No' : accounts.first['bank']} accounts' : 'Accounts',
      subtitle: '${accounts.length} ${accounts.length == 1 ? 'account' : 'accounts'}',
      tab: 1,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Caption('Total balance', color: AppColors.text2), MoneyText(data['total_balance'], cur: cur, size: 30)]),
        ),
        if (accounts.isEmpty) const _Note('No accounts yet. Sync bank texts or add one.'),
        if (accounts.length <= 2)
          for (final a in accounts) Padding(padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.l), child: AccountCard(account: a, cur: cur, onTap: () => _openFinance(context, 1)))
        else ...[
          const _Divider(),
          for (final a in accounts) AccountRow(account: a, cur: cur, onTap: () => _openFinance(context, 1)),
          const SizedBox(height: Space.s),
        ],
      ],
    );
  }
}

class _TransactionsCard extends StatefulWidget {
  const _TransactionsCard({required this.data, required this.cur});
  final Map<String, dynamic> data;
  final String cur;

  @override
  State<_TransactionsCard> createState() => _TransactionsCardState();
}

class _TransactionsCardState extends State<_TransactionsCard> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final txs = listOf(widget.data['transactions']);
    final f = mapOf(widget.data['filters']);
    final shown = _all ? txs : txs.take(8).toList();
    final total = numOf(widget.data['total_matching']).toInt();
    // A total only for one direction; mixing in and out is the summary's job.
    final type = '${f['type'] ?? ''}';
    final sum = type == 'income' ? 'received ${fmtAmount(widget.data['income'])}' : (type == 'expense' ? 'spent ${fmtAmount(widget.data['expense'])}' : null);
    final title = switch (type) {
      'income' => 'Money in',
      'expense' => 'Spending',
      _ => 'Transactions',
    };
    final scope = [f['account'] ?? f['bank'], f['category'], f['query'] == null ? null : '"${f['query']}"'].whereType<Object>().join(' · ');
    return _Frame(
      icon: type == 'income' ? Icons.south_west_rounded : (type == 'expense' ? Icons.north_east_rounded : Icons.receipt_long_rounded),
      title: scope.isEmpty ? title : '$title · $scope',
      subtitle: ['${f['period'] ?? ''}', '$total ${total == 1 ? 'transaction' : 'transactions'}', ?sum].where((x) => x.isNotEmpty).join(' · '),
      tab: 2,
      children: [
        if (txs.isEmpty) const _Note('Nothing matches.'),
        ..._days(context, shown, widget.cur),
        if (txs.length > shown.length)
          TextButton(onPressed: () => setState(() => _all = true), child: Text('Show all ${txs.length}'))
        else if (total > txs.length)
          _Note('${total - txs.length} more in the Finance screen.')
        else
          const SizedBox(height: Space.s),
      ],
    );
  }
}

class _BudgetsCard extends StatelessWidget {
  const _BudgetsCard({required this.budgets, required this.cur, this.removed = false});
  final List<Map<String, dynamic>> budgets;
  final String cur;
  final bool removed;

  @override
  Widget build(BuildContext context) {
    final over = budgets.where((b) => b['over'] == true).length;
    return _Frame(
      icon: Icons.savings_rounded,
      title: removed ? 'Budget removed' : 'Budgets',
      subtitle: budgets.isEmpty ? null : (over > 0 ? '$over over the limit' : 'All on track'),
      tab: 3,
      children: [
        if (budgets.isEmpty) const _Note('No budgets.'),
        for (var i = 0; i < budgets.length; i++) ...[
          if (i > 0) const _Divider(),
          BudgetTile(budget: budgets[i], cur: cur, padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.m)),
        ],
      ],
    );
  }
}

class _InsightsCard extends StatelessWidget {
  const _InsightsCard({required this.data, required this.cur});
  final Map<String, dynamic> data;
  final String cur;

  @override
  Widget build(BuildContext context) {
    // Older cards have no view: they showed everything.
    final view = '${data['view'] ?? 'all'}';
    final who = data['account'] != null ? ' · ${data['account']}' : '';
    final sections = <Widget>[];
    final all = view == 'all';
    if (all || view == 'health') sections.addAll(_health(context));
    if (all || view == 'projection') sections.addAll(_projection(context, divider: all));
    if (all || view == 'budget') sections.addAll(_budget(context, divider: all));
    if (all || view == 'recurring') sections.addAll(_recurring(context, divider: all));
    if (all || view == 'unusual') sections.addAll(_unusual(context, divider: all));
    final (icon, title) = switch (view) {
      'recurring' => (Icons.autorenew_rounded, 'Recurring payments'),
      'unusual' => (Icons.priority_high_rounded, 'Unusually large'),
      'projection' => (Icons.trending_up_rounded, 'Next month'),
      'budget' => (Icons.pie_chart_outline_rounded, '50 / 30 / 20'),
      _ => (Icons.favorite_rounded, 'Financial health'),
    };
    return _Frame(icon: icon, title: '$title$who', subtitle: data['months'] != null ? '${data['months']} months of history' : 'From all your history', tab: 0, children: sections);
  }

  List<Widget> _health(BuildContext context) {
    final score = numOf(data['health_score']).round();
    final color = scoreColor(score);
    final parts = mapOf(data['score_parts']);
    final tips = [for (final t in (data['tips'] as List? ?? const [])) '$t'];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
        child: Row(
          children: [
            ScoreGauge(score: score, color: color, size: 132, caption: '${data['grade'] ?? ''}'),
            const SizedBox(width: Space.l),
            Expanded(
              child: Column(
                children: [
                  for (final (k, label, max) in const [('spending_vs_income', 'Spending vs income', 0.4), ('savings', 'Savings', 0.3), ('stability', 'Steadiness', 0.2), ('essentials', 'Needs vs wants', 0.1)])
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [Expanded(child: Caption(label, color: AppColors.text2)), Caption('${(numOf(parts[k]) * 100).round()}/${(max * 100).round()}')]),
                          const SizedBox(height: 3),
                          ThickBar(value: numOf(parts[k]) / max, color: color, height: 5),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      if (tips.isNotEmpty) _Tips(tips),
    ];
  }

  List<Widget> _projection(BuildContext context, {bool divider = false}) {
    final proj = mapOf(data['projection']);
    final monthly = listOf(data['monthly']);
    return [
      if (divider) const _Divider(),
      Padding(
        padding: EdgeInsets.fromLTRB(Space.m, divider ? Space.m : 0, Space.m, Space.m),
        child: Row(
          children: [
            Expanded(child: _Mini('Expected in', fmtAmount(proj['income']))),
            const SizedBox(width: Space.s),
            Expanded(child: _Mini('Expected out', fmtAmount(proj['expense']))),
            const SizedBox(width: Space.s),
            Expanded(child: _Mini('Left over', '${numOf(proj['savings']) < 0 ? '−' : ''}${fmtAmount(proj['savings'])}')),
          ],
        ),
      ),
      if (monthly.length >= 2) _Block(title: 'Month by month', child: FlowChart(points: monthly, mode: 'both', height: 120, showAverage: false)),
    ];
  }

  List<Widget> _budget(BuildContext context, {bool divider = false}) {
    final b = mapOf(data['budget_503020']);
    if (numOf(b['monthly_income']) <= 0) return [const _Note('Needs some income on record to compare against.')];
    return [
      if (divider) const _Divider(),
      _Block(
        title: 'Each month, of ${fmtCompact(b['monthly_income'])} income',
        child: Column(
          children: [
            for (final (label, actual, target, c) in [
              ('Needs · 50%', b['needs_actual'], b['needs_target'], const Color(0xFF60A5FA)),
              ('Wants · 30%', b['wants_actual'], b['wants_target'], const Color(0xFFF472B6)),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(label, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w500))),
                        Text('${fmtAmount(actual)} / ${fmtAmount(target)}', style: context.text.labelMedium?.copyWith(fontFeatures: tabularFigures)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ThickBar(value: numOf(target) == 0 ? 0 : numOf(actual) / numOf(target), color: numOf(actual) > numOf(target) ? finOut : c),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Row(children: [Expanded(child: Caption('Savings · 20%', color: AppColors.text2)), Caption('aim for ${fmtAmount(b['savings_target'])} a month')]),
            if (numOf(b['uncategorized_actual']) > 0) Padding(padding: const EdgeInsets.only(top: Space.s), child: Caption('${fmtAmount(b['uncategorized_actual'])} a month is uncategorized and not counted.', maxLines: 2)),
          ],
        ),
      ),
    ];
  }

  List<Widget> _recurring(BuildContext context, {bool divider = false}) {
    final recurring = listOf(data['recurring']);
    if (recurring.isEmpty) return divider ? const [] : [const _Note('Nothing has been paid to the same place three or more times yet.')];
    return [
      if (divider) const _Divider(),
      Padding(padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s), child: Column(children: [for (final r in recurring.take(divider ? 4 : 10)) RecurringRow(item: r)])),
    ];
  }

  List<Widget> _unusual(BuildContext context, {bool divider = false}) {
    final out = listOf(data['unusual_expenses']);
    final inn = listOf(data['unusual_income']);
    if (out.isEmpty && inn.isEmpty) return divider ? const [] : [const _Note('Nothing out of the ordinary.')];
    return [
      if (divider) const _Divider(),
      if (out.isNotEmpty) ...[
        if (!divider) const _Note('Spending well above your usual amount:'),
        for (final t in out.take(divider ? 3 : 8)) _Tx(tx: t, cur: cur, showDay: true),
      ],
      if (inn.isNotEmpty && !divider) ...[const _Divider(), const SizedBox(height: Space.s), const _Note('Income well above your usual amount:'), for (final t in inn.take(5)) _Tx(tx: t, cur: cur, showDay: true)],
      const SizedBox(height: Space.s),
    ];
  }
}

class _Tips extends StatelessWidget {
  const _Tips(this.tips);
  final List<String> tips;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
    padding: const EdgeInsets.all(Space.m),
    decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m)),
    child: Column(
      children: [
        for (final t in tips)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_rounded, size: 15, color: AppColors.warning),
                const SizedBox(width: Space.s),
                Expanded(child: Text(t, style: context.text.bodySmall?.copyWith(color: AppColors.text, height: 1.4))),
              ],
            ),
          ),
      ],
    ),
  );
}

// ---- sync & parsing ----------------------------------------------------------------------------

class _SyncCard extends StatelessWidget {
  const _SyncCard({required this.data, required this.cur});
  final Map<String, dynamic> data;
  final String cur;

  @override
  Widget build(BuildContext context) {
    final latest = listOf(data['latest']);
    final fresh = listOf(data['new_accounts']);
    final missed = mapOf(data['not_understood']);
    final byBank = mapOf(data['by_bank']);
    final added = numOf(data['added']).toInt();
    return _Frame(
      icon: Icons.sync_rounded,
      title: added == 0 ? 'Up to date' : '$added new transactions',
      subtitle: '${data['bank_messages']} bank texts of ${data['scanned']} read · ${data['duplicates']} already recorded',
      tab: 2,
      children: [
        if (added > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
            child: Row(
              children: [
                Expanded(child: _Mini('Money in', '+${fmtAmount(data['income'])}')),
                const SizedBox(width: Space.s),
                Expanded(child: _Mini('Spent', '−${fmtAmount(data['expense'])}')),
              ],
            ),
          ),
        if (byBank.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in byBank.entries)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(20)),
                    child: Text('${e.key}  ${e.value}', style: context.text.labelMedium),
                  ),
              ],
            ),
          ),
        if (fresh.isNotEmpty) ...[
          const _Divider(),
          Padding(padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, 0), child: Text('NEW ACCOUNTS', style: context.text.labelSmall?.copyWith(color: AppColors.text3, letterSpacing: 0.9, fontWeight: FontWeight.w600))),
          for (final a in fresh) AccountRow(account: a, cur: cur, onTap: () => _openFinance(context, 1)),
        ],
        if (latest.isNotEmpty) ...[const _Divider(), ..._days(context, latest.take(5).toList(), cur), const SizedBox(height: Space.s)],
        if (missed.isNotEmpty) _Note('Not understood: ${missed.entries.map((e) => '${e.value} from ${e.key}').join(', ')}. Newer bank patterns may help.'),
        _Note('Total balance now ${money(data['total_balance'], cur)}.'),
      ],
    );
  }
}

class _ParsedCard extends StatelessWidget {
  const _ParsedCard({required this.data, required this.cur});
  final Map<String, dynamic> data;
  final String cur;

  @override
  Widget build(BuildContext context) {
    if (data['parsed'] != true) {
      return _Frame(icon: Icons.sms_failed_rounded, title: 'Message not understood', children: [_Note('${data['note'] ?? ''}')]);
    }
    final income = data['type'] == 'income';
    final rows = <(String, String)>[
      if (data['counterparty'] != null) (income ? 'From' : 'To', '${data['counterparty']}'),
      if (data['account'] != null) ('Account', '${data['account']}'),
      if (data['fee'] != null) ('Fees & VAT', money(data['fee'], cur)),
      if (data['balance_after'] != null) ('Balance after', money(data['balance_after'], cur)),
      if (data['reference'] != null) ('Reference', '${data['reference']}'),
    ];
    return _Frame(
      icon: Icons.sms_rounded,
      title: data['saved'] == true ? 'Read and saved' : 'Bank message read',
      subtitle: '${data['bank']} · ${data['pattern'] ?? ''}',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
          child: MoneyText(numOf(data['amount']) * (income ? 1 : -1), cur: cur, size: 30, sign: true, color: income ? finIn : AppColors.text),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
          decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m)),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Divider(height: 1, color: AppColors.line, indent: Space.m, endIndent: Space.m),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s + 2),
                  child: Row(
                    children: [
                      Caption(rows[i].$1),
                      const SizedBox(width: Space.l),
                      Expanded(child: Text(rows[i].$2, textAlign: TextAlign.end, style: context.text.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        if (data['link'] != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
            child: OutlinedButton.icon(
              onPressed: () => launchUrl(Uri.parse('${data['link']}'), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.receipt_long_rounded, size: 18),
              label: const Text('Bank receipt'),
            ),
          ),
        if (data['note'] != null) _Note('${data['note']}'),
      ],
    );
  }
}

class _CategoriesCard extends StatelessWidget {
  const _CategoriesCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final cats = listOf(data['categories']);
    final rules = listOf(data['rules']);
    Widget wrap(Iterable<Map<String, dynamic>> xs) => Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final c in xs)
          Container(
            padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
            decoration: BoxDecoration(color: categoryColor('${c['key']}').withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(categoryIcon(c['icon']), size: 14, color: categoryColor('${c['key']}')),
                const SizedBox(width: 5),
                Text('${c['name']}', style: context.text.labelMedium),
              ],
            ),
          ),
      ],
    );
    return _Frame(
      icon: Icons.sell_rounded,
      title: 'Categories',
      subtitle: '${data['uncategorized'] ?? 0} transactions uncategorized',
      children: [
        _Block(title: 'Spending', child: wrap(cats.where((c) => c['flow'] != 'income'))),
        _Block(title: 'Income', child: wrap(cats.where((c) => c['flow'] == 'income'))),
        if (rules.isNotEmpty)
          _Block(
            title: 'Learned',
            child: Column(
              children: [
                for (final r in rules.take(12))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Expanded(child: Text('${r['counterparty']}', style: context.text.bodySmall?.copyWith(color: AppColors.text), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        Icon(Icons.arrow_forward_rounded, size: 14, color: AppColors.text3),
                        const SizedBox(width: Space.s),
                        Caption('${r['category']}', color: AppColors.text2),
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

class _BanksCard extends StatelessWidget {
  const _BanksCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final banks = listOf(data['banks']);
    final p = mapOf(data['patterns']);
    return _Frame(
      icon: Icons.account_balance_rounded,
      title: 'Supported banks',
      subtitle: p.isEmpty ? null : '${p['patterns']} patterns · ${p['source'] == 'downloaded' ? 'from Totals' : 'shipped with the app'}',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
          child: Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            children: [
              for (final b in banks)
                SizedBox(
                  width: 64,
                  child: Column(
                    children: [
                      b['manual'] == true
                          ? CategoryIconTile(icon: b['id'] == 100 ? 'wallet' : 'more', color: AppColors.text2, size: 36)
                          : BankBadge(name: '${b['short_name']}', colors: b['colors'] as List? ?? const [], size: 36),
                      const SizedBox(height: 4),
                      Text('${b['short_name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall),
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
