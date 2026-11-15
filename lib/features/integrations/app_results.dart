import 'dart:convert';

/// Composio tools answer in each app's own shape. These turn a result into
/// a few kinds the chat has cards for (emails, Slack messages and channels,
/// Notion pages, events, files, issues, tasks, a document, a table) and
/// that the model reads more cheaply than the raw API response.
///
/// Every record is a plain JSON map so it survives the conversation being
/// saved and reopened.
abstract final class AppResults {
  static const _maxItems = 25;
  static const _maxBody = 6000;
  static const _maxDoc = 20000;

  /// The model's view of [data] from [slug] in [toolkit]: the records found
  /// and, when it is small, the raw data too.
  static Map<String, dynamic> summarize(String toolkit, String slug, dynamic data) {
    final parsed = _deepParse(data);
    final out = <String, dynamic>{'app': toolkit, 'tool': slug};
    final found = extract(slug, parsed);
    out.addAll(found);
    String raw;
    try {
      raw = jsonEncode(parsed);
    } catch (_) {
      raw = '$parsed';
    }
    if (found.isEmpty || raw.length < 4000) {
      if (raw.length <= 14000) {
        out['data'] = parsed;
      } else {
        out['data_preview'] = '${raw.substring(0, 14000)}…';
        out['truncated'] = true;
      }
    }
    for (final k in const ['nextPageToken', 'next_page_token', 'next_cursor', 'nextCursor', 'response_metadata']) {
      final v = _find(parsed, k);
      if (v is String && v.isNotEmpty) out['next_page'] = v;
      if (v is Map && v['next_cursor'] is String && (v['next_cursor'] as String).isNotEmpty) out['next_page'] = v['next_cursor'];
    }
    return out;
  }

  /// The records in [value], keyed by kind; empty when none were found.
  static Map<String, dynamic> extract(String slug, dynamic value) {
    final s = slug.toUpperCase();
    if (s.contains('PLAINTEXT') || s.endsWith('_MARKDOWN') && s.contains('GET') || s == 'GOOGLEDRIVE_PARSE_FILE') {
      final text = _longestText(value);
      if (text.length > 40) {
        return {
          'document': {
            'title': _str(_find(value, 'title')) ?? _str(_find(value, 'name')) ?? '',
            'text': text.length > _maxDoc ? '${text.substring(0, _maxDoc)}…' : text,
            if (text.length > _maxDoc) 'truncated_from_chars': text.length,
            'url': ?_str(_find(value, 'url')),
          },
        };
      }
    }
    final emails = <Map<String, dynamic>>[];
    final events = <Map<String, dynamic>>[];
    final messages = <Map<String, dynamic>>[];
    final channels = <Map<String, dynamic>>[];
    final pages = <Map<String, dynamic>>[];
    final issues = <Map<String, dynamic>>[];
    final notifications = <Map<String, dynamic>>[];
    final tasks = <Map<String, dynamic>>[];
    final files = <Map<String, dynamic>>[];
    final seen = <String>{};
    // Records past the cap, by kind, so the model is told the list goes on.
    final skipped = <List<Map<String, dynamic>>, int>{};

    bool add(List<Map<String, dynamic>> list, Map<String, dynamic>? item, String key) {
      if (item == null) return false;
      if (!seen.add(key)) return true;
      if (list.length >= _maxItems) {
        skipped[list] = (skipped[list] ?? 0) + 1;
        return true;
      }
      list.add(item);
      return true;
    }

    void walk(dynamic node, int depth) {
      if (depth > 10 || node == null) return;
      if (node is List) {
        for (final x in node.take(200)) {
          walk(x, depth + 1);
        }
        return;
      }
      if (node is! Map) return;
      final m = Map<String, dynamic>.from(node);
      final email = _email(m);
      if (add(emails, email, 'e:${email?['id'] ?? email?['subject']}')) return;
      final event = _event(m);
      if (add(events, event, 'v:${event?['id'] ?? event?['title']}${event?['start']}')) return;
      final message = _slackMessage(m);
      if (add(messages, message, 's:${message?['ts'] ?? message?['text']}')) return;
      final channel = _slackChannel(m);
      if (add(channels, channel, 'c:${channel?['id']}')) return;
      final note = _notification(m);
      if (add(notifications, note, 'n:${note?['id'] ?? note?['title']}')) return;
      final issue = _issue(m);
      if (add(issues, issue, 'i:${issue?['id'] ?? issue?['url'] ?? issue?['title']}')) return;
      final page = _notionPage(m);
      if (add(pages, page, 'p:${page?['id']}')) return;
      final task = _task(m);
      if (add(tasks, task, 't:${task?['id'] ?? task?['content']}')) return;
      final file = _file(m);
      if (add(files, file, 'f:${file?['id'] ?? file?['name']}')) return;
      for (final v in m.values) {
        walk(v, depth + 1);
      }
    }

    walk(value, 0);
    final out = <String, dynamic>{
      if (emails.isNotEmpty) 'emails': emails,
      if (events.isNotEmpty) 'events': events,
      if (messages.isNotEmpty) 'messages': messages,
      if (channels.isNotEmpty) 'channels': channels,
      if (notifications.isNotEmpty) 'notifications': notifications,
      if (issues.isNotEmpty) 'issues': issues,
      if (pages.isNotEmpty) 'pages': pages,
      if (tasks.isNotEmpty) 'tasks': tasks,
      if (files.isNotEmpty) 'files': files,
    };
    final names = {
      emails: 'emails',
      events: 'events',
      messages: 'messages',
      channels: 'channels',
      notifications: 'notifications',
      issues: 'issues',
      pages: 'pages',
      tasks: 'tasks',
      files: 'files',
    };
    if (skipped.isNotEmpty) {
      out['not_shown'] = {for (final e in skipped.entries) names[e.key]!: e.value};
      out['not_shown_note'] =
          'Only the first $_maxItems of each kind are listed here; the user can see the full response in the tool '
          'details. Ask for fewer results or the next page to read the rest.';
    }
    if (out.isEmpty) {
      final rows = _find(value, 'values');
      if (rows is List && rows.isNotEmpty && rows.every((r) => r is List)) {
        out['table'] = {
          'range': ?_str(_find(value, 'range')),
          'rows': [
            for (final r in rows.take(200)) [for (final c in (r as List).take(30)) '${c ?? ''}'],
          ],
        };
      }
    }
    return out;
  }

