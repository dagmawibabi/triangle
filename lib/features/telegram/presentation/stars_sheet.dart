import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../infrastructure/telegram/telegram_client.dart';
import '../data/telegram_store.dart';
import '../data/telegram_tools.dart';
import 'expression_panel.dart' show StickerImage;
import 'tg_avatar.dart';

const starGold = Color(0xFFFFB300);

/// A post's Stars: how many it got, its top supporters, and giving some.
Future<void> showStarSheet(BuildContext context, td.Message message) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  backgroundColor: AppColors.surface,
  builder: (_) => _StarSheet(message: message),
);

class _StarSheet extends ConsumerStatefulWidget {
  const _StarSheet({required this.message});
  final td.Message message;

  @override
  ConsumerState<_StarSheet> createState() => _StarSheetState();
}

class _StarSheetState extends ConsumerState<_StarSheet> {
  int? _balance;
  bool _sending = false;
  int _amount = 1;

  @override
  void initState() {
    super.initState();
    ref.read(toolRunnerProvider).starBalance().then((b) {
      if (mounted) setState(() => _balance = b);
    }).catchError((Object _) {});
  }

  Future<void> _send() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Send $_amount Star${_amount == 1 ? '' : 's'}?'),
        content: const Text('They go to the owner of this channel or chat, and can\'t be taken back.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _sending = true);
    try {
      await ref.read(toolRunnerProvider).sendStars(widget.message.chatId, widget.message.id, _amount);
      if (!mounted) return;
      Navigator.pop(context);
      showSnack(context, 'Sent $_amount ⭐', icon: Icons.star_rounded);
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        showSnack(context, 'Couldn\'t send Stars: $e', icon: Icons.error_outline_rounded);
      }
    }
  }

  Future<void> _custom() async {
    final ctrl = TextEditingController(text: '$_amount');
    final n = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('How many Stars?'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(suffixText: '⭐', hintText: '1–2500'),
          onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v.trim())),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text.trim())), child: const Text('Set')),
        ],
      ),
    );
    if (n != null && n > 0) setState(() => _amount = n.clamp(1, 2500));
  }

  static const _presets = [1, 5, 10, 25, 50, 100, 500];

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(telegramStoreProvider);
    final reactions = widget.message.interactionInfo?.reactions;
    final total = reactions?.reactions.where((r) => r.type is td.ReactionTypePaid).fold<int>(0, (n, r) => n + r.totalCount) ?? 0;
    final reactors = [...?reactions?.paidReactors]..sort((a, b) => b.starCount.compareTo(a.starCount));
    final mine = reactors.where((p) => p.isMe).fold<int>(0, (n, p) => n + p.starCount);
    final top = reactors.isEmpty ? 1 : reactors.first.starCount.clamp(1, 1 << 30);
    final enough = _balance == null || _balance! >= _amount;
    final number = NumberFormat.decimalPattern();
    final chatTitle = store.chat(widget.message.chatId)?.title ?? 'this chat';
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The total, gold, with what the account has to give.
            Container(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.m),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.l),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [starGold.withValues(alpha: 0.28), starGold.withValues(alpha: 0.06)],
                ),
                border: Border.all(color: starGold.withValues(alpha: 0.35)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.star_rounded, color: starGold, size: 44),
                  const SizedBox(height: 2),
                  Text(
                    number.format(total),
                    style: context.text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, fontFeatures: tabularFigures),
                  ),
                  Text(
                    '${total == 1 ? 'Star' : 'Stars'} on this post${reactors.isEmpty ? '' : ' from ${reactors.length} supporter${reactors.length == 1 ? '' : 's'}'}',
                    style: context.text.bodySmall,
                  ),
                  const SizedBox(height: Space.m),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: Space.s,
                    runSpacing: Space.xs,
                    children: [
                      _Pill(
                        icon: Icons.account_balance_wallet_outlined,
                        text: _balance == null ? 'Balance…' : 'You have ${number.format(_balance)} ⭐',
                      ),
                      if (mine > 0) _Pill(icon: Icons.favorite_rounded, text: 'You gave ${number.format(mine)} ⭐'),
                    ],
                  ),
                ],
              ),
            ),
            if (reactors.isNotEmpty) ...[
              const SizedBox(height: Space.l),
              Text('TOP SUPPORTERS', style: context.text.labelSmall),
              const SizedBox(height: Space.xs),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 230),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: reactors.length,
                  itemBuilder: (_, i) {
                    final p = reactors[i];
                    final anonymous = p.isAnonymous || p.senderId == null;
                    final name = p.isMe ? 'You' : (anonymous ? 'Anonymous' : store.senderName(p.senderId!));
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 24,
                            child: Text(
                              i < 3 ? const ['🥇', '🥈', '🥉'][i] : '${i + 1}',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: i < 3 ? 16 : 12.5, color: AppColors.text3),
                            ),
                          ),
                          const SizedBox(width: Space.s),
                          anonymous
                              ? CircleAvatar(
                                  radius: 16,
                                  backgroundColor: AppColors.surface3,
                                  child: Icon(Icons.visibility_off_outlined, size: 15, color: AppColors.text3),
                                )
                              : TgAvatar(
                                  userId: p.senderId is td.MessageSenderUser ? (p.senderId as td.MessageSenderUser).userId : null,
                                  chatId: p.senderId is td.MessageSenderChat ? (p.senderId as td.MessageSenderChat).chatId : null,
                                  title: name,
                                  size: 32,
                                ),
                          const SizedBox(width: Space.m),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontWeight: p.isMe ? FontWeight.w700 : FontWeight.w500, fontSize: 14),
                                ),
                                const SizedBox(height: 4),
                                // Their share against the top supporter.
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: LinearProgressIndicator(
                                    value: p.starCount / top,
                                    minHeight: 4,
                                    backgroundColor: AppColors.surface3,
                                    color: starGold.withValues(alpha: p.isMe ? 1 : 0.7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: Space.m),
                          Text(
                            '${number.format(p.starCount)} ⭐',
                            style: const TextStyle(color: starGold, fontWeight: FontWeight.w700, fontFeatures: tabularFigures),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: Space.l),
            Text('GIVE STARS', style: context.text.labelSmall),
            const SizedBox(height: Space.s),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final n in _presets)
                  ChoiceChip(
                    label: Text('$n ⭐'),
                    selected: _amount == n,
                    selectedColor: starGold.withValues(alpha: 0.25),
                    side: BorderSide(color: _amount == n ? starGold : AppColors.line),
                    onSelected: (_) => setState(() => _amount = n),
                  ),
                ChoiceChip(
                  avatar: Icon(Icons.edit_outlined, size: 15, color: AppColors.text2),
                  label: Text(_presets.contains(_amount) ? 'Custom' : '$_amount ⭐'),
                  selected: !_presets.contains(_amount),
                  selectedColor: starGold.withValues(alpha: 0.25),
                  side: BorderSide(color: !_presets.contains(_amount) ? starGold : AppColors.line),
                  onSelected: (_) => _custom(),
                ),
              ],
            ),
            const SizedBox(height: Space.m),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: starGold,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: AppColors.surface3,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.l)),
                ),
                onPressed: _sending || !enough ? null : _send,
                icon: _sending
                    ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.star_rounded),
                label: Text(
                  enough ? 'Send $_amount Star${_amount == 1 ? '' : 's'}' : 'Not enough Stars',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ),
            const SizedBox(height: Space.s),
            Text(
              enough
                  ? 'Stars go to $chatTitle and can\'t be taken back.'
                  : 'Buy Stars in Telegram\'s Settings → Telegram Stars.',
              textAlign: TextAlign.center,
              style: context.text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(999)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: starGold),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

