import 'verify_et_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/widgets/app_sheet.dart';
import '../device/device.dart';
import 'finance_insights.dart';
import 'finance_models.dart';
import 'finance_store.dart';
import 'finance_tools.dart';
import 'ui/finance_sheets.dart';
import 'ui/finance_ui.dart';
import '../settings/presentation/feature_tools_tab.dart';
import '../telegram/data/telegram_tools.dart' show ToolCategory;

/// Settings → Finance, and "Open" on the chat's money cards: an overview,
/// accounts, transactions and budgets, with full pages to add and change
/// each.
class FinanceScreen extends ConsumerStatefulWidget {
  const FinanceScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  ConsumerState<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends ConsumerState<FinanceScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this, initialIndex: widget.initialTab.clamp(0, 4))..addListener(() => setState(() {}));
  bool _syncing = false;

  FinanceStore get _store => ref.read(financeStoreProvider.notifier);

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      final r = await _store.syncSms();
      if (!mounted) return;
      showSnack(
        context,
        r.added == 0 ? 'Up to date · ${r.bankMessages} bank texts checked' : '${r.added} new transactions${r.newAccounts.isEmpty ? '' : ' · ${r.newAccounts.length} accounts found'}',
        icon: Icons.sync_rounded,
      );
    } on DeviceException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(financeStoreProvider);
    FinPrivacy.load();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Finance'),
        actions: [
          const HideAmountsButton(),
          if (Device.supported)
            IconButton(
              tooltip: 'Sync bank texts',
              onPressed: _syncing ? null : _sync,
              icon: _syncing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync_rounded),
            ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'currency') {
                final c = await _askText(context, 'Currency code', s.currency);
                if (c != null && c.trim().isNotEmpty) await _store.setCurrency(c);
              } else if (v == 'patterns') {
                if (context.mounted) await _showPatterns(context, ref);
              } else if (v == 'clear') {
                if (await confirmDelete(context, title: 'Delete all finance data?', message: 'Accounts, transactions, rules and budgets on this phone. Your SMS stay.')) await _store.clear();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'currency', child: Text('Currency (${s.currency})')),
              const PopupMenuItem(value: 'patterns', child: Text('Bank SMS patterns')),
              const PopupMenuItem(value: 'clear', child: Text('Delete all finance data')),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
            child: PillTabs<int>(
              options: const [(0, 'Overview'), (1, 'Accounts'), (2, 'Transactions'), (3, 'Budgets'), (4, 'Tools')],
              value: _tabs.index,
              onChanged: _tabs.animateTo,
            ),
          ),
        ),
      ),
      floatingActionButton: switch (_tabs.index) {
        1 => FloatingActionButton.extended(heroTag: 'fin', onPressed: () => _push(context, const AccountEditorPage()), icon: const Icon(Icons.add_rounded), label: const Text('Account')),
        2 => FloatingActionButton.extended(heroTag: 'fin', onPressed: () => _push(context, const TransactionEditorPage()), icon: const Icon(Icons.add_rounded), label: const Text('Transaction')),
        3 when s.budgets.isNotEmpty => FloatingActionButton.extended(heroTag: 'fin', onPressed: () => _push(context, const BudgetEditorPage()), icon: const Icon(Icons.add_rounded), label: const Text('Budget')),
        _ => null,
      },
      body: !s.loaded
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _Overview(onSync: Device.supported ? _sync : null, goTo: _tabs.animateTo),
                const _Accounts(),
                const _Transactions(),
                const _Budgets(),
                const FeatureToolsTab(
                  category: ToolCategory.finance,
                  intro:
                      'With these on, the assistant can read your bank and wallet texts into transactions, answer questions about '
                      'balances, spending, categories and budgets, and add or change accounts, transactions and budgets when you ask. '
                      'Changes it makes and data it reads show in the activity log.',
                  examples: [
                    'Sync my bank texts and show my balances',
                    'How much did I spend on groceries this month?',
                    'Set a 5,000 ETB monthly budget for eating out',
                    'How healthy are my finances?',
                    'Did Abebe really pay me? Verify this receipt',
                  ],
                  setup: [VerifyEtSettings()],
                ),
              ],
            ),
    );
  }
}