  // ---- kinds -----------------------------------------------------------------

  static Map<String, dynamic>? _email(Map<String, dynamic> m) {
    final preview = m['preview'] is Map ? Map<String, dynamic>.from(m['preview']) : const <String, dynamic>{};
    final subject = _str(m['subject']) ?? _str(m['Subject']) ?? _header(m, 'subject') ?? _str(preview['subject']);
    final from = _party(m['sender']) ?? _party(m['from']) ?? _party(m['From']) ?? _header(m, 'from');
    final id = _str(m['messageId']) ?? _str(m['message_id']) ?? (from != null ? _str(m['id']) : null);
    if (subject == null || (id == null && from == null)) return null;
    // Calendar events and Notion pages carry a subject/from-like field too.
    if (m['start'] is Map || m['object'] == 'page') return null;
    final labels = [for (final l in (m['labelIds'] as List? ?? m['label_ids'] as List? ?? const [])) '$l'];
    final body =
        _mailBody(m['messageText']) ??
        _mailBody(m['message_text']) ??
        (m['body'] is Map ? _mailBody((m['body'] as Map)['content']) : _mailBody(m['body'])) ??
        _mailBody(preview['body']) ??
        _mimeBody(m['payload']) ??
        '';
    final snippet = _str(m['snippet']) ?? _str(m['bodyPreview']) ?? _str(preview['body']) ?? body;
    final date =
        _when(m['messageTimestamp']) ??
        _when(m['internalDate']) ??
        _when(m['receivedDateTime']) ??
        _when(m['sentDateTime']) ??
        _when(m['date']) ??
        _header(m, 'date');
    // The message as its sender styled it, kept apart for the reader
    // (the runner moves it into a file so the model never sees it).
    final outlookBody = m['body'] is Map ? Map<String, dynamic>.from(m['body']) : const <String, dynamic>{};
    final html =
        _htmlOf(m['messageText']) ??
        _htmlOf(m['message_text']) ??
        (('${outlookBody['contentType'] ?? ''}').toLowerCase() == 'html' ? _str(outlookBody['content']) : null) ??
        _htmlOf(m['body']) ??
        _mimeHtml(m['payload']);
    final attachments = [
      for (final a in (m['attachmentList'] as List? ?? m['attachments'] as List? ?? const []))
        if (a is Map && (_str(a['filename']) ?? _str(a['name'])) != null) _str(a['filename']) ?? _str(a['name']),
    ];
    return {
      'id': ?id,
      'thread_id': ?(_str(m['threadId']) ?? _str(m['thread_id']) ?? _str(m['conversationId'])),
      'subject': subject,
      'from': from ?? '',
      'to': _parties(m['to']) ?? _parties(m['toRecipients']) ?? _header(m, 'to') ?? '',
      'date': ?date,
      'snippet': _oneLine(snippet, 200),
      'body': body.length > _maxBody ? '${body.substring(0, _maxBody)}…' : body,
      if (labels.isNotEmpty) 'labels': labels,
      if (labels.contains('UNREAD') || m['isRead'] == false) 'unread': true,
      if (labels.contains('STARRED') || (m['flag'] is Map && (m['flag'] as Map)['flagStatus'] == 'flagged')) 'starred': true,
      if (attachments.isNotEmpty) 'attachments': attachments,
      'link': ?_str(m['webLink']),
      '_html': ?html,
    };
  }

