part of 'telegram_tools.dart';

// Personal finance, after Totals (github.com/detached-space/totals): bank
// SMS parsed into transactions, accounts, categories, budgets, summaries
// and insights. Kept on this phone in finance.json; the chat controller
// runs these through features/finance/finance_tools.dart.

const _period = {
  'type': 'string',
  'enum': FinPeriodKeys.all,
  'description': 'The span to cover; default this_month. Ignored when since or until is given.',
};
const _since = {'type': 'string', 'description': 'First day to include, YYYY-MM-DD.'};
const _until = {'type': 'string', 'description': 'Last day to include, YYYY-MM-DD.'};
const _accountRef = {'type': 'string', 'description': 'An account id from finance_accounts, or its nickname, bank name (when it has one account there) or last digits.'};

/// The card views of finance_summary and finance_insights.
abstract final class FinViews {
  static const summary = ['cashflow', 'spending', 'categories', 'payees', 'income', 'balance', 'all'];
  static const insights = ['health', 'recurring', 'unusual', 'projection', 'budget', 'all'];
}

/// The period keys, kept here so the schema is a constant.
abstract final class FinPeriodKeys {
  static const all = ['today', 'yesterday', 'this_week', 'last_week', 'this_month', 'last_month', 'last_7_days', 'last_30_days', 'last_90_days', 'this_year', 'last_year', 'all'];
}