Future<void> _push(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

List<Map<String, dynamic>> _maps(Object? v) => listOf(v);

// ---- overview ----------------------------------------------------------------------------

class _Overview extends ConsumerStatefulWidget {
  const _Overview({this.onSync, required this.goTo});
  final VoidCallback? onSync;
  final void Function(int) goTo;

  @override
  ConsumerState<_Overview> createState() => _OverviewState();
}

class _OverviewState extends ConsumerState<_Overview> {
  String _period = 'this_month';
  String _mode = 'expense';

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(financeStoreProvider);
    final store = ref.read(financeStoreProvider.notifier);
    final cur = s.currency;
    if (s.accounts.isEmpty && s.transactions.isEmpty) {
      return _Empty(
        icon: Icons.account_balance_wallet_rounded,
        title: 'All your money in one place',
        text: 'Read your bank and wallet texts (CBE, Telebirr, Awash, BOA, Dashen, M-Pesa and more) into accounts and transactions, or add them yourself. Everything stays on this phone.',
        actions: [
          if (widget.onSync != null) FilledButton.icon(onPressed: widget.onSync, icon: const Icon(Icons.sms_rounded), label: const Text('Read bank texts')),
          OutlinedButton.icon(onPressed: () => _push(context, const AccountEditorPage()), icon: const Icon(Icons.add_rounded), label: const Text('Add an account')),
        ],
      );
    }
    final p = FinPeriod.resolve(_period);
    final sum = periodSummary(s.transactions, p, categories: s.categoryMap);
    final insights = financeInsights(s.transactions, s.categoryMap);
    final points = _maps(mapOf(sum['series'])['points']);
    final cats = _maps(sum['categories']);
    final accounts = s.accounts.where((a) => !a.dormant).toList()..sort((a, b) => b.balance.compareTo(a.balance));
    final trend = balanceHistory(s.transactions, accounts.where((a) => a.includeInTotals).toList(), from: DateTime.now().subtract(const Duration(days: 90)));
    final month = periodSummary(s.transactions, FinPeriod.resolve('this_month'), categories: s.categoryMap);
    final budgets = budgetStatus(s.budgets, s.transactions, s.categoryMap);
    final score = insights['health_score'] as int;
    final recurring = _maps(insights['recurring']);
    final recent = [for (final t in s.transactions.take(6)) describeTransaction(store, s, t)];
    final net = numOf(month['net']);
    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        // Hero.
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.xl, Space.l, Space.xl, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [Caption('Total balance', color: AppColors.text2), const SizedBox(width: 2), HideAmountsButton(size: 17, compact: true, color: AppColors.text3)]),
              MoneyText(s.totalBalance, cur: cur, size: 40),
              const SizedBox(height: Space.s),
              Row(
                children: [
                  Icon(net >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded, size: 16, color: net >= 0 ? finIn : finOut),
                  const SizedBox(width: 4),
                  Text(money(net, cur, sign: true), style: context.text.labelLarge?.copyWith(color: net >= 0 ? finIn : finOut, fontWeight: FontWeight.w600)),
                  Caption(' this month'),
                  const Spacer(),
                  if (s.lastSync != null) Caption('Synced ${dayLabel(s.lastSync!).toLowerCase()}'),
                ],
              ),
            ],
          ),
        ),
        if (trend.values.length >= 2) Padding(padding: const EdgeInsets.fromLTRB(Space.xl, Space.m, Space.xl, 0), child: Sparkline(values: trend.values, height: 52, color: AppColors.text2)),
        if (accounts.isNotEmpty) ...[
          SectionTitle('Accounts', action: '${accounts.length}  All', onAction: () => widget.goTo(1)),
          AccountCarousel(
            accounts: [for (final a in accounts) describeAccount(store, s, a)],
            cur: cur,
            onTap: (i) => _push(context, AccountPage(accountId: accounts[i].id)),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.xl, Space.l, Space.m),
          child: PillTabs<String>(
            options: const [('this_week', 'Week'), ('this_month', 'Month'), ('last_90_days', '3 months'), ('this_year', 'Year'), ('all', 'All')],
            value: _period,
            onChanged: (v) => setState(() => _period = v),
          ),
        ),
        FinCard(child: CashFlow(income: numOf(sum['income']), expense: numOf(sum['expense']), cur: cur, previous: sum['previous'] is Map ? mapOf(sum['previous']) : null, savingsRate: sum['savings_rate'])),
        if (points.any((x) => numOf(x['income']) + numOf(x['expense']) > 0))
          FinCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CardTitle(
                  _mode == 'income' ? 'Income' : (_mode == 'both' ? 'In and out' : 'Spending'),
                  caption: 'By ${mapOf(sum['series'])['bucket']} · ${fmtAmount(sum['avg_daily_spend'])} $cur a day spent',
                ),
                const SizedBox(height: Space.m),
                SizedBox(
                  width: 210,
                  child: PillTabs<String>(options: const [('expense', 'Out'), ('income', 'In'), ('both', 'Both')], value: _mode, onChanged: (v) => setState(() => _mode = v)),
                ),
                const SizedBox(height: Space.m),
                FlowChart(points: points, mode: _mode, height: 150),
              ],
            ),
          ),
        if (cats.isNotEmpty)
          FinCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CardTitle('Where it went', caption: '${cats.length} categories · ${p.label}'),
                const SizedBox(height: Space.m),
                CategoryBreakdown(items: cats, cur: cur, total: numOf(sum['expense']), onTap: (k) => _push(context, CategoryTransactionsPage(category: k, period: _period))),
              ],
            ),
          ),
        if (budgets.isNotEmpty)
          FinCard(
            padding: const EdgeInsets.fromLTRB(0, Space.l, 0, Space.xs),
            child: Column(
              children: [
                Padding(padding: const EdgeInsets.symmetric(horizontal: Space.l), child: CardTitle('Budgets', action: 'All', onAction: () => widget.goTo(3))),
                for (final b in budgets.take(3)) BudgetTile(budget: b, cur: cur, onTap: () => _push(context, BudgetEditorPage(budget: s.budgets.firstWhere((x) => x.id == b['id'])))),
              ],
            ),
          ),
        FinCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const CardTitle('Financial health', caption: 'From all your history'),
              const SizedBox(height: Space.l),
              Row(
                children: [
                  ScoreGauge(score: score, color: scoreColor(score), size: 128, caption: '${insights['grade']}'),
                  const SizedBox(width: Space.l),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _kv('Savings rate', '${(numOf(insights['savings_rate']) * 100).round()}%'),
                        _kv('Expected in', fmtCompact(mapOf(insights['projection'])['income'])),
                        _kv('Expected out', fmtCompact(mapOf(insights['projection'])['expense'])),
                        _kv('Categorized', '${(numOf(insights['categorized_share']) * 100).round()}%'),
                      ],
                    ),
                  ),
                ],
              ),
              for (final t in (insights['tips'] as List).take(2)) ...[const SizedBox(height: Space.m), _Tip('$t')],
            ],
          ),
        ),
        if (recurring.isNotEmpty)
          FinCard(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const CardTitle('Recurring', caption: 'Paid three or more times'),
                const SizedBox(height: Space.s),
                for (final r in recurring.take(4)) RecurringRow(item: r),
              ],
            ),
          ),
        SectionTitle('Recent', action: 'All', onAction: () => widget.goTo(2)),
        FinCard(
          padding: const EdgeInsets.symmetric(vertical: Space.xs),
          child: Column(children: groupedByDay(recent, cur, dense: true, onTap: (t, _) => showTransactionSheet(context, t, cur), headerPadding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0))),
        ),
      ],
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Caption(k, color: AppColors.text2)),
        Text(v, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600, fontFeatures: tabularFigures)),
      ],
    ),
  );
}

