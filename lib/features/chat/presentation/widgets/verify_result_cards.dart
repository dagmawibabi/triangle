import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../domain/chat_models.dart';

/// The payment verifier's card: a clear verdict, the receipt's details,
/// each check with a tick or a cross, and the receipt itself a tap away.
Widget? verifyResultFor(ToolPart part, Map<String, dynamic> j) {
  if (part.name != 'finance_verify_payment' || j['error'] != null || j['status'] == null) return null;
  return _VerifyCard(data: j);
}

({IconData icon, Color color, String title, String text}) _verdict(Map<String, dynamic> j) => switch ('${j['status']}') {
  'verified' when (j['history'] as Map?)?['seen_before'] == true => (
    icon: Icons.history_rounded,
    color: AppColors.warning,
    title: 'Real, but used before',
    text: 'The bank confirms it, but this receipt was already confirmed ${(j['history'] as Map)['times_confirmed'] ?? 'before'} times. It may be an old receipt shown again.',
  ),
  'verified' when (j['receiver_match'] as Map?)?['matched'] == false => (
    icon: Icons.person_off_outlined,
    color: AppColors.warning,
    title: 'Paid, but not to you',
    text: 'The payment is real, but the receiver isn\'t your account.',
  ),
  'verified' when j['source'] == 'Verify.ET' => (icon: Icons.verified_rounded, color: AppColors.success, title: 'Payment verified', text: 'Verify.ET confirmed it with the bank.'),
  'verified' => (icon: Icons.verified_rounded, color: AppColors.success, title: 'Payment verified', text: 'The bank\'s own receipt exists for this reference.'),
  'in_your_texts' => (icon: Icons.sms_outlined, color: AppColors.warning, title: 'In your bank texts only', text: 'Your SMS show it, but the bank\'s receipt page didn\'t confirm it.'),
  'unreachable' => (icon: Icons.cloud_off_rounded, color: AppColors.warning, title: 'Couldn\'t reach the bank', text: 'The receipt site didn\'t answer. Try again in a bit.'),
  'not_found' => (icon: Icons.gpp_bad_outlined, color: AppColors.danger, title: 'No receipt found', text: 'The bank has no receipt for this reference.'),
  _ => (icon: Icons.help_outline_rounded, color: AppColors.text2, title: 'Can\'t check this bank', text: 'It has no public receipt page; use the link from its SMS.'),
};

class _VerifyCard extends StatelessWidget {
  const _VerifyCard({required this.data});
  final Map<String, dynamic> data;

  Map<String, dynamic> get _details => Map<String, dynamic>.from((data['details'] as Map?) ?? const {});
  Map<String, dynamic>? get _local => data['in_your_texts'] is Map ? Map<String, dynamic>.from(data['in_your_texts'] as Map) : null;
  List<Map<String, dynamic>> get _checks => [for (final c in (data['checks'] as List? ?? const [])) if (c is Map) Map<String, dynamic>.from(c)];

  String? get _amount {
    final d = _details['amount'] ?? _details['total'];
    if (d != null) return '$d';
    final l = _local;
    return l == null ? null : '${(l['amount'] as num).toStringAsFixed(2)} ${l['currency'] ?? 'ETB'}';
  }

