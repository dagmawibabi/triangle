part of 'telegram_tools.dart';

// The web: reading pages and calling APIs over plain HTTP, and a real
// browser (a WebView that runs the page's scripts) for sites that are apps.

final _webTools = <TelegramTool>[
  TelegramTool(
    name: 'fetch_url',
    label: 'Reading a web page',
    category: ToolCategory.web,
    cost: ToolCost.web,
    description:
        'Reads a web page or file over HTTP without running its scripts: title, readable text, links, forms and the '
        'page\'s script files. Fast; best for blogs, articles, docs, JSON APIs and plain sites (e.g. "what blogs are on '
        'dagmawibabi.com/blog": fetch it, then fetch the posts you need from the links). Use find to get only the '
        'parts mentioning something; raw for the exact source (JavaScript, JSON, HTML) e.g. to look for the API a '
        'script calls. If the text is nearly empty the site is a script app: use browser_open instead.',
    parameters: _obj(
      {
        'url': {
          'type': 'string',
          'description': 'Address; https:// is added when missing.',
        },
        'find': {
          'type': 'string',
          'description': 'Only return text around each place this appears (case-insensitive).',
        },
        'raw': {
          'type': 'boolean',
          'description': 'Return the source as it is instead of readable text.',
        },
        'offset': {
          'type': 'integer',
          'description':
              'Start the text here, to read further into long pages.',
        },
        'max_chars': {
          'type': 'integer',
          'description': 'Default 6000, at most 20000.',
        },
        'links': {
          'type': 'boolean',
          'description': 'Include the page\'s links. Default true.',
        },
      },
      ['url'],
    ),
  ),
  TelegramTool(
    name: 'http_request',
    label: 'Calling a web API',
    category: ToolCategory.web,
    cost: ToolCost.web,
    requiresApproval: true,
    description:
        'Sends any HTTP request (GET, POST, PUT, PATCH, DELETE…) with headers and a JSON, form or raw body, and returns '
        'the status, headers and body. For APIs and webhooks. Cookies from earlier fetch_url calls to the same site '
        'are sent along. The user approves it first. For reading pages use fetch_url instead.',
    parameters: _obj(
      {
        'method': {'type': 'string', 'description': 'Default GET.'},
        'url': {'type': 'string'},
        'headers': {
          'type': 'object',
          'additionalProperties': {'type': 'string'},
        },
        'query': {
          'type': 'object',
          'additionalProperties': {'type': 'string'},
          'description': 'Added to the URL.',
        },
        'json': {
          'description': 'A JSON body (object or array); sets content-type application/json.',
        },
        'form': {
          'type': 'object',
          'additionalProperties': {'type': 'string'},
          'description': 'A form-encoded body.',
        },
        'body': {'type': 'string', 'description': 'A raw body.'},
      },
      ['url'],
    ),
  ),
  TelegramTool(
    name: 'submit_form',
    label: 'Submitting a web form',
    category: ToolCategory.web,
    cost: ToolCost.web,
    requiresApproval: true,
    description:
        'Fills in and submits a form on a plain HTML page (one fetch_url listed under forms): hidden fields and '
        'defaults are kept, the values you give are set, and the result page is returned. The user approves it first. '
        'Forms run by scripts need the browser tools instead.',
    parameters: _obj(
      {
        'url': {'type': 'string', 'description': 'The page the form is on.'},
        'form': {
          'type': 'integer',
          'description': 'Which form (from fetch_url). Default 0.',
        },
        'fields': {
          'type': 'object',
          'additionalProperties': {'type': 'string'},
          'description': 'Field name → value.',
        },
      },
      ['url', 'fields'],
    ),
  ),
  TelegramTool(
    name: 'download_file',
    label: 'Downloading a file',
    category: ToolCategory.web,
    cost: ToolCost.web,
    description:
        'Downloads a file from the web onto the phone. It then counts as a file of this conversation: send it to a '
        'chat by passing its name in files, zip it, or look at it with view_image if it is a picture.',
    parameters: _obj(
      {
        'url': {'type': 'string'},
        'name': {
          'type': 'string',
          'description':
              'File name to save as; taken from the address when missing.',
        },
      },
      ['url'],
    ),
  ),
  TelegramTool(
    name: 'browser_open',
    label: 'Opening in the browser',
    category: ToolCategory.web,
    cost: ToolCost.web,
    description:
        'Opens a page in the assistant\'s real browser, which runs the page\'s JavaScript like Chrome does. Returns the '
        'page\'s text and its usable elements, numbered (links, buttons, text fields, selects). Then use browser_type '
        'to fill fields, browser_click to press buttons, browser_read to read again. Use it for sites that are apps '
        '(JavaScript-heavy web apps, forms, anything fetch_url shows empty), and to follow a link (open its href; '
        'no approval needed). The user can watch it live in the app\'s Browser screen.',
    parameters: _obj(
      {
        'url': {'type': 'string'},
        'max_chars': {'type': 'integer', 'description': 'Default 6000.'},
      },
      ['url'],
    ),
  ),
  TelegramTool(
    name: 'browser_read',
    label: 'Reading the browser page',
    category: ToolCategory.web,
    cost: ToolCost.web,
    description:
        'Reads the page open in the browser again, after it changed: text (from offset), or only what mentions find, '
        'and freshly numbered elements. Numbers from an earlier read may have changed.',
    parameters: _obj({
      'offset': {'type': 'integer'},
      'find': {'type': 'string'},
      'max_chars': {'type': 'integer'},
    }),
  ),
  TelegramTool(
    name: 'browser_type',
    label: 'Typing in the browser',
    category: ToolCategory.web,
    cost: ToolCost.web,
    description:
        'Types text into a field of the open page (element number from the last browser_open/browser_read), or picks '
        'an option of a select by its text. Replaces what is there unless append is true. Nothing is sent until a '
        'button is clicked (browser_click) or the field is submitted (browser_submit).',
    parameters: _obj(
      {
        'element': {'type': 'integer'},
        'text': {'type': 'string'},
        'append': {'type': 'boolean'},
      },
      ['element', 'text'],
    ),
  ),
  TelegramTool(
    name: 'browser_click',
    label: 'Clicking in the browser',
    category: ToolCategory.web,
    cost: ToolCost.web,
    requiresApproval: true,
    description:
        'Clicks an element of the open page (a button, link, checkbox, tab) by its number, waits for the page to react '
        'and returns it. Clicks can send or buy things, so the user approves each one. To just follow a link, '
        'browser_open its href instead.',
    parameters: _obj(
      {
        'element': {'type': 'integer'},
      },
      ['element'],
    ),
  ),
  TelegramTool(
    name: 'browser_submit',
    label: 'Submitting in the browser',
    category: ToolCategory.web,
    cost: ToolCost.web,
    requiresApproval: true,
    description: 'Presses Enter in a field of the open page and submits its form, e.g. a search box. The user approves it first.',
    parameters: _obj(
      {
        'element': {'type': 'integer'},
      },
      ['element'],
    ),
  ),
  TelegramTool(
    name: 'browser_back',
    label: 'Going back',
    category: ToolCategory.web,
    cost: ToolCost.web,
    description: 'Goes back to the previous page in the browser and reads it.',
    parameters: _obj({}),
  ),
  TelegramTool(
    name: 'browser_run_js',
    label: 'Running a script on the page',
    category: ToolCategory.web,
    cost: ToolCost.web,
    requiresApproval: true,
    description:
        'Runs JavaScript in the open page and returns the value of its last expression (as JSON). For reading what the '
        'other tools miss (document.querySelectorAll(...)) or doing what they can\'t. The user approves it first.',
    parameters: _obj(
      {
        'script': {'type': 'string'},
      },
      ['script'],
    ),
  ),
];