  static String? _htmlOf(dynamic v) {
    final s = _str(v);
    return s != null && RegExp(r'<(html|body|div|table|p|br|a|img|span)\b', caseSensitive: false).hasMatch(s) ? s : null;
  }

  /// The text/html part of a Gmail payload, decoded.
  static String? _mimeHtml(dynamic payload) {
    if (payload is! Map) return null;
    final mime = '${payload['mimeType'] ?? ''}'.toLowerCase();
    final data = payload['body'] is Map ? _str((payload['body'] as Map)['data']) : null;
    if (data != null && mime == 'text/html') {
      try {
        return utf8.decode(base64Url.decode(base64Url.normalize(data)), allowMalformed: true);
      } catch (_) {}
    }
    for (final p in (payload['parts'] as List? ?? const [])) {
      final h = _mimeHtml(p);
      if (h != null) return h;
    }
    return null;
  }

  static Map<String, dynamic>? _event(Map<String, dynamic> m) {
    final title = _str(m['summary']) ?? _str(m['subject']);
    final start = _eventTime(m['start']) ?? _str(m['start_time']);
    if (title == null || start == null || m['start'] is! Map && m['start_time'] == null) return null;
    final loc = m['location'];
    final attendees = m['attendees'] as List? ?? const [];
    final meet = _str(m['hangoutLink']) ?? (m['onlineMeeting'] is Map ? _str((m['onlineMeeting'] as Map)['joinUrl']) : null);
    return {
      'id': ?_str(m['id']),
      'title': title,
      'start': start,
      'end': ?(_eventTime(m['end']) ?? _str(m['end_time'])),
      if (m['start'] is Map && (m['start'] as Map)['date'] != null || m['isAllDay'] == true) 'all_day': true,
      'location': ?(loc is Map ? _str(loc['displayName']) : _str(loc)),
      'link': ?(_str(m['htmlLink']) ?? _str(m['webLink'])),
      'meet': ?meet,
      if (attendees.isNotEmpty) 'attendees': attendees.length,
      'organizer': ?_party(m['organizer']),
      'status': ?_str(m['status']),
      'description': ?(_mailBody(m['description']) ?? (m['bodyPreview'] is String ? _str(m['bodyPreview']) : null)),
    };
  }

  static String? _eventTime(dynamic v) {
    if (v is String) return v;
    if (v is! Map) return null;
    return _str(v['dateTime']) ?? _str(v['date']);
  }

