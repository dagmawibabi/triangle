part of 'telegram_tools.dart';

// Vercel, with the user's access token (Settings → Development → Vercel):
// projects, deployments and their build and runtime logs, promoting and
// rolling back, environment variables, domains and DNS, aliases, Edge
// Config, webhooks, firewall, checks, team and usage; deploying files from
// the conversation to a live URL; and any other REST path. Reading runs
// freely; changes ask first; deletions are destructive tools.

const _vcProject = {'type': 'string', 'description': 'Project name or id, as vercel_projects lists it.'};
const _vcDeployment = {'type': 'string', 'description': 'Deployment id (dpl_…) or its URL, e.g. my-app-abc123.vercel.app.'};
const _vcTargets = {
  'type': 'array',
  'items': {'type': 'string', 'enum': ['production', 'preview', 'development'], 'description': 'An environment.'},
  'description': 'Environments it applies to. Default all three.',
};

TelegramTool _vc(String name, String label, String description, Map<String, dynamic> params, {List<String> required = const [], bool change = false, bool destructive = false, bool alwaysAsk = false}) =>
    TelegramTool(
      name: name,
      label: label,
      category: ToolCategory.vercel,
      cost: ToolCost.cloud,
      requiresApproval: change || destructive,
      destructive: destructive,
      alwaysAsk: alwaysAsk,
      description: description,
      parameters: _obj(params, required),
    );