class _Tip extends StatelessWidget {
  const _Tip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(Space.m),
    decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m)),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.lightbulb_rounded, size: 16, color: AppColors.warning),
        const SizedBox(width: Space.s),
        Expanded(child: Text(text, style: context.text.bodySmall?.copyWith(color: AppColors.text, height: 1.4))),
      ],
    ),
  );
}

/// A recurring payment: who, how often, about how much, when next.
class RecurringRow extends StatelessWidget {
  const RecurringRow({super.key, required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        CategoryIconTile(icon: 'transfer', color: AppColors.text2, size: 36),
        const SizedBox(width: Space.m),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${item['label']}', style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
              Caption('${item['every']} · ${item['count']}×${item['next_expected'] != null ? ' · next ~${dayLabel(DateTime.parse('${item['next_expected']}'))}' : ''}'),
            ],
          ),
        ),
        Text('≈${fmtAmount(item['avg'])}', style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600, fontFeatures: tabularFigures)),
      ],
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.text, this.actions = const []});
  final IconData icon;
  final String title;
  final String text;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(Space.x4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: AppColors.surface2, shape: BoxShape.circle, border: Border.all(color: AppColors.line)),
            child: Icon(icon, size: 32, color: AppColors.text2),
          ),
          const SizedBox(height: Space.l),
          Text(title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.center),
          const SizedBox(height: Space.s),
          Text(text, style: context.text.bodySmall?.copyWith(color: AppColors.text2, height: 1.45), textAlign: TextAlign.center),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: Space.xl),
            for (final a in actions) Padding(padding: const EdgeInsets.only(bottom: Space.s), child: SizedBox(width: 240, child: a)),
          ],
        ],
      ),
    ),
  );
}

// ---- accounts ------------------------------------------------------------------------------

class _Accounts extends ConsumerWidget {
  const _Accounts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(financeStoreProvider);
    final store = ref.read(financeStoreProvider.notifier);
    if (s.accounts.isEmpty) {
      return _Empty(
        icon: Icons.account_balance_rounded,
        title: 'No accounts yet',
        text: 'Add a bank account, wallet or cash, or sync your bank texts to find them.',
        actions: [FilledButton.icon(onPressed: () => _push(context, const AccountEditorPage()), icon: const Icon(Icons.add_rounded), label: const Text('Add an account'))],
      );
    }
    final active = s.accounts.where((a) => !a.dormant).toList()..sort((a, b) => b.balance.compareTo(a.balance));
    final dormant = s.accounts.where((a) => a.dormant).toList();
    Widget card(FinAccount a) => Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.m),
      child: AccountCard(account: describeAccount(store, s, a), cur: s.currency, onTap: () => _push(context, AccountPage(accountId: a.id))),
    );
    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.xl, Space.l, Space.xl, Space.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [Caption('Across ${active.where((a) => a.includeInTotals).length} accounts', color: AppColors.text2), const SizedBox(width: 2), HideAmountsButton(size: 17, compact: true, color: AppColors.text3)]),
              MoneyText(s.totalBalance, cur: s.currency, size: 32),
            ],
          ),
        ),
        for (final a in active) card(a),
        if (dormant.isNotEmpty) ...[const SectionTitle('Not in use'), for (final a in dormant) card(a)],
      ],
    );
  }
}