extension _WebTools on TelegramToolRunner {
  Future<ToolOutput>? _runWeb(String name, Map<String, dynamic> args) =>
      switch (name) {
        'fetch_url' => _fetchUrl(args),
        'http_request' => _httpRequest(args),
        'submit_form' => _submitForm(args),
        'download_file' => _download(args),
        'browser_open' => _browse(
          () => _browser.open(
            '${WebFetcher.normalize('${args['url'] ?? ''}')}',
            maxChars: TelegramToolRunner._int(
              args,
              'max_chars',
              fallback: 6000,
              max: 20000,
            ),
          ),
        ),
        'browser_read' => _browse(
          () => _browser.read(
            offset: TelegramToolRunner._int(
              args,
              'offset',
              fallback: 0,
              min: 0,
            ),
            maxChars: TelegramToolRunner._int(
              args,
              'max_chars',
              fallback: 6000,
              max: 20000,
            ),
            find: args['find'] as String?,
          ),
        ),
        'browser_type' => _browse(
          () => _browser.type(
            _element(args),
            '${args['text'] ?? ''}',
            clear: args['append'] != true,
          ),
        ),
        'browser_submit' => _browse(
          () =>
              _browser.type(_element(args), '', clear: false, pressEnter: true),
        ),
        'browser_click' => _browse(() => _browser.click(_element(args))),
        'browser_back' => _browse(_browser.back),
        'browser_run_js' => _browse(
          () async => {
            'result': await _browser.evaluate('${args['script'] ?? ''}'),
          },
        ),
        _ => null,
      };

