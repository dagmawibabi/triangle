part of 'telegram_tools.dart';

// Cloudflare (zones, DNS, cache, Workers, Pages, KV, R2 storage) with the
// user's API token and R2 access key, and E2B cloud sandboxes that run
// code, the two services ScholarXIV uses for storage and executePython.
// Keys and options are under Settings → Apps & web (Cloudflare and E2B tabs).

const _zoneParam = {'type': 'string', 'description': 'Zone id or domain name, e.g. example.com.'};
const _bucketParam = {'type': 'string', 'description': 'R2 bucket name. Default: the bucket set in Settings.'};

final _cloudTools = <TelegramTool>[
  // ---- E2B -------------------------------------------------------------------
  TelegramTool(
    name: 'e2b_run_code',
    label: 'Running code in E2B',
    category: ToolCategory.e2b,
    cost: ToolCost.cloud,
    description:
        'Runs code in the user\'s E2B cloud sandbox (a Linux VM with Jupyter): python (default; numpy, pandas, '
        'matplotlib, scipy, requests… and pip install), javascript, bash, r or java. The sandbox keeps its state '
        'between calls while it lives (variables, files, installed packages) when the user keeps it in Settings. '
        'Charts (plt.show() or the last expression) are shown to the user; printed output and results come back. '
        'Use for heavy work the phone sandbox (run_code) can\'t do: big data, network, packages, long jobs. Put files '
        'from this conversation in the sandbox first with e2b_upload_file. The code is shown to the user, who can edit '
        'and rerun it.',
    parameters: _obj({
      'code': {'type': 'string'},
      'language': {'type': 'string', 'enum': E2BClient.languages},
      'timeout_seconds': {'type': 'integer', 'description': '10-600, default 120.'},
    }, ['code']),
  ),
  TelegramTool(
    name: 'e2b_run_command',
    label: 'Running a command in E2B',
    category: ToolCategory.e2b,
    cost: ToolCost.cloud,
    description: 'Runs a shell command in the E2B sandbox (e.g. "ls -la", "pip install x", "git clone …") and returns its output and exit code.',
    parameters: _obj({
      'command': {'type': 'string'},
      'cwd': {'type': 'string', 'description': 'Working directory, default /home/user.'},
      'timeout_seconds': {'type': 'integer', 'description': '5-600, default 120.'},
    }, ['command']),
  ),
  TelegramTool(
    name: 'e2b_upload_file',
    label: 'Putting a file in E2B',
    category: ToolCategory.e2b,
    cost: ToolCost.cloud,
    description: 'Copies a file from this conversation (its name or path) into the E2B sandbox, by default into /home/user.',
    parameters: _obj({
      'file': {'type': 'string', 'description': 'A file of this conversation.'},
      'path': {'type': 'string', 'description': 'Where in the sandbox. Default /home/user/<name>.'},
    }, ['file']),
  ),
  TelegramTool(
    name: 'e2b_download_file',
    label: 'Getting a file from E2B',
    category: ToolCategory.e2b,
    cost: ToolCost.cloud,
    description: 'Copies a file out of the E2B sandbox onto the phone (up to 15 MB). It becomes a file of this conversation: shown to the user, and sendable with send_message.',
    parameters: _obj({
      'path': {'type': 'string'},
    }, ['path']),
  ),
  TelegramTool(
    name: 'e2b_list_files',
    label: 'Listing E2B files',
    category: ToolCategory.e2b,
    cost: ToolCost.cloud,
    description: 'Lists a folder in the E2B sandbox (default /home/user): names, sizes, dates.',
    parameters: _obj({
      'path': {'type': 'string'},
    }),
  ),
  TelegramTool(
    name: 'e2b_sandboxes',
    label: 'Checking E2B sandboxes',
    category: ToolCategory.e2b,
    cost: ToolCost.cloud,
    description: 'Shows the sandbox this app is using, and every sandbox running on the user\'s E2B account.',
    parameters: _obj({}),
  ),
  TelegramTool(
    name: 'e2b_reset_sandbox',
    label: 'Restarting the E2B sandbox',
    category: ToolCategory.e2b,
    cost: ToolCost.cloud,
    description: 'Stops the sandbox this app is using; the next run starts a clean one. Its variables and files are lost.',
    parameters: _obj({}),
  ),
  TelegramTool(
    name: 'e2b_kill_sandbox',
    label: 'Stopping an E2B sandbox',
    category: ToolCategory.e2b,
    cost: ToolCost.cloud,
    requiresApproval: true,
    destructive: true,
    description: 'Stops any sandbox on the user\'s E2B account by id (from e2b_sandboxes), including ones other apps started. Its state is lost.',
    parameters: _obj({
      'sandbox_id': {'type': 'string'},
    }, ['sandbox_id']),
  ),

  // ---- Cloudflare: read --------------------------------------------------------
  TelegramTool(
    name: 'cloudflare_zones',
    label: 'Listing Cloudflare sites',
    category: ToolCategory.cloudflare,
    cost: ToolCost.cloud,
    description: 'Lists the user\'s Cloudflare zones (sites): status, plan, name servers. name filters by domain.',
    parameters: _obj({
      'name': {'type': 'string'},
    }),
  ),
  TelegramTool(
    name: 'cloudflare_dns_records',
    label: 'Reading DNS records',
    category: ToolCategory.cloudflare,
    cost: ToolCost.cloud,
    description: 'Lists a zone\'s DNS records (type, name, content, proxied, TTL), optionally filtered by type or name.',
    parameters: _obj({
      'zone': _zoneParam,
      'type': {'type': 'string', 'description': 'A, AAAA, CNAME, MX, TXT, NS, SRV, CAA…'},
      'name': {'type': 'string', 'description': 'Full record name, e.g. www.example.com.'},
    }, ['zone']),
  ),
  TelegramTool(
    name: 'cloudflare_workers',
    label: 'Listing Workers',
    category: ToolCategory.cloudflare,
    cost: ToolCost.cloud,
    description: 'Lists the account\'s Workers scripts with when each was created and last changed.',
    parameters: _obj({}),
  ),
  TelegramTool(
    name: 'cloudflare_pages',
    label: 'Listing Pages projects',
    category: ToolCategory.cloudflare,
    cost: ToolCost.cloud,
    description: 'Lists Cloudflare Pages projects with their domains and latest deployment; give project for its recent deployments.',
    parameters: _obj({
      'project': {'type': 'string'},
    }),
  ),
  TelegramTool(
    name: 'cloudflare_kv',
    label: 'Reading Workers KV',
    category: ToolCategory.cloudflare,
    cost: ToolCost.cloud,
    description: 'Workers KV: with no namespace_id lists namespaces; with one lists its keys (prefix filters); with key too, reads that value.',
    parameters: _obj({
      'namespace_id': {'type': 'string'},
      'prefix': {'type': 'string'},
      'key': {'type': 'string'},
    }),
  ),
  TelegramTool(
    name: 'cloudflare_api_get',
    label: 'Asking the Cloudflare API',
    category: ToolCategory.cloudflare,
    cost: ToolCost.cloud,
    description:
        'GET any Cloudflare API v4 path the other tools don\'t cover (e.g. /zones/{id}/settings, /accounts/{account_id}/d1/database). '
        '{account_id} is filled in. Read-only.',
    parameters: _obj({
      'path': {'type': 'string', 'description': 'Starts with /, e.g. /zones/abc/settings/ssl.'},
    }, ['path']),
  ),

  // ---- Cloudflare: changes -----------------------------------------------------
  TelegramTool(
    name: 'cloudflare_create_dns_record',
    label: 'Adding a DNS record',
    category: ToolCategory.cloudflare,
    cost: ToolCost.cloud,
    requiresApproval: true,
    description: 'Adds a DNS record to a zone. Only when the user asked; they approve first.',
    parameters: _obj({
      'zone': _zoneParam,
      'type': {'type': 'string'},
      'name': {'type': 'string', 'description': 'e.g. www, or the full name.'},
      'content': {'type': 'string', 'description': 'IP address, target hostname or text.'},
      'proxied': {'type': 'boolean', 'description': 'Through Cloudflare (orange cloud). A/AAAA/CNAME only.'},
      'ttl': {'type': 'integer', 'description': '1 for automatic, else seconds.'},
      'priority': {'type': 'integer', 'description': 'MX and SRV.'},
      'comment': {'type': 'string'},
    }, ['zone', 'type', 'name', 'content']),
  ),
  TelegramTool(
    name: 'cloudflare_update_dns_record',
    label: 'Changing a DNS record',
    category: ToolCategory.cloudflare,
    cost: ToolCost.cloud,
    requiresApproval: true,
    description: 'Changes fields of a DNS record (record_id from cloudflare_dns_records). Only when the user asked; they approve first.',
    parameters: _obj({
      'zone': _zoneParam,
      'record_id': {'type': 'string'},
      'type': {'type': 'string'},
      'name': {'type': 'string'},
      'content': {'type': 'string'},
      'proxied': {'type': 'boolean'},
      'ttl': {'type': 'integer'},
      'comment': {'type': 'string'},
    }, ['zone', 'record_id']),
  ),
  TelegramTool(
    name: 'cloudflare_purge_cache',
    label: 'Purging the cache',
    category: ToolCategory.cloudflare,
    cost: ToolCost.cloud,
    requiresApproval: true,
    description: 'Purges a zone\'s cache: everything, or only the given URLs. They approve first.',
    parameters: _obj({
      'zone': _zoneParam,
      'urls': {'type': 'array', 'items': {'type': 'string'}, 'description': 'Full URLs; empty for everything.'},
    }, ['zone']),
  ),
  TelegramTool(
    name: 'cloudflare_kv_put',
    label: 'Writing to Workers KV',
    category: ToolCategory.cloudflare,
    cost: ToolCost.cloud,
    requiresApproval: true,
    description: 'Writes a value under a key in a Workers KV namespace. They approve first.',
    parameters: _obj({
      'namespace_id': {'type': 'string'},
      'key': {'type': 'string'},
      'value': {'type': 'string'},
      'expiration_ttl': {'type': 'integer', 'description': 'Seconds until it expires (60+).'},
    }, ['namespace_id', 'key', 'value']),
  ),

  // ---- R2 ----------------------------------------------------------------------
  TelegramTool(
    name: 'r2_buckets',
    label: 'Listing R2 buckets',
    category: ToolCategory.r2,
    cost: ToolCost.cloud,
    description: 'Lists the account\'s R2 storage buckets.',
    parameters: _obj({}),
  ),
  TelegramTool(
    name: 'r2_list',
    label: 'Browsing R2',
    category: ToolCategory.r2,
    cost: ToolCost.cloud,
    description: 'Lists files in an R2 bucket one folder at a time (prefix is the folder, e.g. "photos/"), with sizes and dates. Shown to the user as a file browser.',
    parameters: _obj({
      'bucket': _bucketParam,
      'prefix': {'type': 'string'},
      'recursive': {'type': 'boolean', 'description': 'Everything under prefix, not just one level.'},
      'cursor': {'type': 'string', 'description': 'next_cursor from an earlier call.'},
    }),
  ),
  TelegramTool(
    name: 'r2_download',
    label: 'Getting a file from R2',
    category: ToolCategory.r2,
    cost: ToolCost.cloud,
    description: 'Downloads an R2 object onto the phone (up to 50 MB). It becomes a file of this conversation: read it with run_code, or send it with send_message.',
    parameters: _obj({
      'bucket': _bucketParam,
      'key': {'type': 'string'},
    }, ['key']),
  ),
  TelegramTool(
    name: 'r2_share_link',
    label: 'Making a share link',
    category: ToolCategory.r2,
    cost: ToolCost.cloud,
    description: 'A temporary link anyone can open to download an R2 object (presigned; default 1 hour, up to 7 days).',
    parameters: _obj({
      'bucket': _bucketParam,
      'key': {'type': 'string'},
      'hours': {'type': 'integer'},
    }, ['key']),
  ),
  TelegramTool(
    name: 'r2_upload',
    label: 'Uploading to R2',
    category: ToolCategory.r2,
    cost: ToolCost.cloud,
    requiresApproval: true,
    description: 'Uploads a file of this conversation (or text) to an R2 bucket under key. Overwrites an object with the same key. They approve first.',
    parameters: _obj({
      'bucket': _bucketParam,
      'key': {'type': 'string', 'description': 'e.g. reports/october.pdf. Default: the file name.'},
      'file': {'type': 'string', 'description': 'A file of this conversation.'},
      'text': {'type': 'string', 'description': 'Upload this text instead of a file.'},
    }),
  ),
  TelegramTool(
    name: 'r2_create_bucket',
    label: 'Creating an R2 bucket',
    category: ToolCategory.r2,
    cost: ToolCost.cloud,
    requiresApproval: true,
    description: 'Creates an R2 bucket. They approve first.',
    parameters: _obj({
      'name': {'type': 'string', 'description': 'Lowercase letters, digits and hyphens.'},
    }, ['name']),
  ),

  // ---- destructive ---------------------------------------------------------------
  TelegramTool(
    name: 'cloudflare_delete_dns_record',
    label: 'Deleting a DNS record',
    category: ToolCategory.cloudflare,
    cost: ToolCost.cloud,
    requiresApproval: true,
    destructive: true,
    description: 'Deletes a DNS record. Can take a site or email offline. Only when the user clearly asked for exactly this.',
    parameters: _obj({'zone': _zoneParam, 'record_id': {'type': 'string'}}, ['zone', 'record_id']),
  ),
  TelegramTool(
    name: 'cloudflare_kv_delete',
    label: 'Deleting a KV key',
    category: ToolCategory.cloudflare,
    cost: ToolCost.cloud,
    requiresApproval: true,
    destructive: true,
    description: 'Deletes a key from a Workers KV namespace.',
    parameters: _obj({'namespace_id': {'type': 'string'}, 'key': {'type': 'string'}}, ['namespace_id', 'key']),
  ),
  TelegramTool(
    name: 'cloudflare_delete_worker',
    label: 'Deleting a Worker',
    category: ToolCategory.cloudflare,
    cost: ToolCost.cloud,
    requiresApproval: true,
    destructive: true,
    description: 'Deletes a Workers script. Whatever it serves stops working.',
    parameters: _obj({'name': {'type': 'string'}}, ['name']),
  ),
  TelegramTool(
    name: 'cloudflare_api_request',
    label: 'Changing something in Cloudflare',
    category: ToolCategory.cloudflare,
    cost: ToolCost.cloud,
    requiresApproval: true,
    destructive: true,
    description:
        'POST, PUT, PATCH or DELETE on any Cloudflare API v4 path, with a JSON body written as text. For changes the other tools '
        'don\'t cover. {account_id} is filled in. Always asks first.',
    parameters: _obj({
      'method': {'type': 'string', 'enum': ['POST', 'PUT', 'PATCH', 'DELETE']},
      'path': {'type': 'string'},
      'body_json': {'type': 'string'},
    }, ['method', 'path']),
  ),
  TelegramTool(
    name: 'r2_delete',
    label: 'Deleting from R2',
    category: ToolCategory.r2,
    cost: ToolCost.cloud,
    requiresApproval: true,
    destructive: true,
    description: 'Deletes objects from an R2 bucket. There is no undo.',
    parameters: _obj({
      'bucket': _bucketParam,
      'keys': {'type': 'array', 'items': {'type': 'string'}},
    }, ['keys']),
  ),
  TelegramTool(
    name: 'r2_delete_bucket',
    label: 'Deleting an R2 bucket',
    category: ToolCategory.r2,
    cost: ToolCost.cloud,
    requiresApproval: true,
    destructive: true,
    description: 'Deletes an empty R2 bucket.',
    parameters: _obj({'name': {'type': 'string'}}, ['name']),
  ),
];