/// One account: its card, this month's flows, the balance over time and
/// its transactions.
class AccountPage extends ConsumerWidget {
  const AccountPage({super.key, required this.accountId});
  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(financeStoreProvider);
    final store = ref.read(financeStoreProvider.notifier);
    final a = s.account(accountId);
    if (a == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('This account was removed.')));
    final cur = s.currency;
    final info = describeAccount(store, s, a);
    final mine = s.transactions.where((t) => t.accountId == a.id).toList();
    final trend = balanceHistory(s.transactions, [a]);
    final transfers = ownTransfers(s.transactions);
    final rows = [for (final t in mine.take(80)) describeTransaction(store, s, t, transfers: transfers)];
    return Scaffold(
      appBar: AppBar(
        title: Text(store.accountName(a)),
        actions: [IconButton(tooltip: 'Edit', onPressed: () => _push(context, AccountEditorPage(account: a)), icon: const Icon(Icons.edit_outlined))],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.x4),
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.xl), child: AccountCard(account: info, cur: cur)),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _Action(icon: Icons.south_west_rounded, label: 'Money in', color: finIn, onTap: () => _push(context, TransactionEditorPage(accountId: a.id, income: true))),
                _Action(icon: Icons.north_east_rounded, label: 'Spending', color: finOut, onTap: () => _push(context, TransactionEditorPage(accountId: a.id))),
                _Action(icon: Icons.tune_rounded, label: 'Edit', color: AppColors.text2, onTap: () => _push(context, AccountEditorPage(account: a))),
              ],
            ),
          ),
          () {
            final month = FinPeriod.resolve('this_month');
            final now = mine.where((t) => month.contains(t.time)).toList();
            final fees = now.fold(0.0, (x, t) => x + t.fee);
            final out = now.where((t) => t.isDebit).fold(0.0, (x, t) => x + t.outflow);
            return FinCard(
              child: Row(
                children: [
                  Expanded(child: _Stat(label: 'This month', value: now.length.toDouble(), color: AppColors.text2, whole: true, unit: now.length == 1 ? 'payment' : 'payments')),
                  Container(width: 1, height: 40, color: AppColors.line, margin: const EdgeInsets.only(right: Space.l)),
                  Expanded(child: _Stat(label: 'Per day', value: out / DateTime.now().day, color: finOut)),
                  Container(width: 1, height: 40, color: AppColors.line, margin: const EdgeInsets.only(right: Space.l)),
                  Expanded(child: _Stat(label: 'Fees', value: fees, color: AppColors.warning)),
                ],
              ),
            );
          }(),
          if (trend.values.length >= 2)
            FinCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CardTitle('Balance', caption: a.balanceAt == null ? null : 'Last reported ${whenLabel(a.balanceAt!.toIso8601String())}'),
                  const SizedBox(height: Space.m),
                  BalanceChart(values: trend.values, times: trend.times, height: 150, cur: cur),
                ],
              ),
            ),
          if (rows.isEmpty)
            const Padding(padding: EdgeInsets.all(Space.x4), child: Center(child: Caption('No transactions on this account yet.')))
          else ...[
            SectionTitle('Transactions', action: mine.length > rows.length ? '${mine.length}' : null),
            FinCard(
              padding: const EdgeInsets.symmetric(vertical: Space.xs),
              child: Column(children: groupedByDay(rows, cur, dense: true, onTap: (t, _) => showTransactionSheet(context, t, cur), headerPadding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0))),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color, this.whole = false, this.unit});
  final String label;
  final double value;
  final Color color;
  final bool whole;
  final String? unit;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), const SizedBox(width: 6), Caption(label, color: AppColors.text2)]),
      const SizedBox(height: 4),
      if (whole)
        Text.rich(
          TextSpan(children: [
            TextSpan(text: '${value.round()}', style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            if (unit != null) TextSpan(text: ' $unit', style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        )
      else
        MoneyText(value, size: 20),
    ],
  );
}

/// A round quick action with its label under it.
class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(Radii.l),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.xs),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.13), shape: BoxShape.circle, border: Border.all(color: color.withValues(alpha: 0.25))),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 6),
          Text(label, style: context.text.labelMedium?.copyWith(color: AppColors.text2)),
        ],
      ),
    ),
  );
}

/// Adds an account, or changes [account]: the bank as a grid, then the
/// number, names, balance and switches.
class AccountEditorPage extends ConsumerStatefulWidget {
  const AccountEditorPage({super.key, this.account});
  final FinAccount? account;

  @override
  ConsumerState<AccountEditorPage> createState() => _AccountEditorPageState();
}

class _AccountEditorPageState extends ConsumerState<AccountEditorPage> {
  late int _bank = widget.account?.bankId ?? 1;
  late final _number = TextEditingController(text: widget.account?.number ?? '');
  late final _holder = TextEditingController(text: widget.account?.holder ?? '');
  late final _nick = TextEditingController(text: widget.account?.nickname ?? '');
  late final _balance = TextEditingController(text: widget.account == null ? '' : widget.account!.balance.toStringAsFixed(2));
  late bool _totals = widget.account?.includeInTotals ?? true;
  late bool _dormant = widget.account?.dormant ?? false;
  late bool _default = widget.account?.isDefault ?? false;