  String? _describeWeb(String name, Map<String, dynamic> args) {
    String el() {
      final i = TelegramToolRunner._intOrNull(args, 'element');
      final text = i == null ? null : _browser.elementLabel(i);
      return '${text == null || text.isEmpty ? 'element $i' : '“$text”'} on ${_browser.host ?? 'the open page'}';
    }

    return switch (name) {
      'http_request' => () {
        final method = '${args['method'] ?? 'GET'}'.toUpperCase();
        final body = args['json'] != null
            ? jsonEncode(args['json'])
            : args['form'] != null
            ? jsonEncode(args['form'])
            : '${args['body'] ?? ''}';
        return '$method ${args['url']}${body.isEmpty ? '' : '\n${body.length > 400 ? '${body.substring(0, 400)}…' : body}'}';
      }(),
      'submit_form' =>
        'Submit form ${args['form'] ?? 0} on ${args['url']} with:\n'
            '${[for (final e in ((args['fields'] as Map?) ?? const {}).entries) '${e.key}: ${e.value}'].join('\n')}',
      'browser_click' => 'Click ${el()}',
      'browser_submit' => 'Press Enter in ${el()}',
      'browser_run_js' =>
        'Run this script on ${_browser.host ?? 'the open page'}:\n${args['script']}',
      _ => null,
    };
  }

  int _element(Map<String, dynamic> args) {
    final i = TelegramToolRunner._intOrNull(args, 'element');
    if (i == null)
      throw ArgumentError(
        'element is required: a number from browser_open or browser_read.',
      );
    return i;
  }

  Future<ToolOutput> _browse(
    Future<Map<String, dynamic>> Function() action,
  ) async {
    try {
      return ToolOutput(await action());
    } on UnsupportedError catch (e) {
      return ToolOutput({'error': '${e.message}'});
    } on StateError catch (e) {
      return ToolOutput({'error': e.message});
    } catch (e) {
      return ToolOutput({'error': 'The browser failed: $e'});
    }
  }

  Future<ToolOutput> _fetchUrl(Map<String, dynamic> args) async {
    final url = WebFetcher.normalize('${args['url'] ?? ''}');
    final maxChars = TelegramToolRunner._int(
      args,
      'max_chars',
      fallback: 6000,
      max: 20000,
    );
    final offset = TelegramToolRunner._int(args, 'offset', fallback: 0, min: 0);
    final find = '${args['find'] ?? ''}'.trim();
    final r = await _web.request('GET', url);
    final out = <String, dynamic>{
      'url': r.request?.url.toString() ?? url.toString(),
      'status': r.statusCode,
      'content_type': r.headers['content-type'],
    };
    final source = WebFetcher.decodeBody(r);
    String text;
    if (args['raw'] != true && WebFetcher.isHtml(r)) {
      final page = ReadablePage.parse(source, r.request?.url ?? url);
      out['title'] = page.title;
      // For the link preview card: share image, site name, author, date.
      out.addAll(pagePreviewMeta(source, r.request?.url ?? url));
      if (page.description case final d? when d.isNotEmpty)
        out['description'] = d;
      text = page.text;
      if (args['links'] != false && find.isEmpty)
        out['links'] = page.links.take(80).toList();
      if (page.forms.isNotEmpty) out['forms'] = page.forms;
      if (page.scripts.isNotEmpty)
        out['scripts'] = page.scripts.take(40).toList();
      if (text.length < 120) {
        out['note'] =
            'Almost no text without scripts: this site is a JavaScript app. Use browser_open to use it, '
            'or fetch its scripts with raw and find (e.g. "fetch(" or "/api") to see the API it calls.';
      }
    } else if (WebFetcher.isJson(r) && args['raw'] != true) {
      try {
        text = const JsonEncoder.withIndent(' ').convert(jsonDecode(source));
      } catch (_) {
        text = source;
      }
    } else {
      text = source;
    }
    out['length'] = text.length;
    if (find.isNotEmpty) {
      out['matches'] = BrowserSession.findSnippets(
        text,
        find,
        max: 20,
        context: 200,
      );
    } else {
      final end = (offset + maxChars).clamp(0, text.length);
      out['text'] = offset >= text.length ? '' : text.substring(offset, end);
      if (end < text.length) out['more_text'] = 'Continues; pass offset=$end.';
    }
    return ToolOutput(out);
  }

