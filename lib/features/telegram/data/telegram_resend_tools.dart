part of 'telegram_tools.dart';

// Resend, with the user's API key (Settings → Development → Resend):
// sending email (attachments from the conversation, scheduling, batches),
// what was sent and whether it was delivered, domains and their DNS,
// audiences and contacts, broadcasts, API keys and webhooks, and any other
// REST path. Sending asks first; deleting is a destructive tool.

const _rsAudience = {'type': 'string', 'description': 'Audience id, as resend_audiences lists it.'};
const _rsDomain = {'type': 'string', 'description': 'Domain id or name, e.g. example.com.'};
const _rsAddresses = {
  'type': 'array',
  'items': {'type': 'string', 'description': 'An email address, or "Name <address>".'},
  'description': 'Email addresses.',
};

TelegramTool _rs(String name, String label, String description, Map<String, dynamic> params, {List<String> required = const [], bool change = false, bool destructive = false, bool alwaysAsk = false}) =>
    TelegramTool(
      name: name,
      label: label,
      category: ToolCategory.resend,
      cost: ToolCost.cloud,
      requiresApproval: change || destructive || alwaysAsk,
      destructive: destructive,
      alwaysAsk: alwaysAsk,
      description: description,
      parameters: _obj(params, required),
    );

final _resendTools = <TelegramTool>[
  // ---- read ----------------------------------------------------------------------
  _rs('resend_emails', 'Listing sent emails',
      'Emails sent through Resend, newest first: to, subject, when, and the last event (delivered, opened, clicked, bounced, '
          'complained, scheduled). Shown as a list the user can open.', {
        'limit': {'type': 'integer', 'description': '1-100, default 20.'},
        'after': {'type': 'string', 'description': 'An email id to list the ones after it (next page).'},
      }),
  _rs('resend_email', 'Opening a sent email', 'One sent email in full: addresses, subject, text and HTML, status and timings.', {
    'id': {'type': 'string', 'description': 'Email id from resend_emails or a send.'},
  }, required: ['id']),
  _rs('resend_domains', 'Listing sending domains', 'Domains on the Resend account with their status (verified, pending, failed) and region.', {}),
  _rs('resend_domain', 'Checking a domain\'s DNS',
      'One domain with every DNS record it needs (SPF, DKIM, MX for return path, DMARC) and whether each is verified. Shown with copy buttons.',
      {'domain': _rsDomain}, required: ['domain']),
  _rs('resend_api_keys', 'Listing Resend API keys', 'The account\'s API keys: name, when made and when last used. Keys themselves are never shown.', {}),
  _rs('resend_audiences', 'Listing audiences', 'Audiences (contact lists) on the account.', {}),
  _rs('resend_contacts', 'Listing contacts',
      'Contacts in an audience with their names and whether they unsubscribed; with contact, just that one.', {
        'audience': _rsAudience,
        'contact': {'type': 'string', 'description': 'One contact\'s id or email.'},
      }, required: ['audience']),
  _rs('resend_broadcasts', 'Listing broadcasts', 'Broadcasts (newsletters): status (draft, queued, sent), audience and when; with id, one in full.', {
    'id': {'type': 'string', 'description': 'One broadcast\'s id.'},
  }),
  _rs('resend_webhooks', 'Listing Resend webhooks', 'Webhooks that receive email events, with their endpoint and events.', {}),
  _rs('resend_api_get', 'Asking the Resend API', 'GET any Resend REST path the other tools don\'t cover (resend.com/docs/api-reference). Read-only.', {
    'path': {'type': 'string', 'description': 'Starts with /, e.g. /templates.'},
    'query': {'type': 'object', 'description': 'Query parameters as string values.', 'additionalProperties': {'type': 'string', 'description': 'A query value.'}},
  }, required: ['path']),

  // ---- changes -------------------------------------------------------------------
  _rs('resend_send_email', 'Sending an email',
      'Sends one email through Resend from a verified domain: plain text and/or HTML, cc, bcc, reply-to, files of this conversation as '
          'attachments, tags, custom headers, or scheduled for later. from defaults to the address in Settings. Only when the user asked; '
          'they approve first. Shown as a card that follows delivery.', {
        'to': _rsAddresses,
        'subject': {'type': 'string', 'description': 'Subject line.'},
        'text': {'type': 'string', 'description': 'Plain-text body.'},
        'html': {'type': 'string', 'description': 'HTML body.'},
        'from': {'type': 'string', 'description': 'Sender, e.g. "Me <me@example.com>". Default: Settings → Development → Resend.'},
        'cc': _rsAddresses,
        'bcc': _rsAddresses,
        'reply_to': _rsAddresses,
        'attachments': {'type': 'array', 'items': {'type': 'string', 'description': 'A file of this conversation.'}, 'description': 'Files of this conversation to attach (40 MB in all).'},
        'scheduled_at': {'type': 'string', 'description': 'Send later: ISO 8601 time or natural text like "in 1 hour".'},
        'tags': {
          'type': 'array',
          'description': 'Tags for filtering events.',
          'items': {
            'type': 'object',
            'description': 'One tag.',
            'properties': {
              'name': {'type': 'string', 'description': 'Tag name (letters, digits, _ and -).'},
              'value': {'type': 'string', 'description': 'Tag value.'},
            },
            'required': ['name', 'value'],
          },
        },
        'headers': {'type': 'object', 'description': 'Extra email headers.', 'additionalProperties': {'type': 'string', 'description': 'A header value.'}},
      }, required: ['to', 'subject'], change: true),
  _rs('resend_send_batch', 'Sending a batch of emails',
      'Sends up to 100 different emails in one call (each its own to, subject and body). Always asks first.', {
        'emails': {
          'type': 'array',
          'description': 'The emails.',
          'items': {
            'type': 'object',
            'description': 'One email.',
            'properties': {
              'to': _rsAddresses,
              'subject': {'type': 'string', 'description': 'Subject line.'},
              'text': {'type': 'string', 'description': 'Plain-text body.'},
              'html': {'type': 'string', 'description': 'HTML body.'},
              'from': {'type': 'string', 'description': 'Sender. Default: Settings.'},
              'reply_to': _rsAddresses,
            },
            'required': ['to', 'subject'],
          },
        },
      }, required: ['emails'], alwaysAsk: true),
  _rs('resend_reschedule_email', 'Rescheduling an email', 'Moves a scheduled email to another time. They approve first.', {
    'id': {'type': 'string', 'description': 'The scheduled email\'s id.'},
    'scheduled_at': {'type': 'string', 'description': 'New time: ISO 8601 or natural text like "tomorrow at 9am".'},
  }, required: ['id', 'scheduled_at'], change: true),
  _rs('resend_cancel_email', 'Cancelling a scheduled email', 'Cancels an email that is scheduled and not yet sent.', {
    'id': {'type': 'string', 'description': 'The scheduled email\'s id.'},
  }, required: ['id'], change: true),
  _rs('resend_add_domain', 'Adding a sending domain', 'Adds a domain to send from. Returns the DNS records to create. They approve first.', {
    'name': {'type': 'string', 'description': 'Domain or subdomain, e.g. mail.example.com.'},
    'region': {'type': 'string', 'enum': ['us-east-1', 'eu-west-1', 'sa-east-1', 'ap-northeast-1'], 'description': 'Where mail is sent from. Default us-east-1.'},
  }, required: ['name'], change: true),
  _rs('resend_verify_domain', 'Verifying a domain', 'Asks Resend to check a domain\'s DNS records again.', {'domain': _rsDomain}, required: ['domain'], change: true),
  _rs('resend_update_domain', 'Changing domain tracking', 'Turns open and click tracking on or off, or sets TLS to opportunistic or enforced.', {
    'domain': _rsDomain,
    'open_tracking': {'type': 'boolean', 'description': 'Track opens.'},
    'click_tracking': {'type': 'boolean', 'description': 'Track link clicks.'},
    'tls': {'type': 'string', 'enum': ['opportunistic', 'enforced'], 'description': 'TLS policy.'},
  }, required: ['domain'], change: true),
  _rs('resend_create_api_key', 'Creating a Resend API key',
      'Creates an API key (full access, or sending only, optionally for one domain). The key is shown once. They approve first.', {
        'name': {'type': 'string', 'description': 'A name for the key.'},
        'permission': {'type': 'string', 'enum': ['full_access', 'sending_access'], 'description': 'Default full_access.'},
        'domain': {'type': 'string', 'description': 'For sending_access, only this domain (id or name).'},
      }, required: ['name'], change: true),
  _rs('resend_create_audience', 'Creating an audience', 'Creates an audience (contact list).', {
    'name': {'type': 'string', 'description': 'Audience name.'},
  }, required: ['name'], change: true),
  _rs('resend_add_contact', 'Adding a contact', 'Adds a contact to an audience.', {
    'audience': _rsAudience,
    'email': {'type': 'string', 'description': 'Their email address.'},
    'first_name': {'type': 'string', 'description': 'First name.'},
    'last_name': {'type': 'string', 'description': 'Last name.'},
    'unsubscribed': {'type': 'boolean', 'description': 'Add as unsubscribed.'},
  }, required: ['audience', 'email'], change: true),
  _rs('resend_update_contact', 'Changing a contact', 'Changes a contact\'s name or subscription.', {
    'audience': _rsAudience,
    'contact': {'type': 'string', 'description': 'The contact\'s id or email.'},
    'first_name': {'type': 'string', 'description': 'New first name.'},
    'last_name': {'type': 'string', 'description': 'New last name.'},
    'unsubscribed': {'type': 'boolean', 'description': 'true unsubscribes them from broadcasts.'},
  }, required: ['audience', 'contact'], change: true),
  _rs('resend_create_broadcast', 'Drafting a broadcast', 'Creates a broadcast draft for an audience. Nothing is sent until resend_send_broadcast.', {
    'audience': _rsAudience,
    'subject': {'type': 'string', 'description': 'Subject line.'},
    'html': {'type': 'string', 'description': 'HTML body. {{{FIRST_NAME|there}}} and {{{RESEND_UNSUBSCRIBE_URL}}} are filled per contact.'},
    'text': {'type': 'string', 'description': 'Plain-text body.'},
    'from': {'type': 'string', 'description': 'Sender. Default: Settings.'},
    'reply_to': _rsAddresses,
    'name': {'type': 'string', 'description': 'Internal name for the broadcast.'},
  }, required: ['audience', 'subject'], change: true),
  _rs('resend_update_broadcast', 'Changing a broadcast', 'Changes a draft broadcast. Give only what changes.', {
    'id': {'type': 'string', 'description': 'Broadcast id.'},
    'subject': {'type': 'string', 'description': 'New subject.'},
    'html': {'type': 'string', 'description': 'New HTML body.'},
    'text': {'type': 'string', 'description': 'New text body.'},
    'from': {'type': 'string', 'description': 'New sender.'},
    'name': {'type': 'string', 'description': 'New internal name.'},
  }, required: ['id'], change: true),
  _rs('resend_send_broadcast', 'Sending a broadcast', 'Sends a broadcast to its whole audience, now or at scheduled_at. Mass email: always asks first.', {
    'id': {'type': 'string', 'description': 'Broadcast id.'},
    'scheduled_at': {'type': 'string', 'description': 'Send later: ISO 8601 or natural text.'},
  }, required: ['id'], alwaysAsk: true),
  _rs('resend_create_webhook', 'Adding a Resend webhook', 'Creates a webhook that posts email events (email.delivered, email.bounced…) to a URL.', {
    'endpoint': {'type': 'string', 'description': 'https:// address that receives the events.'},
    'events': {'type': 'array', 'items': {'type': 'string', 'description': 'An event, e.g. email.bounced.'}, 'description': 'Events to send.'},
  }, required: ['endpoint', 'events'], change: true),

  // ---- destructive ---------------------------------------------------------------
  _rs('resend_delete_domain', 'Removing a sending domain', 'Removes a domain; mail from it stops sending.', {'domain': _rsDomain}, required: ['domain'], destructive: true),
  _rs('resend_delete_api_key', 'Revoking a Resend API key', 'Revokes an API key; whatever uses it stops working.', {
    'id': {'type': 'string', 'description': 'API key id from resend_api_keys.'},
  }, required: ['id'], destructive: true),
  _rs('resend_delete_audience', 'Deleting an audience', 'Deletes an audience and its contacts.', {'audience': _rsAudience}, required: ['audience'], destructive: true),
  _rs('resend_delete_contact', 'Deleting a contact', 'Removes a contact from an audience.', {
    'audience': _rsAudience,
    'contact': {'type': 'string', 'description': 'The contact\'s id or email.'},
  }, required: ['audience', 'contact'], destructive: true),
  _rs('resend_delete_broadcast', 'Deleting a broadcast', 'Deletes a draft or scheduled broadcast.', {
    'id': {'type': 'string', 'description': 'Broadcast id.'},
  }, required: ['id'], destructive: true),
  _rs('resend_delete_webhook', 'Deleting a Resend webhook', 'Deletes a webhook.', {
    'id': {'type': 'string', 'description': 'Webhook id.'},
  }, required: ['id'], destructive: true),
  _rs('resend_api_request', 'Changing something on Resend',
      'POST, PUT, PATCH or DELETE on any Resend REST path with a JSON body written as text, for what the other tools don\'t cover. Always asks first.', {
        'method': {'type': 'string', 'enum': ['POST', 'PUT', 'PATCH', 'DELETE'], 'description': 'HTTP method.'},
        'path': {'type': 'string', 'description': 'Starts with /, e.g. /templates.'},
        'body_json': {'type': 'string', 'description': 'Request body as a JSON object.'},
      }, required: ['method', 'path'], destructive: true),
];

