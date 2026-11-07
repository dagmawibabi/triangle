import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teleai/features/assistant/reminders.dart';
import 'package:teleai/features/assistant/watches.dart';
import 'package:teleai/features/brief/brief_prefs.dart';
import 'package:teleai/features/chat/domain/chat_models.dart';
import 'package:teleai/features/settings/data/settings.dart';
import 'package:teleai/features/telegram/data/account_tools.dart';
import 'package:teleai/features/telegram/data/telegram_tools.dart';
import 'package:teleai/infrastructure/telegram/accounts.dart';

void main() {
  const work = TelegramAccount(id: 'main', userId: 11, name: 'Dagi Work', username: 'dagi_work');
  const personal = TelegramAccount(id: 'a1', userId: 22, name: 'Dagi Babi', username: 'dagi');
  const hidden = TelegramAccount(id: 'a2', userId: 33, name: 'Side', aiAccess: false);

  group('AccountsState', () {
    test('the one being added is not counted as signed in', () {
      const s = AccountsState(
        accounts: [work, TelegramAccount(id: 'a9', userId: 99)],
        activeId: 'a9',
        addingId: 'a9',
        returnToId: 'main',
      );
      expect(s.signedIn.map((a) => a.id), ['main']);
      expect(s.hasSeveral, isFalse);
      expect(s.canAdd, isFalse, reason: 'one add at a time');
    });

    test('up to five accounts', () {
      expect(maxAccounts, 5);
      const four = AccountsState(
        accounts: [work, personal, hidden, TelegramAccount(id: 'a3', userId: 44)],
        activeId: 'main',
      );
      expect(four.canAdd, isTrue);
      const five = AccountsState(
        accounts: [work, personal, hidden, TelegramAccount(id: 'a3', userId: 44), TelegramAccount(id: 'a4', userId: 55)],
        activeId: 'main',
      );
      expect(five.canAdd, isFalse);
    });

    test('the assistant only sees accounts it may use', () {
      const s = AccountsState(accounts: [work, personal, hidden], activeId: 'a2');
      expect(s.forAi.map((a) => a.id), ['main', 'a1']);
      // The active account is off limits, so calls default elsewhere.
      expect(defaultAiAccount(s), 'main');
    });
  });

  group('resolveAccount', () {
    const s = AccountsState(accounts: [work, personal, hidden], activeId: 'a1');

    test('by @username, name, id or user id', () {
      expect(resolveAccount(s, '@dagi_work'), 'main');
      expect(resolveAccount(s, 'dagi'), 'a1');
      expect(resolveAccount(s, 'Dagi Babi'), 'a1');
      expect(resolveAccount(s, '11'), 'main');
      expect(resolveAccount(s, 'work'), 'main', reason: 'one name word matching one account');
    });

    test('never an account the assistant may not use', () {
      expect(resolveAccount(s, 'Side'), isNull);
      expect(resolveAccount(s, '33'), isNull);
    });

    test('unknown or empty names fall back to the default', () {
      expect(resolveAccount(s, 'nobody'), isNull);
      expect(accountForCall(s, {'account': ''}), 'a1');
      expect(accountForCall(s, {}), 'a1');
      expect(withoutAccount({'account': '@dagi', 'chat_id': 1}), {'chat_id': 1});
    });
  });

  group('limitedTo (what an automatic run may use)', () {
    const s = AccountsState(accounts: [work, personal, hidden], activeId: 'main');

    test('only the covered accounts, defaulting to where the message came from', () {
      final v = s.limitedTo(['main', 'a1'], preferred: 'a1');
      expect(v.forAi.map((a) => a.id), ['main', 'a1']);
      expect(defaultAiAccount(v), 'a1');
    });

    test('accounts outside are out of reach', () {
      final v = s.limitedTo(['a1']);
      expect(v.forAi.map((a) => a.id), ['a1']);
      expect(defaultAiAccount(v), 'a1', reason: 'the active account is not covered');
      expect(resolveAccount(v, '@dagi_work'), isNull);
    });

    test('a preferred account it does not cover is ignored', () {
      expect(defaultAiAccount(s.limitedTo(['main'], preferred: 'a1')), 'main');
    });

    test('null covers every account the assistant may use', () {
      expect(s.limitedTo(null).forAi.map((a) => a.id), ['main', 'a1']);
    });
  });

  group('accountsArgument', () {
    const s = AccountsState(accounts: [work, personal, hidden], activeId: 'main');

    test('names to ids; "all" or nothing means every account', () {
      expect(accountsArgument(s, ['@dagi', 'Side']), ['a1', 'a2']);
      expect(accountsArgument(s, 'dagi_work, dagi'), ['main', 'a1']);
      expect(accountsArgument(s, ['all']), isNull);
      expect(accountsArgument(s, null), isNull);
    });

    test('an unknown name is an error, not a silent "all"', () {
      expect(() => accountsArgument(s, ['nobody']), throwsFormatException);
    });
  });

  group('Watch accounts', () {
    Watch watch({WatchScope scope = WatchScope.allDms, List<String>? accounts, String? folderAccount}) => Watch(
      id: 'w',
      name: 'w',
      scope: scope,
      mode: WatchMode.notify,
      accountIds: accounts,
      folderAccountId: folderAccount,
      createdAt: DateTime(2026),
    );

    test('covers its accounts, or all of them', () {
      expect(watch().covers('a1'), isTrue);
      expect(watch(accounts: ['main']).covers('a1'), isFalse);
      expect(watch(accounts: ['main']).covers('main'), isTrue);
    });

    test('a folder watch covers its folder\'s account only', () {
      final old = watch(scope: WatchScope.folder);
      expect(old.covers(legacyAccountId), isTrue, reason: 'made before several accounts');
      expect(old.covers('a1'), isFalse);
      final w = watch(scope: WatchScope.folder, folderAccount: 'a1', accounts: ['main']);
      expect(w.covers('a1'), isTrue);
      expect(w.covers('main'), isFalse);
      expect(w.runAccounts, ['a1']);
    });

    test('survives saving', () {
      final w = Watch.fromJson(watch(accounts: ['a1']).toJson());
      expect(w.accountIds, ['a1']);
      expect(Watch.fromJson(watch().toJson()).accountIds, isNull);
      expect(watch(accounts: ['a1']).copyWith(allAccounts: true).accountIds, isNull);
    });

    test('jobs and briefs keep their accounts too', () {
      final r = Reminder(id: 'r', text: 't', prompt: 'p', createdAt: DateTime(2026), accountIds: const ['a1']);
      expect(Reminder.fromJson(r.toJson()).accountIds, ['a1']);
      expect(BriefPrefs.fromJson(const BriefPrefs(accountIds: ['main']).toJson()).accountIds, ['main']);
      expect(BriefPrefs.fromJson(const BriefPrefs().toJson()).accountIds, isNull);
    });
  });

  test('a post remembers the account it was read in', () {
    final p = PostSnapshot(chatId: 5, messageId: 9, chatTitle: 'Alice', date: DateTime(2026), text: 'hi', accountId: 'a1');
    expect(PostSnapshot.fromJson(p.toJson()).accountId, 'a1');
    final old = PostSnapshot(chatId: 5, messageId: 9, chatTitle: 'Alice', date: DateTime(2026), text: 'hi');
    expect(PostSnapshot.fromJson(old.toJson()).accountId, isNull, reason: 'saved before accounts: opened by lookup');
  });

  group('per-account rules', () {
    const settings = AppSettings(approvalMode: ApprovalMode.never);
    final send = toolNamed('send_message')!;
    final read = toolNamed('list_chats')!;

    test('a read-only account keeps only the tools that read', () {
      const locked = TelegramAccount(id: 'a1', userId: 22, readOnly: true);
      expect(toolOnFor(send, settings, locked), isFalse);
      expect(toolOnFor(read, settings, locked), isTrue);
      expect(toolOnFor(send, settings, personal), isTrue);
    });

    test('an account can ask for approval when Settings don\'t', () {
      const careful = TelegramAccount(id: 'a1', userId: 22, approvalMode: 'ask');
      expect(approvalModeFor(settings, careful), ApprovalMode.ask);
      expect(approvalModeFor(settings, personal), ApprovalMode.never);
      expect(approvalModeFor(settings, null), ApprovalMode.never);
    });

    test('rules survive saving', () {
      const a = TelegramAccount(id: 'a1', userId: 22, readOnly: true, approvalMode: 'watches', mentionAlerts: false);
      final back = TelegramAccount.fromJson(a.toJson());
      expect(back.readOnly, isTrue);
      expect(back.approvalMode, 'watches');
      expect(back.mentionAlerts, isFalse);
      expect(back.copyWith(clearApprovalMode: true).approvalMode, isNull);
    });

    test('apps & web and device tools follow an account\'s own switches too', () {
      final web = toolNamed('web_search')!;
      const own = TelegramAccount(id: 'a1', userId: 22, disabledTools: {'web_search'}, enabledDangerTools: {});
      expect(toolOnFor(web, const AppSettings(), own), isFalse);
      expect(toolOnFor(web, const AppSettings(), personal), web.isOn(const AppSettings()));
    });

    test('naming an account in the request', () {
      expect(namesAccount('comments under that post on @dagi please', personal), isTrue);
      expect(namesAccount('use Dagi Work for this', work), isTrue);
      expect(namesAccount('comments under that post', personal), isFalse);
    });

    test('a redone call acts in the account it named', () {
      const s = AccountsState(accounts: [work, personal], activeId: 'main');
      expect(accountOfCall(s, 'send_message', {'account': 'a1', 'chat_id': 1}), 'a1');
      expect(accountOfCall(s, 'send_message', {'chat_id': 1}), 'main');
      expect(accountOfCall(s, 'web_search', {'query': 'x'}), isNull, reason: 'not a Telegram account tool');
    });
  });

  group('AccountRegistry', () {
    test('no saved list: the existing account, unchanged', () async {
      SharedPreferences.setMockInitialValues({});
      final s = await AccountRegistry.load();
      expect(s.accounts.single.id, legacyAccountId);
      expect(s.activeId, legacyAccountId);
    });

    test('round-trips, and drops an add the app was closed during', () async {
      SharedPreferences.setMockInitialValues({});
      final saved = AccountsState(
        accounts: [
          work,
          personal.copyWith(disabledTools: {'send_message'}, enabledDangerTools: {}),
          const TelegramAccount(id: 'a5'),
        ],
        activeId: 'a5',
        addingId: 'a5',
        returnToId: 'a1',
      );
      await AccountRegistry.save(saved);
      final s = await AccountRegistry.load();
      expect(s.accounts.map((a) => a.id), ['main', 'a1']);
      expect(s.activeId, 'a1', reason: 'back to the account open before adding');
      expect(s.byId('a1')!.customTools, isTrue);
      expect(s.byId('a1')!.disabledTools, {'send_message'});
      expect(s.byId('main')!.customTools, isFalse);
    });
  });
}