  /// Runs only after the person approved it in the chat.
  Future<ToolOutput> _httpRequest(Map<String, dynamic> args) async {
    var url = WebFetcher.normalize('${args['url'] ?? ''}');
    if (args['query'] case final Map q when q.isNotEmpty) {
      url = url.replace(
        queryParameters: {
          ...url.queryParameters,
          for (final e in q.entries) '${e.key}': '${e.value}',
        },
      );
    }
    final method = '${args['method'] ?? 'GET'}'.toUpperCase();
    final headers = {
      for (final e in ((args['headers'] as Map?) ?? const {}).entries)
        '${e.key}'.toLowerCase(): '${e.value}',
    };
    Object? body;
    if (args['json'] != null) {
      body = jsonEncode(args['json']);
      headers.putIfAbsent('content-type', () => 'application/json');
    } else if (args['form'] case final Map f) {
      body = {for (final e in f.entries) '${e.key}': '${e.value}'};
    } else if (args['body'] case final String b when b.isNotEmpty) {
      body = b;
    }
    final r = await _web.request(method, url, headers: headers, body: body);
    final text = WebFetcher.decodeBody(r);
    Object? parsed;
    if (WebFetcher.isJson(r) ||
        text.trimLeft().startsWith('{') ||
        text.trimLeft().startsWith('[')) {
      try {
        parsed = jsonDecode(text);
      } catch (_) {}
    }
    final encoded = parsed == null ? text : jsonEncode(parsed);
    return ToolOutput({
      'done': r.statusCode < 400,
      'status': r.statusCode,
      'url': r.request?.url.toString() ?? url.toString(),
      'headers': {
        for (final k in const [
          'content-type',
          'location',
          'content-length',
          'retry-after',
          'www-authenticate',
        ])
          if (r.headers[k] != null) k: r.headers[k],
      },
      if (parsed != null && encoded.length <= 20000)
        'json': parsed
      else
        'body': TelegramToolRunner._clip(
          WebFetcher.isHtml(r) ? ReadablePage.parse(text, url).text : text,
          12000,
        ),
      if (r.statusCode >= 400)
        'error':
            'HTTP ${r.statusCode}${r.reasonPhrase == null ? '' : ' ${r.reasonPhrase}'}',
    });
  }

  /// Runs only after the person approved it in the chat.
  Future<ToolOutput> _submitForm(Map<String, dynamic> args) async {
    final url = WebFetcher.normalize('${args['url'] ?? ''}');
    final page = await _web.request('GET', url);
    final doc = ReadablePage.parse(
      WebFetcher.decodeBody(page),
      page.request?.url ?? url,
    );
    final index = TelegramToolRunner._int(args, 'form', fallback: 0, min: 0);
    if (index >= doc.forms.length)
      throw ArgumentError('That page has ${doc.forms.length} form(s).');
    final form = doc.forms[index];
    final values = <String, String>{
      for (final f in (form['fields'] as List).cast<Map<String, dynamic>>())
        // Checkboxes and radios count only when given; buttons never.
        if (!const {
          'submit',
          'button',
          'image',
          'reset',
          'file',
          'checkbox',
          'radio',
        }.contains(f['type']))
          '${f['name']}': '${f['value'] ?? ''}',
      for (final e in ((args['fields'] as Map?) ?? const {}).entries)
        '${e.key}': '${e.value}',
    };
    final action = Uri.parse('${form['action']}');
    final get = form['method'] == 'GET';
    final r = get
        ? await _web.request(
            'GET',
            action.replace(
              queryParameters: {...action.queryParameters, ...values},
            ),
          )
        : await _web.request(
            'POST',
            action,
            body: values,
            headers: {'referer': url.toString()},
          );
    final source = WebFetcher.decodeBody(r);
    final result = WebFetcher.isHtml(r)
        ? ReadablePage.parse(source, r.request?.url ?? action)
        : null;
    return ToolOutput({
      'done': r.statusCode < 400,
      'status': r.statusCode,
      'url': r.request?.url.toString(),
      if (result != null) 'title': result.title,
      'text': TelegramToolRunner._clip(result?.text ?? source, 4000),
      if (r.statusCode >= 400) 'error': 'HTTP ${r.statusCode}',
    });
  }

  Future<ToolOutput> _download(Map<String, dynamic> args) async {
    final url = WebFetcher.normalize('${args['url'] ?? ''}');
    final clock = Stopwatch()..start();
    final file = await _web.download(url, name: args['name'] as String?);
    final size = await file.length();
    final name = file.path.split(RegExp(r'[\\/]')).last;
    final head = await file.openRead(0, 32).expand((b) => b).toList();
    return ToolOutput({
      'created': true,
      'file_path': file.path,
      // Shows the picture on the tool card and in its details.
      if (WebFetcher.isPicture(head)) 'image_path': file.path,
      'name': name,
      'size_kb': (size / 1024).ceil(),
      'size': formatBytes(size),
      'type': ?lookupMimeType(file.path, headerBytes: head),
      'seconds': (clock.elapsedMilliseconds / 1000).toStringAsFixed(1),
      'from': url.host,
      'note':
          'Saved on the phone. Send it with send_message by passing "$name" in files.',
    });
  }
}