final _cloudToolNames = {for (final t in _cloudTools) t.name};

/// Whether the model is offered [t]: Cloudflare and E2B tools need their keys.
bool cloudToolReady(TelegramTool t, AppSettings s) {
  if (!_cloudToolNames.contains(t.name)) return true;
  if (t.category == ToolCategory.e2b) return s.hasE2bKey;
  return s.hasCloudflare;
}

/// What a Cloudflare or E2B tool still needs, for the Tools list.
String? cloudToolNeeds(TelegramTool t, AppSettings s) {
  if (!_cloudToolNames.contains(t.name)) return null;
  if (t.category == ToolCategory.e2b) return s.hasE2bKey ? null : 'Needs an E2B key';
  if (!s.hasCloudflare) return 'Needs a Cloudflare token';
  const s3 = {'r2_list', 'r2_download', 'r2_share_link', 'r2_upload', 'r2_delete'};
  if (s3.contains(t.name) && !s.hasR2Keys) return 'Needs an R2 access key';
  return null;
}

extension _CloudToolRuns on TelegramToolRunner {
  Future<ToolOutput>? _runCloud(String name, Map<String, dynamic> args) {
    if (!_cloudToolNames.contains(name)) return null;
    return name.startsWith('e2b_') ? _e2b(name, args) : _cloudflare(name, args);
  }