final _vercelTools = <TelegramTool>[
  // ---- read ----------------------------------------------------------------------
  _vc('vercel_account', 'Looking at your Vercel account',
      'The Vercel user the token belongs to, the teams it can reach and which one the tools act on. Shown as an account card.', {}),
  _vc('vercel_projects', 'Listing Vercel projects',
      'Lists Vercel projects, newest activity first: framework, git repository, production URL and the latest deployment\'s state. '
          'Shown as a project list the user can open.', {
        'search': {'type': 'string', 'description': 'Only projects whose name contains this.'},
        'limit': {'type': 'integer', 'description': '1-100, default 30.'},
      }),
  _vc('vercel_project', 'Opening a Vercel project',
      'One project in full: settings (framework, build and output, root directory, Node version), git link, domains, crons, '
          'production and recent deployments. Shown as a project card with actions.', {'project': _vcProject}, required: ['project']),
  _vc('vercel_deployments', 'Listing deployments',
      'Recent deployments, newest first, across the account or for one project: state (BUILDING, READY, ERROR…), target, branch, '
          'commit, who and when. Shown as a live list: building ones update as they finish.', {
        'project': {'type': 'string', 'description': 'Only this project (name or id).'},
        'target': {'type': 'string', 'enum': ['production', 'preview'], 'description': 'Only production or only preview deployments.'},
        'state': {'type': 'string', 'enum': ['BUILDING', 'ERROR', 'INITIALIZING', 'QUEUED', 'READY', 'CANCELED'], 'description': 'Only deployments in this state.'},
        'since_hours': {'type': 'number', 'description': 'Only deployments created in the last this many hours.'},
        'limit': {'type': 'integer', 'description': '1-100, default 20.'},
      }),
  _vc('vercel_deployment', 'Checking a deployment',
      'One deployment: state, URL, aliases, target, branch and commit, timings, and the error when it failed. Shown as a live card that '
          'follows a build to the end.', {'deployment': _vcDeployment}, required: ['deployment']),
  _vc('vercel_build_logs', 'Reading build logs',
      'A deployment\'s build output (the lines Vercel shows while building), oldest first. errors_only keeps warnings and errors. '
          'Use to find why a build failed.', {
        'deployment': _vcDeployment,
        'errors_only': {'type': 'boolean', 'description': 'Only error and warning lines.'},
        'limit': {'type': 'integer', 'description': 'Lines, 1-1000, default 300.'},
      }, required: ['deployment']),
  _vc('vercel_runtime_logs', 'Reading runtime logs',
      'Recent runtime logs of a deployment (function invocations, status codes, console output), collected for a few seconds. '
          'Defaults to the project\'s current production deployment.', {
        'project': _vcProject,
        'deployment': {'type': 'string', 'description': 'Deployment id or URL. Default: the production deployment.'},
        'seconds': {'type': 'integer', 'description': 'How long to collect, 2-20, default 6.'},
        'limit': {'type': 'integer', 'description': 'Lines, 1-500, default 150.'},
      }, required: ['project']),
  _vc('vercel_deployment_files', 'Listing deployment files',
      'The file tree of a deployment\'s source or output, with sizes.', {'deployment': _vcDeployment}, required: ['deployment']),
  _vc('vercel_env', 'Reading environment variables',
      'A project\'s environment variables: key, environments, type, branch and when changed. Values stay hidden unless reveal is true; '
          'secret values then go to the AI model, so reveal only when the user asks to see them.', {
        'project': _vcProject,
        'target': {'type': 'string', 'enum': ['production', 'preview', 'development'], 'description': 'Only variables for this environment.'},
        'reveal': {'type': 'boolean', 'description': 'Include decrypted values. Only when the user asks.'},
      }, required: ['project']),
  _vc('vercel_domains', 'Listing domains',
      'Domains on the account with their registrar, name servers, verification and expiry; with domain, that domain\'s configuration '
          '(misconfigured or not, the records Vercel expects).', {
        'domain': {'type': 'string', 'description': 'One domain to inspect, e.g. example.com.'},
      }),
  _vc('vercel_project_domains', 'Listing a project\'s domains',
      'The domains attached to a project: verified or not, redirects, the git branch each follows, and what DNS they still need.', {'project': _vcProject},
      required: ['project']),
  _vc('vercel_domain_check', 'Checking a domain',
      'Whether a domain can be bought through Vercel and its price.', {
        'domain': {'type': 'string', 'description': 'The domain to check, e.g. example.com.'},
      }, required: ['domain']),
  _vc('vercel_dns_records', 'Reading Vercel DNS',
      'DNS records of a domain whose DNS Vercel hosts.', {
        'domain': {'type': 'string', 'description': 'The domain, e.g. example.com.'},
      }, required: ['domain']),
  _vc('vercel_aliases', 'Listing aliases',
      'Aliases (custom URLs) pointing at deployments: for one deployment, one project, or the whole account.', {
        'deployment': {'type': 'string', 'description': 'Only this deployment\'s aliases (id or URL).'},
        'project': {'type': 'string', 'description': 'Only aliases of this project.'},
        'limit': {'type': 'integer', 'description': '1-100, default 40.'},
      }),
  _vc('vercel_usage', 'Reading Vercel usage and cost',
      'What the account was billed over a period, by service (functions, bandwidth, builds, edge requests…) and by day. Shown as a chart.', {
        'days': {'type': 'integer', 'description': 'How far back, 1-90, default 30.'},
      }),
  _vc('vercel_team_members', 'Listing team members',
      'Members of the current team with their role and when they joined. Needs a team in Settings.', {}),
  _vc('vercel_webhooks', 'Listing webhooks', 'The account\'s webhooks: URL, the events they send and the projects they cover.', {}),
  _vc('vercel_edge_config', 'Reading Edge Config',
      'Edge Config stores: with no id lists them; with id lists that store\'s items (key and value).', {
        'id': {'type': 'string', 'description': 'Edge Config id (ecfg_…) to read the items of.'},
      }),
  _vc('vercel_firewall', 'Reading the firewall',
      'A project\'s Vercel Firewall configuration: whether it is on, custom rules, IP blocks and managed rule sets.', {'project': _vcProject},
      required: ['project']),
  _vc('vercel_checks', 'Reading deployment checks', 'The checks run against a deployment (integrations, tests) with status and conclusion.',
      {'deployment': _vcDeployment}, required: ['deployment']),
  _vc('vercel_api_get', 'Asking the Vercel API',
      'GET any Vercel REST path the other tools don\'t cover (vercel.com/docs/rest-api), e.g. /v1/integrations/configurations. The team is added. '
          'Read-only.', {
        'path': {'type': 'string', 'description': 'Starts with /, e.g. /v9/projects/my-app/crons.'},
        'query': {'type': 'object', 'description': 'Query parameters as string values.', 'additionalProperties': {'type': 'string', 'description': 'A query value.'}},
      }, required: ['path']),

  // ---- changes -------------------------------------------------------------------
  _vc('vercel_deploy', 'Deploying to Vercel',
      'Publishes files to a live https URL on Vercel as a static site: files of this conversation (an index.html, a folder\'s files, '
          'images…), inline html, or text files written here. Creates the project if it is new. Returns the URL right away; the card follows '
          'the build. Only when the user asked; they approve first.', {
        'name': {'type': 'string', 'description': 'Project name: lowercase letters, digits and hyphens.'},
        'files': {'type': 'array', 'items': {'type': 'string', 'description': 'A file of this conversation.'}, 'description': 'Files of this conversation to publish, at the site\'s root.'},
        'html': {'type': 'string', 'description': 'A whole HTML page to publish as index.html.'},
        'text_files': {
          'type': 'array',
          'description': 'Files written here.',
          'items': {
            'type': 'object',
            'description': 'One file.',
            'properties': {
              'path': {'type': 'string', 'description': 'Path in the site, e.g. about/index.html or styles.css.'},
              'content': {'type': 'string', 'description': 'The file\'s text.'},
            },
            'required': ['path', 'content'],
          },
        },
        'production': {'type': 'boolean', 'description': 'Deploy to production (the project\'s main URL). Default true.'},
      }, required: ['name'], change: true),
  _vc('vercel_redeploy', 'Redeploying',
      'Builds an existing deployment again from the same source (e.g. after changing env vars), as production or preview. They approve first.', {
        'deployment': _vcDeployment,
        'production': {'type': 'boolean', 'description': 'Make the new build production. Default: same target as the original.'},
      }, required: ['deployment'], change: true),
  _vc('vercel_promote', 'Promoting to production',
      'Points a project\'s production domains at an existing deployment without rebuilding. They approve first.', {
        'project': _vcProject,
        'deployment': _vcDeployment,
      }, required: ['project', 'deployment'], change: true),
  _vc('vercel_rollback', 'Rolling back',
      'Instant rollback: production goes back to an earlier deployment. Auto-assigning production stops until the next promote. They approve first.', {
        'project': _vcProject,
        'deployment': {'type': 'string', 'description': 'The earlier deployment to go back to (id or URL).'},
      }, required: ['project', 'deployment'], change: true),
  _vc('vercel_cancel_deployment', 'Cancelling a build', 'Stops a deployment that is still queued or building. They approve first.',
      {'deployment': _vcDeployment}, required: ['deployment'], change: true),
  _vc('vercel_create_project', 'Creating a Vercel project',
      'Creates a project, optionally linked to a GitHub, GitLab or Bitbucket repository so pushes deploy. They approve first.', {
        'name': {'type': 'string', 'description': 'Project name: lowercase letters, digits and hyphens.'},
        'framework': {'type': 'string', 'description': 'Framework preset, e.g. nextjs, vite, sveltekit, astro, remix, nuxtjs. Empty: detected.'},
        'repo': {'type': 'string', 'description': 'Repository as owner/name to link.'},
        'repo_type': {'type': 'string', 'enum': ['github', 'gitlab', 'bitbucket'], 'description': 'Where the repository lives. Default github.'},
        'root_directory': {'type': 'string', 'description': 'Folder in the repository the app is in.'},
      }, required: ['name'], change: true),
  _vc('vercel_update_project', 'Changing project settings',
      'Changes a project\'s build settings or name. Give only what changes. They approve first.', {
        'project': _vcProject,
        'name': {'type': 'string', 'description': 'New project name.'},
        'framework': {'type': 'string', 'description': 'Framework preset, e.g. nextjs.'},
        'build_command': {'type': 'string', 'description': 'Build command, e.g. npm run build.'},
        'install_command': {'type': 'string', 'description': 'Install command, e.g. pnpm install.'},
        'output_directory': {'type': 'string', 'description': 'Output directory, e.g. dist.'},
        'root_directory': {'type': 'string', 'description': 'Folder the app is in.'},
        'node_version': {'type': 'string', 'description': 'Node.js version, e.g. 22.x.'},
        'body_json': {'type': 'string', 'description': 'Any other project fields as a JSON object, merged in.'},
      }, required: ['project'], change: true),
  _vc('vercel_pause_project', 'Pausing or resuming a project',
      'Pauses a project (its deployments stop serving and stop costing) or resumes it. They approve first.', {
        'project': _vcProject,
        'pause': {'type': 'boolean', 'description': 'true pauses, false resumes.'},
      }, required: ['project', 'pause'], change: true),
  _vc('vercel_env_set', 'Setting an environment variable',
      'Adds or replaces an environment variable on a project. Takes effect on the next deployment (redeploy to apply). They approve first.', {
        'project': _vcProject,
        'key': {'type': 'string', 'description': 'Variable name, e.g. DATABASE_URL.'},
        'value': {'type': 'string', 'description': 'Its value.'},
        'targets': _vcTargets,
        'type': {'type': 'string', 'enum': ['encrypted', 'sensitive', 'plain'], 'description': 'sensitive can never be read back. Default encrypted.'},
        'git_branch': {'type': 'string', 'description': 'Only for preview deployments of this branch.'},
        'comment': {'type': 'string', 'description': 'A note shown next to the variable.'},
      }, required: ['project', 'key', 'value'], change: true),
  _vc('vercel_add_domain', 'Adding a domain',
      'Adds a domain to a project, or redirects it to another domain. Returns the DNS records still needed. They approve first.', {
        'project': _vcProject,
        'domain': {'type': 'string', 'description': 'e.g. www.example.com.'},
        'redirect': {'type': 'string', 'description': 'Redirect this domain to that one instead of serving.'},
        'git_branch': {'type': 'string', 'description': 'Serve this branch\'s latest preview instead of production.'},
      }, required: ['project', 'domain'], change: true),
  _vc('vercel_verify_domain', 'Verifying a domain', 'Asks Vercel to check a project domain\'s verification records again.', {
    'project': _vcProject,
    'domain': {'type': 'string', 'description': 'The domain to verify.'},
  }, required: ['project', 'domain'], change: true),
  _vc('vercel_dns_create', 'Adding a Vercel DNS record', 'Adds a DNS record to a domain whose DNS Vercel hosts. They approve first.', {
    'domain': {'type': 'string', 'description': 'The domain, e.g. example.com.'},
    'type': {'type': 'string', 'enum': ['A', 'AAAA', 'ALIAS', 'CAA', 'CNAME', 'HTTPS', 'MX', 'SRV', 'TXT', 'NS'], 'description': 'Record type.'},
    'name': {'type': 'string', 'description': 'Subdomain, e.g. www; empty for the apex.'},
    'value': {'type': 'string', 'description': 'IP address, hostname or text.'},
    'ttl': {'type': 'integer', 'description': 'Seconds, default 60.'},
    'mx_priority': {'type': 'integer', 'description': 'MX priority.'},
    'comment': {'type': 'string', 'description': 'A note on the record.'},
  }, required: ['domain', 'type', 'value'], change: true),
  _vc('vercel_alias_assign', 'Assigning an alias', 'Points a custom domain or *.vercel.app name at a deployment. They approve first.', {
    'deployment': _vcDeployment,
    'alias': {'type': 'string', 'description': 'The alias, e.g. demo.example.com or my-demo.vercel.app.'},
  }, required: ['deployment', 'alias'], change: true),
  _vc('vercel_edge_config_update', 'Changing Edge Config', 'Creates, updates, upserts or deletes items in an Edge Config store. They approve first.', {
    'id': {'type': 'string', 'description': 'Edge Config id (ecfg_…).'},
    'items': {
      'type': 'array',
      'description': 'Changes to apply in order.',
      'items': {
        'type': 'object',
        'description': 'One change.',
        'properties': {
          'operation': {'type': 'string', 'enum': ['create', 'update', 'upsert', 'delete'], 'description': 'What to do.'},
          'key': {'type': 'string', 'description': 'Item key.'},
          'value_json': {'type': 'string', 'description': 'The value as JSON (a string needs quotes). Not for delete.'},
        },
        'required': ['operation', 'key'],
      },
    },
  }, required: ['id', 'items'], change: true),
  _vc('vercel_webhook_create', 'Adding a webhook', 'Creates a webhook that posts events (deployment.created, deployment.succeeded, deployment.error…) to a URL.', {
    'url': {'type': 'string', 'description': 'https:// address that receives the events.'},
    'events': {'type': 'array', 'items': {'type': 'string', 'description': 'An event name, e.g. deployment.error.'}, 'description': 'Events to send.'},
    'projects': {'type': 'array', 'items': {'type': 'string', 'description': 'A project name or id.'}, 'description': 'Only these projects. Empty: all.'},
  }, required: ['url', 'events'], change: true),

  // ---- destructive ---------------------------------------------------------------
  _vc('vercel_delete_deployment', 'Deleting a deployment', 'Deletes a deployment and its URL. Can\'t be undone.', {'deployment': _vcDeployment},
      required: ['deployment'], destructive: true),
  _vc('vercel_delete_project', 'Deleting a project', 'Deletes a project with all its deployments, domains and env vars. Can\'t be undone.', {'project': _vcProject},
      required: ['project'], destructive: true),
  _vc('vercel_env_delete', 'Deleting an environment variable', 'Removes an environment variable (by key, or by id from vercel_env) from a project.', {
    'project': _vcProject,
    'key': {'type': 'string', 'description': 'Variable name, or its id.'},
    'target': {'type': 'string', 'enum': ['production', 'preview', 'development'], 'description': 'When the key exists per environment, only this one.'},
  }, required: ['project', 'key'], destructive: true),
  _vc('vercel_remove_domain', 'Removing a domain', 'Removes a domain from a project, or with no project from the whole account.', {
    'domain': {'type': 'string', 'description': 'The domain to remove.'},
    'project': {'type': 'string', 'description': 'The project to remove it from. Empty removes it from the account.'},
  }, required: ['domain'], destructive: true),
  _vc('vercel_dns_delete', 'Deleting a Vercel DNS record', 'Deletes a DNS record (id from vercel_dns_records). Can take a site or email offline.', {
    'domain': {'type': 'string', 'description': 'The domain.'},
    'record_id': {'type': 'string', 'description': 'Record id from vercel_dns_records.'},
  }, required: ['domain', 'record_id'], destructive: true),
  _vc('vercel_alias_delete', 'Removing an alias', 'Removes an alias so it no longer points at its deployment.', {
    'alias': {'type': 'string', 'description': 'The alias or its id.'},
  }, required: ['alias'], destructive: true),
  _vc('vercel_webhook_delete', 'Deleting a webhook', 'Deletes a webhook by id (from vercel_webhooks).', {
    'id': {'type': 'string', 'description': 'Webhook id.'},
  }, required: ['id'], destructive: true),
  _vc('vercel_api_request', 'Changing something on Vercel',
      'POST, PUT, PATCH or DELETE on any Vercel REST path, with a JSON body written as text, for what the other tools don\'t cover. '
          'The team is added. Always asks first.', {
        'method': {'type': 'string', 'enum': ['POST', 'PUT', 'PATCH', 'DELETE'], 'description': 'HTTP method.'},
        'path': {'type': 'string', 'description': 'Starts with /, e.g. /v1/edge-config.'},
        'body_json': {'type': 'string', 'description': 'Request body as a JSON object.'},
      }, required: ['method', 'path'], destructive: true),
];

