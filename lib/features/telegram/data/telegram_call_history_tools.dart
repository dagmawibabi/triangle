part of 'telegram_tools.dart';

// The phone's call history, analysed (features/calls/call_history.dart).
// Android only; the chat controller runs these.

final _callHistoryTools = <TelegramTool>[
  TelegramTool(
    name: 'call_history_summary',
    label: 'Analysing your calls',
    category: ToolCategory.callHistory,
    cost: ToolCost.device,
    description:
        'Analyses the whole phone call log for a period as one focused card chosen by view: overview (calls in, out and missed, '
        'talk time, answer rate, a chart by day/week/month and the change from before; the default), missed (missed and '
        'declined calls, and the ones never returned), people (who calls most and who takes the most time), patterns (busiest '
        'hours and weekdays, average and longest call), or all (every section, only for a full report).',
    parameters: _obj({
      'view': {'type': 'string', 'enum': ['overview', 'missed', 'people', 'patterns', 'all'], 'description': 'Which card to show; default overview.'},
      'period': {'type': 'string', 'enum': FinPeriodKeys.all, 'description': 'The span to cover; default last_30_days. Ignored when since or until is given.'},
      'since': {'type': 'string', 'description': 'First day to include, YYYY-MM-DD.'},
      'until': {'type': 'string', 'description': 'Last day to include, YYYY-MM-DD.'},
    }),
  ),
  TelegramTool(
    name: 'call_history_person',
    label: 'Looking at calls with someone',
    category: ToolCategory.callHistory,
    cost: ToolCost.device,
    description:
        'Everything about calls with one person, by name or number: how many each way, talk time, missed, who usually calls, '
        'first and last call, longest call, month by month, the hours they call, recent calls, and whether a missed call from '
        'them was never returned.',
    parameters: _obj({
      'who': {'type': 'string', 'description': 'A contact name or phone number, or part of one.'},
    }, ['who']),
  ),
  TelegramTool(
    name: 'call_history_calls',
    label: 'Listing calls',
    category: ToolCategory.callHistory,
    cost: ToolCost.device,
    description:
        'Calls from the log, filtered by type (incoming, outgoing, missed, rejected, blocked), person, minimum length and dates, '
        'newest or longest first, with the matching count and talk time. The user sees just that list.',
    parameters: _obj({
      'type': {'type': 'string', 'enum': ['all', 'incoming', 'outgoing', 'missed', 'rejected', 'blocked'], 'description': 'Which calls; default all.'},
      'who': {'type': 'string', 'description': 'Only calls with this name or number.'},
      'min_minutes': {'type': 'number', 'description': 'Only calls at least this long.'},
      'period': {'type': 'string', 'enum': FinPeriodKeys.all, 'description': 'The span to cover; default all. Ignored when since or until is given.'},
      'since': {'type': 'string', 'description': 'First day to include, YYYY-MM-DD.'},
      'until': {'type': 'string', 'description': 'Last day to include, YYYY-MM-DD.'},
      'sort': {'type': 'string', 'enum': ['newest', 'longest'], 'description': 'Order; default newest.'},
      'limit': {'type': 'integer', 'description': 'How many to list, 1-200; default 30.'},
    }),
  ),
];

final callHistoryToolNames = {for (final t in _callHistoryTools) t.name};

const _callHistoryPolicies = <String, ToolPolicy>{
  'call_history_summary': ToolPolicy(ToolAccess.read),
  'call_history_person': ToolPolicy(ToolAccess.read),
  'call_history_calls': ToolPolicy(ToolAccess.read),
};

const _callHistoryReferences = <String, ToolReference>{
  'call_history_summary': ToolReference(['view', 'period', 'calls', 'incoming', 'outgoing', 'missed', 'rejected', 'blocked', 'talk_time', 'answer_rate', 'series', 'hours', 'weekdays', 'top_by_calls', 'top_by_time', 'longest', 'unreturned_missed', 'previous']),
  'call_history_person': ToolReference(['who', 'number', 'calls', 'incoming', 'outgoing', 'missed', 'talk_time', 'first', 'last', 'longest', 'you_call_share', 'monthly', 'hours', 'recent', 'unreturned']),
  'call_history_calls': ToolReference(['total_matching', 'talk_time', 'calls', 'filters'], limits: ['limit: 1-200.']),
};