/// Who reacted to a message, and with what.
Future<void> showReactorsSheet(BuildContext context, td.Message message) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  backgroundColor: AppColors.surface,
  builder: (_) => _ReactorsSheet(message: message),
);

class _ReactorsSheet extends ConsumerStatefulWidget {
  const _ReactorsSheet({required this.message});
  final td.Message message;

  @override
  ConsumerState<_ReactorsSheet> createState() => _ReactorsSheetState();
}

class _ReactorsSheetState extends ConsumerState<_ReactorsSheet> {
  List<td.AddedReaction>? _list;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref
        .read(telegramClientProvider)
        .send<td.AddedReactions>(
          td.GetMessageAddedReactions(chatId: widget.message.chatId, messageId: widget.message.id, offset: '', limit: 100),
          limited: true,
        )
        .then((r) {
          if (mounted) setState(() => _list = r.reactions);
        })
        .catchError((Object e) {
          // Channels don't say who reacted; only the counts are public.
          if (mounted) setState(() => _error = 'Telegram only shows the counts here, not who reacted.');
        });
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(telegramStoreProvider);
    final reactions = widget.message.interactionInfo?.reactions?.reactions ?? const <td.MessageReaction>[];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Reactions', style: context.text.titleLarge),
            const SizedBox(height: Space.m),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final r in reactions)
                  Chip(
                    avatar: ReactionIcon(type: r.type, size: 18),
                    label: Text(NumberFormat.decimalPattern().format(r.totalCount)),
                  ),
              ],
            ),
            const SizedBox(height: Space.m),
            if (_error != null)
              Text(_error!, style: context.text.bodySmall)
            else if (_list == null)
              const Padding(padding: EdgeInsets.all(Space.l), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final a in _list!)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: TgAvatar(
                          userId: a.senderId is td.MessageSenderUser ? (a.senderId as td.MessageSenderUser).userId : null,
                          chatId: a.senderId is td.MessageSenderChat ? (a.senderId as td.MessageSenderChat).chatId : null,
                          title: store.senderName(a.senderId),
                          size: 32,
                        ),
                        title: Text(a.isOutgoing ? 'You' : store.senderName(a.senderId)),
                        trailing: ReactionIcon(type: a.type, size: 22),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A reaction as a picture: the emoji, a gold star for paid ones, or the