final _vercelToolNames = {for (final t in _vercelTools) t.name};

const _vercelPolicies = <String, ToolPolicy>{
  'vercel_account': ToolPolicy(ToolAccess.read),
  'vercel_projects': ToolPolicy(ToolAccess.read),
  'vercel_project': ToolPolicy(ToolAccess.read),
  'vercel_deployments': ToolPolicy(ToolAccess.read),
  'vercel_deployment': ToolPolicy(ToolAccess.read),
  'vercel_build_logs': ToolPolicy(ToolAccess.read),
  'vercel_runtime_logs': ToolPolicy(ToolAccess.read),
  'vercel_deployment_files': ToolPolicy(ToolAccess.read),
  'vercel_env': ToolPolicy(ToolAccess.read),
  'vercel_domains': ToolPolicy(ToolAccess.read),
  'vercel_project_domains': ToolPolicy(ToolAccess.read),
  'vercel_domain_check': ToolPolicy(ToolAccess.read),
  'vercel_dns_records': ToolPolicy(ToolAccess.read),
  'vercel_aliases': ToolPolicy(ToolAccess.read),
  'vercel_usage': ToolPolicy(ToolAccess.read),
  'vercel_team_members': ToolPolicy(ToolAccess.read),
  'vercel_webhooks': ToolPolicy(ToolAccess.read),
  'vercel_edge_config': ToolPolicy(ToolAccess.read),
  'vercel_firewall': ToolPolicy(ToolAccess.read),
  'vercel_checks': ToolPolicy(ToolAccess.read),
  'vercel_api_get': ToolPolicy(ToolAccess.read),
  'vercel_deploy': ToolPolicy(ToolAccess.modify),
  'vercel_redeploy': ToolPolicy(ToolAccess.modify),
  'vercel_promote': ToolPolicy(ToolAccess.modify),
  'vercel_rollback': ToolPolicy(ToolAccess.modify),
  'vercel_cancel_deployment': ToolPolicy(ToolAccess.modify),
  'vercel_create_project': ToolPolicy(ToolAccess.modify),
  'vercel_update_project': ToolPolicy(ToolAccess.modify),
  'vercel_pause_project': ToolPolicy(ToolAccess.modify),
  'vercel_env_set': ToolPolicy(ToolAccess.modify),
  'vercel_add_domain': ToolPolicy(ToolAccess.modify),
  'vercel_verify_domain': ToolPolicy(ToolAccess.modify),
  'vercel_dns_create': ToolPolicy(ToolAccess.modify),
  'vercel_alias_assign': ToolPolicy(ToolAccess.modify),
  'vercel_edge_config_update': ToolPolicy(ToolAccess.modify),
  'vercel_webhook_create': ToolPolicy(ToolAccess.modify),
  'vercel_delete_deployment': ToolPolicy(ToolAccess.destructive),
  'vercel_delete_project': ToolPolicy(ToolAccess.destructive),
  'vercel_env_delete': ToolPolicy(ToolAccess.destructive),
  'vercel_remove_domain': ToolPolicy(ToolAccess.destructive),
  'vercel_dns_delete': ToolPolicy(ToolAccess.destructive),
  'vercel_alias_delete': ToolPolicy(ToolAccess.destructive),
  'vercel_webhook_delete': ToolPolicy(ToolAccess.destructive),
  'vercel_api_request': ToolPolicy(ToolAccess.destructive),
};

const _vcDeploymentFields = ['id', 'url', 'name', 'state', 'target', 'created', 'ready', 'branch', 'commit', 'creator', 'aliases', 'inspector_url', 'error'];

const _vercelReferences = <String, ToolReference>{
  'vercel_account': ToolReference(['dev', 'user: username, name, email', 'teams', 'team']),
  'vercel_projects': ToolReference(['dev', 'projects: id, name, framework, repo, production_url, latest', 'more']),
  'vercel_project': ToolReference(['dev', 'project', 'domains', 'deployments', 'crons'], limits: ['Recent deployments: up to 8.']),
  'vercel_deployments': ToolReference(['dev', 'deployments', ..._vcDeploymentFields], limits: ['Up to 100 per call.']),
  'vercel_deployment': ToolReference(['dev', 'deployment', ..._vcDeploymentFields]),
  'vercel_build_logs': ToolReference(['dev', 'deployment', 'state', 'lines: at, type, text'], limits: ['Up to 1000 lines, the latest ones.']),
  'vercel_runtime_logs': ToolReference(['dev', 'deployment', 'lines: at, level, status, path, text'], limits: ['Collects for up to 20 seconds; quiet sites may return nothing.']),
  'vercel_deployment_files': ToolReference(['dev', 'deployment', 'files: path, size, type']),
  'vercel_env': ToolReference(['dev', 'project', 'env: id, key, targets, type, branch, value (when revealed)']),
  'vercel_domains': ToolReference(['dev', 'domains', 'domain', 'config']),
  'vercel_project_domains': ToolReference(['dev', 'project', 'domains: name, verified, redirect, git_branch, verification']),
  'vercel_domain_check': ToolReference(['dev', 'domain', 'available', 'price', 'period']),
  'vercel_dns_records': ToolReference(['dev', 'domain', 'dns_records: id, type, name, value, ttl']),
  'vercel_aliases': ToolReference(['dev', 'aliases: alias, deployment, created']),
  'vercel_usage': ToolReference(['dev', 'days', 'total', 'currency', 'by_service', 'by_day'], limits: ['From Vercel\'s billing data (FOCUS); usage on Hobby plans may be empty.']),
  'vercel_team_members': ToolReference(['dev', 'members: name, username, email, role, joined']),
  'vercel_webhooks': ToolReference(['dev', 'webhooks: id, url, events, projects']),
  'vercel_edge_config': ToolReference(['dev', 'edge_configs', 'items']),
  'vercel_firewall': ToolReference(['dev', 'project', 'firewall']),
  'vercel_checks': ToolReference(['dev', 'deployment', 'checks: name, status, conclusion']),
  'vercel_api_get': ToolReference(['dev', 'path', 'result'], limits: ['Long answers are cut at about 14,000 characters.']),
  'vercel_deploy': ToolReference(['dev', 'done', 'deployment', 'url', 'files', 'bytes'], limits: ['Static files only (no build step). Up to 200 files and 100 MB.']),
  'vercel_redeploy': ToolReference(['dev', 'done', 'deployment']),
  'vercel_promote': ToolReference(['dev', 'done', 'project', 'deployment']),
  'vercel_rollback': ToolReference(['dev', 'done', 'project', 'deployment']),
  'vercel_cancel_deployment': ToolReference(['dev', 'done', 'deployment']),
  'vercel_create_project': ToolReference(['dev', 'done', 'project']),
  'vercel_update_project': ToolReference(['dev', 'done', 'project']),
  'vercel_pause_project': ToolReference(['dev', 'done', 'paused']),
  'vercel_env_set': ToolReference(['dev', 'done', 'key', 'targets']),
  'vercel_add_domain': ToolReference(['dev', 'done', 'domain', 'verified', 'verification']),
  'vercel_verify_domain': ToolReference(['dev', 'done', 'domain', 'verified']),
  'vercel_dns_create': ToolReference(['dev', 'done', 'record_id']),
  'vercel_alias_assign': ToolReference(['dev', 'done', 'alias']),
  'vercel_edge_config_update': ToolReference(['dev', 'done', 'changed']),
  'vercel_webhook_create': ToolReference(['dev', 'done', 'webhook', 'secret (shown once)']),
  'vercel_delete_deployment': ToolReference(['dev', 'deleted']),
  'vercel_delete_project': ToolReference(['dev', 'deleted']),
  'vercel_env_delete': ToolReference(['dev', 'deleted']),
  'vercel_remove_domain': ToolReference(['dev', 'deleted']),
  'vercel_dns_delete': ToolReference(['dev', 'deleted']),
  'vercel_alias_delete': ToolReference(['dev', 'deleted']),
  'vercel_webhook_delete': ToolReference(['dev', 'deleted']),
  'vercel_api_request': ToolReference(['dev', 'done', 'result']),
};