final _resendToolNames = {for (final t in _resendTools) t.name};

const _resendPolicies = <String, ToolPolicy>{
  'resend_emails': ToolPolicy(ToolAccess.read),
  'resend_email': ToolPolicy(ToolAccess.read),
  'resend_domains': ToolPolicy(ToolAccess.read),
  'resend_domain': ToolPolicy(ToolAccess.read),
  'resend_api_keys': ToolPolicy(ToolAccess.read),
  'resend_audiences': ToolPolicy(ToolAccess.read),
  'resend_contacts': ToolPolicy(ToolAccess.read),
  'resend_broadcasts': ToolPolicy(ToolAccess.read),
  'resend_webhooks': ToolPolicy(ToolAccess.read),
  'resend_api_get': ToolPolicy(ToolAccess.read),
  'resend_send_email': ToolPolicy(ToolAccess.modify),
  'resend_send_batch': ToolPolicy(ToolAccess.modify),
  'resend_reschedule_email': ToolPolicy(ToolAccess.modify),
  'resend_cancel_email': ToolPolicy(ToolAccess.modify),
  'resend_add_domain': ToolPolicy(ToolAccess.modify),
  'resend_verify_domain': ToolPolicy(ToolAccess.modify),
  'resend_update_domain': ToolPolicy(ToolAccess.modify),
  'resend_create_api_key': ToolPolicy(ToolAccess.modify),
  'resend_create_audience': ToolPolicy(ToolAccess.modify),
  'resend_add_contact': ToolPolicy(ToolAccess.modify),
  'resend_update_contact': ToolPolicy(ToolAccess.modify),
  'resend_create_broadcast': ToolPolicy(ToolAccess.modify),
  'resend_update_broadcast': ToolPolicy(ToolAccess.modify),
  'resend_send_broadcast': ToolPolicy(ToolAccess.modify),
  'resend_create_webhook': ToolPolicy(ToolAccess.modify),
  'resend_delete_domain': ToolPolicy(ToolAccess.destructive),
  'resend_delete_api_key': ToolPolicy(ToolAccess.destructive),
  'resend_delete_audience': ToolPolicy(ToolAccess.destructive),
  'resend_delete_contact': ToolPolicy(ToolAccess.destructive),
  'resend_delete_broadcast': ToolPolicy(ToolAccess.destructive),
  'resend_delete_webhook': ToolPolicy(ToolAccess.destructive),
  'resend_api_request': ToolPolicy(ToolAccess.destructive),
};