  String _arg(Map<String, dynamic> a, String k) => '${a[k] ?? ''}'.trim();

  Future<ToolOutput> _e2b(String name, Map<String, dynamic> a) async {
    final session = _e2bSession;
    if (session == null || !_settings.hasE2bKey) {
      return const ToolOutput({'error': 'No E2B key. The user can add one in Settings → Apps & web → E2B.'});
    }
    int secs(String k, int fallback, int max) => TelegramToolRunner._int(a, k, fallback: fallback, min: 5, max: max);
    try {
      switch (name) {
        case 'e2b_run_code':
          final code = '${a['code'] ?? ''}';
          if (code.trim().isEmpty) return const ToolOutput({'error': 'code is empty'});
          final run = await session.run(
            code,
            language: E2BClient.languages.contains(_arg(a, 'language')) ? _arg(a, 'language') : 'python',
            timeout: Duration(seconds: secs('timeout_seconds', 120, 600)),
          );
          return ToolOutput({
            ...run.toJson(),
            // An exception is a failed run, not a finished one.
            if (run.error != null) 'error': '${run.error!['name'] ?? 'Error'}: ${run.error!['value'] ?? ''}'.trim(),
          });
        case 'e2b_run_command':
          final cmd = _arg(a, 'command');
          if (cmd.isEmpty) return const ToolOutput({'error': 'command is empty'});
          final t = secs('timeout_seconds', 120, 600);
          final j = await session.withSandbox(
            (c, box) => c.command(
              box,
              cmd,
              cwd: _arg(a, 'cwd').isEmpty ? '/home/user' : _arg(a, 'cwd'),
              timeout: Duration(seconds: t),
            ),
          );
          return ToolOutput({
            'sandbox': 'e2b',
            'command': cmd,
            'exit_code': j['exit_code'],
            if ('${j['stdout'] ?? ''}'.isNotEmpty) 'stdout': j['stdout'],
            if ('${j['stderr'] ?? ''}'.isNotEmpty) 'stderr': j['stderr'],
            if (j['exit_code'] is num && j['exit_code'] != 0) 'error': 'The command exited with code ${j['exit_code']}.',
          });
        case 'e2b_upload_file':
          final f = File(_arg(a, 'file'));
          if (!f.existsSync()) return ToolOutput({'error': 'No file "${_arg(a, 'file')}" in this conversation.'});
          final bytes = await f.readAsBytes();
          if (bytes.length > 20 << 20) return const ToolOutput({'error': 'Files over 20 MB can\'t be uploaded from the phone.'});
          final fileName = f.path.split(RegExp(r'[\\/]')).last.replaceFirst(RegExp(r'^[0-9a-f]{8}_'), '');
          final path = _arg(a, 'path').isEmpty ? '/home/user/$fileName' : _arg(a, 'path');
          await session.withSandbox((c, box) => c.writeFile(box, path, bytes));
          return ToolOutput({'uploaded': true, 'path': path, 'size': bytes.length});
        case 'e2b_download_file':
          final path = _arg(a, 'path');
          final bytes = await session.withSandbox((c, box) => c.readFile(box, path));
          final file = await saveGeneratedBytes(path, bytes, folder: 'sandbox');
          final image = RegExp(r'\.(png|jpe?g|gif|webp)$', caseSensitive: false).hasMatch(file.path);
          return ToolOutput({
            'downloaded': true,
            'from': path,
            'size': bytes.length,
            'created_files': [file.path],
            if (image) 'image_path': file.path,
          });
        case 'e2b_list_files':
          final path = _arg(a, 'path').isEmpty ? '/home/user' : _arg(a, 'path');
          final files = await session.withSandbox((c, box) => c.listFiles(box, path));
          return ToolOutput({'sandbox': 'e2b', 'path': path, 'files': files});
        case 'e2b_sandboxes':
          final all = await session.client().sandboxes();
          return ToolOutput({
            'sandbox': 'e2b',
            'current': session.current?.id,
            'template': _settings.e2bTemplate,
            'keeps_sandbox': _settings.e2bKeepAlive,
            'sandboxes': [for (final s in all) s.toJson()],
          });
        case 'e2b_reset_sandbox':
          final had = session.current?.id;
          await session.stop(null, 'stopped by the assistant');
          return ToolOutput({'stopped': had ?? 'none was running', 'note': 'The next run starts a clean sandbox.'});
        case 'e2b_kill_sandbox':
          final id = _arg(a, 'sandbox_id');
          if (id == session.current?.id) {
            await session.stop(null, 'stopped by the assistant');
          } else {
            await session.client().kill(id);
            await session.markStopped(id, 'stopped by the assistant');
          }
          return ToolOutput({'stopped': id});
      }
    } on AiException catch (e) {
      return ToolOutput({'error': 'E2B: ${e.message}'});
    }
    return ToolOutput({'error': 'Unknown tool $name'});
  }

