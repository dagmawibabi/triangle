part of 'app_result_cards.dart';

/// Opens a Slack channel full screen.
void openSlackChannel(BuildContext context, {required String id, String? name}) => Navigator.of(context).push(
  MaterialPageRoute<void>(builder: (_) => SlackChannelScreen(channelId: id, name: name)),
);

/// A Slack channel, read through the Slack connection: its messages with
/// the newest at the bottom, older ones as you scroll up, threads in a
/// sheet, and a box to post to it.
class SlackChannelScreen extends ConsumerStatefulWidget {
  const SlackChannelScreen({super.key, required this.channelId, this.name});
  final String channelId;
  final String? name;

  @override
  ConsumerState<SlackChannelScreen> createState() => _SlackChannelScreenState();
}

class _SlackChannelScreenState extends ConsumerState<SlackChannelScreen> {
  final _messages = <Map<String, dynamic>>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  String? _cursor;
  String? _error;
  bool _loading = false;
  bool _sending = false;
  bool _done = false;

  String get _title => widget.name == null || widget.name!.isEmpty ? 'Slack' : '#${widget.name}';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      // The list is reversed: the far end is the oldest message.
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _load();
    });
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool fresh = false}) async {
    if (_loading || (_done && !fresh)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await ref.read(toolRunnerProvider).run('slack_fetch_conversation_history', {
      'channel': widget.channelId,
      'limit': 25,
      if (!fresh && _cursor != null) 'cursor': _cursor,
    });
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.json['error'] != null) {
        _error = '${r.json['error']}';
        return;
      }
      final got = [for (final m in (r.json['messages'] as List? ?? const [])) if (m is Map) Map<String, dynamic>.from(m)];
      if (fresh) _messages.clear();
      final seen = {for (final m in _messages) m['ts']};
      _messages.addAll(got.where((m) => !seen.contains(m['ts'])));
      // Newest first, for the reversed list.
      _messages.sort((a, b) => _ts(b).compareTo(_ts(a)));
      _cursor = r.json['next_page'] as String?;
      _done = _cursor == null || got.isEmpty;
    });
  }

  static double _ts(Map<String, dynamic> m) => double.tryParse('${m['ts']}') ?? 0;

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final r = await ref.read(toolRunnerProvider).run('slack_send_message', {'channel': widget.channelId, 'markdown_text': text});
    if (!mounted) return;
    setState(() => _sending = false);
    if (r.json['error'] != null) {
      showSnack(context, 'Couldn\'t send: ${r.json['error']}', icon: Icons.error_outline_rounded);
      return;
    }
    _input.clear();
    await _load(fresh: true);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final count = _messages.length;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            const _AppLogo('slack', size: 22),
            const SizedBox(width: Space.s),
            Flexible(child: Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : () => _load(fresh: true),
          ),
          IconButton(
            tooltip: 'Open in Slack',
            icon: const Icon(Icons.open_in_new_rounded, size: 20),
            onPressed: () => _open('https://slack.com/app_redirect?channel=${widget.channelId}'),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: _error != null && count == 0
                  ? _SlackError(error: _error!, onRetry: () => _load(fresh: true))
                  : count == 0 && _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : count == 0
                  ? Center(child: Text('No messages here yet.', style: context.text.bodyMedium?.copyWith(color: AppColors.text3)))
                  : RefreshIndicator(
                      onRefresh: () => _load(fresh: true),
                      child: ListView.builder(
                        controller: _scroll,
                        reverse: true,
                        padding: const EdgeInsets.symmetric(vertical: Space.s),
                        itemCount: count + 1,
                        itemBuilder: (context, i) {
                          if (i == count) {
                            // The far (top) end: older messages, or the start.
                            return Padding(
                              padding: const EdgeInsets.all(Space.l),
                              child: Center(
                                child: _loading
                                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                    : _error != null
                                    ? TextButton(onPressed: _load, child: const Text('Couldn\'t load older messages. Retry'))
                                    : Text(_done ? 'Start of what Slack shares here' : '', style: context.text.labelSmall),
                              ),
                            );
                          }
                          final m = _messages[i];
                          // A new day starts above this message.
                          final older = i + 1 < count ? _messages[i + 1] : null;
                          final day = _day(m);
                          final showDay = older == null || _day(older) != day;
                          // Messages from the same person within a few minutes run together.
                          final grouped = older != null && !showDay && older['author'] == m['author'] && _ts(m) - _ts(older) < 300;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (showDay && day != null) _SlackDay(day: day),
                              _SlackMessageTile(
                                message: m,
                                grouped: grouped,
                                onThread: m['replies'] == null
                                    ? null
                                    : () => _showThread(context, m),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
            ),
            _SlackComposer(controller: _input, sending: _sending, hint: 'Message $_title', onSend: _send),
          ],
        ),
      ),
    );
  }

  static DateTime? _day(Map<String, dynamic> m) {
    final t = _ts(m);
    if (t == 0) return null;
    final d = DateTime.fromMillisecondsSinceEpoch((t * 1000).round());
    return DateTime(d.year, d.month, d.day);
  }

  void _showThread(BuildContext context, Map<String, dynamic> parent) => showAppSheet<void>(
    context,
    initialSize: 0.85,
    builder: (_, scroll) => _SlackThread(channelId: widget.channelId, parent: parent, scroll: scroll),
  );
}

class _SlackDay extends StatelessWidget {
  const _SlackDay({required this.day});
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final label = day == today
        ? 'Today'
        : day == today.subtract(const Duration(days: 1))
        ? 'Yesterday'
        : DateFormat(day.year == now.year ? 'EEEE, d MMMM' : 'd MMMM y').format(day);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s),
            child: Text(label, style: context.text.labelSmall),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}