final _financeTools = <TelegramTool>[
  TelegramTool(
    name: 'finance_sync_sms',
    label: 'Reading bank texts',
    category: ToolCategory.finance,
    cost: ToolCost.device,
    description:
        'Reads the phone\'s SMS inbox and turns bank and wallet messages (CBE, Awash, BOA, Dashen, Zemen, Telebirr, NIB, M-Pesa, '
        'Amhara, Ahadu, Berhan, Hibret, Apollo, CBE Birr) into transactions with Totals\' parser: amount, fees, balance after, '
        'counterparty, reference and receipt link, de-duplicated by reference. Account balances follow the newest message. Accounts '
        'named in messages but not added yet are created (detected: true) unless create_accounts is false. By default reads from the '
        'last sync, or 180 days back the first time. Run it before answering about money when the last sync is old. The user sees a sync card.',
    parameters: _obj({
      'since_days': {'type': 'integer', 'description': 'Read this many days back instead of from the last sync, 1-730.'},
      'create_accounts': {'type': 'boolean', 'description': 'Create accounts found in messages; default true.'},
    }),
  ),
  TelegramTool(
    name: 'finance_parse_sms',
    label: 'Reading a bank message',
    category: ToolCategory.finance,
    cost: ToolCost.local,
    description:
        'Parses one bank SMS the user pasted or forwarded, without saving it: bank, CREDIT/DEBIT, amount, fees, balance after, '
        'account, counterparty, reference, receipt link. With save true it is recorded as a transaction like a synced one.',
    parameters: _obj({
      'text': {'type': 'string', 'description': 'The message text exactly as the bank sent it.'},
      'sender': {'type': 'string', 'description': 'The sender id, like "CBE" or "127", when known.'},
      'bank': {'type': 'string', 'description': 'The bank name or id when the sender is unknown, like "Telebirr".'},
      'save': {'type': 'boolean', 'description': 'Record it as a transaction; default false.'},
    }, ['text']),
  ),
  TelegramTool(
    name: 'finance_overview',
    label: 'Checking your money',
    category: ToolCategory.finance,
    cost: ToolCost.local,
    description:
        'The complete picture in one dashboard: total balance, every account, this period\'s income, spending and net with a daily chart, '
        'top categories, budgets and the latest transactions. Only for broad asks like "how am I doing" or "give me the full picture"; '
        'for one thing (a balance, an account, spending, transactions) use the tool for that instead. The user sees a dashboard card.',
    parameters: _obj({'period': _period}),
  ),
  TelegramTool(
    name: 'finance_accounts',
    label: 'Listing accounts',
    category: ToolCategory.finance,
    cost: ToolCost.local,
    description:
        'Account balances. With account_id (or bank) only that account: its card, balance, when it was last reported and this '
        'month\'s in and out. Without, every account and the total. "How much is in my CBE?" is account_id "CBE"; "what are my '
        'balances?" is no filter. The user sees account cards for exactly what is returned.',
    parameters: _obj({
      'account_id': _accountRef,
      'bank': {'type': 'string', 'description': 'Only accounts at this bank, by name or id.'},
      'include_dormant': {'type': 'boolean', 'description': 'Also list accounts marked dormant; default true.'},
    }),
  ),
  TelegramTool(
    name: 'finance_add_account',
    label: 'Adding an account',
    category: ToolCategory.finance,
    cost: ToolCost.device,
    description:
        'Adds a bank account, wallet or cash pocket. bank: a bank from finance_banks (name, short name or id), "Cash", or "Other". '
        'number: the full account number, or the phone number for wallets like Telebirr; the last digits are what match bank SMS. '
        'Transactions from that bank waiting for an account move onto it.',
    parameters: _obj({
      'bank': {'type': 'string', 'description': 'Bank name, short name or id, e.g. "CBE", "Telebirr", "Cash".'},
      'number': {'type': 'string', 'description': 'Account or phone number; may be left out for cash.'},
      'holder': {'type': 'string', 'description': 'The account holder\'s name.'},
      'nickname': {'type': 'string', 'description': 'A short name like "Salary account".'},
      'balance': {'type': 'number', 'description': 'The current balance, when known.'},
      'include_in_totals': {'type': 'boolean', 'description': 'Count it in the total balance; default true.'},
      'default': {'type': 'boolean', 'description': 'Where this bank\'s messages go when they don\'t say which account.'},
    }, ['bank']),
  ),
  TelegramTool(
    name: 'finance_update_account',
    label: 'Updating an account',
    category: ToolCategory.finance,
    cost: ToolCost.device,
    description: 'Changes an account: nickname, number, holder, balance (a manual correction), whether it counts in totals, dormant, default.',
    parameters: _obj({
      'account_id': _accountRef,
      'nickname': {'type': 'string', 'description': 'New nickname; empty to clear.'},
      'number': {'type': 'string', 'description': 'New account or phone number.'},
      'holder': {'type': 'string', 'description': 'New holder name.'},
      'balance': {'type': 'number', 'description': 'Set the balance to this.'},
      'include_in_totals': {'type': 'boolean', 'description': 'Count it in the total balance.'},
      'dormant': {'type': 'boolean', 'description': 'Mark it no longer in use; history stays.'},
      'default': {'type': 'boolean', 'description': 'Make it the bank\'s default account.'},
    }, ['account_id']),
  ),
  TelegramTool(
    name: 'finance_delete_account',
    label: 'Removing an account',
    category: ToolCategory.finance,
    cost: ToolCost.device,
    requiresApproval: true,
    description: 'Removes an account. Its transactions stay (without an account) unless delete_transactions is true. The user approves first.',
    parameters: _obj({
      'account_id': _accountRef,
      'delete_transactions': {'type': 'boolean', 'description': 'Also delete its transactions; default false.'},
    }, ['account_id']),
  ),
  TelegramTool(
    name: 'finance_transactions',
    label: 'Looking at transactions',
    category: ToolCategory.finance,
    cost: ToolCost.local,
    description:
        'Transaction history, newest first, filtered by account, bank, type, category, counterparty or note words, amount range and '
        'dates, with the matching totals. Filter to what was asked: "my spending at Shoa" is type expense and query Shoa; "CBE '
        'transactions" is account_id CBE. The user sees just that list. Use ids from here to update or delete one.',
    parameters: _obj({
      'account_id': _accountRef,
      'bank': {'type': 'string', 'description': 'Only this bank, by name or id.'},
      'type': {'type': 'string', 'enum': ['all', 'income', 'expense'], 'description': 'Money in, money out, or both (default).'},
      'category': {'type': 'string', 'description': 'A category key or name; "uncategorized" for those without one.'},
      'query': {'type': 'string', 'description': 'Words to find in the counterparty, note or reference.'},
      'min_amount': {'type': 'number', 'description': 'Smallest amount to include.'},
      'max_amount': {'type': 'number', 'description': 'Largest amount to include.'},
      'period': {..._period, 'description': 'The span to cover; default all. Ignored when since or until is given.'},
      'since': _since,
      'until': _until,
      'sort': {'type': 'string', 'enum': ['newest', 'oldest', 'largest'], 'description': 'Order; default newest.'},
      'limit': {'type': 'integer', 'description': 'How many to list, 1-200; default 25.'},
    }),
  ),
  TelegramTool(
    name: 'finance_add_transaction',
    label: 'Recording a transaction',
    category: ToolCategory.finance,
    cost: ToolCost.device,
    description:
        'Records money in or out by hand: cash spending, a payment the bank didn\'t text about, a loan. Moves the account\'s balance '
        'unless adjust_balance is false. Without an account it goes to the Cash wallet when there is one.',
    parameters: _obj({
      'type': {'type': 'string', 'enum': ['income', 'expense'], 'description': 'Money in or money out.'},
      'amount': {'type': 'number', 'description': 'The amount, positive.'},
      'account_id': _accountRef,
      'counterparty': {'type': 'string', 'description': 'Who paid, or who was paid, like "Shoa supermarket".'},
      'category': {'type': 'string', 'description': 'A category key or name from finance_categories; guessed when left out.'},
      'note': {'type': 'string', 'description': 'A note about it.'},
      'date': {'type': 'string', 'description': 'When, YYYY-MM-DD or YYYY-MM-DDTHH:MM; default now.'},
      'fee': {'type': 'number', 'description': 'Any fee on top of the amount.'},
      'adjust_balance': {'type': 'boolean', 'description': 'Move the account balance by it; default true.'},
    }, ['type', 'amount']),
  ),
  TelegramTool(
    name: 'finance_update_transaction',
    label: 'Updating a transaction',
    category: ToolCategory.finance,
    cost: ToolCost.device,
    description:
        'Changes a transaction: its category (with remember true, every transaction with that counterparty gets it, now and later), '
        'note, counterparty, account, amount, type or date.',
    parameters: _obj({
      'transaction_id': {'type': 'string', 'description': 'The id from finance_transactions.'},
      'category': {'type': 'string', 'description': 'A category key or name; "none" to clear it.'},
      'remember': {'type': 'boolean', 'description': 'Use this category for the counterparty from now on; default false.'},
      'note': {'type': 'string', 'description': 'New note.'},
      'counterparty': {'type': 'string', 'description': 'New counterparty name.'},
      'account_id': _accountRef,
      'amount': {'type': 'number', 'description': 'Corrected amount.'},
      'type': {'type': 'string', 'enum': ['income', 'expense'], 'description': 'Corrected direction.'},
      'date': {'type': 'string', 'description': 'Corrected date, YYYY-MM-DD or YYYY-MM-DDTHH:MM.'},
    }, ['transaction_id']),
  ),
  TelegramTool(
    name: 'finance_delete_transaction',
    label: 'Deleting a transaction',
    category: ToolCategory.finance,
    cost: ToolCost.device,
    requiresApproval: true,
    description: 'Deletes one transaction, such as a duplicate or a wrong manual entry. Balances aren\'t changed. The user approves first.',
    parameters: _obj({
      'transaction_id': {'type': 'string', 'description': 'The id from finance_transactions.'},
    }, ['transaction_id']),
  ),
  TelegramTool(
    name: 'finance_summary',
    label: 'Adding up your money',
    category: ToolCategory.finance,
    cost: ToolCost.local,
    description:
        'Totals for a period as one focused card, chosen by view: cashflow (income vs spending and net; the default), spending '
        '(what went out, with a chart and daily average), categories (spending by category), payees (who was paid most), income '
        '(income and where it came from), balance (the balance over time), or all (every section, only when asked for a full '
        'report). Pick the view that answers the question. Own transfers between accounts are left out.',
    parameters: _obj({
      'view': {'type': 'string', 'enum': FinViews.summary, 'description': 'Which card to show; default cashflow.'},
      'period': _period,
      'since': _since,
      'until': _until,
      'account_id': _accountRef,
    }),
  ),
  TelegramTool(
    name: 'finance_insights',
    label: 'Looking for insights',
    category: ToolCategory.finance,
    cost: ToolCost.local,
    description:
        'Totals\' analysis over all history as one focused card, chosen by view: health (the 0-100 score, what makes it up and '
        'tips; the default), recurring (repeated payments and when the next is due), unusual (unusually large expenses and income), '
        'projection (month by month and next month\'s expected income and spending), budget (the 50/30/20 comparison), or all.',
    parameters: _obj({
      'view': {'type': 'string', 'enum': FinViews.insights, 'description': 'Which card to show; default health.'},
      'account_id': _accountRef,
    }),
  ),
  TelegramTool(
    name: 'finance_budgets',
    label: 'Checking budgets',
    category: ToolCategory.finance,
    cost: ToolCost.local,
    description: 'Budgets with what has been spent this week or month, what is left, the per-day allowance and which are over. With category only that budget.',
    parameters: _obj({
      'category': {'type': 'string', 'description': 'Only the budget for this category; "all" for the all-spending budget.'},
    }),
  ),
  TelegramTool(
    name: 'finance_set_budget',
    label: 'Setting a budget',
    category: ToolCategory.finance,
    cost: ToolCost.device,
    description: 'Sets a weekly or monthly spending limit for a category, or for all spending when category is left out. remove true deletes it.',
    parameters: _obj({
      'category': {'type': 'string', 'description': 'A category key or name; leave out for all spending.'},
      'limit': {'type': 'number', 'description': 'The limit per period.'},
      'period': {'type': 'string', 'enum': ['month', 'week'], 'description': 'Default month.'},
      'remove': {'type': 'boolean', 'description': 'Remove this budget instead.'},
    }),
  ),
  TelegramTool(
    name: 'finance_categories',
    label: 'Listing categories',
    category: ToolCategory.finance,
    cost: ToolCost.local,
    description: 'Spending and income categories (key, name, essential or not), the counterparty rules learned so far, and how many transactions are uncategorized.',
    parameters: _obj({}),
  ),
  TelegramTool(
    name: 'finance_categorize',
    label: 'Categorizing',
    category: ToolCategory.finance,
    cost: ToolCost.device,
    description:
        'Files every transaction with a counterparty under a category and remembers it for future ones. A category name that '
        'doesn\'t exist is created when create is true. category "none" forgets the rule.',
    parameters: _obj({
      'counterparty': {'type': 'string', 'description': 'The counterparty exactly as transactions show it.'},
      'category': {'type': 'string', 'description': 'A category key or name.'},
      'create': {'type': 'boolean', 'description': 'Create the category when it doesn\'t exist; default false.'},
      'income': {'type': 'boolean', 'description': 'A new category is for income; default false.'},
      'essential': {'type': 'boolean', 'description': 'A new category is a need rather than a want; default false.'},
    }, ['counterparty', 'category']),
  ),
  TelegramTool(
    name: 'finance_update_patterns',
    label: 'Updating bank SMS patterns',
    category: ToolCategory.finance,
    cost: ToolCost.web,
    description:
        'Downloads the newest bank list and SMS patterns that Totals publishes, so new bank message wording is understood. '
        'finance_sync_sms already checks once a day; use this when messages weren\'t understood or the user asks. Only the pattern '
        'files are fetched; nothing about the user is sent. A broken or incomplete download is ignored and the current patterns stay. '
        'reset true goes back to the copy the app shipped with.',
    parameters: _obj({
      'reset': {'type': 'boolean', 'description': 'Use the patterns the app shipped with instead of a download; default false.'},
    }),
  ),
  TelegramTool(
    name: 'finance_verify_payment',
    label: 'Verifying a payment',
    category: ToolCategory.finance,
    cost: ToolCost.web,
    description:
        'Checks whether a payment is real. With a Verify.ET key (Money → Tools) it asks Verify.ET first: CBE, Telebirr, '
        'Bank of Abyssinia, Dashen, Awash, M-Pesa, CBE Birr, Siinqee, Kaafi and Coopay eBirr, with the payer, receiver, '
        'amount and date, whether it was paid into the user’s account, and whether the receipt was already used before. '
        'Without a key, or when Verify.ET fails, it reads the bank’s own receipt page from the phone. It also checks the '
        'user’s bank texts. Takes a reference, a receipt link or a full SMS in reference, or a picture of a receipt’s QR code. '
        'Give expected_amount and expected_from to compare. Use for "did they really pay me", "is this receipt real".',
    parameters: _obj({
      'reference': {'type': 'string', 'description': 'The transaction reference or receipt ID (e.g. FT25123ABCDE, CHQ0FJ403O), a receipt link, or the payment SMS text.'},
      'bank': {
        'type': 'string',
        'enum': ['auto', 'cbe', 'telebirr', 'boa', 'dashen', 'awash', 'mpesa', 'cbebirr', 'siinqee', 'kaafiebirr', 'coopayebirr', 'zemen'],
        'description': 'Default auto (from the reference or the user’s texts).',
      },
      'account': {'type': 'string', 'description': 'Older CBE FT references need the account’s last 8 digits, Bank of Abyssinia its last 5 (the payer’s or the user’s account).'},
      'phone': {'type': 'string', 'description': 'CBE Birr: the phone number the payment came from.'},
      'to_account': {'type': 'string', 'description': 'The account or phone the money should have gone to, to confirm the receiver. Default: the user’s only account at that bank.'},
      'receipt_url': {'type': 'string', 'description': 'A receipt link (from an SMS or a QR code).'},
      'image': {'type': 'string', 'description': 'A picture of the receipt with its QR code, by name or path from list_attachments.'},
      'expected_amount': {'type': 'number', 'description': 'The amount that was claimed, to compare.'},
      'expected_from': {'type': 'string', 'description': 'Who supposedly paid, to compare with the payer.'},
      'direct': {'type': 'boolean', 'description': 'Skip Verify.ET and check only the bank’s own receipt page from the phone.'},
    }),
  ),
  TelegramTool(
    name: 'finance_banks',
    label: 'Listing banks',
    category: ToolCategory.finance,
    cost: ToolCost.local,
    description: 'The banks and wallets whose SMS can be read, with their sender ids, plus Cash and Other for manual accounts.',
    parameters: _obj({}),
  ),
];