  @override
  void dispose() {
    for (final c in [_number, _holder, _nick, _balance]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final store = ref.read(financeStoreProvider.notifier);
    final a = widget.account;
    final bal = double.tryParse(_balance.text.replaceAll(',', '').trim());
    if (a == null) {
      await store.addAccount(bankId: _bank, number: _number.text, holder: _holder.text, nickname: _nick.text, balance: bal ?? 0, includeInTotals: _totals, isDefault: _default);
    } else {
      await store.updateAccount(
        a.id,
        bankId: _bank,
        number: _number.text,
        holder: _holder.text,
        nickname: _nick.text,
        balance: bal != null && (bal - a.balance).abs() > 0.004 ? bal : null,
        includeInTotals: _totals,
        dormant: _dormant,
        isDefault: _default,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.read(financeStoreProvider.notifier);
    final banks = store.banks;
    final bank = store.bank(_bank);
    final a = widget.account;
    return Scaffold(
      appBar: AppBar(
        title: Text(a == null ? 'Add account' : 'Edit account'),
        actions: [
          if (a != null)
            IconButton(
              tooltip: 'Remove account',
              icon: Icon(Icons.delete_outline_rounded, color: AppColors.danger),
              onPressed: () async {
                final n = ref.read(financeStoreProvider).transactions.where((t) => t.accountId == a.id).length;
                if (await confirmDelete(context, title: 'Remove ${store.accountName(a)}?', message: '$n transactions stay, without an account.', action: 'Remove')) {
                  await store.deleteAccount(a.id);
                  if (context.mounted) Navigator.of(context)..pop()..maybePop();
                }
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.x4),
        children: [
          const _Label('Bank or wallet'),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: Space.s,
            crossAxisSpacing: Space.s,
            childAspectRatio: 0.95,
            children: [
              for (final b in banks)
                _Choice(
                  selected: b.id == _bank,
                  onTap: () => setState(() => _bank = b.id),
                  color: b.colors.isEmpty ? AppColors.text : hexColor(b.colors.first),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      BankBadge(name: b.shortName, colors: b.colors, size: 34),
                      const SizedBox(height: 6),
                      Text(b.shortName, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall),
                    ],
                  ),
                ),
            ],
          ),
          const _Label('Details'),
          TextField(
            controller: _number,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: bank.simBased ? 'Phone number' : (bank.id == cashBankId ? 'Number (optional)' : 'Account number'), helperText: 'The last digits are matched against the bank\'s texts'),
          ),
          const SizedBox(height: Space.m),
          TextField(controller: _nick, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Nickname', hintText: 'e.g. Salary account')),
          const SizedBox(height: Space.m),
          TextField(controller: _holder, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Account holder (optional)')),
          const SizedBox(height: Space.m),
          TextField(
            controller: _balance,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Current balance', suffixText: ref.read(financeStoreProvider).currency),
          ),
          const _Label('Options'),
          Material(
            color: AppColors.surface,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.l), side: BorderSide(color: AppColors.line)),
            child: Column(
              children: [
                SwitchListTile(title: const Text('Count in total balance'), value: _totals, onChanged: (v) => setState(() => _totals = v)),
                SwitchListTile(title: const Text('Default for this bank'), subtitle: const Text('Where texts go when they don\'t say which account'), value: _default, onChanged: (v) => setState(() => _default = v)),
                if (a != null) SwitchListTile(title: const Text('Not in use'), subtitle: const Text('Hidden from totals and the overview; history stays'), value: _dormant, onChanged: (v) => setState(() => _dormant = v)),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _SaveBar(label: a == null ? 'Add account' : 'Save', onPressed: _save),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.xs, Space.xl, 0, Space.s),
    child: Text(text.toUpperCase(), style: context.text.labelSmall?.copyWith(color: AppColors.text3, letterSpacing: 0.9, fontWeight: FontWeight.w600)),
  );
}

class _Choice extends StatelessWidget {
  const _Choice({required this.selected, required this.onTap, required this.child, required this.color});
  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? color.withValues(alpha: 0.14) : AppColors.surface,
    borderRadius: BorderRadius.circular(Radii.l),
    child: InkWell(
      borderRadius: BorderRadius.circular(Radii.l),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: selected ? color.withValues(alpha: 0.9) : AppColors.line, width: selected ? 1.5 : 1)),
        child: child,
      ),
    ),
  );
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Container(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.m),
      decoration: BoxDecoration(color: AppColors.bg, border: Border(top: BorderSide(color: AppColors.line))),
      child: SizedBox(height: 50, child: FilledButton(onPressed: onPressed, child: Text(label))),
    ),
  );
}

/// A large centred amount field.
class _AmountField extends StatelessWidget {
  const _AmountField({required this.controller, required this.cur, this.color, this.autofocus = false});
  final TextEditingController controller;
  final String cur;
  final Color? color;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(cur, style: context.text.labelLarge?.copyWith(color: AppColors.text3, letterSpacing: 1)),
      IntrinsicWidth(
        child: TextField(
          controller: controller,
          autofocus: autofocus,
          textAlign: TextAlign.center,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
          style: TextStyle(fontSize: 46, fontWeight: FontWeight.w700, color: color ?? AppColors.text, letterSpacing: -1, fontFeatures: tabularFigures),
          decoration: InputDecoration(
            hintText: '0',
            hintStyle: TextStyle(fontSize: 46, fontWeight: FontWeight.w700, color: AppColors.text3.withValues(alpha: 0.5)),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            constraints: const BoxConstraints(minWidth: 80),
          ),
        ),
      ),
    ],
  );
}

// ---- transactions ---------------------------------------------------------------------------

class _Transactions extends ConsumerStatefulWidget {
  const _Transactions();

  @override
  ConsumerState<_Transactions> createState() => _TransactionsState();
}

class _TransactionsState extends ConsumerState<_Transactions> {
  String _q = '';
  String _filter = 'all';
  int _shown = 60;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(financeStoreProvider);
    final store = ref.read(financeStoreProvider.notifier);
    final transfers = ownTransfers(s.transactions);
    final q = _q.toLowerCase();
    final list = s.transactions.where((t) {
      if (_filter == 'in' && !t.isCredit) return false;
      if (_filter == 'out' && !t.isDebit) return false;
      if (_filter == 'none' && t.category != null) return false;
      if (q.isNotEmpty && !'${t.counterparty} ${t.note} ${t.reference} ${s.categoryMap[t.category]?.name ?? ''}'.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
    final inSum = list.where((t) => t.isCredit && !transfers.contains(t.id)).fold(0.0, (a, t) => a + t.amount);
    final outSum = list.where((t) => t.isDebit && !transfers.contains(t.id)).fold(0.0, (a, t) => a + t.outflow);
    final uncategorized = s.transactions.where((t) => t.category == null).length;
    final rows = [for (final t in list.take(_shown)) describeTransaction(store, s, t, transfers: transfers)];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              hintText: 'Search people, notes, categories',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
            onChanged: (v) => setState(() {
              _q = v;
              _shown = 60;
            }),
          ),
        ),
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.xs),
            children: [
              for (final (k, l) in [('all', 'All'), ('in', 'Money in'), ('out', 'Money out'), ('none', 'Uncategorized${uncategorized > 0 ? ' · $uncategorized' : ''}')])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Pill(dense: true, label: l, selected: _filter == k, onTap: () => setState(() => _filter = k)),
                ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? _Empty(icon: Icons.receipt_long_rounded, title: q.isEmpty ? 'No transactions' : 'Nothing matches', text: q.isEmpty ? 'Sync bank texts or add one yourself.' : 'Try other words.')
              : ListView(
                  padding: const EdgeInsets.only(bottom: 100),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.xl, Space.s, Space.xl, 0),
                      child: Row(
                        children: [
                          Caption('${list.length} transactions'),
                          const Spacer(),
                          Text('+${fmtAmount(inSum)}', style: context.text.labelMedium?.copyWith(color: finIn, fontFeatures: tabularFigures)),
                          const SizedBox(width: Space.m),
                          Text('−${fmtAmount(outSum)}', style: context.text.labelMedium?.copyWith(color: AppColors.text2, fontFeatures: tabularFigures)),
                        ],
                      ),
                    ),
                    ...groupedByDay(rows, s.currency, onTap: (t, _) => showTransactionSheet(context, t, s.currency)),
                    if (list.length > _shown) TextButton(onPressed: () => setState(() => _shown += 100), child: Text('Show more (${list.length - _shown})')),
                  ],
                ),
        ),
      ],
    );
  }
}