  /// omni_ai's Cloudflare client, with the token and R2 keys from Settings.
  CloudflareClient _cf() => CloudflareClient(
    token: _settings.cloudflareToken,
    accountId: _settings.cloudflareAccountId,
    r2: R2Credentials(
      accountId: _settings.cloudflareAccountId,
      accessKeyId: _settings.r2AccessKeyId,
      secretAccessKey: _settings.r2SecretKey,
    ),
  );

  Future<String> _zoneId(CloudflareClient c, String zone) async {
    try {
      return await c.zoneId(zone.toLowerCase());
    } on AiException {
      throw AiException('No zone "$zone" on this account. Use cloudflare_zones.', provider: 'cloudflare');
    }
  }

  String _bucket(Map<String, dynamic> a) {
    final b = _arg(a, 'bucket').isEmpty ? _settings.r2Bucket : _arg(a, 'bucket');
    if (b.isEmpty) throw AiException('Which bucket? Name one, or set a default in Settings → Apps & web → Cloudflare.', provider: 'cloudflare');
    return b;
  }

  Future<ToolOutput> _cloudflare(String name, Map<String, dynamic> a) async {
    if (!_settings.hasCloudflare) {
      return const ToolOutput({'error': 'No Cloudflare token. The user can add one in Settings → Apps & web → Cloudflare.'});
    }
    final c = _cf();
    // R2's S3 endpoint is account-scoped; find the account from the token.
    Future<CloudflareClient> withAccount() async {
      if (_settings.cloudflareAccountId.isNotEmpty) return c;
      final id = await c.account();
      return CloudflareClient(
        token: _settings.cloudflareToken,
        accountId: id,
        r2: R2Credentials(accountId: id, accessKeyId: _settings.r2AccessKeyId, secretAccessKey: _settings.r2SecretKey),
      );
    }

    String fill(String path, String account) => path.replaceAll('{account_id}', account);
    try {
      switch (name) {
        case 'cloudflare_zones':
          final zones = await c.call('GET', '/zones', query: {'per_page': '50', if (_arg(a, 'name').isNotEmpty) 'name': _arg(a, 'name')});
          return ToolOutput({
            'cloud': 'cloudflare',
            'zones': [
              for (final z in (zones as List).whereType<Map>())
                {
                  'id': z['id'],
                  'name': z['name'],
                  'status': z['status'],
                  'paused': z['paused'],
                  'plan': (z['plan'] as Map?)?['name'],
                  'name_servers': z['name_servers'],
                  'modified': z['modified_on'],
                },
            ],
          });
        case 'cloudflare_dns_records':
          final zone = await _zoneId(c, _arg(a, 'zone'));
          final recs = await c.call('GET', '/zones/$zone/dns_records', query: {
            'per_page': '200',
            if (_arg(a, 'type').isNotEmpty) 'type': _arg(a, 'type').toUpperCase(),
            if (_arg(a, 'name').isNotEmpty) 'name': _arg(a, 'name'),
          });
          return ToolOutput({
            'cloud': 'cloudflare',
            'zone': _arg(a, 'zone'),
            'zone_id': zone,
            'dns_records': [
              for (final r in (recs as List).whereType<Map>())
                {
                  'id': r['id'],
                  'type': r['type'],
                  'name': r['name'],
                  'content': r['content'],
                  'proxied': r['proxied'],
                  'ttl': r['ttl'],
                  'priority': ?r['priority'],
                  if ('${r['comment'] ?? ''}'.isNotEmpty) 'comment': r['comment'],
                },
            ],
          });
        case 'cloudflare_workers':
          final acc = await c.account();
          final list = await c.call('GET', '/accounts/$acc/workers/scripts');
          return ToolOutput({
            'cloud': 'cloudflare',
            'workers': [
              for (final w in (list as List).whereType<Map>())
                {'name': w['id'], 'created': w['created_on'], 'modified': w['modified_on'], 'usage_model': ?w['usage_model']},
            ],
          });
        case 'cloudflare_pages':
          final acc = await c.account();
          final project = _arg(a, 'project');
          if (project.isNotEmpty) {
            final deps = await c.call('GET', '/accounts/$acc/pages/projects/$project/deployments', query: {'per_page': '10'});
            return ToolOutput({
              'cloud': 'cloudflare',
              'project': project,
              'deployments': [
                for (final d in (deps as List).whereType<Map>())
                  {
                    'id': d['id'],
                    'url': d['url'],
                    'environment': d['environment'],
                    'created': d['created_on'],
                    'status': (d['latest_stage'] as Map?)?['status'],
                    'stage': (d['latest_stage'] as Map?)?['name'],
                    'branch': ((d['deployment_trigger'] as Map?)?['metadata'] as Map?)?['branch'],
                    'commit': ((d['deployment_trigger'] as Map?)?['metadata'] as Map?)?['commit_message'],
                  },
              ],
            });
          }
          final list = await c.call('GET', '/accounts/$acc/pages/projects');
          return ToolOutput({
            'cloud': 'cloudflare',
            'pages': [
              for (final p in (list as List).whereType<Map>())
                {
                  'name': p['name'],
                  'subdomain': p['subdomain'],
                  'domains': p['domains'],
                  'production_branch': p['production_branch'],
                  'latest': (p['latest_deployment'] as Map?)?['created_on'],
                  'status': ((p['latest_deployment'] as Map?)?['latest_stage'] as Map?)?['status'],
                },
            ],
          });
        case 'cloudflare_kv':
          final acc = await c.account();
          final ns = _arg(a, 'namespace_id');
          if (ns.isEmpty) {
            final list = await c.call('GET', '/accounts/$acc/storage/kv/namespaces', query: {'per_page': '100'});
            return ToolOutput({
              'cloud': 'cloudflare',
              'kv_namespaces': [for (final n in (list as List).whereType<Map>()) {'id': n['id'], 'title': n['title']}],
            });
          }
          if (_arg(a, 'key').isNotEmpty) {
            final v = await c.call('GET', '/accounts/$acc/storage/kv/namespaces/$ns/values/${Uri.encodeComponent(_arg(a, 'key'))}');
            final text = v is String ? v : jsonEncode(v);
            return ToolOutput({'cloud': 'cloudflare', 'namespace_id': ns, 'key': _arg(a, 'key'), 'value': TelegramToolRunner._clip(text, 12000)});
          }
          final keys = await c.call('GET', '/accounts/$acc/storage/kv/namespaces/$ns/keys', query: {
            'limit': '200',
            if (_arg(a, 'prefix').isNotEmpty) 'prefix': _arg(a, 'prefix'),
          });
          return ToolOutput({
            'cloud': 'cloudflare',
            'namespace_id': ns,
            'kv_keys': [for (final k in (keys as List).whereType<Map>()) {'name': k['name'], 'expiration': ?k['expiration']}],
          });
        case 'cloudflare_api_get':
          final acc = _arg(a, 'path').contains('{account_id}') ? await c.account() : '';
          final r = await c.call('GET', fill(_arg(a, 'path'), acc));
          final text = jsonEncode(r);
          return ToolOutput({'cloud': 'cloudflare', 'path': _arg(a, 'path'), 'result': text.length > 14000 ? '${text.substring(0, 14000)}…' : r});
        case 'cloudflare_create_dns_record' || 'cloudflare_update_dns_record':
          final zone = await _zoneId(c, _arg(a, 'zone'));
          final body = {
            for (final k in const ['type', 'name', 'content', 'comment'])
              if (_arg(a, k).isNotEmpty) k: k == 'type' ? _arg(a, k).toUpperCase() : _arg(a, k),
            if (a['proxied'] is bool) 'proxied': a['proxied'],
            if (a['ttl'] is num) 'ttl': (a['ttl'] as num).toInt() else if (name == 'cloudflare_create_dns_record') 'ttl': 1,
            if (a['priority'] is num) 'priority': (a['priority'] as num).toInt(),
          };
          final r = name == 'cloudflare_create_dns_record'
              ? await c.call('POST', '/zones/$zone/dns_records', body: body)
              : await c.call('PATCH', '/zones/$zone/dns_records/${_arg(a, 'record_id')}', body: body);
          return ToolOutput({'done': true, 'cloud': 'cloudflare', 'zone': _arg(a, 'zone'), 'dns_records': [r]});
        case 'cloudflare_purge_cache':
          final zone = await _zoneId(c, _arg(a, 'zone'));
          final urls = [for (final u in (a['urls'] as List? ?? const [])) '$u'];
          await c.call('POST', '/zones/$zone/purge_cache', body: urls.isEmpty ? {'purge_everything': true} : {'files': urls});
          return ToolOutput({'done': true, 'purged': urls.isEmpty ? 'everything' : urls});
        case 'cloudflare_kv_put':
          final acc = await c.account();
          final ttl = a['expiration_ttl'] is num ? '?expiration_ttl=${(a['expiration_ttl'] as num).toInt()}' : '';
          await c.call(
            'PUT',
            '/accounts/$acc/storage/kv/namespaces/${_arg(a, 'namespace_id')}/values/${Uri.encodeComponent(_arg(a, 'key'))}$ttl',
            rawBody: '${a['value'] ?? ''}',
          );
          return ToolOutput({'done': true, 'key': _arg(a, 'key')});
        case 'cloudflare_delete_dns_record':
          final zone = await _zoneId(c, _arg(a, 'zone'));
          await c.call('DELETE', '/zones/$zone/dns_records/${_arg(a, 'record_id')}');
          return ToolOutput({'deleted': _arg(a, 'record_id')});
        case 'cloudflare_kv_delete':
          final acc = await c.account();
          await c.call('DELETE', '/accounts/$acc/storage/kv/namespaces/${_arg(a, 'namespace_id')}/values/${Uri.encodeComponent(_arg(a, 'key'))}');
          return ToolOutput({'deleted': _arg(a, 'key')});
        case 'cloudflare_delete_worker':
          final acc = await c.account();
          await c.call('DELETE', '/accounts/$acc/workers/scripts/${_arg(a, 'name')}');
          return ToolOutput({'deleted': _arg(a, 'name')});
        case 'cloudflare_api_request':
          final acc = _arg(a, 'path').contains('{account_id}') ? await c.account() : '';
          final raw = _arg(a, 'body_json');
          final body = raw.isEmpty ? null : _tryJson(raw);
          if (raw.isNotEmpty && body == null) return const ToolOutput({'error': 'body_json is not valid JSON.'});
          final r = await c.call(_arg(a, 'method').toUpperCase(), fill(_arg(a, 'path'), acc), body: body);
          final text = jsonEncode(r);
          return ToolOutput({'done': true, 'result': text.length > 10000 ? '${text.substring(0, 10000)}…' : r});
        case 'r2_buckets':
          final acc = await c.account();
          final r = await c.call('GET', '/accounts/$acc/r2/buckets', query: {'per_page': '100'});
          final list = r is Map ? (r['buckets'] as List? ?? const []) : (r as List? ?? const []);
          return ToolOutput({
            'cloud': 'r2',
            'default_bucket': ?(_settings.r2Bucket.isEmpty ? null : _settings.r2Bucket),
            'buckets': [
              for (final b in list.whereType<Map>()) {'name': b['name'], 'created': b['creation_date'], 'location': ?b['location']},
            ],
          });
        case 'r2_create_bucket':
          final acc = await c.account();
          await c.call('POST', '/accounts/$acc/r2/buckets', body: {'name': _arg(a, 'name')});
          return ToolOutput({'done': true, 'created': _arg(a, 'name')});
        case 'r2_delete_bucket':
          final acc = await c.account();
          await c.call('DELETE', '/accounts/$acc/r2/buckets/${_arg(a, 'name')}');
          return ToolOutput({'deleted': _arg(a, 'name')});
        case 'r2_list':
          final cc = await withAccount();
          final r = await cc.listObjects(
            _bucket(a),
            prefix: _arg(a, 'prefix'),
            delimiter: a['recursive'] != true,
            cursor: _arg(a, 'cursor').isEmpty ? null : _arg(a, 'cursor'),
          );
          return ToolOutput({'cloud': 'r2', ...r});
        case 'r2_download':
          final cc = await withAccount();
          final key = _arg(a, 'key');
          final bytes = await cc.getObject(_bucket(a), key);
          if (bytes.length > 50 << 20) return const ToolOutput({'error': 'That object is over 50 MB.'});
          final file = await saveGeneratedBytes(key, bytes, folder: 'downloads');
          final image = RegExp(r'\.(png|jpe?g|gif|webp)$', caseSensitive: false).hasMatch(file.path);
          return ToolOutput({'downloaded': true, 'key': key, 'size': bytes.length, 'created_files': [file.path], if (image) 'image_path': file.path});
        case 'r2_share_link':
          final cc = await withAccount();
          final hours = TelegramToolRunner._int(a, 'hours', fallback: 1, max: 168);
          return ToolOutput({
            'cloud': 'r2',
            'key': _arg(a, 'key'),
            'url': cc.presign(_bucket(a), _arg(a, 'key'), expires: Duration(hours: hours)),
            'expires_in_hours': hours,
          });
        case 'r2_upload':
          final cc = await withAccount();
          final bucket = _bucket(a);
          final Uint8List bytes;
          var key = _arg(a, 'key');
          String type;
          if (_arg(a, 'file').isNotEmpty) {
            final f = File(_arg(a, 'file'));
            if (!f.existsSync()) return ToolOutput({'error': 'No file "${_arg(a, 'file')}" in this conversation.'});
            bytes = await f.readAsBytes();
            if (key.isEmpty) key = f.path.split(RegExp(r'[\\/]')).last.replaceFirst(RegExp(r'^[0-9a-f]{8}_'), '');
            type = lookupMimeType(f.path) ?? 'application/octet-stream';
          } else {
            bytes = Uint8List.fromList(utf8.encode('${a['text'] ?? ''}'));
            if (key.isEmpty) return const ToolOutput({'error': 'key is required when uploading text.'});
            type = lookupMimeType(key) ?? 'text/plain; charset=utf-8';
          }
          await cc.putObject(bucket, key, bytes, type);
          return ToolOutput({'done': true, 'cloud': 'r2', 'bucket': bucket, 'key': key, 'size': bytes.length});
        case 'r2_delete':
          final cc = await withAccount();
          final bucket = _bucket(a);
          final keys = [for (final k in (a['keys'] as List? ?? const [])) '$k'];
          for (final k in keys) {
            await cc.deleteObject(bucket, k);
          }
          return ToolOutput({'deleted': keys, 'bucket': bucket});
      }
    } on AiException catch (e) {
      return ToolOutput({'error': 'Cloudflare: ${e.message}'});
    }
    return ToolOutput({'error': 'Unknown tool $name'});
  }