  @override
  Widget build(BuildContext context) {
    final v = _verdict(data);
    final d = _details;
    final local = _local;
    final inbound = local != null && local['type'] == 'money in';
    final outbound = local != null && local['type'] == 'money out';
    final payer = d['payer'] ?? (inbound ? local['counterparty'] : null);
    final receiver = d['receiver'] ?? (outbound ? local['counterparty'] : null);
    return Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Radii.l), border: Border.all(color: v.color.withValues(alpha: 0.45))),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => _sheet(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(Space.m),
                color: v.color.withValues(alpha: 0.1),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: v.color, shape: BoxShape.circle),
                      child: Icon(v.icon, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: Space.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(v.title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                          Text(v.text, style: context.text.bodySmall?.copyWith(color: AppColors.text2, height: 1.3)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.s),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            [if (data['bank'] != null) '${data['bank']}', 'Ref ${data['reference']}'].join(' · '),
                            style: context.text.labelSmall?.copyWith(color: AppColors.text3, fontFeatures: tabularFigures),
                          ),
                          if (_amount != null)
                            Text(_amount!, style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, fontFeatures: tabularFigures)),
                          if (d['date'] != null || local?['date'] != null)
                            Text('${d['date'] ?? '${local!['date']}'.replaceFirst('T', ' ')}', style: context.text.labelSmall?.copyWith(color: AppColors.text3)),
                        ],
                      ),
                    ),
                    if (d['status'] != null) _Chip('${d['status']}'),
                  ],
                ),
              ),
              if (payer != null || receiver != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
                  child: Row(
                    children: [
                      Expanded(child: _Party(label: 'From', name: '${payer ?? '—'}', account: d['payer_account'] as String?)),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: Space.s), child: Icon(Icons.arrow_forward_rounded, size: 18, color: AppColors.text3)),
                      Expanded(child: _Party(label: 'To', name: '${receiver ?? '—'}', account: d['receiver_account'] as String?)),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
                child: Column(children: [for (final c in _checks) _CheckRow(c: c)]),
              ),
              Container(
                decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
                padding: const EdgeInsets.fromLTRB(Space.s, 2, 0, 2),
                child: Row(
                  children: [
                    // Takes the free space, so the buttons sit at the right edge.
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: Space.s),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(data['source'] == 'Verify.ET' ? Icons.cloud_done_outlined : Icons.account_balance_outlined, size: 13, color: AppColors.text3),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                data['source'] == 'Verify.ET'
                                    ? 'Verify.ET'
                                    : switch (Uri.tryParse('${data['receipt_url'] ?? ''}')?.host ?? '') {
                                        '' => 'Bank receipt page',
                                        final host => host,
                                      },
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.text.labelSmall?.copyWith(color: AppColors.text3),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (data['file_path'] != null && File('${data['file_path']}').existsSync())
                      _button(Icons.picture_as_pdf_outlined, 'Receipt', () => OpenFilex.open('${data['file_path']}'))
                    else if (data['receipt_url'] != null)
                      _button(Icons.open_in_new_rounded, 'Receipt', () => launchUrl(Uri.parse('${data['receipt_url']}'), mode: LaunchMode.externalApplication)),
                    _button(Icons.info_outline_rounded, 'Details', () => _sheet(context)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _sheet(BuildContext context) {
    final v = _verdict(data);
    final d = _details;
    final local = _local;
    showAppSheet<void>(
      context,
      initialSize: 0.8,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.x4),
        children: [
          Row(
            children: [
              Icon(v.icon, color: v.color, size: 28),
              const SizedBox(width: Space.m),
              Expanded(child: Text(v.title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            ],
          ),
          const SizedBox(height: Space.s),
          Text('${data['note'] ?? v.text}', style: context.text.bodySmall?.copyWith(color: AppColors.text2, height: 1.4)),
          const SizedBox(height: Space.l),
          _Section(title: 'CHECKS', children: [for (final c in _checks) _CheckRow(c: c)]),
          if (d.isNotEmpty)
            _Section(
              title: data['source'] == 'Verify.ET' ? 'FROM THE BANK, VIA VERIFY.ET' : 'ON THE BANK\'S RECEIPT',
              children: [
                for (final e in const [
                  ('payer', 'Payer'),
                  ('payer_account', 'Payer account'),
                  ('receiver', 'Receiver'),
                  ('receiver_account', 'Receiver account'),
                  ('amount', 'Amount'),
                  ('fee', 'Fee'),
                  ('total', 'Total'),
                  ('date', 'Date'),
                  ('status', 'Status'),
                  ('reason', 'Reason'),
                  ('reference', 'Reference'),
                  ('receipt_number', 'Receipt number'),
                ])
                  if (d[e.$1] != null) _Field(e.$2, '${d[e.$1]}'),
              ],
            ),
          if (local != null)
            _Section(
              title: 'IN YOUR BANK TEXTS',
              children: [
                _Field('Kind', '${local['type']}'),
                _Field('Amount', '${(local['amount'] as num).toStringAsFixed(2)} ${local['currency'] ?? ''}'),
                if ('${local['counterparty'] ?? ''}'.isNotEmpty) _Field(local['type'] == 'money in' ? 'From' : 'To', '${local['counterparty']}'),
                if (local['account'] != null) _Field('Account', '${local['account']}'),
                _Field('When', '${local['date']}'.replaceFirst('T', ' ')),
              ],
            ),
          if (data['receiver_match'] is Map || data['history'] is Map)
            _Section(
              title: 'SAFETY',
              children: [
                if (data['receiver_match'] is Map) ...[
                  _Field('Paid to you', (data['receiver_match'] as Map)['matched'] == true ? 'Yes · ${(data['receiver_match'] as Map)['confidence'] ?? ''} confidence' : 'No'),
                  if ((data['receiver_match'] as Map)['account'] != null) _Field('Receiving account', '${(data['receiver_match'] as Map)['account']}'),
                ],
                if (data['history'] is Map) ...[
                  _Field('Used before', (data['history'] as Map)['seen_before'] == true ? 'Yes' : 'No, first time'),
                  if ((data['history'] as Map)['times_confirmed'] != null) _Field('Times confirmed', '${(data['history'] as Map)['times_confirmed']}'),
                  if ((data['history'] as Map)['first_confirmed'] != null) _Field('First confirmed', '${(data['history'] as Map)['first_confirmed']}'.replaceFirst('T', ' ').split('.').first),
                ],
              ],
            ),
          _Section(
            title: 'SOURCE',
            children: [
              _Field('Reference', '${data['reference']}', copy: true),
              if (data['bank'] != null) _Field('Bank', '${data['bank']}'),
              if (data['receipt_url'] != null) _Field('Receipt page', '${data['receipt_url']}', copy: true),
              if (data['qr'] != null) _Field('QR code', '${data['qr']}', copy: true),
              if (data['source'] == 'Verify.ET') ...[
                const _Field('Checked by', 'Verify.ET (verify.et)'),
                if (data['request_id'] != null) _Field('Request', '${data['request_id']}', copy: true),
              ] else ...[
                _Field('Pages tried', '${data['tried'] ?? 0}'),
                const _Field('Checked from', 'This phone, directly with the bank'),
                if (data['verify_et'] != null) _Field('Verify.ET', '${data['verify_et']}'),
              ],
            ],
          ),
          if (data['file_path'] != null && File('${data['file_path']}').existsSync())
            FilledButton.icon(onPressed: () => OpenFilex.open('${data['file_path']}'), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Open the receipt PDF'))
          else if (data['receipt_url'] != null)
            FilledButton.icon(
              onPressed: () => launchUrl(Uri.parse('${data['receipt_url']}'), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Open the bank\'s receipt'),
            ),
        ],
      ),
    );
  }
}

Widget _button(IconData icon, String label, VoidCallback onTap) => TextButton.icon(
  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: AppColors.text),
  onPressed: onTap,
  icon: Icon(icon, size: 16),
  label: Text(label),
);

class _Chip extends StatelessWidget {
  const _Chip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.line)),
    child: Text(text, style: context.text.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
  );
}