/// custom emoji's image.
class ReactionIcon extends ConsumerStatefulWidget {
  const ReactionIcon({super.key, required this.type, this.size = 16});
  final td.ReactionType type;
  final double size;

  @override
  ConsumerState<ReactionIcon> createState() => _ReactionIconState();
}

/// Custom emoji stickers by id, fetched once for the whole app.
final Map<int, Future<td.Sticker?>> _customEmoji = {};

class _ReactionIconState extends ConsumerState<ReactionIcon> {
  td.Sticker? _sticker;

  @override
  void initState() {
    super.initState();
    if (widget.type case td.ReactionTypeCustomEmoji(:final customEmojiId)) {
      final client = ref.read(telegramClientProvider);
      _customEmoji[customEmojiId] ??= client
          .send<td.Stickers>(td.GetCustomEmojiStickers(customEmojiIds: [customEmojiId]), limited: true)
          .then<td.Sticker?>((s) => s.stickers.firstOrNull)
          .catchError((Object _) => null);
      _customEmoji[customEmojiId]!.then((s) {
        if (mounted && s != null) setState(() => _sticker = s);
      });
    }
  }

  @override
  Widget build(BuildContext context) => switch (widget.type) {
    td.ReactionTypeEmoji(:final emoji) => Text(emoji, style: TextStyle(fontSize: widget.size * 0.85, height: 1.1)),
    td.ReactionTypePaid() => Icon(Icons.star_rounded, color: starGold, size: widget.size + 2),
    _ => _sticker == null
        ? Icon(Icons.auto_awesome_rounded, size: widget.size, color: AppColors.text2)
        : StickerImage(sticker: _sticker!, size: widget.size + 2),
  };
}
