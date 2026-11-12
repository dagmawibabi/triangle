import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/widgets/app_sheet.dart';
import '../settings/data/settings.dart';
import 'vault.dart';

/// Settings → Vault: personal details the assistant can use, such as phone
/// numbers, addresses and document numbers. Kept encrypted on this phone.
class VaultScreen extends ConsumerStatefulWidget {
  const VaultScreen({super.key});

  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen> {
  String _q = '';
  final Set<String> _revealed = {};

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(vaultProvider);
    final vault = ref.read(vaultProvider.notifier);
    final shown = _q.isEmpty ? items : vault.find(_q);
    final s = ref.watch(settingsProvider);
    final toolsOff = !s.toolOn('vault_get') && !s.toolOn('vault_list');
    final groups = <VaultCategory, List<VaultItem>>{};
    for (final c in VaultCategory.values) {
      final inCat = shown.where((i) => i.category == c).toList()..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
      if (inCat.isNotEmpty) groups[c] = inCat;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Vault')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.text,
        foregroundColor: AppColors.bg,
        onPressed: () => _edit(context, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 96),
        children: [
          Container(
            padding: const EdgeInsets.all(Space.m),
            decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Radii.l)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.shield_outlined, size: 20, color: AppColors.text2),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Text(
                    'Details about you the assistant can use when you ask, like your numbers, addresses or ID numbers. '
                    'They\'re encrypted on this phone and go to the AI model only in a conversation that needs them. '
                    'Sensitive items are left out of watches, routines and any run that has read other people\'s messages. '
                    'Don\'t keep passwords or card numbers here.',
                    style: context.text.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          if (toolsOff)
            Padding(
              padding: const EdgeInsets.only(top: Space.s),
              child: Text('The vault tools are off in Settings → Tools, so the assistant can\'t see these.', style: context.text.bodySmall?.copyWith(color: AppColors.warning)),
            ),
          const SizedBox(height: Space.m),
          if (items.length > 4)
            TextField(
              onChanged: (v) => setState(() => _q = v.trim()),
              decoration: const InputDecoration(isDense: true, hintText: 'Search the vault', prefixIcon: Icon(Icons.search_rounded, size: 20)),
            ),
          if (items.isEmpty) ...[
            const SizedBox(height: Space.xl),
            Text('Start with', style: context.text.labelSmall),
            const SizedBox(height: Space.s),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (label, cat) in const [
                  ('Personal phone', VaultCategory.phone),
                  ('Personal email', VaultCategory.email),
                  ('Home address', VaultCategory.address),
                  ('Work address', VaultCategory.work),
                  ('Date of birth', VaultCategory.personal),
                  ('Passport number', VaultCategory.identity),
                  ('Car plate', VaultCategory.vehicle),
                  ('Emergency contact', VaultCategory.phone),
                  ('Blood type', VaultCategory.health),
                ])
                  ActionChip(
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: const VisualDensity(horizontal: -1, vertical: -3),
                    avatar: Icon(cat.icon, size: 16, color: AppColors.text2),
                    label: Text(label),
                    onPressed: () => _edit(context, null, label: label, category: cat),
                  ),
              ],
            ),
            const SizedBox(height: Space.l),
            Text(
              'Or tell the assistant in chat: "save my work number, +251 911 …"',
              style: context.text.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
          for (final MapEntry(key: cat, value: list) in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xs, Space.l, Space.xs, Space.xs),
              child: Text(cat.label.toUpperCase(), style: context.text.labelSmall),
            ),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(Radii.l),
                border: Border.all(color: AppColors.line),
              ),
              clipBehavior: Clip.antiAlias,
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  children: [
                    for (final (i, item) in list.indexed) ...[
                      if (i > 0) const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: lead(Icon(cat.icon)),
                        title: Row(
                          children: [
                            Flexible(child: Text(item.label, overflow: TextOverflow.ellipsis)),
                            if (item.sensitive) ...[const SizedBox(width: 6), Icon(Icons.lock_outline_rounded, size: 14, color: AppColors.text3)],
                            if (item.addedByAssistant) ...[const SizedBox(width: 6), Icon(Icons.auto_awesome_outlined, size: 14, color: AppColors.text3)],
                          ],
                        ),
                        subtitle: Text(
                          [
                            item.sensitive && !_revealed.contains(item.id) ? item.masked : item.value,
                            if (item.note.isNotEmpty) item.note,
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (item.sensitive)
                              IconButton(
                                tooltip: _revealed.contains(item.id) ? 'Hide' : 'Show',
                                icon: Icon(_revealed.contains(item.id) ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                                onPressed: () => setState(() => _revealed.contains(item.id) ? _revealed.remove(item.id) : _revealed.add(item.id)),
                              ),
                            IconButton(
                              tooltip: 'Copy',
                              icon: const Icon(Icons.copy_rounded, size: 20),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: item.value));
                                showSnack(context, 'Copied ${item.label}');
                              },
                            ),
                          ],
                        ),
                        onTap: () => _edit(context, item),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          if (items.isNotEmpty) ...[
            const SizedBox(height: Space.xl),
            Center(
              child: TextButton.icon(
                onPressed: () async {
                  if (await confirmDelete(context, title: 'Empty the vault?', message: 'All ${items.length} items are removed from this phone.', action: 'Empty')) {
                    await vault.clear();
                  }
                },
                icon: Icon(Icons.delete_sweep_outlined, color: AppColors.danger),
                label: Text('Empty the vault', style: TextStyle(color: AppColors.danger)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, VaultItem? item, {String? label, VaultCategory? category}) =>
      showFormSheet<void>(context, builder: (_) => _VaultItemSheet(item: item, label: label, category: category));
}

class _VaultItemSheet extends ConsumerStatefulWidget {
  const _VaultItemSheet({this.item, this.label, this.category});
  final VaultItem? item;
  final String? label;
  final VaultCategory? category;

  @override
  ConsumerState<_VaultItemSheet> createState() => _VaultItemSheetState();
}

class _VaultItemSheetState extends ConsumerState<_VaultItemSheet> {
  late final _label = TextEditingController(text: widget.item?.label ?? widget.label ?? '');
  late final _value = TextEditingController(text: widget.item?.value ?? '');
  late final _note = TextEditingController(text: widget.item?.note ?? '');
  late VaultCategory _category = widget.item?.category ?? widget.category ?? VaultCategory.other;
  late bool _sensitive = widget.item?.sensitive ?? (_category == VaultCategory.identity || _category == VaultCategory.health || _category == VaultCategory.account);

  @override
  void dispose() {
    _label.dispose();
    _value.dispose();
    _note.dispose();
    super.dispose();
  }

  static final _secret = RegExp(r'password|passcode|\bpin\b|cvv|cvc|security code', caseSensitive: false);

  Future<void> _save() async {
    final label = _label.text.trim(), value = _value.text.trim();
    if (label.isEmpty || value.isEmpty) {
      showSnack(context, 'Give it a name and a value', icon: Icons.info_outline_rounded);
      return;
    }
    if (_secret.hasMatch(label)) {
      showSnack(context, 'Keep passwords and PINs in a password manager, not here', icon: Icons.info_outline_rounded);
      return;
    }
    final vault = ref.read(vaultProvider.notifier);
    if (widget.item == null) {
      await vault.add(label: label, value: value, category: _category, note: _note.text, sensitive: _sensitive);
    } else {
      await vault.update(widget.item!.id, (i) => i.copyWith(label: label, value: value, category: _category, note: _note.text.trim(), sensitive: _sensitive));
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(item == null ? 'Add to the vault' : 'Edit', style: context.text.titleMedium),
        if (item != null)
          Text(
            '${item.addedByAssistant ? 'Saved by the assistant' : 'Added by you'} · changed ${DateFormat('d MMM y').format(item.updatedAt)}',
            style: context.text.bodySmall,
          ),
        const SizedBox(height: Space.m),
        TextField(controller: _label, autofocus: item == null && widget.label == null, decoration: const InputDecoration(labelText: 'What it is', hintText: 'e.g. Personal phone, Home address')),
        const SizedBox(height: Space.m),
        TextField(controller: _value, autofocus: widget.label != null, minLines: 1, maxLines: 4, decoration: const InputDecoration(labelText: 'Value')),
        const SizedBox(height: Space.m),
        TextField(controller: _note, decoration: const InputDecoration(labelText: 'When to use it (optional)', hintText: 'e.g. for deliveries; only for work')),
        const SizedBox(height: Space.m),
        Text('KIND', style: context.text.labelSmall),
        const SizedBox(height: Space.xs),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final c in VaultCategory.values)
              ChoiceChip(
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: const VisualDensity(horizontal: -1, vertical: -3),
                avatar: Icon(c.icon, size: 16, color: AppColors.text2),
                label: Text(c.label),
                selected: _category == c,
                onSelected: (_) => setState(() => _category = c),
              ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Sensitive'),
          subtitle: Text(
            'Hidden in lists, never in the assistant\'s standing instructions, and held back from watches, routines and runs that read other people\'s messages',
            style: context.text.bodySmall,
          ),
          value: _sensitive,
          onChanged: (v) => setState(() => _sensitive = v),
        ),
        const SizedBox(height: Space.s),
        Row(
          children: [
            if (item != null)
              TextButton.icon(
                onPressed: () async {
                  if (await confirmDelete(context, title: 'Remove "${item.label}"?', action: 'Remove')) {
                    await ref.read(vaultProvider.notifier).remove(item.id);
                    if (context.mounted) Navigator.pop(context);
                  }
                },
                icon: Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                label: Text('Remove', style: TextStyle(color: AppColors.danger)),
              ),
            const Spacer(),
            FilledButton(onPressed: _save, child: const Text('Save')),
          ],
        ),
      ],
    );
  }
}