/// A category's transactions in a period, from the overview.
class CategoryTransactionsPage extends ConsumerWidget {
  const CategoryTransactionsPage({super.key, required this.category, this.period = 'this_month'});
  final String category;
  final String period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(financeStoreProvider);
    final store = ref.read(financeStoreProvider.notifier);
    final p = FinPeriod.resolve(period);
    final c = s.categoryMap[category];
    final list = s.transactions.where((t) => (category == 'uncategorized' ? t.category == null && t.isDebit : t.category == category) && p.contains(t.time)).toList();
    final total = list.fold(0.0, (a, t) => a + t.amount);
    return Scaffold(
      appBar: AppBar(title: Text(c?.name ?? 'Uncategorized')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.x4),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, Space.s, Space.xl, Space.l),
            child: Row(
              children: [
                CategoryIconTile(icon: c?.icon ?? 'more', category: category, size: 52),
                const SizedBox(width: Space.l),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MoneyText(total, cur: s.currency, size: 28),
                      Caption('${list.length} transactions · ${p.label}'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          FinCard(
            padding: const EdgeInsets.symmetric(vertical: Space.xs),
            child: Column(children: groupedByDay([for (final t in list) describeTransaction(store, s, t)], s.currency, dense: true, onTap: (t, _) => showTransactionSheet(context, t, s.currency), headerPadding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0))),
          ),
        ],
      ),
    );
  }
}

/// Records a transaction by hand: direction, a large amount, account,
/// category, who, note and date.
class TransactionEditorPage extends ConsumerStatefulWidget {
  const TransactionEditorPage({super.key, this.accountId, this.income = false});

  /// The account to start on; otherwise Cash or the first one.
  final String? accountId;
  final bool income;

  @override
  ConsumerState<TransactionEditorPage> createState() => _TransactionEditorPageState();
}

class _TransactionEditorPageState extends ConsumerState<TransactionEditorPage> {
  late bool _income = widget.income;
  String? _account;
  String? _category;
  DateTime _date = DateTime.now();
  final _amount = TextEditingController();
  final _who = TextEditingController();
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    final s = ref.read(financeStoreProvider);
    _account = widget.accountId ?? s.accounts.where((a) => a.bankId == cashBankId).firstOrNull?.id ?? s.accounts.firstOrNull?.id;
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amount.dispose();
    _who.dispose();
    _note.dispose();
    super.dispose();
  }

  double? get _value => double.tryParse(_amount.text.replaceAll(',', '').trim());

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(financeStoreProvider);
    final store = ref.read(financeStoreProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('New transaction')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.x4),
        children: [
          PillTabs<bool>(
            options: const [(false, 'Money out'), (true, 'Money in')],
            value: _income,
            onChanged: (v) => setState(() {
              _income = v;
              _category = null;
            }),
          ),
          const SizedBox(height: Space.xl),
          _AmountField(controller: _amount, cur: s.currency, autofocus: true, color: _income ? finIn : null),
          if (s.accounts.isNotEmpty) ...[
            const _Label('Account'),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final a in s.accounts.where((a) => !a.dormant))
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Pill(dense: true, label: store.accountName(a), icon: Icons.account_balance_wallet_outlined, selected: _account == a.id, onTap: () => setState(() => _account = a.id)),
                    ),
                  Pill(dense: true, label: 'None', selected: _account == null, onTap: () => setState(() => _account = null)),
                ],
              ),
            ),
          ],
          const _Label('Category'),
          CategoryPills(categories: [for (final c in s.categories.where((c) => c.income == _income)) (c.key, c.name, c.icon)], selected: _category, onChanged: (k) => setState(() => _category = k)),
          const _Label('Details'),
          TextField(controller: _who, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: _income ? 'From' : 'Paid to', prefixIcon: const Icon(Icons.person_outline_rounded, size: 20))),
          const SizedBox(height: Space.m),
          TextField(controller: _note, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Note', prefixIcon: Icon(Icons.notes_rounded, size: 20))),
          const SizedBox(height: Space.m),
          Material(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(Radii.m),
            child: ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.m)),
              leading: const Icon(Icons.event_rounded, size: 20),
              title: Text(dayLabel(_date)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2015), lastDate: DateTime.now());
                if (d != null) setState(() => _date = DateTime(d.year, d.month, d.day, _date.hour, _date.minute));
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: _SaveBar(
        label: 'Save',
        onPressed: _value == null || _value! <= 0
            ? null
            : () async {
                await store.addTransaction(type: _income ? 'CREDIT' : 'DEBIT', amount: _value!, accountId: _account, time: _date, counterparty: _who.text, note: _note.text, category: _category);
                if (context.mounted) Navigator.pop(context);
              },
      ),
    );
  }
}

