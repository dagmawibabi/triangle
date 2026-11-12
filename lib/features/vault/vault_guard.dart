import 'vault.dart';

/// Tools that carry text out to other people: messages, posts, comments,
/// emails, SMS. A call to one of these that holds something from the vault
/// waits for the user (unless approvals are set to "Never ask"), whatever
/// else would have let it run on its own.
const outgoingTools = {
  // Telegram
  'send_message',
  'reply_to_message',
  'forward_message',
  'edit_message',
  'schedule_message',
  'comment_on_post',
  'send_contact',
  'send_voice_message',
  'send_rich_message',
  'edit_rich_message',
  'reply_channel_dm',
  'post_story',
  'edit_story',
  'set_welcome_message',
  'send_inline_result',
  'stream_bot_message',
  'bot_api',
  // Phone
  'send_sms',
  // Email
  'gmail_send_email',
  'gmail_reply_to_thread',
  'gmail_forward_message',
  'gmail_create_email_draft',
  'gmail_send_draft',
  'outlook_send_email',
  'outlook_reply_email',
  'outlook_create_draft',
  // Other apps
  'slack_send_message',
  'slack_schedule_message',
  'slack_updates_a_slack_message',
  'notion_create_comment',
  'github_create_an_issue_comment',
  'linear_create_linear_comment',
  'x_post',
};

/// Every string in [args], nested lists and maps included, joined.
String _textOf(Object? v) => switch (v) {
  String s => s,
  num n => '$n',
  List l => l.map(_textOf).join('\n'),
  Map m => m.values.map(_textOf).join('\n'),
  _ => '',
};

String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');

String _squash(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// The vault items whose values appear in an outgoing call's arguments.
/// Numbers (phones, IDs, accounts) match on their digits, so "+251 911
/// 234 567" and "0911234567" are the same; other values match as text,
/// ignoring case and spacing. Values too short to tell apart are skipped.
List<VaultItem> vaultItemsIn(String tool, Map<String, dynamic> args, Iterable<VaultItem> items) {
  if (!outgoingTools.contains(tool)) return const [];
  final text = _textOf(args);
  if (text.trim().isEmpty) return const [];
  final squashed = _squash(text);
  // Each number in the text, written with spaces, dashes or brackets or
  // not, as its digits alone; separate numbers stay separate.
  final numbers = [for (final m in RegExp(r'\d[\d \-().]*\d').allMatches(text)) _digits(m[0]!)];
  final found = <VaultItem>[];
  for (final i in items) {
    final value = i.value.trim();
    if (value.isEmpty) continue;
    final d = _digits(value);
    // A number (digits and separators only): compare digits, with the last
    // nine for phones so a country code or leading 0 doesn't matter. One
    // with letters in it ("EP1234567") matches as text.
    if (d.length >= 6 && RegExp(r'^\+?[\d \-().]+$').hasMatch(value)) {
      final tail = i.category == VaultCategory.phone && d.length > 9 ? d.substring(d.length - 9) : d;
      if (numbers.any((n) => n.contains(tail))) found.add(i);
      continue;
    }
    final v = _squash(value);
    if (v.length >= 5 && squashed.contains(v)) found.add(i);
  }
  return found;
}