  static Map<String, dynamic>? _slackMessage(Map<String, dynamic> m) {
    final text = _str(m['text']);
    final ts = _str(m['ts']) ?? _str(m['message_ts']);
    if (text == null || ts == null || m['subject'] != null) return null;
    final channel = m['channel'];
    final profile = m['user_profile'] is Map ? Map<String, dynamic>.from(m['user_profile']) : const <String, dynamic>{};
    return {
      'ts': ts,
      'text': text.length > 4000 ? '${text.substring(0, 4000)}…' : text,
      'author':
          _str(m['username']) ?? _str(profile['real_name']) ?? _str(profile['display_name']) ?? _str(m['user_name']) ?? _str(m['user']) ?? _str(m['bot_id']) ?? '',
      'channel': ?(channel is Map ? (_str(channel['name']) ?? _str(channel['id'])) : _str(channel) ?? _str(m['channel_name'])),
      // The channel's id, when known, so the chat can open the channel.
      'channel_id': ?_slackId(channel is Map ? _str(channel['id']) : _str(channel) ?? _str(m['channel_id'])),
      'when': ?_when(ts),
      'permalink': ?_str(m['permalink']),
      if ((m['reply_count'] as num? ?? 0) > 0) 'replies': m['reply_count'],
      'thread_ts': ?_str(m['thread_ts']),
      if (m['reactions'] is List)
        'reactions': [
          for (final r in m['reactions'] as List)
            if (r is Map) '${r['name']} ${r['count'] ?? ''}'.trim(),
        ],
    };
  }

  /// [s] when it is a Slack conversation id (C…, G… or D…), else null.
  static String? _slackId(String? s) => s != null && RegExp(r'^[CGD][A-Z0-9]{6,}$').hasMatch(s) ? s : null;

  static Map<String, dynamic>? _slackChannel(Map<String, dynamic> m) {
    final id = _str(m['id']);
    final name = _str(m['name']) ?? _str(m['name_normalized']);
    if (id == null || name == null || m['text'] != null) return null;
    final looks = m['is_channel'] == true || m['is_group'] == true || m['is_im'] == true || m['is_private'] != null && m['num_members'] != null;
    if (!looks) return null;
    String? sub(String k) => m[k] is Map ? _str((m[k] as Map)['value']) : null;
    return {
      'id': id,
      'name': name,
      if (m['is_private'] == true) 'private': true,
      'members': ?m['num_members'],
      'topic': ?(sub('topic') ?? sub('purpose')),
      if (m['is_member'] == true) 'joined': true,
    };
  }

  static Map<String, dynamic>? _notification(Map<String, dynamic> m) {
    final subject = m['subject'];
    final repo = m['repository'];
    if (subject is! Map || repo is! Map || m['reason'] == null) return null;
    return {
      'id': ?_str(m['id']),
      'title': _str(subject['title']) ?? '',
      'type': _str(subject['type']) ?? '',
      'repo': _str(repo['full_name']) ?? '',
      'reason': _str(m['reason']) ?? '',
      if (m['unread'] == true) 'unread': true,
      'updated': ?_str(m['updated_at']),
      'url': ?_githubWebUrl(_str(subject['url'])),
    };
  }

  static String? _githubWebUrl(String? api) {
    if (api == null) return null;
    return api.replaceFirst('https://api.github.com/repos/', 'https://github.com/').replaceFirst('/pulls/', '/pull/');
  }

  static Map<String, dynamic>? _issue(Map<String, dynamic> m) {
    final title = _str(m['title']);
    if (title == null) return null;
    final number = m['number'];
    final identifier = _str(m['identifier']);
    final url = _str(m['html_url']) ?? _str(m['url']);
    if (number == null && identifier == null) return null;
    if (url == null && m['state'] == null) return null;
    final state = m['state'];
    final repoUrl = _str(m['repository_url']);
    return {
      'id': ?(_str(m['id']) ?? identifier),
      'title': title,
      'number': ?(identifier ?? (number == null ? null : '#$number')),
      'state': ?(state is Map ? _str(state['name']) : _str(state)),
      if (m['pull_request'] != null || (url ?? '').contains('/pull/')) 'pull': true,
      if (m['merged'] == true || m['merged_at'] != null) 'merged': true,
      'url': ?url,
      'repo': ?(repoUrl?.replaceFirst('https://api.github.com/repos/', '') ?? (m['team'] is Map ? _str((m['team'] as Map)['name']) : null)),
      'author': ?(m['user'] is Map ? _str((m['user'] as Map)['login']) : (m['creator'] is Map ? _str((m['creator'] as Map)['name']) : null)),
      'assignee': ?(m['assignee'] is Map ? (_str((m['assignee'] as Map)['login']) ?? _str((m['assignee'] as Map)['name'])) : null),
      if (m['labels'] is List)
        'labels': [
          for (final l in m['labels'] as List)
            if (l is Map && l['name'] != null) '${l['name']}' else if (l is String) l,
        ],
      'priority': ?_str(m['priorityLabel']),
      'updated': ?(_str(m['updated_at']) ?? _str(m['updatedAt'])),
      'comments': ?m['comments'],
      'body': ?_clip(_str(m['body']) ?? _str(m['description']), 3000),
    };
  }

