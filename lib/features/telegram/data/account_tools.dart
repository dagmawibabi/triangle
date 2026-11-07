import '../../../infrastructure/telegram/accounts.dart';
import '../../settings/data/settings.dart';
import 'telegram_tools.dart';

/// How the assistant's Telegram tools pick an account when several are
/// signed in: each call may name one in an `account` argument; without it
/// the call goes to the active account (or, if the assistant may not use
/// that one, the first account it may use).

/// The argument Telegram tools take when the assistant can reach more than
/// one account.
const accountArgument = 'account';

/// Whether [t] is one of the tools that act inside a Telegram account (and
/// so is routed to one and switchable per account).
bool isAccountTool(TelegramTool t) => t.needsTelegram;

/// Whether the assistant gets [t] in [a]: the account's own switches when it
/// has them, Settings → Tools otherwise. Read-only mode applies either way.
bool toolOnFor(TelegramTool t, AppSettings s, TelegramAccount a) {
  // An account made read-only keeps only the tools that read in it.
  if (isAccountTool(t) && a.readOnly && (t.modifiesData || t.destructive)) return false;
  // Every tool, apps & web and device ones too, follows the account's own
  // switches when it has them: those apply while working in that account.
  if (!a.customTools) return t.isOn(s);
  final chosen = t.destructive ? a.enabledDangerTools!.contains(t.name) : !a.disabledTools!.contains(t.name);
  return chosen && !(s.readOnlyMode && (t.modifiesData || t.destructive));
}

/// Whether [t] is on in at least one account the assistant may use, so it
/// is worth offering.
bool toolOnSomewhere(TelegramTool t, AppSettings s, AccountsState accounts) {
  final ai = accounts.forAi;
  if (ai.isEmpty) return t.isOn(s);
  // An apps & web or device tool follows the account being worked in.
  if (!isAccountTool(t)) {
    final home = accounts.byId(defaultAiAccount(accounts));
    return home == null || !accounts.hasSeveral ? t.isOn(s) : toolOnFor(t, s, home);
  }
  return ai.any((a) => toolOnFor(t, s, a));
}

/// Whether [text] (what the user wrote) names [a]: its @username, username
/// or display name.
bool namesAccount(String text, TelegramAccount a) {
  final t = text.toLowerCase();
  final u = a.username?.toLowerCase();
  if (u != null && u.isNotEmpty && t.contains(u)) return true;
  final name = a.name.trim().toLowerCase();
  return name.isNotEmpty && t.contains(name);
}

/// The approval mode for the assistant's actions in [a]: its own, else
/// Settings → Approvals.
ApprovalMode approvalModeFor(AppSettings s, TelegramAccount? a) =>
    ApprovalMode.values.asNameMap()[a?.approvalMode] ?? s.approvalMode;

/// The account a tool call in a chat acts in, for cards that show or redo
/// the call: the one it names (written in when it was approved), else the
/// default. Null for tools that don't act in an account.
String? accountOfCall(AccountsState s, String tool, Map<String, dynamic> args) {
  final t = toolNamed(tool);
  if (t == null || !isAccountTool(t)) return null;
  return resolveAnyAccount(s, args[accountArgument]) ?? defaultAiAccount(s);
}

/// The account calls go to when they don't name one.
String defaultAiAccount(AccountsState s) {
  final ai = s.forAi;
  if (ai.any((a) => a.id == s.activeId)) return s.activeId;
  return ai.firstOrNull?.id ?? s.activeId;
}

/// The account [name] refers to among those the assistant may use: its id,
/// display name, @username or Telegram user id. Null when none matches.
String? resolveAccount(AccountsState s, Object? name) {
  final q = '${name ?? ''}'.trim().toLowerCase().replaceFirst('@', '');
  if (q.isEmpty) return null;
  for (final a in s.forAi) {
    if (a.id.toLowerCase() == q ||
        a.label.toLowerCase() == q ||
        a.username?.toLowerCase() == q ||
        '${a.userId}' == q) {
      return a.id;
    }
  }
  // A first name alone ("work" won't match, "Dagi" will).
  final partial = [
    for (final a in s.forAi)
      if (a.label.toLowerCase().split(RegExp(r'\s+')).contains(q)) a.id,
  ];
  return partial.length == 1 ? partial.first : null;
}

/// The signed-in account [name] refers to, whether or not the assistant may
/// use it (a notify-only watch can cover any account).
String? resolveAnyAccount(AccountsState s, Object? name) {
  final q = '${name ?? ''}'.trim().toLowerCase().replaceFirst('@', '');
  if (q.isEmpty) return null;
  for (final a in s.signedIn) {
    if (a.id.toLowerCase() == q || a.label.toLowerCase() == q || a.username?.toLowerCase() == q || '${a.userId}' == q) {
      return a.id;
    }
  }
  return null;
}

/// The `accounts` argument of watch and reminder tools: null when absent
/// or "all", else the account ids it names. Throws [FormatException] for a
/// name that matches no account.
List<String>? accountsArgument(AccountsState s, Object? value) {
  if (value == null) return null;
  final names = value is List ? value.map((e) => '$e') : '$value'.split(',');
  final list = [for (final n in names) if (n.trim().isNotEmpty) n.trim()];
  if (list.isEmpty || list.any((n) => n.toLowerCase() == 'all')) return null;
  final ids = <String>[];
  for (final n in list) {
    final id = resolveAnyAccount(s, n);
    if (id == null) {
      throw FormatException('No Telegram account "$n". Accounts: ${s.signedIn.map(accountHandle).join(', ')}, or "all".');
    }
    if (!ids.contains(id)) ids.add(id);
  }
  return ids;
}

/// The schema of the `accounts` argument watch and reminder tools take.
Map<String, dynamic> accountsParameter(String what) => {
  'type': 'array',
  'items': {'type': 'string'},
  'description':
      'Only with several Telegram accounts: which accounts $what covers, by @username or name. '
      'Omit (or ["all"]) for every account.',
};

/// The account a call goes to: the one it names, else the default.
String accountForCall(AccountsState s, Map<String, dynamic> args) =>
    resolveAccount(s, args[accountArgument]) ?? defaultAiAccount(s);

/// [args] without the routing argument, as the tool itself expects them.
Map<String, dynamic> withoutAccount(Map<String, dynamic> args) =>
    args.containsKey(accountArgument) ? ({...args}..remove(accountArgument)) : args;

/// How each account is referred to in tool calls and the prompt.
String accountHandle(TelegramAccount a) => a.username != null ? '@${a.username}' : a.label;

/// [t]'s parameters, with the `account` argument added when the assistant
/// can reach several accounts.
Map<String, dynamic> parametersWithAccount(TelegramTool t, AccountsState s, AppSettings settings) {
  final params = t.parameters;
  final ai = s.forAi;
  if (!isAccountTool(t) || ai.length < 2) return params;
  // Only the accounts where the tool is on can be picked.
  final on = [for (final a in ai) if (toolOnFor(t, settings, a)) a];
  final active = s.byId(defaultAiAccount(s));
  return {
    ...params,
    'properties': {
      ...?(params['properties'] as Map?)?.cast<String, dynamic>(),
      accountArgument: {
        'type': 'string',
        'enum': [for (final a in on.isEmpty ? ai : on) accountHandle(a)],
        'description': t.modifiesData
            ? 'Which of the user\'s Telegram accounts acts. Required for this tool: name the account the user meant.'
            : 'Which of the user\'s Telegram accounts to read. Default: ${active == null ? 'the active one' : accountHandle(active)}.',
      },
    },
    if (t.modifiesData) 'required': [...?(params['required'] as List?), accountArgument],
  };
}