const _rsEmailFields = ['id', 'to', 'from', 'subject', 'created', 'last_event', 'scheduled_at'];

const _resendReferences = <String, ToolReference>{
  'resend_emails': ToolReference(['dev', 'emails', ..._rsEmailFields, 'more']),
  'resend_email': ToolReference(['dev', 'email', ..._rsEmailFields, 'text', 'html', 'cc', 'bcc', 'reply_to']),
  'resend_domains': ToolReference(['dev', 'domains: id, name, status, region, created']),
  'resend_domain': ToolReference(['dev', 'domain', 'records: record, type, name, value, priority, status, ttl']),
  'resend_api_keys': ToolReference(['dev', 'api_keys: id, name, created, last_used']),
  'resend_audiences': ToolReference(['dev', 'audiences: id, name, created']),
  'resend_contacts': ToolReference(['dev', 'audience', 'contacts: id, email, first_name, last_name, unsubscribed, created']),
  'resend_broadcasts': ToolReference(['dev', 'broadcasts', 'broadcast']),
  'resend_webhooks': ToolReference(['dev', 'webhooks: id, endpoint, events, status']),
  'resend_api_get': ToolReference(['dev', 'path', 'result'], limits: ['Long answers are cut at about 14,000 characters.']),
  'resend_send_email': ToolReference(['dev', 'done', 'id', 'email'], limits: ['From must be on a verified domain (or onboarding@resend.dev to yourself). 40 MB of attachments.']),
  'resend_send_batch': ToolReference(['dev', 'done', 'ids', 'count'], limits: ['Up to 100 emails; no attachments or scheduling in a batch.']),
  'resend_reschedule_email': ToolReference(['dev', 'done', 'id', 'scheduled_at']),
  'resend_cancel_email': ToolReference(['dev', 'done', 'id']),
  'resend_add_domain': ToolReference(['dev', 'done', 'domain', 'records']),
  'resend_verify_domain': ToolReference(['dev', 'done', 'domain']),
  'resend_update_domain': ToolReference(['dev', 'done', 'domain']),
  'resend_create_api_key': ToolReference(['dev', 'done', 'id', 'token (shown once)']),
  'resend_create_audience': ToolReference(['dev', 'done', 'audience']),
  'resend_add_contact': ToolReference(['dev', 'done', 'contact']),
  'resend_update_contact': ToolReference(['dev', 'done', 'contact']),
  'resend_create_broadcast': ToolReference(['dev', 'done', 'broadcast']),
  'resend_update_broadcast': ToolReference(['dev', 'done', 'broadcast']),
  'resend_send_broadcast': ToolReference(['dev', 'done', 'broadcast']),
  'resend_create_webhook': ToolReference(['dev', 'done', 'webhook', 'signing_secret (shown once)']),
  'resend_delete_domain': ToolReference(['dev', 'deleted']),
  'resend_delete_api_key': ToolReference(['dev', 'deleted']),
  'resend_delete_audience': ToolReference(['dev', 'deleted']),
  'resend_delete_contact': ToolReference(['dev', 'deleted']),
  'resend_delete_broadcast': ToolReference(['dev', 'deleted']),
  'resend_delete_webhook': ToolReference(['dev', 'deleted']),
  'resend_api_request': ToolReference(['dev', 'done', 'result']),
};