/// One message in the channel: author and time (unless it runs on from the
/// one above), the text, reactions and its thread.
class _SlackMessageTile extends StatelessWidget {
  const _SlackMessageTile({required this.message, this.grouped = false, this.onThread});
  final Map<String, dynamic> message;
  final bool grouped;
  final VoidCallback? onThread;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final author = '${m['author'] ?? ''}';
    final reactions = (m['reactions'] as List? ?? const []);
    final ts = double.tryParse('${m['ts']}');
    final time = ts == null ? '' : DateFormat.Hm().format(DateTime.fromMillisecondsSinceEpoch((ts * 1000).round()));
    return InkWell(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: '${m['text'] ?? ''}'));
        showSnack(context, 'Message copied', icon: Icons.content_copy_rounded);
      },
      child: Padding(
        padding: EdgeInsets.fromLTRB(Space.l, grouped ? 2 : Space.s, Space.l, 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 36, child: grouped ? null : _Avatar(author, size: 36)),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!grouped)
                    Row(
                      children: [
                        Flexible(
                          child: Text(author, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: Space.s),
                        Text(time, style: context.text.labelSmall),
                      ],
                    ),
                  MarkdownBody(
                    data: _slackText('${m['text'] ?? ''}'),
                    selectable: false,
                    onTapLink: (_, href, _) => _open(href),
                    styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                      p: context.text.bodyMedium?.copyWith(height: 1.4),
                    ),
                  ),
                  if (reactions.isNotEmpty || onThread != null) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final r in reactions) _Pill(':$r'),
                        if (onThread != null)
                          InkWell(
                            borderRadius: BorderRadius.circular(99),
                            onTap: onThread,
                            child: _Pill('${m['replies']} repl${m['replies'] == 1 ? 'y' : 'ies'}', icon: Icons.forum_outlined, color: AppColors.accent),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A message's thread, with a box to reply in it.
class _SlackThread extends ConsumerStatefulWidget {
  const _SlackThread({required this.channelId, required this.parent, required this.scroll});
  final String channelId;
  final Map<String, dynamic> parent;
  final ScrollController scroll;

  @override
  ConsumerState<_SlackThread> createState() => _SlackThreadState();
}

class _SlackThreadState extends ConsumerState<_SlackThread> {
  final _input = TextEditingController();
  List<Map<String, dynamic>>? _replies;
  String? _error;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await ref.read(toolRunnerProvider).run('slack_fetch_message_thread_from_a_conversation', {
      'channel': widget.channelId,
      'ts': widget.parent['ts'],
      'limit': 100,
    });
    if (!mounted) return;
    setState(() {
      _error = r.json['error'] == null ? null : '${r.json['error']}';
      _replies = [
        for (final m in (r.json['messages'] as List? ?? const []))
          if (m is Map && m['ts'] != widget.parent['ts']) Map<String, dynamic>.from(m),
      ]..sort((a, b) => _SlackChannelScreenState._ts(a).compareTo(_SlackChannelScreenState._ts(b)));
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final r = await ref.read(toolRunnerProvider).run('slack_send_message', {
      'channel': widget.channelId,
      'thread_ts': widget.parent['ts'],
      'markdown_text': text,
    });
    if (!mounted) return;
    setState(() => _sending = false);
    if (r.json['error'] != null) {
      showSnack(context, 'Couldn\'t reply: ${r.json['error']}', icon: Icons.error_outline_rounded);
      return;
    }
    _input.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final replies = _replies;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              controller: widget.scroll,
              padding: const EdgeInsets.only(bottom: Space.l),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
                  child: Text('Thread', style: context.text.titleMedium),
                ),
                _SlackMessageTile(message: widget.parent),
                const Divider(height: Space.l),
                if (replies == null)
                  const Padding(padding: EdgeInsets.all(Space.xl), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                else if (_error != null)
                  _SlackError(error: _error!, onRetry: _load)
                else if (replies.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(Space.l),
                    child: Text('No replies yet.', style: context.text.bodySmall),
                  )
                else
                  for (final (i, m) in replies.indexed)
                    _SlackMessageTile(
                      message: m,
                      grouped: i > 0 && replies[i - 1]['author'] == m['author'],
                    ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: _SlackComposer(controller: _input, sending: _sending, hint: 'Reply in thread', onSend: _send),
          ),
        ],
      ),
    );
  }
}

class _SlackComposer extends StatefulWidget {
  const _SlackComposer({required this.controller, required this.sending, required this.hint, required this.onSend});
  final TextEditingController controller;
  final bool sending;
  final String hint;
  final VoidCallback onSend;

  @override
  State<_SlackComposer> createState() => _SlackComposerState();
}

class _SlackComposerState extends State<_SlackComposer> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final canSend = widget.controller.text.trim().isNotEmpty && !widget.sending;
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.m),
      padding: const EdgeInsets.fromLTRB(Space.l, 2, 4, 2),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(Radii.xl),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: widget.controller,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: widget.hint,
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Send',
            onPressed: canSend ? widget.onSend : null,
            icon: widget.sending
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.send_rounded, color: canSend ? AppColors.accent : AppColors.text3),
          ),
        ],
      ),
    );
  }
}

class _SlackError extends StatelessWidget {
  const _SlackError({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 36, color: AppColors.text3),
          const SizedBox(height: Space.m),
          Text('Couldn\'t load from Slack', style: context.text.titleSmall),
          const SizedBox(height: Space.xs),
          Text(error, textAlign: TextAlign.center, style: context.text.bodySmall),
          const SizedBox(height: Space.m),
          OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Try again')),
        ],
      ),
    ),
  );
}