class _Party extends StatelessWidget {
  const _Party({required this.label, required this.name, this.account});
  final String label;
  final String name;
  final String? account;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(Space.s + 2),
    decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.m), border: Border.all(color: AppColors.line)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: context.text.labelSmall?.copyWith(color: AppColors.text3, fontSize: 9.5, letterSpacing: 0.6)),
        Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
        if (account != null) Text(account!, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: AppColors.text3, fontFeatures: tabularFigures)),
      ],
    ),
  );
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.c});
  final Map<String, dynamic> c;

  @override
  Widget build(BuildContext context) {
    final ok = c['ok'] == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle_rounded : Icons.cancel_rounded, size: 18, color: ok ? AppColors.success : AppColors.danger),
          const SizedBox(width: Space.s),
          Expanded(child: Text('${c['check']}', style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w600))),
          Flexible(child: Text('${c['note'] ?? ''}', textAlign: TextAlign.end, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(color: AppColors.text3))),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.l),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: context.text.labelSmall?.copyWith(color: AppColors.text3, letterSpacing: 0.8)),
        const SizedBox(height: Space.s),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.xs),
          decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.l)),
          child: Column(children: children),
        ),
      ],
    ),
  );
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value, {this.copy = false});
  final String label;
  final String value;
  final bool copy;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: copy
        ? () {
            Clipboard.setData(ClipboardData(text: value));
            showSnack(context, '$label copied');
          }
        : null,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: context.text.bodySmall?.copyWith(color: AppColors.text3))),
          Expanded(child: Text(value, style: context.text.bodyMedium)),
          if (copy) Icon(Icons.copy_rounded, size: 14, color: AppColors.text3),
        ],
      ),
    ),
  );
}