Map<String, dynamic> resendEmailSummary(Map e) => {
  'id': e['id'],
  'to': e['to'],
  'from': e['from'],
  'subject': e['subject'],
  'created': e['created_at'],
  'last_event': e['last_event'],
  'scheduled_at': ?e['scheduled_at'],
  'cc': ?(e['cc'] is List && (e['cc'] as List).isNotEmpty ? e['cc'] : null),
  'bcc': ?(e['bcc'] is List && (e['bcc'] as List).isNotEmpty ? e['bcc'] : null),
  'reply_to': ?(e['reply_to'] is List && (e['reply_to'] as List).isNotEmpty ? e['reply_to'] : null),
};

extension _ResendToolRuns on TelegramToolRunner {
  Future<ToolOutput>? _runResend(String name, Map<String, dynamic> a) {
    if (!_resendToolNames.contains(name)) return null;
    return _resend(name, a);
  }

  String _ra(Map<String, dynamic> a, String k) => '${a[k] ?? ''}'.trim();

  List<String> _rsList(Object? v) => v is List ? [for (final x in v) if ('$x'.trim().isNotEmpty) '$x'.trim()] : (v is String && v.trim().isNotEmpty ? [v.trim()] : const []);

  /// A domain's id from its id or name.
  Future<String> _rsDomainId(ResendApi api, String ref) async {
    if (ref.isEmpty) throw const DevApiException('resend', 'Which domain?');
    if (!ref.contains('.')) return ref;
    final r = await api.call('GET', '/domains') as Map;
    for (final d in (r['data'] as List? ?? const []).whereType<Map>()) {
      if ('${d['name']}'.toLowerCase() == ref.toLowerCase()) return '${d['id']}';
    }
    throw DevApiException('resend', 'No domain "$ref" on this Resend account.');
  }

  String _rsFrom(Map<String, dynamic> a) {
    final from = _ra(a, 'from').isNotEmpty ? _ra(a, 'from') : _settings.resendFrom;
    if (from.isEmpty) throw const DevApiException('resend', 'No sender: give from, or set a From address in Settings → Development → Resend.');
    return from;
  }

