import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/app_sheet.dart';
import '../finance_store.dart';
import '../finance_tools.dart';
import 'finance_ui.dart';

/// A transaction's sheet: the amount and who, its category as tight pills
/// (a tap saves it), whether to remember that for the counterparty, the
/// details, the bank's receipt and delete. [tx] is the tool or screen map;
/// when the transaction is still on the phone it's edited live, otherwise
/// the sheet only shows it.
Future<void> showTransactionSheet(BuildContext context, Map<String, dynamic> tx, String cur) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  backgroundColor: AppColors.surface,
  builder: (context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: _TxSheet(initial: tx, cur: cur),
  ),
);

class _TxSheet extends ConsumerStatefulWidget {
  const _TxSheet({required this.initial, required this.cur});
  final Map<String, dynamic> initial;
  final String cur;

  @override
  ConsumerState<_TxSheet> createState() => _TxSheetState();
}

class _TxSheetState extends ConsumerState<_TxSheet> {
  bool _remember = true;
  late final TextEditingController _note = TextEditingController(text: '${widget.initial['note'] ?? ''}');

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(financeStoreProvider);
    final store = ref.read(financeStoreProvider.notifier);
    final live = s.transactions.where((t) => t.id == widget.initial['id']).firstOrNull;
    final tx = live == null ? widget.initial : describeTransaction(store, s, live);
    final income = tx['type'] == 'income';
    final who = '${tx['counterparty'] ?? ''}';
    final cats = [
      for (final c in s.categories)
        if (c.income == income || c.key == 'transfer') (c.key, c.name, c.icon),
    ];
    final rows = <(String, String, bool)>[
      ('Account', '${tx['account'] ?? tx['bank'] ?? '—'}', false),
      ('When', whenLabel(tx['date']), false),
      if (tx['fee'] != null) ('Fees & VAT', money(tx['fee'], widget.cur), false),
      if (tx['balance_after'] != null) ('Balance after', money(tx['balance_after'], widget.cur), false),
      ('Reference', '${tx['reference'] ?? '—'}', true),
      ('Source', tx['source'] == 'sms' ? 'Bank SMS' : 'Added by hand', false),
      if (tx['own_transfer'] == true) ('Counted as', 'Transfer between your accounts', false),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CategoryIconTile(icon: tx['icon'] ?? (income ? 'in' : 'out'), category: tx['category'] as String?, color: tx['category'] == null ? (income ? finIn : AppColors.text2) : null, size: 52),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(who.isEmpty ? (income ? 'Money in' : 'Money out') : who, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        if (live != null)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            iconSize: 16,
                            tooltip: 'Rename',
                            onPressed: () async {
                              final v = await _ask(context, income ? 'From' : 'Paid to', who);
                              if (v != null) await store.updateTransaction(live.id, counterparty: v);
                            },
                            icon: Icon(Icons.edit_outlined, color: AppColors.text3),
                          ),
                      ],
                    ),
                    Caption('${tx['category_name'] ?? 'Uncategorized'} · ${dayLabel(DateTime.tryParse('${tx['date']}') ?? DateTime.now())}'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.l),
          MoneyText(numOf(tx['amount']) * (income ? 1 : -1), cur: widget.cur, size: 34, sign: true, color: income ? finIn : AppColors.text),
          if (live != null) ...[
            const SizedBox(height: Space.xl),
            Row(
              children: [
                Text('Category', style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                if (who.isNotEmpty)
                  GestureDetector(
                    onTap: () => setState(() => _remember = !_remember),
                    child: Row(
                      children: [
                        Caption('Always for ${who.length > 18 ? '${who.substring(0, 17)}…' : who}', color: AppColors.text2),
                        const SizedBox(width: 4),
                        SizedBox(
                          height: 24,
                          child: FittedBox(child: Switch(value: _remember, onChanged: (v) => setState(() => _remember = v))),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Space.s),
            CategoryPills(
              categories: cats,
              selected: tx['category'] as String?,
              onChanged: (k) {
                HapticFeedback.selectionClick();
                store.updateTransaction(live.id, category: k, clearCategory: k == null, remember: _remember && k != null);
              },
            ),
            const SizedBox(height: Space.l),
            TextField(
              controller: _note,
              decoration: const InputDecoration(hintText: 'Add a note', prefixIcon: Icon(Icons.notes_rounded, size: 20), isDense: true),
              textInputAction: TextInputAction.done,
              onSubmitted: (v) => store.updateTransaction(live.id, note: v),
              onTapOutside: (_) {
                if (_note.text != live.note) store.updateTransaction(live.id, note: _note.text);
                FocusScope.of(context).unfocus();
              },
            ),
          ],
          const SizedBox(height: Space.l),
          Container(
            decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.l)),
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) Divider(height: 1, indent: Space.l, endIndent: Space.l, color: AppColors.line),
                  InkWell(
                    onTap: rows[i].$3
                        ? () {
                            Clipboard.setData(ClipboardData(text: rows[i].$2));
                            showSnack(context, 'Reference copied');
                          }
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
                      child: Row(
                        children: [
                          Text(rows[i].$1, style: context.text.bodySmall?.copyWith(color: AppColors.text3)),
                          const SizedBox(width: Space.l),
                          Expanded(child: Text(rows[i].$2, textAlign: TextAlign.end, style: context.text.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis)),
                          if (rows[i].$3) ...[const SizedBox(width: 6), Icon(Icons.copy_rounded, size: 14, color: AppColors.text3)],
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: Space.l),
          Row(
            children: [
              if (tx['link'] != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => launchUrl(Uri.parse('${tx['link']}'), mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.receipt_long_rounded, size: 18),
                    label: const Text('Bank receipt'),
                  ),
                ),
              if (tx['link'] != null && live != null) const SizedBox(width: Space.s),
              if (live != null)
                Expanded(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                    onPressed: () async {
                      if (await confirmDelete(context, title: 'Delete this transaction?', message: 'The account balance isn\'t changed.')) {
                        await store.deleteTransaction(live.id);
                        if (context.mounted) Navigator.pop(context);
                      }
                    },
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Delete'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<String?> _ask(BuildContext context, String label, String initial) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(label),
      content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.words),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Save')),
      ],
    ),
  );
}