  /// What a Cloudflare or E2B change would do, for the approval card.
  String? _describeCloud(String name, Map<String, dynamic> a) {
    if (!_cloudToolNames.contains(name)) return null;
    String v(String k) => '${a[k] ?? ''}'.trim();
    final bucket = v('bucket').isEmpty ? _settings.r2Bucket : v('bucket');
    return switch (name) {
      'cloudflare_create_dns_record' =>
        'Add a ${v('type').toUpperCase()} record on ${v('zone')}\n${v('name')} → ${v('content')}${a['proxied'] == true ? ' (proxied)' : ''}',
      'cloudflare_update_dns_record' => 'Change DNS record ${v('record_id')} on ${v('zone')}\n${[for (final k in const ['type', 'name', 'content', 'proxied', 'ttl']) if (a[k] != null) '$k: ${a[k]}'].join('\n')}',
      'cloudflare_delete_dns_record' => 'Delete DNS record ${v('record_id')} on ${v('zone')}',
      'cloudflare_purge_cache' =>
        (a['urls'] as List? ?? const []).isEmpty ? 'Purge everything cached for ${v('zone')}' : 'Purge from ${v('zone')}:\n${(a['urls'] as List).join('\n')}',
      'cloudflare_kv_put' => 'Write KV key “${v('key')}” in ${v('namespace_id')}\n“${TelegramToolRunner._clip(v('value'), 300)}”',
      'cloudflare_kv_delete' => 'Delete KV key “${v('key')}” from ${v('namespace_id')}',
      'cloudflare_delete_worker' => 'Delete the Worker “${v('name')}”',
      'cloudflare_api_request' => '${v('method')} ${v('path')}${v('body_json').isEmpty ? '' : '\n${TelegramToolRunner._clip(v('body_json'), 600)}'}',
      'r2_upload' => 'Upload ${v('file').isEmpty ? 'text' : v('file').split(RegExp(r'[\\/]')).last} to R2 $bucket/${v('key')}',
      'r2_create_bucket' => 'Create the R2 bucket “${v('name')}”',
      'r2_delete' => 'Delete from R2 $bucket:\n${(a['keys'] as List? ?? const []).join('\n')}',
      'r2_delete_bucket' => 'Delete the R2 bucket “${v('name')}”',
      'e2b_kill_sandbox' => 'Stop E2B sandbox ${v('sandbox_id')}',
      _ => null,
    };
  }
}