// ---- shapes the cards and the model read ---------------------------------------------

String? _vcIso(Object? ms) {
  if (ms is! num || ms <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(ms.toInt(), isUtc: true).toIso8601String();
}

Map<String, dynamic> vercelDeploymentSummary(Map d) {
  final meta = d['meta'] is Map ? d['meta'] as Map : const {};
  final creator = d['creator'] is Map ? d['creator'] as Map : const {};
  final url = '${d['url'] ?? ''}';
  final aliases = d['alias'] is List ? [for (final a in d['alias'] as List) '$a'] : const <String>[];
  return {
    'id': d['uid'] ?? d['id'],
    'name': d['name'],
    'url': url.isEmpty ? null : 'https://$url',
    'state': d['readyState'] ?? d['state'] ?? d['status'],
    'target': d['target'] ?? 'preview',
    'created': _vcIso(d['createdAt'] ?? d['created']),
    'building_at': ?_vcIso(d['buildingAt']),
    'ready': ?_vcIso(d['ready']),
    'branch': ?(meta['githubCommitRef'] ?? meta['gitlabCommitRef'] ?? meta['bitbucketCommitRef']),
    'commit': ?(meta['githubCommitMessage'] ?? meta['gitlabCommitMessage'] ?? meta['bitbucketCommitMessage']),
    'sha': ?((meta['githubCommitSha'] ?? meta['gitlabCommitSha'] ?? meta['bitbucketCommitSha']) as String?)?.substring(0, 7),
    'repo': ?(meta['githubRepo'] == null ? null : '${meta['githubOrg'] ?? meta['githubCommitOrg'] ?? ''}/${meta['githubRepo']}'),
    'creator': creator['username'] ?? creator['email'],
    'source': ?d['source'],
    if (aliases.isNotEmpty) 'aliases': aliases,
    'inspector_url': ?d['inspectorUrl'],
    'error': ?(d['errorMessage'] ?? d['errorCode']),
    'project_id': ?d['projectId'],
  };
}

Map<String, dynamic> _vcProjectSummary(Map p) {
  final link = p['link'] is Map ? p['link'] as Map : const {};
  final latest = p['latestDeployments'] is List && (p['latestDeployments'] as List).isNotEmpty ? (p['latestDeployments'] as List).first as Map : null;
  final prod = (p['targets'] is Map ? (p['targets'] as Map)['production'] : null) as Map?;
  final prodAlias = prod?['alias'] is List && (prod!['alias'] as List).isNotEmpty ? '${(prod['alias'] as List).first}' : null;
  return {
    'id': p['id'],
    'name': p['name'],
    'framework': p['framework'],
    'repo': ?(link['repo'] == null ? null : '${link['org'] ?? link['owner'] ?? link['projectNamespace'] ?? ''}/${link['repo']}'.replaceFirst(RegExp(r'^/'), '')),
    'repo_type': ?link['type'],
    'production_branch': ?link['productionBranch'],
    'production_url': ?(prodAlias == null ? null : 'https://$prodAlias'),
    'updated': _vcIso(p['updatedAt']),
    'paused': ?(p['paused'] == true ? true : null),
    'node_version': ?p['nodeVersion'],
    if (latest != null) 'latest': vercelDeploymentSummary(latest),
  };
}

extension _VercelToolRuns on TelegramToolRunner {
  Future<ToolOutput>? _runVercel(String name, Map<String, dynamic> a) {
    if (!_vercelToolNames.contains(name)) return null;
    return _vercel(name, a);
  }

  String _va(Map<String, dynamic> a, String k) => '${a[k] ?? ''}'.trim();

  Future<String> _vcProjectId(VercelApi api, String ref) async {
    if (ref.isEmpty) throw const DevApiException('vercel', 'Which project? Give its name or id.');
    if (ref.startsWith('prj_')) return ref;
    final p = await api.call('GET', '/v9/projects/${Uri.encodeComponent(ref)}');
    return '${(p as Map)['id']}';
  }

  Future<Map> _vcDeploymentRaw(VercelApi api, String ref) async {
    if (ref.isEmpty) throw const DevApiException('vercel', 'Which deployment? Give its id or URL.');
    final clean = ref.replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'/.*$'), '');
    return await api.call('GET', '/v13/deployments/${Uri.encodeComponent(clean)}') as Map;
  }

  Future<ToolOutput> _vercel(String name, Map<String, dynamic> a) async {
    if (!_settings.hasVercelToken) {
      return const ToolOutput({'error': 'No Vercel token. The user can add one in Settings → Development → Vercel.'});
    }
    final api = VercelApi(token: _settings.vercelToken, teamId: _settings.vercelTeamId);
    int n(String k, int fallback, int max, {int min = 1}) => TelegramToolRunner._int(a, k, fallback: fallback, min: min, max: max);
    Map<String, dynamic> out(Map<String, dynamic> m) => {'dev': 'vercel', ...m};
    try {
      switch (name) {
        case 'vercel_account':
          final user = await api.call('GET', '/v2/user') as Map;
          final u = user['user'] as Map? ?? user;
          List teams = const [];
          try {
            final t = await api.call('GET', '/v2/teams', query: {'limit': '50'});
            teams = (t as Map)['teams'] as List? ?? const [];
          } catch (_) {}
          return ToolOutput(out({
            'user': {
              'username': u['username'],
              'name': u['name'],
              'email': u['email'],
              'avatar': u['avatar'] == null ? null : 'https://vercel.com/api/www/avatar/${u['avatar']}',
              'plan': (u['billing'] as Map?)?['plan'] ?? u['softBlock'],
            },
            'teams': [
              for (final t in teams.whereType<Map>()) {'id': t['id'], 'slug': t['slug'], 'name': t['name'], 'role': (t['membership'] as Map?)?['role']},
            ],
            'team': _settings.vercelTeamId.isEmpty ? 'personal account' : _settings.vercelTeamId,
          }));
        case 'vercel_projects':
          final r = await api.call('GET', '/v9/projects', query: {
            'limit': '${n('limit', 30, 100)}',
            if (_va(a, 'search').isNotEmpty) 'search': _va(a, 'search'),
          }) as Map;
          final projects = [for (final p in (r['projects'] as List? ?? const []).whereType<Map>()) _vcProjectSummary(p)];
          return ToolOutput(out({'projects': projects, if ((r['pagination'] as Map?)?['next'] != null) 'more': true}));
        case 'vercel_project':
          final ref = _va(a, 'project');
          final p = await api.call('GET', '/v9/projects/${Uri.encodeComponent(ref)}') as Map;
          final id = '${p['id']}';
          final results = await Future.wait([
            api.call('GET', '/v9/projects/$id/domains', query: {'limit': '50'}).then<Object?>((v) => v).catchError((_) => null),
            api.call('GET', '/v6/deployments', query: {'projectId': id, 'limit': '8'}).then<Object?>((v) => v).catchError((_) => null),
          ]);
          final domains = results[0] is Map ? ((results[0] as Map)['domains'] as List? ?? const []) : const [];
          final deps = results[1] is Map ? ((results[1] as Map)['deployments'] as List? ?? const []) : const [];
          final crons = p['crons'] is Map ? ((p['crons'] as Map)['definitions'] as List? ?? const []) : const [];
          return ToolOutput(out({
            'project': {
              ..._vcProjectSummary(p),
              'build_command': p['buildCommand'],
              'install_command': p['installCommand'],
              'output_directory': p['outputDirectory'],
              'root_directory': p['rootDirectory'],
              'dev_command': p['devCommand'],
              'created': _vcIso(p['createdAt']),
              'serverless_region': p['serverlessFunctionRegion'],
              'skew_protection': ?p['skewProtectionMaxAge'],
            },
            'domains': [
              for (final d in domains.whereType<Map>())
                {'name': d['name'], 'verified': d['verified'], 'redirect': ?d['redirect'], 'git_branch': ?d['gitBranch']},
            ],
            'deployments': [for (final d in deps.whereType<Map>()) vercelDeploymentSummary(d)],
            if (crons.isNotEmpty) 'crons': [for (final c in crons.whereType<Map>()) {'path': c['path'], 'schedule': c['schedule']}],
          }));
        case 'vercel_deployments':
          final project = _va(a, 'project');
          final since = a['since_hours'] is num ? DateTime.now().subtract(Duration(minutes: ((a['since_hours'] as num) * 60).round())).millisecondsSinceEpoch : null;
          final r = await api.call('GET', '/v6/deployments', query: {
            'limit': '${n('limit', 20, 100)}',
            if (project.isNotEmpty) 'projectId': await _vcProjectId(api, project),
            if (_va(a, 'target').isNotEmpty) 'target': _va(a, 'target'),
            if (_va(a, 'state').isNotEmpty) 'state': _va(a, 'state'),
            'since': ?since?.toString(),
          }) as Map;
          return ToolOutput(out({
            'project': ?(project.isEmpty ? null : project),
            'deployments': [for (final d in (r['deployments'] as List? ?? const []).whereType<Map>()) vercelDeploymentSummary(d)],
          }));
        case 'vercel_deployment':
          final d = await _vcDeploymentRaw(api, _va(a, 'deployment'));
          return ToolOutput(out({'deployment': vercelDeploymentSummary(d)}));
        case 'vercel_build_logs':
          final d = await _vcDeploymentRaw(api, _va(a, 'deployment'));
          final id = '${d['id'] ?? d['uid']}';
          final events = await api.events(id, limit: n('limit', 300, 1000));
          final errorsOnly = a['errors_only'] == true;
          final lines = <Map<String, dynamic>>[];
          for (final e in events) {
            final p = e['payload'] is Map ? e['payload'] as Map : e;
            final text = '${p['text'] ?? e['text'] ?? ''}'.trimRight();
            if (text.isEmpty) continue;
            final type = '${e['type'] ?? ''}';
            final bad = type == 'stderr' || RegExp(r'\b(error|failed|err!|warn(ing)?)\b', caseSensitive: false).hasMatch(text);
            if (errorsOnly && !bad) continue;
            lines.add({'at': _vcIso(e['created'] ?? p['date']), 'type': bad && type != 'stderr' ? 'warning' : type, 'text': TelegramToolRunner._clip(text, 600)});
          }
          return ToolOutput(out({'deployment': vercelDeploymentSummary(d), 'state': d['readyState'], 'lines': lines}));
        case 'vercel_runtime_logs':
          final projectId = await _vcProjectId(api, _va(a, 'project'));
          var dep = _va(a, 'deployment');
          if (dep.isEmpty) {
            final r = await api.call('GET', '/v6/deployments', query: {'projectId': projectId, 'target': 'production', 'state': 'READY', 'limit': '1'}) as Map;
            final list = r['deployments'] as List? ?? const [];
            if (list.isEmpty) return ToolOutput(out({'error': 'This project has no ready production deployment.'}));
            dep = '${(list.first as Map)['uid']}';
          } else if (!dep.startsWith('dpl_')) {
            dep = '${(await _vcDeploymentRaw(api, dep))['id']}';
          }
          final lines = await _vcRuntimeLogs(api, projectId, dep, seconds: n('seconds', 6, 20, min: 2), limit: n('limit', 150, 500));
          return ToolOutput(out({'deployment': dep, 'lines': lines, if (lines.isEmpty) 'note': 'No requests reached it while listening.'}));
        case 'vercel_deployment_files':
          final d = await _vcDeploymentRaw(api, _va(a, 'deployment'));
          final r = await api.call('GET', '/v6/deployments/${d['id']}/files');
          final files = <Map<String, dynamic>>[];
          void walk(Object? nodes, String prefix) {
            for (final f in (nodes as List? ?? const []).whereType<Map>()) {
              final path = prefix.isEmpty ? '${f['name']}' : '$prefix/${f['name']}';
              if (f['type'] == 'directory') {
                walk(f['children'], path);
              } else if (files.length < 400) {
                files.add({'path': path, 'type': f['type'], 'size': ?f['size'], 'uid': ?f['uid']});
              }
            }
          }
          walk(r, '');
          return ToolOutput(out({'deployment': vercelDeploymentSummary(d), 'files': files}));
        case 'vercel_env':
          final id = await _vcProjectId(api, _va(a, 'project'));
          final reveal = a['reveal'] == true;
          final r = await api.call('GET', '/v10/projects/$id/env', query: {if (reveal) 'decrypt': 'true'}) as Map;
          final target = _va(a, 'target');
          return ToolOutput(out({
            'project': _va(a, 'project'),
            'project_id': id,
            'env': [
              for (final e in (r['envs'] as List? ?? const []).whereType<Map>())
                if (target.isEmpty || ((e['target'] as List?) ?? const []).contains(target))
                  {
                    'id': e['id'],
                    'key': e['key'],
                    'targets': e['target'],
                    'type': e['type'],
                    'branch': ?e['gitBranch'],
                    'comment': ?e['comment'],
                    'updated': _vcIso(e['updatedAt']),
                    if (reveal && e['type'] != 'sensitive') 'value': e['value'],
                  },
            ],
          }));
        case 'vercel_domains':
          final domain = _va(a, 'domain');
          if (domain.isNotEmpty) {
            final results = await Future.wait([
              api.call('GET', '/v5/domains/${Uri.encodeComponent(domain)}').then<Object?>((v) => v).catchError((Object e) => {'error': '$e'}),
              api.call('GET', '/v6/domains/${Uri.encodeComponent(domain)}/config').then<Object?>((v) => v).catchError((Object e) => {'error': '$e'}),
            ]);
            final d = (results[0] as Map)['domain'] as Map? ?? results[0] as Map;
            return ToolOutput(out({'domain': _vcDomain(d), 'config': results[1]}));
          }
          final r = await api.call('GET', '/v5/domains', query: {'limit': '100'}) as Map;
          return ToolOutput(out({'domains': [for (final d in (r['domains'] as List? ?? const []).whereType<Map>()) _vcDomain(d)]}));
        case 'vercel_project_domains':
          final id = await _vcProjectId(api, _va(a, 'project'));
          final r = await api.call('GET', '/v9/projects/$id/domains', query: {'limit': '100'}) as Map;
          return ToolOutput(out({
            'project': _va(a, 'project'),
            'domains': [
              for (final d in (r['domains'] as List? ?? const []).whereType<Map>())
                {
                  'name': d['name'],
                  'verified': d['verified'],
                  'redirect': ?d['redirect'],
                  'git_branch': ?d['gitBranch'],
                  if (d['verification'] is List && (d['verification'] as List).isNotEmpty) 'verification': d['verification'],
                },
            ],
          }));
        case 'vercel_domain_check':
          final domain = Uri.encodeComponent(_va(a, 'domain'));
          Object? avail;
          Object? price;
          try {
            avail = await api.call('GET', '/v4/domains/status', query: {'name': _va(a, 'domain')});
          } catch (e) {
            avail = {'error': '$e'};
          }
          try {
            price = await api.call('GET', '/v4/domains/price', query: {'name': _va(a, 'domain')});
          } catch (e) {
            try {
              price = await api.call('GET', '/v1/registrar/domains/$domain/price');
            } catch (_) {
              price = {'error': '$e'};
            }
          }
          return ToolOutput(out({
            'domain': _va(a, 'domain'),
            'available': ?(avail is Map ? avail['available'] : null),
            'price': ?(price is Map ? (price['price'] ?? price['purchasePrice']) : null),
            'period': ?(price is Map ? price['period'] ?? price['years'] : null),
            if (avail is Map && avail['error'] != null) 'problem': avail['error'],
          }));
        case 'vercel_dns_records':
          final r = await api.call('GET', '/v4/domains/${Uri.encodeComponent(_va(a, 'domain'))}/records', query: {'limit': '100'}) as Map;
          return ToolOutput(out({
            'domain': _va(a, 'domain'),
            'dns_records': [
              for (final d in (r['records'] as List? ?? const []).whereType<Map>())
                {'id': d['id'], 'type': d['type'], 'name': d['name'], 'value': d['value'], 'ttl': d['ttl'], 'mx_priority': ?d['mxPriority'], 'comment': ?d['comment']},
            ],
          }));
        case 'vercel_aliases':
          final dep = _va(a, 'deployment');
          final project = _va(a, 'project');
          final Map r;
          if (dep.isNotEmpty) {
            final d = await _vcDeploymentRaw(api, dep);
            r = await api.call('GET', '/v2/deployments/${d['id']}/aliases') as Map;
          } else {
            r = await api.call('GET', '/v4/aliases', query: {
              'limit': '${n('limit', 40, 100)}',
              if (project.isNotEmpty) 'projectId': await _vcProjectId(api, project),
            }) as Map;
          }
          return ToolOutput(out({
            'aliases': [
              for (final x in (r['aliases'] as List? ?? const []).whereType<Map>())
                {'id': x['uid'], 'alias': x['alias'], 'deployment': x['deploymentId'] ?? (x['deployment'] as Map?)?['id'], 'url': ?(x['deployment'] as Map?)?['url'], 'created': _vcIso(x['createdAt'] ?? x['created'])},
            ],
          }));
        case 'vercel_usage':
          final days = n('days', 30, 90);
          final to = DateTime.now().toUtc();
          final from = to.subtract(Duration(days: days));
          final raw = await api.call('GET', '/v1/billing/charges', query: {'from': from.toIso8601String(), 'to': to.toIso8601String()});
          return ToolOutput(out({'days': days, ..._vcCharges(raw)}));
        case 'vercel_team_members':
          if (_settings.vercelTeamId.isEmpty) return ToolOutput(out({'error': 'No team set. Pick a team in Settings → Development → Vercel.'}));
          final r = await api.call('GET', '/v2/teams/${_settings.vercelTeamId}/members', query: {'limit': '100'}) as Map;
          return ToolOutput(out({
            'members': [
              for (final m in (r['members'] as List? ?? const []).whereType<Map>())
                {'name': m['name'], 'username': m['username'], 'email': m['email'], 'role': m['role'], 'joined': _vcIso(m['joinedFrom'] is Map ? (m['joinedFrom'] as Map)['dsyncConnectedAt'] : m['createdAt'] ?? m['accessRequestedAt'])},
            ],
          }));
        case 'vercel_webhooks':
          final r = await api.call('GET', '/v1/webhooks');
          return ToolOutput(out({
            'webhooks': [
              for (final w in (r is List ? r : const []).whereType<Map>()) {'id': w['id'], 'url': w['url'], 'events': w['events'], 'projects': w['projectIds'] ?? 'all', 'created': _vcIso(w['createdAt'])},
            ],
          }));
        case 'vercel_edge_config':
          final id = _va(a, 'id');
          if (id.isEmpty) {
            final r = await api.call('GET', '/v1/edge-config');
            return ToolOutput(out({
              'edge_configs': [
                for (final e in (r is List ? r : const []).whereType<Map>()) {'id': e['id'], 'slug': e['slug'], 'items': e['itemCount'], 'size': e['sizeInBytes'], 'updated': _vcIso(e['updatedAt'])},
              ],
            }));
          }
          final r = await api.call('GET', '/v1/edge-config/$id/items');
          return ToolOutput(out({
            'id': id,
            'items': [for (final i in (r is List ? r : const []).whereType<Map>()) {'key': i['key'], 'value': i['value'], 'updated': _vcIso(i['updatedAt'])}],
          }));
        case 'vercel_firewall':
          final id = await _vcProjectId(api, _va(a, 'project'));
          final r = await api.call('GET', '/v1/security/firewall/config/active', query: {'projectId': id});
          final text = jsonEncode(r);
          return ToolOutput(out({'project': _va(a, 'project'), 'firewall': text.length > 12000 ? '${text.substring(0, 12000)}…' : r}));
        case 'vercel_checks':
          final d = await _vcDeploymentRaw(api, _va(a, 'deployment'));
          final r = await api.call('GET', '/v1/deployments/${d['id']}/checks') as Map;
          return ToolOutput(out({
            'deployment': vercelDeploymentSummary(d),
            'checks': [
              for (final c in (r['checks'] as List? ?? const []).whereType<Map>())
                {'id': c['id'], 'name': c['name'], 'status': c['status'], 'conclusion': c['conclusion'], 'blocking': c['blocking'], 'url': ?c['detailsUrl']},
            ],
          }));
        case 'vercel_api_get':
          final q = a['query'] is Map ? {for (final e in (a['query'] as Map).entries) '${e.key}': '${e.value}'} : null;
          final r = await api.call('GET', _va(a, 'path'), query: q);
          final text = r is String ? r : jsonEncode(r);
          return ToolOutput(out({'path': _va(a, 'path'), 'result': text.length > 14000 ? '${text.substring(0, 14000)}…' : r}), full: r);

        // ---- changes ---------------------------------------------------------------
        case 'vercel_deploy':
          return await _vcDeploy(api, a);
        case 'vercel_redeploy':
          final d = await _vcDeploymentRaw(api, _va(a, 'deployment'));
          final production = a['production'] is bool ? a['production'] as bool : d['target'] == 'production';
          final r = await api.call('POST', '/v13/deployments', query: {'forceNew': '1'}, body: {
            'name': d['name'],
            'deploymentId': d['id'],
            if (production) 'target': 'production',
          }) as Map;
          return ToolOutput(out({'done': true, 'deployment': vercelDeploymentSummary(r)}));
        case 'vercel_promote':
          final id = await _vcProjectId(api, _va(a, 'project'));
          final d = await _vcDeploymentRaw(api, _va(a, 'deployment'));
          await api.call('POST', '/v10/projects/$id/promote/${d['id']}');
          return ToolOutput(out({'done': true, 'project': _va(a, 'project'), 'deployment': vercelDeploymentSummary(d)}));
        case 'vercel_rollback':
          final id = await _vcProjectId(api, _va(a, 'project'));
          final d = await _vcDeploymentRaw(api, _va(a, 'deployment'));
          await api.call('POST', '/v9/projects/$id/rollback/${d['id']}');
          return ToolOutput(out({'done': true, 'project': _va(a, 'project'), 'deployment': vercelDeploymentSummary(d)}));
        case 'vercel_cancel_deployment':
          final d = await _vcDeploymentRaw(api, _va(a, 'deployment'));
          final r = await api.call('PATCH', '/v12/deployments/${d['id']}/cancel') as Map;
          return ToolOutput(out({'done': true, 'deployment': vercelDeploymentSummary(r)}));
        case 'vercel_create_project':
          final repo = _va(a, 'repo');
          final r = await api.call('POST', '/v11/projects', body: {
            'name': _va(a, 'name'),
            if (_va(a, 'framework').isNotEmpty) 'framework': _va(a, 'framework'),
            if (_va(a, 'root_directory').isNotEmpty) 'rootDirectory': _va(a, 'root_directory'),
            if (repo.isNotEmpty) 'gitRepository': {'type': _va(a, 'repo_type').isEmpty ? 'github' : _va(a, 'repo_type'), 'repo': repo},
          }) as Map;
          return ToolOutput(out({'done': true, 'project': _vcProjectSummary(r)}));
        case 'vercel_update_project':
          final id = await _vcProjectId(api, _va(a, 'project'));
          final extra = _va(a, 'body_json').isEmpty ? null : _tryJson(_va(a, 'body_json'));
          if (_va(a, 'body_json').isNotEmpty && extra is! Map) return ToolOutput(out({'error': 'body_json is not a JSON object.'}));
          final body = {
            for (final (k, f) in const [
              ('name', 'name'),
              ('framework', 'framework'),
              ('build_command', 'buildCommand'),
              ('install_command', 'installCommand'),
              ('output_directory', 'outputDirectory'),
              ('root_directory', 'rootDirectory'),
              ('node_version', 'nodeVersion'),
            ])
              if (a[k] != null) f: _va(a, k).isEmpty ? null : _va(a, k),
            ...?(extra as Map?)?.cast<String, dynamic>(),
          };
          if (body.isEmpty) return ToolOutput(out({'error': 'Nothing to change.'}));
          final r = await api.call('PATCH', '/v9/projects/$id', body: body) as Map;
          return ToolOutput(out({'done': true, 'project': _vcProjectSummary(r), 'changed': body.keys.toList()}));
        case 'vercel_pause_project':
          final id = await _vcProjectId(api, _va(a, 'project'));
          final pause = a['pause'] != false;
          await api.call('POST', '/v1/projects/$id/${pause ? 'pause' : 'unpause'}');
          return ToolOutput(out({'done': true, 'project': _va(a, 'project'), 'paused': pause}));
        case 'vercel_env_set':
          final id = await _vcProjectId(api, _va(a, 'project'));
          final targets = [for (final t in (a['targets'] as List? ?? const ['production', 'preview', 'development'])) '$t'];
          await api.call('POST', '/v10/projects/$id/env', query: {'upsert': 'true'}, body: {
            'key': _va(a, 'key'),
            'value': '${a['value'] ?? ''}',
            'type': _va(a, 'type').isEmpty ? 'encrypted' : _va(a, 'type'),
            'target': targets,
            if (_va(a, 'git_branch').isNotEmpty) 'gitBranch': _va(a, 'git_branch'),
            if (_va(a, 'comment').isNotEmpty) 'comment': _va(a, 'comment'),
          });
          return ToolOutput(out({'done': true, 'key': _va(a, 'key'), 'targets': targets, 'note': 'Redeploy for it to take effect.'}));
        case 'vercel_add_domain':
          final id = await _vcProjectId(api, _va(a, 'project'));
          final r = await api.call('POST', '/v10/projects/$id/domains', body: {
            'name': _va(a, 'domain'),
            if (_va(a, 'redirect').isNotEmpty) 'redirect': _va(a, 'redirect'),
            if (_va(a, 'git_branch').isNotEmpty) 'gitBranch': _va(a, 'git_branch'),
          }) as Map;
          return ToolOutput(out({'done': true, 'domain': r['name'], 'verified': r['verified'], 'verification': ?r['verification']}));
        case 'vercel_verify_domain':
          final id = await _vcProjectId(api, _va(a, 'project'));
          final r = await api.call('POST', '/v9/projects/$id/domains/${Uri.encodeComponent(_va(a, 'domain'))}/verify') as Map;
          return ToolOutput(out({'done': true, 'domain': r['name'], 'verified': r['verified'], 'verification': ?r['verification']}));
        case 'vercel_dns_create':
          final r = await api.call('POST', '/v2/domains/${Uri.encodeComponent(_va(a, 'domain'))}/records', body: {
            'type': _va(a, 'type').toUpperCase(),
            'name': _va(a, 'name'),
            'value': _va(a, 'value'),
            'ttl': n('ttl', 60, 604800, min: 60),
            if (a['mx_priority'] is num) 'mxPriority': (a['mx_priority'] as num).toInt(),
            if (_va(a, 'comment').isNotEmpty) 'comment': _va(a, 'comment'),
          }) as Map;
          return ToolOutput(out({'done': true, 'record_id': r['uid'] ?? r['id']}));
        case 'vercel_alias_assign':
          final d = await _vcDeploymentRaw(api, _va(a, 'deployment'));
          final r = await api.call('POST', '/v2/deployments/${d['id']}/aliases', body: {'alias': _va(a, 'alias')}) as Map;
          return ToolOutput(out({'done': true, 'alias': r['alias'] ?? _va(a, 'alias')}));
        case 'vercel_edge_config_update':
          final items = <Map<String, dynamic>>[];
          for (final i in (a['items'] as List? ?? const []).whereType<Map>()) {
            final op = '${i['operation']}';
            final raw = '${i['value_json'] ?? ''}'.trim();
            final value = raw.isEmpty ? null : (_tryJson(raw) ?? raw);
            items.add({'operation': op, 'key': '${i['key']}', if (op != 'delete') 'value': value});
          }
          await api.call('PATCH', '/v1/edge-config/${_va(a, 'id')}/items', body: {'items': items});
          return ToolOutput(out({'done': true, 'changed': [for (final i in items) '${i['operation']} ${i['key']}']}));
        case 'vercel_webhook_create':
          final ids = <String>[for (final p in (a['projects'] as List? ?? const [])) await _vcProjectId(api, '$p')];
          final r = await api.call('POST', '/v1/webhooks', body: {
            'url': _va(a, 'url'),
            'events': [for (final e in (a['events'] as List? ?? const [])) '$e'],
            if (ids.isNotEmpty) 'projectIds': ids,
          }) as Map;
          return ToolOutput(out({'done': true, 'webhook': {'id': r['id'], 'url': r['url'], 'events': r['events']}, 'secret': ?r['secret']}));

        // ---- destructive -----------------------------------------------------------
        case 'vercel_delete_deployment':
          final d = await _vcDeploymentRaw(api, _va(a, 'deployment'));
          await api.call('DELETE', '/v13/deployments/${d['id']}');
          return ToolOutput(out({'deleted': d['url'] ?? d['id']}));
        case 'vercel_delete_project':
          final id = await _vcProjectId(api, _va(a, 'project'));
          await api.call('DELETE', '/v9/projects/$id');
          return ToolOutput(out({'deleted': _va(a, 'project')}));
        case 'vercel_env_delete':
          final id = await _vcProjectId(api, _va(a, 'project'));
          final key = _va(a, 'key');
          final r = await api.call('GET', '/v10/projects/$id/env') as Map;
          final target = _va(a, 'target');
          final matches = [
            for (final e in (r['envs'] as List? ?? const []).whereType<Map>())
              if ((e['id'] == key || e['key'] == key) && (target.isEmpty || ((e['target'] as List?) ?? const []).contains(target))) e,
          ];
          if (matches.isEmpty) return ToolOutput(out({'error': 'No variable "$key" on this project.'}));
          for (final e in matches) {
            await api.call('DELETE', '/v9/projects/$id/env/${e['id']}');
          }
          return ToolOutput(out({'deleted': key, 'count': matches.length}));
        case 'vercel_remove_domain':
          final domain = Uri.encodeComponent(_va(a, 'domain'));
          if (_va(a, 'project').isNotEmpty) {
            final id = await _vcProjectId(api, _va(a, 'project'));
            await api.call('DELETE', '/v9/projects/$id/domains/$domain');
          } else {
            await api.call('DELETE', '/v6/domains/$domain');
          }
          return ToolOutput(out({'deleted': _va(a, 'domain')}));
        case 'vercel_dns_delete':
          await api.call('DELETE', '/v2/domains/${Uri.encodeComponent(_va(a, 'domain'))}/records/${_va(a, 'record_id')}');
          return ToolOutput(out({'deleted': _va(a, 'record_id')}));
        case 'vercel_alias_delete':
          await api.call('DELETE', '/v2/aliases/${Uri.encodeComponent(_va(a, 'alias'))}');
          return ToolOutput(out({'deleted': _va(a, 'alias')}));
        case 'vercel_webhook_delete':
          await api.call('DELETE', '/v1/webhooks/${_va(a, 'id')}');
          return ToolOutput(out({'deleted': _va(a, 'id')}));
        case 'vercel_api_request':
          final raw = _va(a, 'body_json');
          final body = raw.isEmpty ? null : _tryJson(raw);
          if (raw.isNotEmpty && body == null) return ToolOutput(out({'error': 'body_json is not valid JSON.'}));
          final r = await api.call(_va(a, 'method').toUpperCase(), _va(a, 'path'), body: body);
          final text = r is String ? r : jsonEncode(r);
          return ToolOutput(out({'done': true, 'result': text.length > 10000 ? '${text.substring(0, 10000)}…' : r}), full: r);
      }
    } on DevApiException catch (e) {
      return ToolOutput({'dev': 'vercel', 'error': 'Vercel: ${e.message}'});
    } on TimeoutException {
      return const ToolOutput({'dev': 'vercel', 'error': 'Vercel didn\'t answer in time.'});
    } on SocketException catch (e) {
      return ToolOutput({'dev': 'vercel', 'error': 'Couldn\'t reach Vercel: ${e.message}'});
    } finally {
      api.close();
    }
    return ToolOutput({'error': 'Unknown tool $name'});
  }

  Map<String, dynamic> _vcDomain(Map d) => {
    'name': d['name'],
    'verified': d['verified'],
    'service_type': d['serviceType'],
    'registrar': ?(d['boughtAt'] != null ? 'Vercel' : d['registrar']),
    'name_servers': d['nameservers'] ?? d['intendedNameservers'],
    'intended_name_servers': ?d['intendedNameservers'],
    'expires': ?_vcIso(d['expiresAt']),
    'renew': ?d['renew'],
    'created': _vcIso(d['createdAt']),
  };

  Future<List<Map<String, dynamic>>> _vcRuntimeLogs(VercelApi api, String projectId, String deploymentId, {required int seconds, required int limit}) async {
    final client = http.Client();
    final lines = <Map<String, dynamic>>[];
    try {
      final req = http.Request('GET', api.uri('/v1/projects/$projectId/deployments/$deploymentId/runtime-logs'))
        ..headers['Authorization'] = 'Bearer ${api.token}'
        ..headers['Accept'] = 'application/stream+json';
      final res = await client.send(req).timeout(const Duration(seconds: 20));
      if (res.statusCode >= 300) {
        final body = await res.stream.bytesToString();
        throw DevApiException('vercel', 'Runtime logs: HTTP ${res.statusCode} ${TelegramToolRunner._clip(body, 200)}');
      }
      final done = Completer<void>();
      final sub = res.stream.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        if (line.trim().isEmpty) return;
        try {
          final j = jsonDecode(line) as Map;
          lines.add({
            'at': _vcIso(j['timestampInMs'] ?? j['timestamp']),
            'level': ?j['level'],
            'status': ?(j['responseStatusCode'] ?? j['statusCode']),
            'method': ?j['requestMethod'],
            'path': ?j['requestPath'],
            'text': TelegramToolRunner._clip('${j['message'] ?? ''}'.trimRight(), 500),
          });
        } catch (_) {
          lines.add({'text': TelegramToolRunner._clip(line, 500)});
        }
        if (lines.length >= limit && !done.isCompleted) done.complete();
      }, onDone: () {
        if (!done.isCompleted) done.complete();
      }, onError: (Object _) {
        if (!done.isCompleted) done.complete();
      });
      await done.future.timeout(Duration(seconds: seconds), onTimeout: () {});
      await sub.cancel();
    } finally {
      client.close();
    }
    return lines;
  }

  /// FOCUS billing lines (JSON per line) summed by service and by day.
  Map<String, dynamic> _vcCharges(Object? raw) {
    final rows = <Map>[];
    if (raw is String) {
      for (final line in const LineSplitter().convert(raw)) {
        if (line.trim().isEmpty) continue;
        try {
          final j = jsonDecode(line);
          if (j is Map) rows.add(j);
        } catch (_) {}
      }
    } else if (raw is List) {
      rows.addAll(raw.whereType<Map>());
    } else if (raw is Map && raw['charges'] is List) {
      rows.addAll((raw['charges'] as List).whereType<Map>());
    }
    final byService = <String, double>{};
    final byDay = <String, double>{};
    var total = 0.0;
    String? currency;
    for (final r in rows) {
      final cost = (r['BilledCost'] ?? r['billedCost'] ?? r['EffectiveCost'] ?? r['cost']) as Object?;
      final v = cost is num ? cost.toDouble() : double.tryParse('$cost') ?? 0;
      if (v == 0) continue;
      final service = '${r['ServiceName'] ?? r['serviceName'] ?? r['ChargeDescription'] ?? 'Other'}';
      final day = '${r['ChargePeriodStart'] ?? r['chargePeriodStart'] ?? ''}';
      byService[service] = (byService[service] ?? 0) + v;
      if (day.length >= 10) byDay[day.substring(0, 10)] = (byDay[day.substring(0, 10)] ?? 0) + v;
      total += v;
      currency ??= (r['BillingCurrency'] ?? r['billingCurrency']) as String?;
    }
    double round(double x) => (x * 100).roundToDouble() / 100;
    return {
      'total': round(total),
      'currency': currency ?? 'USD',
      'by_service': [
        for (final e in (byService.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))) {'service': e.key, 'cost': round(e.value)},
      ],
      'by_day': [
        for (final e in (byDay.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))) {'day': e.key, 'cost': round(e.value)},
      ],
      if (rows.isEmpty) 'note': 'No billed usage in this period.',
    };
  }

  Future<ToolOutput> _vcDeploy(VercelApi api, Map<String, dynamic> a) async {
    final name = _va(a, 'name').toLowerCase().replaceAll(RegExp(r'[^a-z0-9-]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    if (name.isEmpty) return const ToolOutput({'dev': 'vercel', 'error': 'Give the project a name.'});
    final entries = <(String, Uint8List)>[];
    for (final f in (a['files'] as List? ?? const [])) {
      final file = File('$f');
      if (!file.existsSync()) return ToolOutput({'dev': 'vercel', 'error': 'No file "$f" in this conversation.'});
      final base = file.path.split(RegExp(r'[\\/]')).last.replaceFirst(RegExp(r'^[0-9a-f]{8}_'), '');
      entries.add((base, await file.readAsBytes()));
    }
    for (final t in (a['text_files'] as List? ?? const []).whereType<Map>()) {
      final path = '${t['path'] ?? ''}'.trim().replaceFirst(RegExp(r'^/+'), '');
      if (path.isEmpty) continue;
      entries.add((path, Uint8List.fromList(utf8.encode('${t['content'] ?? ''}'))));
    }
    if (_va(a, 'html').isNotEmpty) entries.add(('index.html', Uint8List.fromList(utf8.encode('${a['html']}'))));
    if (entries.isEmpty) return const ToolOutput({'dev': 'vercel', 'error': 'Nothing to deploy: give files, html or text_files.'});
    if (entries.length > 200) return const ToolOutput({'dev': 'vercel', 'error': 'Up to 200 files.'});
    // A lone HTML page is the site's index.
    if (!entries.any((e) => e.$1 == 'index.html')) {
      final pages = [for (final e in entries) if (e.$1.toLowerCase().endsWith('.html') && !e.$1.contains('/')) e];
      if (pages.length == 1) {
        final i = entries.indexOf(pages.first);
        entries[i] = ('index.html', pages.first.$2);
      }
    }
    final total = entries.fold<int>(0, (s, e) => s + e.$2.length);
    if (total > 100 << 20) return const ToolOutput({'dev': 'vercel', 'error': 'Over 100 MB.'});
    final progress = DownloadProgress.startUpload('Deploying $name to Vercel', total: total, files: entries.length);
    final files = <Map<String, dynamic>>[];
    try {
      for (final (path, bytes) in entries) {
        final sha = await api.uploadFile(bytes);
        files.add({'file': path, 'sha': sha, 'size': bytes.length});
        progress?.add(bytes.length);
      }
      final production = a['production'] != false;
      final r = await api.call('POST', '/v13/deployments', query: {'skipAutoDetectionConfirmation': '1'}, body: {
        'name': name,
        'files': files,
        'projectSettings': {'framework': null, 'buildCommand': null, 'installCommand': null, 'outputDirectory': null},
        if (production) 'target': 'production',
      }) as Map;
      progress?.finish('');
      final summary = vercelDeploymentSummary(r);
      return ToolOutput({
        'dev': 'vercel',
        'done': true,
        'deployment': summary,
        'url': (summary['aliases'] as List?)?.isNotEmpty == true ? 'https://${(summary['aliases'] as List).first}' : summary['url'],
        'files': [for (final f in files) f['file']],
        'bytes': total,
      });
    } catch (e) {
      progress?.fail('$e');
      rethrow;
    }
  }

  /// What a Vercel change would do, for the approval card.
  String? _describeVercel(String name, Map<String, dynamic> a) {
    if (!_vercelToolNames.contains(name)) return null;
    String v(String k) => '${a[k] ?? ''}'.trim();
    return switch (name) {
      'vercel_deploy' => 'Deploy “${v('name')}” to Vercel${a['production'] == false ? ' (preview)' : ' (production)'}\n${[
          for (final f in (a['files'] as List? ?? const [])) '$f'.split(RegExp(r'[\\/]')).last,
          for (final t in (a['text_files'] as List? ?? const []).whereType<Map>()) '${t['path']}',
          if (v('html').isNotEmpty) 'index.html',
        ].join(', ')}',
      'vercel_redeploy' => 'Rebuild deployment ${v('deployment')}${a['production'] == true ? ' as production' : ''}',
      'vercel_promote' => 'Make ${v('deployment')} production for ${v('project')}',
      'vercel_rollback' => 'Roll ${v('project')} production back to ${v('deployment')}',
      'vercel_cancel_deployment' => 'Cancel the build of ${v('deployment')}',
      'vercel_create_project' => 'Create the Vercel project “${v('name')}”${v('repo').isEmpty ? '' : ' linked to ${v('repo')}'}',
      'vercel_update_project' => 'Change ${v('project')} settings:\n${[for (final k in const ['name', 'framework', 'build_command', 'install_command', 'output_directory', 'root_directory', 'node_version', 'body_json']) if (a[k] != null) '$k: ${a[k]}'].join('\n')}',
      'vercel_pause_project' => '${a['pause'] == false ? 'Resume' : 'Pause'} the project ${v('project')}',
      'vercel_env_set' => 'Set ${v('key')} on ${v('project')} (${(a['targets'] as List?)?.join(', ') ?? 'all environments'})\n${v('type') == 'sensitive' ? '••••' : TelegramToolRunner._clip(v('value'), 120)}',
      'vercel_add_domain' => 'Add ${v('domain')} to ${v('project')}${v('redirect').isEmpty ? '' : ' → redirect to ${v('redirect')}'}',
      'vercel_verify_domain' => 'Verify ${v('domain')} on ${v('project')}',
      'vercel_dns_create' => 'Add a ${v('type').toUpperCase()} record on ${v('domain')}\n${v('name').isEmpty ? '@' : v('name')} → ${v('value')}',
      'vercel_alias_assign' => 'Point ${v('alias')} at ${v('deployment')}',
      'vercel_edge_config_update' => 'Change Edge Config ${v('id')}:\n${[for (final i in (a['items'] as List? ?? const []).whereType<Map>()) '${i['operation']} ${i['key']}'].join('\n')}',
      'vercel_webhook_create' => 'Send ${(a['events'] as List?)?.join(', ')} to ${v('url')}',
      'vercel_delete_deployment' => 'Delete the deployment ${v('deployment')}',
      'vercel_delete_project' => 'Delete the Vercel project ${v('project')} with all its deployments',
      'vercel_env_delete' => 'Delete ${v('key')} from ${v('project')}${v('target').isEmpty ? '' : ' (${v('target')})'}',
      'vercel_remove_domain' => 'Remove ${v('domain')}${v('project').isEmpty ? ' from the Vercel account' : ' from ${v('project')}'}',
      'vercel_dns_delete' => 'Delete DNS record ${v('record_id')} on ${v('domain')}',
      'vercel_alias_delete' => 'Remove the alias ${v('alias')}',
      'vercel_webhook_delete' => 'Delete webhook ${v('id')}',
      'vercel_api_request' => '${v('method')} ${v('path')}${v('body_json').isEmpty ? '' : '\n${TelegramToolRunner._clip(v('body_json'), 600)}'}',
      _ => null,
    };
  }
}