  static Map<String, dynamic>? _notionPage(Map<String, dynamic> m) {
    final object = m['object'];
    final url = _str(m['url']);
    final isNotion = object == 'page' || object == 'database' || object == 'data_source' || (url ?? '').contains('notion.so');
    if (!isNotion) return null;
    final id = _str(m['id']);
    if (id == null) return null;
    String? title = _str(m['title']) ;
    if (m['title'] is List) title = _richText(m['title']);
    final props = m['properties'];
    if (title == null && props is Map) {
      for (final p in props.values) {
        if (p is Map && p['type'] == 'title') {
          title = _richText(p['title']);
          break;
        }
      }
    }
    final icon = m['icon'];
    return {
      'id': id,
      'title': title == null || title.isEmpty ? 'Untitled' : title,
      'kind': object == 'database' || object == 'data_source' ? 'database' : 'page',
      'url': ?url,
      'icon': ?(icon is Map && icon['type'] == 'emoji' ? _str(icon['emoji']) : null),
      'edited': ?_str(m['last_edited_time']),
      if (m['archived'] == true || m['in_trash'] == true) 'archived': true,
    };
  }

  static Map<String, dynamic>? _task(Map<String, dynamic> m) {
    final content = _str(m['content']);
    if (content == null || m['title'] != null) return null;
    if (m['due'] == null && m['priority'] == null && m['project_id'] == null && m['checked'] == null && m['is_completed'] == null) return null;
    final due = m['due'];
    return {
      'id': ?_str(m['id']),
      'content': content,
      'description': ?_str(m['description']),
      'due': ?(due is Map ? (_str(due['string']) ?? _str(due['datetime']) ?? _str(due['date'])) : _str(due)),
      'due_date': ?(due is Map ? _str(due['date']) : null),
      'priority': ?m['priority'],
      if (m['checked'] == true || m['is_completed'] == true) 'done': true,
      'url': ?_str(m['url']),
      if (m['labels'] is List && (m['labels'] as List).isNotEmpty) 'labels': [for (final l in m['labels'] as List) '$l'],
    };
  }

  static Map<String, dynamic>? _file(Map<String, dynamic> m) {
    final name = _str(m['name']) ?? _str(m['title']);
    final mime = _str(m['mimeType']) ?? _str(m['mime_type']);
    if (name == null || mime == null) return null;
    return {
      'id': ?_str(m['id']),
      'name': name,
      'mime': mime,
      'modified': ?(_str(m['modifiedTime']) ?? _str(m['modified_time'])),
      'link': ?(_str(m['webViewLink']) ?? _str(m['alternateLink']) ?? _str(m['url'])),
      'size': ?m['size'],
      'owner': ?(m['owners'] is List && (m['owners'] as List).isNotEmpty ? _party((m['owners'] as List).first) : null),
      if (m['shared'] == true) 'shared': true,
    };
  }

  // ---- helpers ---------------------------------------------------------------

  /// Tool data is often JSON inside a string; open it up.
  /// [data] with JSON held in strings opened up: the complete response as
  /// the tool sheet shows it.
  static dynamic parse(dynamic data) => _deepParse(data);

  static dynamic _deepParse(dynamic v, [int depth = 0]) {
    if (depth > 6) return v;
    if (v is String) {
      final t = v.trim();
      if ((t.startsWith('{') && t.endsWith('}')) || (t.startsWith('[') && t.endsWith(']'))) {
        try {
          return _deepParse(jsonDecode(t), depth + 1);
        } catch (_) {}
      }
      return v;
    }
    if (v is List) return [for (final x in v) _deepParse(x, depth + 1)];
    if (v is Map) return {for (final e in v.entries) '${e.key}': _deepParse(e.value, depth + 1)};
    return v;
  }

  static dynamic _find(dynamic v, String key, [int depth = 0]) {
    if (depth > 6 || v == null) return null;
    if (v is Map) {
      if (v.containsKey(key)) return v[key];
      for (final x in v.values) {
        final r = _find(x, key, depth + 1);
        if (r != null) return r;
      }
    } else if (v is List) {
      for (final x in v.take(20)) {
        final r = _find(x, key, depth + 1);
        if (r != null) return r;
      }
    }
    return null;
  }