  Future<ToolOutput> _resend(String name, Map<String, dynamic> a) async {
    if (!_settings.hasResendKey) {
      return const ToolOutput({'error': 'No Resend key. The user can add one in Settings → Development → Resend.'});
    }
    final api = ResendApi(key: _settings.resendKey);
    Map<String, dynamic> out(Map<String, dynamic> m) => {'dev': 'resend', ...m};
    List<Map> data(Object? r) => r is Map ? (r['data'] as List? ?? const []).whereType<Map>().toList() : const [];
    try {
      switch (name) {
        case 'resend_emails':
          final r = await api.call('GET', '/emails', query: {
            'limit': '${TelegramToolRunner._int(a, 'limit', fallback: 20, max: 100)}',
            if (_ra(a, 'after').isNotEmpty) 'after': _ra(a, 'after'),
          });
          final list = data(r);
          return ToolOutput(out({'emails': [for (final e in list) resendEmailSummary(e)], if (r is Map && r['has_more'] == true) 'more': true}));
        case 'resend_email':
          final e = await api.call('GET', '/emails/${_ra(a, 'id')}') as Map;
          return ToolOutput(out({
            'email': {
              ...resendEmailSummary(e),
              'text': ?(e['text'] == null ? null : TelegramToolRunner._clip('${e['text']}', 8000)),
              'html': ?(e['html'] == null ? null : TelegramToolRunner._clip('${e['html']}', 30000)),
            },
          }));
        case 'resend_domains':
          final r = await api.call('GET', '/domains');
          return ToolOutput(out({
            'domains': [for (final d in data(r)) {'id': d['id'], 'name': d['name'], 'status': d['status'], 'region': d['region'], 'created': d['created_at']}],
          }));
        case 'resend_domain':
          final id = await _rsDomainId(api, _ra(a, 'domain'));
          final d = await api.call('GET', '/domains/$id') as Map;
          return ToolOutput(out(_rsDomainOut(d)));
        case 'resend_api_keys':
          final r = await api.call('GET', '/api-keys');
          return ToolOutput(out({
            'api_keys': [for (final k in data(r)) {'id': k['id'], 'name': k['name'], 'created': k['created_at'], 'last_used': ?k['last_used_at']}],
          }));
        case 'resend_audiences':
          final r = await api.call('GET', '/audiences');
          return ToolOutput(out({'audiences': [for (final x in data(r)) {'id': x['id'], 'name': x['name'], 'created': x['created_at']}]}));
        case 'resend_contacts':
          final aud = _ra(a, 'audience');
          if (_ra(a, 'contact').isNotEmpty) {
            final c = await api.call('GET', '/audiences/$aud/contacts/${Uri.encodeComponent(_ra(a, 'contact'))}') as Map;
            return ToolOutput(out({'audience': aud, 'contacts': [_rsContact(c)]}));
          }
          final r = await api.call('GET', '/audiences/$aud/contacts');
          return ToolOutput(out({'audience': aud, 'contacts': [for (final c in data(r)) _rsContact(c)]}));
        case 'resend_broadcasts':
          if (_ra(a, 'id').isNotEmpty) {
            final b = await api.call('GET', '/broadcasts/${_ra(a, 'id')}') as Map;
            return ToolOutput(out({'broadcast': _rsBroadcast(b, full: true)}));
          }
          final r = await api.call('GET', '/broadcasts');
          return ToolOutput(out({'broadcasts': [for (final b in data(r)) _rsBroadcast(b)]}));
        case 'resend_webhooks':
          final r = await api.call('GET', '/webhooks');
          return ToolOutput(out({
            'webhooks': [for (final w in data(r)) {'id': w['id'], 'endpoint': w['endpoint'], 'events': w['events'], 'status': w['status'], 'created': w['created_at']}],
          }));
        case 'resend_api_get':
          final q = a['query'] is Map ? {for (final e in (a['query'] as Map).entries) '${e.key}': '${e.value}'} : null;
          final r = await api.call('GET', _ra(a, 'path'), query: q);
          final text = jsonEncode(r);
          return ToolOutput(out({'path': _ra(a, 'path'), 'result': text.length > 14000 ? '${text.substring(0, 14000)}…' : r}), full: r);

        // ---- changes ---------------------------------------------------------------
        case 'resend_send_email':
          final to = _rsList(a['to']);
          if (to.isEmpty) return ToolOutput(out({'error': 'Give at least one address in to.'}));
          if (_ra(a, 'text').isEmpty && _ra(a, 'html').isEmpty) return ToolOutput(out({'error': 'Give text or html.'}));
          final attachments = <Map<String, dynamic>>[];
          var size = 0;
          for (final f in _rsList(a['attachments'])) {
            final file = File(f);
            if (!file.existsSync()) return ToolOutput(out({'error': 'No file "$f" in this conversation.'}));
            final bytes = await file.readAsBytes();
            size += bytes.length;
            attachments.add({
              'filename': file.path.split(RegExp(r'[\\/]')).last.replaceFirst(RegExp(r'^[0-9a-f]{8}_'), ''),
              'content': base64Encode(bytes),
              'content_type': ?lookupMimeType(file.path),
            });
          }
          if (size > 40 << 20) return ToolOutput(out({'error': 'Attachments are over 40 MB.'}));
          final body = {
            'from': _rsFrom(a),
            'to': to,
            'subject': _ra(a, 'subject'),
            if (_ra(a, 'text').isNotEmpty) 'text': '${a['text']}',
            if (_ra(a, 'html').isNotEmpty) 'html': '${a['html']}',
            if (_rsList(a['cc']).isNotEmpty) 'cc': _rsList(a['cc']),
            if (_rsList(a['bcc']).isNotEmpty) 'bcc': _rsList(a['bcc']),
            if (_rsList(a['reply_to']).isNotEmpty) 'reply_to': _rsList(a['reply_to']),
            if (attachments.isNotEmpty) 'attachments': attachments,
            if (_ra(a, 'scheduled_at').isNotEmpty) 'scheduled_at': _ra(a, 'scheduled_at'),
            if (a['tags'] is List) 'tags': [for (final t in (a['tags'] as List).whereType<Map>()) {'name': '${t['name']}', 'value': '${t['value']}'}],
            if (a['headers'] is Map) 'headers': {for (final e in (a['headers'] as Map).entries) '${e.key}': '${e.value}'},
          };
          final r = await api.call('POST', '/emails', body: body) as Map;
          return ToolOutput(out({
            'done': true,
            'id': r['id'],
            'email': {
              'id': r['id'],
              'to': to,
              'from': body['from'],
              'subject': body['subject'],
              'last_event': _ra(a, 'scheduled_at').isNotEmpty ? 'scheduled' : 'sent',
              'scheduled_at': ?(_ra(a, 'scheduled_at').isEmpty ? null : _ra(a, 'scheduled_at')),
              'attachments': ?(attachments.isEmpty ? null : [for (final x in attachments) x['filename']]),
              'text': ?(_ra(a, 'text').isEmpty ? null : TelegramToolRunner._clip('${a['text']}', 4000)),
            },
          }));
        case 'resend_send_batch':
          final emails = [
            for (final e in (a['emails'] as List? ?? const []).whereType<Map>())
              {
                'from': '${e['from'] ?? ''}'.trim().isEmpty ? _rsFrom(const {}) : '${e['from']}'.trim(),
                'to': _rsList(e['to']),
                'subject': '${e['subject'] ?? ''}',
                if ('${e['text'] ?? ''}'.isNotEmpty) 'text': '${e['text']}',
                if ('${e['html'] ?? ''}'.isNotEmpty) 'html': '${e['html']}',
                if (_rsList(e['reply_to']).isNotEmpty) 'reply_to': _rsList(e['reply_to']),
              },
          ];
          if (emails.isEmpty || emails.length > 100) return ToolOutput(out({'error': 'Give 1 to 100 emails.'}));
          final r = await api.call('POST', '/emails/batch', body: emails);
          final ids = [for (final x in data(r)) x['id']];
          return ToolOutput(out({'done': true, 'ids': ids, 'count': ids.length}));
        case 'resend_reschedule_email':
          await api.call('PATCH', '/emails/${_ra(a, 'id')}', body: {'scheduled_at': _ra(a, 'scheduled_at')});
          return ToolOutput(out({'done': true, 'id': _ra(a, 'id'), 'scheduled_at': _ra(a, 'scheduled_at')}));
        case 'resend_cancel_email':
          await api.call('POST', '/emails/${_ra(a, 'id')}/cancel');
          return ToolOutput(out({'done': true, 'id': _ra(a, 'id'), 'last_event': 'canceled'}));
        case 'resend_add_domain':
          final d = await api.call('POST', '/domains', body: {'name': _ra(a, 'name'), if (_ra(a, 'region').isNotEmpty) 'region': _ra(a, 'region')}) as Map;
          return ToolOutput(out({'done': true, ..._rsDomainOut(d)}));
        case 'resend_verify_domain':
          final id = await _rsDomainId(api, _ra(a, 'domain'));
          await api.call('POST', '/domains/$id/verify');
          final d = await api.call('GET', '/domains/$id') as Map;
          return ToolOutput(out({'done': true, ..._rsDomainOut(d)}));
        case 'resend_update_domain':
          final id = await _rsDomainId(api, _ra(a, 'domain'));
          await api.call('PATCH', '/domains/$id', body: {
            if (a['open_tracking'] is bool) 'open_tracking': a['open_tracking'],
            if (a['click_tracking'] is bool) 'click_tracking': a['click_tracking'],
            if (_ra(a, 'tls').isNotEmpty) 'tls': _ra(a, 'tls'),
          });
          return ToolOutput(out({'done': true, 'domain': _ra(a, 'domain')}));
        case 'resend_create_api_key':
          final domain = _ra(a, 'domain');
          final r = await api.call('POST', '/api-keys', body: {
            'name': _ra(a, 'name'),
            if (_ra(a, 'permission').isNotEmpty) 'permission': _ra(a, 'permission'),
            if (domain.isNotEmpty) 'domain_id': await _rsDomainId(api, domain),
          }) as Map;
          return ToolOutput(out({'done': true, 'id': r['id'], 'token': r['token'], 'note': 'Shown once: copy it now.'}));
        case 'resend_create_audience':
          final r = await api.call('POST', '/audiences', body: {'name': _ra(a, 'name')}) as Map;
          return ToolOutput(out({'done': true, 'audience': {'id': r['id'], 'name': r['name']}}));
        case 'resend_add_contact':
          final r = await api.call('POST', '/audiences/${_ra(a, 'audience')}/contacts', body: {
            'email': _ra(a, 'email'),
            if (_ra(a, 'first_name').isNotEmpty) 'first_name': _ra(a, 'first_name'),
            if (_ra(a, 'last_name').isNotEmpty) 'last_name': _ra(a, 'last_name'),
            if (a['unsubscribed'] is bool) 'unsubscribed': a['unsubscribed'],
          }) as Map;
          return ToolOutput(out({'done': true, 'contact': {'id': r['id'], 'email': _ra(a, 'email')}}));
        case 'resend_update_contact':
          await api.call('PATCH', '/audiences/${_ra(a, 'audience')}/contacts/${Uri.encodeComponent(_ra(a, 'contact'))}', body: {
            if (_ra(a, 'first_name').isNotEmpty) 'first_name': _ra(a, 'first_name'),
            if (_ra(a, 'last_name').isNotEmpty) 'last_name': _ra(a, 'last_name'),
            if (a['unsubscribed'] is bool) 'unsubscribed': a['unsubscribed'],
          });
          return ToolOutput(out({'done': true, 'contact': {'id_or_email': _ra(a, 'contact'), 'unsubscribed': ?a['unsubscribed']}}));
        case 'resend_create_broadcast':
          final r = await api.call('POST', '/broadcasts', body: {
            'audience_id': _ra(a, 'audience'),
            'from': _rsFrom(a),
            'subject': _ra(a, 'subject'),
            if (_ra(a, 'html').isNotEmpty) 'html': '${a['html']}',
            if (_ra(a, 'text').isNotEmpty) 'text': '${a['text']}',
            if (_rsList(a['reply_to']).isNotEmpty) 'reply_to': _rsList(a['reply_to']),
            if (_ra(a, 'name').isNotEmpty) 'name': _ra(a, 'name'),
          }) as Map;
          return ToolOutput(out({'done': true, 'broadcast': {'id': r['id'], 'subject': _ra(a, 'subject'), 'status': 'draft'}}));
        case 'resend_update_broadcast':
          await api.call('PATCH', '/broadcasts/${_ra(a, 'id')}', body: {
            for (final k in const ['subject', 'html', 'text', 'from', 'name'])
              if (a[k] != null) k: '${a[k]}',
          });
          return ToolOutput(out({'done': true, 'broadcast': {'id': _ra(a, 'id')}}));
        case 'resend_send_broadcast':
          await api.call('POST', '/broadcasts/${_ra(a, 'id')}/send', body: {if (_ra(a, 'scheduled_at').isNotEmpty) 'scheduled_at': _ra(a, 'scheduled_at')});
          return ToolOutput(out({'done': true, 'broadcast': {'id': _ra(a, 'id'), 'status': _ra(a, 'scheduled_at').isEmpty ? 'queued' : 'scheduled'}}));
        case 'resend_create_webhook':
          final r = await api.call('POST', '/webhooks', body: {'endpoint': _ra(a, 'endpoint'), 'events': _rsList(a['events'])}) as Map;
          return ToolOutput(out({'done': true, 'webhook': {'id': r['id'], 'endpoint': _ra(a, 'endpoint')}, 'signing_secret': ?r['signing_secret']}));

        // ---- destructive -----------------------------------------------------------
        case 'resend_delete_domain':
          final id = await _rsDomainId(api, _ra(a, 'domain'));
          await api.call('DELETE', '/domains/$id');
          return ToolOutput(out({'deleted': _ra(a, 'domain')}));
        case 'resend_delete_api_key':
          await api.call('DELETE', '/api-keys/${_ra(a, 'id')}');
          return ToolOutput(out({'deleted': _ra(a, 'id')}));
        case 'resend_delete_audience':
          await api.call('DELETE', '/audiences/${_ra(a, 'audience')}');
          return ToolOutput(out({'deleted': _ra(a, 'audience')}));
        case 'resend_delete_contact':
          await api.call('DELETE', '/audiences/${_ra(a, 'audience')}/contacts/${Uri.encodeComponent(_ra(a, 'contact'))}');
          return ToolOutput(out({'deleted': _ra(a, 'contact')}));
        case 'resend_delete_broadcast':
          await api.call('DELETE', '/broadcasts/${_ra(a, 'id')}');
          return ToolOutput(out({'deleted': _ra(a, 'id')}));
        case 'resend_delete_webhook':
          await api.call('DELETE', '/webhooks/${_ra(a, 'id')}');
          return ToolOutput(out({'deleted': _ra(a, 'id')}));
        case 'resend_api_request':
          final raw = _ra(a, 'body_json');
          final body = raw.isEmpty ? null : _tryJson(raw);
          if (raw.isNotEmpty && body == null) return ToolOutput(out({'error': 'body_json is not valid JSON.'}));
          final r = await api.call(_ra(a, 'method').toUpperCase(), _ra(a, 'path'), body: body);
          final text = jsonEncode(r);
          return ToolOutput(out({'done': true, 'result': text.length > 10000 ? '${text.substring(0, 10000)}…' : r}), full: r);
      }
    } on DevApiException catch (e) {
      return ToolOutput({'dev': 'resend', 'error': 'Resend: ${e.message}'});
    } on TimeoutException {
      return const ToolOutput({'dev': 'resend', 'error': 'Resend didn\'t answer in time.'});
    } on SocketException catch (e) {
      return ToolOutput({'dev': 'resend', 'error': 'Couldn\'t reach Resend: ${e.message}'});
    } finally {
      api.close();
    }
    return ToolOutput({'error': 'Unknown tool $name'});
  }