// ---- budgets -----------------------------------------------------------------------------------

class _Budgets extends ConsumerWidget {
  const _Budgets();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(financeStoreProvider);
    final cur = s.currency;
    final status = budgetStatus(s.budgets, s.transactions, s.categoryMap);
    if (status.isEmpty) {
      return _Empty(
        icon: Icons.savings_rounded,
        title: 'Plan your spending',
        text: 'Set a weekly or monthly limit for groceries, eating out or anything else, or for all your spending, and see what\'s left as you go.',
        actions: [FilledButton.icon(onPressed: () => _push(context, const BudgetEditorPage()), icon: const Icon(Icons.add_rounded), label: const Text('Create a budget'))],
      );
    }
    final monthly = status.where((b) => b['period'] == 'month').toList();
    final weekly = status.where((b) => b['period'] == 'week').toList();
    final overall = monthly.where((b) => b['category'] == null).firstOrNull;
    final limit = overall != null ? numOf(overall['limit']) : monthly.fold(0.0, (a, b) => a + numOf(b['limit']));
    final spent = overall != null ? numOf(overall['spent']) : monthly.fold(0.0, (a, b) => a + numOf(b['spent']));
    final now = DateTime.now();
    final daysLeft = DateTime(now.year, now.month + 1).difference(now).inDays;
    final left = limit - spent;
    final color = spent > limit ? finOut : (limit > 0 && spent / limit > 0.85 ? AppColors.warning : finIn);
    FinBudget of(Map<String, dynamic> b) => s.budgets.firstWhere((x) => x.id == b['id']);
    return ListView(
      padding: const EdgeInsets.only(top: Space.m, bottom: 100),
      children: [
        if (limit > 0)
          FinCard(
            child: Row(
              children: [
                RingProgress(
                  value: limit == 0 ? 0 : spent / limit,
                  color: color,
                  size: 104,
                  stroke: 10,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${(limit == 0 ? 0 : spent / limit * 100).round()}%', style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      Caption('used'),
                    ],
                  ),
                ),
                const SizedBox(width: Space.xl),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Caption(overall != null ? 'This month' : 'Monthly budgets together', color: AppColors.text2),
                      const SizedBox(height: 2),
                      MoneyText(spent, size: 26),
                      Caption('of ${fmtAmount(limit)} $cur'),
                      const SizedBox(height: Space.s),
                      Text(
                        left >= 0 ? '${fmtAmount(left)} left · ${fmtCompact(left / (daysLeft + 1))}/day' : '${fmtAmount(-left)} over',
                        style: context.text.labelMedium?.copyWith(color: left >= 0 ? AppColors.text : finOut, fontWeight: FontWeight.w600),
                      ),
                      Caption('$daysLeft ${daysLeft == 1 ? 'day' : 'days'} to go'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        for (final (title, list) in [('Monthly', monthly), ('Weekly', weekly)])
          if (list.isNotEmpty) ...[
            SectionTitle(title),
            FinCard(
              padding: const EdgeInsets.symmetric(vertical: Space.xs),
              child: Column(
                children: [
                  for (var i = 0; i < list.length; i++) ...[
                    if (i > 0) Divider(height: 1, indent: Space.l, endIndent: Space.l, color: AppColors.line),
                    BudgetTile(budget: list[i], cur: cur, onTap: () => _push(context, BudgetEditorPage(budget: of(list[i])))),
                  ],
                ],
              ),
            ),
          ],
      ],
    );
  }
}

/// Sets a budget on its own page: a large limit, weekly or monthly, and
/// what it's for as a grid of categories, with what's typically spent.
class BudgetEditorPage extends ConsumerStatefulWidget {
  const BudgetEditorPage({super.key, this.budget});
  final FinBudget? budget;

  @override
  ConsumerState<BudgetEditorPage> createState() => _BudgetEditorPageState();
}

class _BudgetEditorPageState extends ConsumerState<BudgetEditorPage> {
  late String? _category = widget.budget?.category;
  late String _period = widget.budget?.period ?? 'month';
  late final _limit = TextEditingController(text: widget.budget == null ? '' : widget.budget!.limit.toStringAsFixed(0));