final financeToolNames = {for (final t in _financeTools) t.name};

const _financePolicies = <String, ToolPolicy>{
  'finance_sync_sms': ToolPolicy(ToolAccess.modify),
  'finance_parse_sms': ToolPolicy(ToolAccess.read),
  'finance_overview': ToolPolicy(ToolAccess.read),
  'finance_accounts': ToolPolicy(ToolAccess.read),
  'finance_add_account': ToolPolicy(ToolAccess.modify),
  'finance_update_account': ToolPolicy(ToolAccess.modify),
  'finance_delete_account': ToolPolicy(ToolAccess.modify),
  'finance_transactions': ToolPolicy(ToolAccess.read),
  'finance_add_transaction': ToolPolicy(ToolAccess.modify),
  'finance_update_transaction': ToolPolicy(ToolAccess.modify),
  'finance_delete_transaction': ToolPolicy(ToolAccess.modify),
  'finance_summary': ToolPolicy(ToolAccess.read),
  'finance_insights': ToolPolicy(ToolAccess.read),
  'finance_budgets': ToolPolicy(ToolAccess.read),
  'finance_set_budget': ToolPolicy(ToolAccess.modify),
  'finance_categories': ToolPolicy(ToolAccess.read),
  'finance_categorize': ToolPolicy(ToolAccess.modify),
  'finance_update_patterns': ToolPolicy(ToolAccess.modify),
  'finance_banks': ToolPolicy(ToolAccess.read),
  'finance_verify_payment': ToolPolicy(ToolAccess.read),
};