  Map<String, dynamic> _rsDomainOut(Map d) => {
    'domain': {
      'id': d['id'],
      'name': d['name'],
      'status': d['status'],
      'region': d['region'],
      'created': d['created_at'],
      'open_tracking': ?d['open_tracking'],
      'click_tracking': ?d['click_tracking'],
      'tls': ?d['tls'],
    },
    'records': [
      for (final r in (d['records'] as List? ?? const []).whereType<Map>())
        {'record': r['record'], 'type': r['type'], 'name': r['name'], 'value': r['value'], 'priority': ?r['priority'], 'ttl': r['ttl'], 'status': r['status']},
    ],
  };

  Map<String, dynamic> _rsContact(Map c) => {
    'id': c['id'],
    'email': c['email'],
    'first_name': ?c['first_name'],
    'last_name': ?c['last_name'],
    'unsubscribed': c['unsubscribed'],
    'created': c['created_at'],
  };

  Map<String, dynamic> _rsBroadcast(Map b, {bool full = false}) => {
    'id': b['id'],
    'name': b['name'],
    'subject': ?b['subject'],
    'status': b['status'],
    'audience': b['audience_id'],
    'from': ?b['from'],
    'created': b['created_at'],
    'scheduled_at': ?b['scheduled_at'],
    'sent_at': ?b['sent_at'],
    if (full && b['text'] != null) 'text': TelegramToolRunner._clip('${b['text']}', 6000),
    if (full && b['html'] != null) 'html': TelegramToolRunner._clip('${b['html']}', 20000),
  };