  static String _longestText(dynamic v) {
    var best = '';
    void walk(dynamic n, int d) {
      if (d > 8) return;
      if (n is String) {
        if (n.length > best.length) best = n;
      } else if (n is Map) {
        for (final x in n.values) {
          walk(x, d + 1);
        }
      } else if (n is List) {
        for (final x in n.take(400)) {
          walk(x, d + 1);
        }
      }
    }

    walk(v, 0);
    return best.trim();
  }

  static String? _str(dynamic v) {
    if (v is! String && v is! num) return null;
    final s = '$v'.trim();
    return s.isEmpty ? null : s;
  }

  static String? _clip(String? s, int max) => s == null || s.length <= max ? s : '${s.substring(0, max)}…';

  static String _oneLine(String s, int max) {
    final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length <= max ? t : '${t.substring(0, max)}…';
  }

  static String? _richText(dynamic v) {
    if (v is! List) return _str(v);
    final s = v.map((x) => x is Map ? (x['plain_text'] ?? (x['text'] is Map ? x['text']['content'] : '') ?? '') : '$x').join().trim();
    return s.isEmpty ? null : s;
  }

  static String? _party(dynamic v) {
    if (v is String) return _str(v);
    if (v is! Map) return null;
    if (v['emailAddress'] is Map) return _party(v['emailAddress']);
    final name = _str(v['name']) ?? _str(v['displayName']);
    final email = _str(v['email']) ?? _str(v['address']) ?? _str(v['emailAddress']);
    if (name != null && email != null && name != email) return '$name <$email>';
    return name ?? email;
  }

  static String? _parties(dynamic v) {
    if (v is List) {
      final s = v.map(_party).whereType<String>().join(', ');
      return s.isEmpty ? null : s;
    }
    return _party(v);
  }

  static String? _when(dynamic v) {
    if (v == null) return null;
    final s = '$v'.trim();
    if (RegExp(r'^\d{12,13}$').hasMatch(s)) {
      return DateTime.fromMillisecondsSinceEpoch(int.parse(s)).toIso8601String();
    }
    if (RegExp(r'^\d{10}(\.\d+)?$').hasMatch(s)) {
      return DateTime.fromMillisecondsSinceEpoch((double.parse(s) * 1000).round()).toIso8601String();
    }
    return s.isEmpty ? null : s;
  }

  static String? _header(Map<String, dynamic> m, String name) {
    final payload = m['payload'];
    if (payload is! Map || payload['headers'] is! List) return null;
    for (final h in payload['headers'] as List) {
      if (h is Map && '${h['name']}'.toLowerCase() == name) return _str(h['value']);
    }
    return null;
  }

  static String? _mailBody(dynamic v) {
    final s = _str(v);
    if (s == null) return null;
    return RegExp(r'<[a-zA-Z][\s\S]*>').hasMatch(s) ? htmlToText(s) : s;
  }

  static String? _mimeBody(dynamic payload) {
    if (payload is! Map) return null;
    final mime = '${payload['mimeType'] ?? ''}'.toLowerCase();
    final data = payload['body'] is Map ? _str((payload['body'] as Map)['data']) : null;
    if (data != null && (mime.startsWith('text/') || mime.isEmpty)) {
      try {
        final decoded = utf8.decode(base64Url.decode(base64Url.normalize(data)), allowMalformed: true);
        return mime == 'text/html' ? htmlToText(decoded) : decoded.trim();
      } catch (_) {}
    }
    String? html;
    for (final p in (payload['parts'] as List? ?? const [])) {
      final t = _mimeBody(p);
      if (t == null) continue;
      if ('${(p as Map)['mimeType']}'.toLowerCase() != 'text/html') return t;
      html ??= t;
    }
    return html;
  }

  /// Readable text from an email's HTML.
  static String htmlToText(String html) {
    var s = html
        .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</(p|div|tr|li|h\d)>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '');
    s = s
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll(RegExp(r'&#0*39;|&apos;'), "'")
        .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
          final c = int.tryParse(m[1]!);
          return c == null || c <= 0 || c > 0x10FFFF ? m[0]! : String.fromCharCode(c);
        });
    return s.replaceAll(RegExp(r'[ \t]+\n'), '\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }
}