const _financeReferences = <String, ToolReference>{
  'finance_sync_sms': ToolReference(['scanned', 'bank_messages', 'added', 'duplicates', 'skipped', 'not_understood', 'unparsed_samples', 'new_accounts', 'by_bank', 'latest', 'total_balance', 'currency', 'patterns']),
  'finance_parse_sms': ToolReference(['parsed', 'bank', 'type', 'amount', 'fee', 'balance_after', 'account', 'counterparty', 'reference', 'link', 'pattern', 'saved', 'transaction']),
  'finance_overview': ToolReference(['currency', 'total_balance', 'accounts', 'summary', 'budgets', 'recent', 'last_sync', 'uncategorized']),
  'finance_accounts': ToolReference(['currency', 'total_balance', 'count', 'accounts']),
  'finance_add_account': ToolReference(['created', 'account', 'moved_transactions']),
  'finance_update_account': ToolReference(['updated', 'account']),
  'finance_delete_account': ToolReference(['deleted', 'account', 'transactions_deleted', 'transactions_kept']),
  'finance_transactions': ToolReference(['currency', 'total_matching', 'income', 'expense', 'transactions', 'filters'], limits: ['limit: 1-200.']),
  'finance_add_transaction': ToolReference(['created', 'transaction', 'account']),
  'finance_update_transaction': ToolReference(['updated', 'transaction', 'rule_saved', 'also_categorized']),
  'finance_delete_transaction': ToolReference(['deleted', 'transaction']),
  'finance_summary': ToolReference(['currency', 'view', 'period', 'income', 'expense', 'fees', 'net', 'savings_rate', 'transactions', 'avg_daily_spend', 'series', 'categories', 'income_sources', 'top_payees', 'top_payers', 'accounts', 'previous', 'biggest_expense', 'balance_trend']),
  'finance_insights': ToolReference(['currency', 'view', 'health_score', 'grade', 'score_parts', 'savings_rate', 'monthly', 'recurring', 'unusual_expenses', 'unusual_income', 'projection', 'budget_503020', 'tips']),
  'finance_budgets': ToolReference(['currency', 'budgets']),
  'finance_set_budget': ToolReference(['saved', 'removed', 'budget', 'budgets']),
  'finance_categories': ToolReference(['categories', 'rules', 'uncategorized']),
  'finance_categorize': ToolReference(['categorized', 'category', 'counterparty', 'created_category', 'forgotten']),
  'finance_update_patterns': ToolReference(['updated', 'changed', 'error', 'patterns', 'note']),
  'finance_banks': ToolReference(['banks', 'patterns']),
  'finance_verify_payment': ToolReference(['status', 'source', 'reference', 'bank', 'receipt_url', 'format', 'file_path', 'details', 'in_your_texts', 'receiver_match', 'history', 'checks', 'qr', 'tried', 'verify_et', 'request_id', 'note'], limits: ['Bank receipt sites may only answer from Ethiopian networks.']),
};