  @override
  void initState() {
    super.initState();
    _limit.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  /// The average spent per week or month on the chosen category over the
  /// last three months, and so far in this period.
  (double, double) _history(FinanceState s) {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month - 3);
    final to = DateTime(now.year, now.month);
    bool match(FinTransaction t) => t.isDebit && t.category != 'transfer' && (_category == null || t.category == _category);
    final past = s.transactions.where((t) => match(t) && !t.time.isBefore(from) && t.time.isBefore(to)).fold(0.0, (a, t) => a + t.outflow);
    final avg = _period == 'week' ? past / 13 : past / 3;
    final p = FinPeriod.resolve(_period == 'week' ? 'this_week' : 'this_month');
    final current = s.transactions.where((t) => match(t) && p.contains(t.time)).fold(0.0, (a, t) => a + t.outflow);
    return (avg, current);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(financeStoreProvider);
    final store = ref.read(financeStoreProvider.notifier);
    final b = widget.budget;
    final (avg, current) = _history(s);
    final limit = double.tryParse(_limit.text.replaceAll(',', '').trim());
    final exists = s.budgets.any((x) => x.id != b?.id && x.category == _category && x.period == _period);
    final name = _category == null ? 'all spending' : (s.categoryMap[_category]?.name ?? _category!);
    return Scaffold(
      appBar: AppBar(
        title: Text(b == null ? 'New budget' : 'Edit budget'),
        actions: [
          if (b != null)
            IconButton(
              tooltip: 'Remove budget',
              icon: Icon(Icons.delete_outline_rounded, color: AppColors.danger),
              onPressed: () async {
                await store.removeBudget(b.id);
                if (context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.x4),
        children: [
          _AmountField(controller: _limit, cur: s.currency, autofocus: b == null),
          Center(child: Caption('a ${_period == 'week' ? 'week' : 'month'} for $name', color: AppColors.text2)),
          const SizedBox(height: Space.m),
          if (avg > 0)
            Center(
              child: ActionChip(
                avatar: const Icon(Icons.auto_awesome_rounded, size: 16),
                label: Text('You usually spend ${fmtAmount(avg.roundToDouble())} — use that'),
                onPressed: () => _limit.text = (avg / 50).ceil() * 50 == 0 ? '' : '${(avg / 50).ceil() * 50}',
              ),
            ),
          const SizedBox(height: Space.xl),
          PillTabs<String>(options: const [('week', 'Weekly'), ('month', 'Monthly')], value: _period, onChanged: (v) => setState(() => _period = v)),
          if (limit != null && limit > 0) ...[
            const SizedBox(height: Space.l),
            FinCard(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.all(Space.m + 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Caption('Spent so far this ${_period == 'week' ? 'week' : 'month'}', color: AppColors.text2),
                      const Spacer(),
                      Text('${fmtAmount(current)} / ${fmtAmount(limit)}', style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w600, fontFeatures: tabularFigures)),
                    ],
                  ),
                  const SizedBox(height: Space.s),
                  ThickBar(value: current / limit, color: current > limit ? finOut : categoryColor(_category ?? 'misc')),
                ],
              ),
            ),
          ],
          const _Label('For'),
          CategoryGrid(
            allLabel: 'All spending',
            categories: [for (final c in s.categories.where((c) => !c.income && c.key != 'transfer')) (c.key, c.name, c.icon)],
            selected: _category,
            onChanged: (k) => setState(() => _category = k),
          ),
          if (exists) Padding(padding: const EdgeInsets.only(top: Space.m), child: Caption('There\'s already a ${_period}ly budget for $name; saving replaces it.', color: AppColors.warning, maxLines: 2)),
        ],
      ),
      bottomNavigationBar: _SaveBar(
        label: b == null ? 'Create budget' : 'Save',
        onPressed: limit == null || limit <= 0
            ? null
            : () async {
                if (b != null && (b.category != _category || b.period != _period)) await store.removeBudget(b.id);
                await store.setBudget(category: _category, limit: limit, period: _period);
                if (context.mounted) Navigator.pop(context);
              },
      ),
    );
  }
}

// ---- settings sheets ----------------------------------------------------------------------------

/// Where the SMS patterns come from, with a button to check for newer ones
/// and one to go back to the copy the app shipped with.
Future<void> _showPatterns(BuildContext context, WidgetRef ref) => showFormSheet<void>(
  context,
  builder: (context) => Consumer(
    builder: (context, ref, _) {
      final store = ref.read(financeStoreProvider.notifier);
      final p = ref.watch(financeStoreProvider).parser ?? store.parser;
      var busy = false;
      return StatefulBuilder(
        builder: (context, set) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Bank SMS patterns', style: context.text.titleLarge),
            const SizedBox(height: Space.s),
            Text(
              'Bank texts are read with the patterns the Totals app publishes. The app ships with a copy and checks Totals\' server '
              'for a newer one at most once a day, before a sync. Only the pattern files are downloaded; nothing about you or your money is sent.',
              style: context.text.bodySmall,
            ),
            const SizedBox(height: Space.l),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(p.source == 'downloaded' ? Icons.cloud_done_outlined : Icons.inventory_2_outlined),
              title: Text(p.source == 'downloaded' ? 'Downloaded from Totals' : 'Shipped with the app'),
              subtitle: Text(
                '${p.patterns.length} patterns · ${p.banks.where((b) => !b.manual).length} banks'
                '${p.fetchedAt != null ? ' · ${MaterialLocalizations.of(context).formatMediumDate(p.fetchedAt!)} ${TimeOfDay.fromDateTime(p.fetchedAt!).format(context)}' : ''}',
              ),
            ),
            const SizedBox(height: Space.m),
            FilledButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      set(() => busy = true);
                      final r = await store.refreshParser(force: true);
                      set(() => busy = false);
                      if (!context.mounted) return;
                      showSnack(
                        context,
                        r.error ?? (r.changed ? 'Updated to ${r.config.patterns.length} patterns. Sync again to re-read texts.' : 'Already up to date'),
                        icon: r.error == null ? Icons.check_rounded : Icons.error_outline_rounded,
                      );
                    },
              icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.cloud_download_outlined),
              label: const Text('Check for newer patterns'),
            ),
            if (p.source == 'downloaded') TextButton(onPressed: busy ? null : store.resetParser, child: const Text('Use the shipped copy instead')),
          ],
        ),
      );
    },
  ),
);

Future<String?> _askText(BuildContext context, String label, String initial) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(label),
      content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.characters),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Save')),
      ],
    ),
  );
}