  /// What a Resend change would do, for the approval card.
  String? _describeResend(String name, Map<String, dynamic> a) {
    if (!_resendToolNames.contains(name)) return null;
    String v(String k) => '${a[k] ?? ''}'.trim();
    final from = v('from').isEmpty ? _settings.resendFrom : v('from');
    return switch (name) {
      'resend_send_email' =>
        'Email ${_rsList(a['to']).join(', ')}${_rsList(a['cc']).isEmpty ? '' : '\ncc ${_rsList(a['cc']).join(', ')}'}${_rsList(a['bcc']).isEmpty ? '' : '\nbcc ${_rsList(a['bcc']).join(', ')}'}\nfrom $from\n“${v('subject')}”${v('scheduled_at').isEmpty ? '' : '\nat ${v('scheduled_at')}'}${_rsList(a['attachments']).isEmpty ? '' : '\n📎 ${_rsList(a['attachments']).map((f) => f.split(RegExp(r'[\\/]')).last).join(', ')}'}\n\n${TelegramToolRunner._clip(v('text').isNotEmpty ? v('text') : v('html').replaceAll(RegExp(r'<[^>]+>'), ' '), 500)}',
      'resend_send_batch' => 'Send ${(a['emails'] as List? ?? const []).length} emails:\n${[for (final e in (a['emails'] as List? ?? const []).whereType<Map>().take(12)) '${_rsList(e['to']).join(', ')} · “${e['subject']}”'].join('\n')}',
      'resend_reschedule_email' => 'Move email ${v('id')} to ${v('scheduled_at')}',
      'resend_cancel_email' => 'Cancel the scheduled email ${v('id')}',
      'resend_add_domain' => 'Add ${v('name')} as a Resend sending domain${v('region').isEmpty ? '' : ' (${v('region')})'}',
      'resend_verify_domain' => 'Verify ${v('domain')} on Resend',
      'resend_update_domain' => 'Change ${v('domain')}: ${[for (final k in const ['open_tracking', 'click_tracking', 'tls']) if (a[k] != null) '$k ${a[k]}'].join(', ')}',
      'resend_create_api_key' => 'Create a Resend API key “${v('name')}” (${v('permission').isEmpty ? 'full_access' : v('permission')})',
      'resend_create_audience' => 'Create the audience “${v('name')}”',
      'resend_add_contact' => 'Add ${v('email')} to audience ${v('audience')}',
      'resend_update_contact' => 'Change contact ${v('contact')}${a['unsubscribed'] == true ? ' (unsubscribe)' : ''}',
      'resend_create_broadcast' => 'Draft a broadcast to audience ${v('audience')}\n“${v('subject')}”',
      'resend_update_broadcast' => 'Change broadcast ${v('id')}',
      'resend_send_broadcast' => 'Send broadcast ${v('id')} to its whole audience${v('scheduled_at').isEmpty ? ' now' : ' at ${v('scheduled_at')}'}',
      'resend_create_webhook' => 'Send ${_rsList(a['events']).join(', ')} to ${v('endpoint')}',
      'resend_delete_domain' => 'Remove ${v('domain')} from Resend',
      'resend_delete_api_key' => 'Revoke Resend API key ${v('id')}',
      'resend_delete_audience' => 'Delete audience ${v('audience')} and its contacts',
      'resend_delete_contact' => 'Delete ${v('contact')} from audience ${v('audience')}',
      'resend_delete_broadcast' => 'Delete broadcast ${v('id')}',
      'resend_delete_webhook' => 'Delete webhook ${v('id')}',
      'resend_api_request' => '${v('method')} ${v('path')}${v('body_json').isEmpty ? '' : '\n${TelegramToolRunner._clip(v('body_json'), 600)}'}',
      _ => null,
    };
  }
}
