import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'activity_log.dart';
import 'untrusted.dart';

/// "Always allow replies in chat X", "allow reactions anywhere": standing
/// approvals the user made, usually from an approval card. A call a rule
/// covers runs without a card, whatever the approval mode. Destructive and
/// money-spending tools never get rules.
@immutable
class ApprovalRule {
  const ApprovalRule({
    required this.id,
    required this.tool,
    required this.toolLabel,
    this.chatId,
    this.chatTitle,
    this.account,
    required this.createdAt,
  });

  final String id;

  /// The tool's name, e.g. `reply_to_message`.
  final String tool;
  final String toolLabel;

  /// Only calls in this chat; null for anywhere.
  final int? chatId;
  final String? chatTitle;

  /// Only calls in this Telegram account; null for any.
  final String? account;
  final DateTime createdAt;

  bool get anywhere => chatId == null;

  String get description =>
      '$toolLabel · ${chatId == null ? 'anywhere' : 'in ${chatTitle?.trim().isNotEmpty == true ? chatTitle : 'chat $chatId'}'}';

  /// Whether this rule covers a call of [tool] with [args] in [accountId].
  bool covers(String tool, Map<String, dynamic> args, {String? accountId}) {
    if (tool != this.tool) return false;
    if (account != null && accountId != null && account != accountId) return false;
    if (chatId == null) return true;
    final chats = chatsOfCall(args);
    return chats.isNotEmpty && chats.every((c) => c == chatId);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'tool': tool,
    'label': toolLabel,
    'chat_id': ?chatId,
    'chat_title': ?chatTitle,
    'account': ?account,
    'at': createdAt.toIso8601String(),
  };

  factory ApprovalRule.fromJson(Map<String, dynamic> j) => ApprovalRule(
    id: '${j['id']}',
    tool: '${j['tool']}',
    toolLabel: '${j['label'] ?? j['tool']}',
    chatId: (j['chat_id'] as num?)?.toInt(),
    chatTitle: j['chat_title'] as String?,
    account: j['account'] as String?,
    createdAt: DateTime.tryParse('${j['at']}') ?? DateTime.now(),
  );
}

class ApprovalRuleStore extends Notifier<List<ApprovalRule>> {
  static const _key = 'approval_rules.v1';

  @override
  List<ApprovalRule> build() {
    _load();
    return const [];
  }

  Future<void> _load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return;
      state = [
        for (final j in jsonDecode(raw) as List) ApprovalRule.fromJson(Map<String, dynamic>.from(j as Map)),
      ];
    } catch (e) {
      debugPrint('[ApprovalRules] loading: $e');
    }
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode([for (final r in state) r.toJson()]));
  }

  /// The rule that covers this call, if any.
  ApprovalRule? match(String tool, Map<String, dynamic> args, {String? accountId}) =>
      state.where((r) => r.covers(tool, args, accountId: accountId)).firstOrNull;

  Future<ApprovalRule> add({
    required String tool,
    required String toolLabel,
    int? chatId,
    String? chatTitle,
    String? account,
  }) async {
    // The same rule again replaces the old one.
    final rule = ApprovalRule(
      id: const Uuid().v4(),
      tool: tool,
      toolLabel: toolLabel,
      chatId: chatId,
      chatTitle: chatTitle,
      account: account,
      createdAt: DateTime.now(),
    );
    state = [
      for (final r in state)
        if (!(r.tool == tool && r.chatId == chatId && r.account == account)) r,
      rule,
    ];
    await _save();
    ref.read(activityLogProvider.notifier).recordEvent(
      kind: ActivityKind.settings,
      title: 'Standing approval added: $toolLabel${chatTitle == null ? '' : ' in $chatTitle'}',
      detail: 'This tool now runs without asking${chatTitle == null ? '' : ' in that chat'}.',
    );
    return rule;
  }

  Future<void> remove(String id) async {
    final gone = state.where((r) => r.id == id).firstOrNull;
    state = [for (final r in state) if (r.id != id) r];
    await _save();
    if (gone != null) {
      ref.read(activityLogProvider.notifier).recordEvent(
        kind: ActivityKind.settings,
        title: 'Standing approval removed: ${gone.toolLabel}${gone.chatTitle == null ? '' : ' in ${gone.chatTitle}'}',
      );
    }
  }
}

final approvalRulesProvider = NotifierProvider<ApprovalRuleStore, List<ApprovalRule>>(ApprovalRuleStore.new);
