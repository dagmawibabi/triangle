import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teleai/features/chat/domain/chat_models.dart';
import 'package:teleai/features/chat/presentation/widgets/rich_results.dart';
import 'package:teleai/features/development/development_screen.dart';
import 'package:teleai/infrastructure/telegram/telegram_client.dart';

const _dep = {
  'id': 'dpl_1',
  'name': 'site',
  'url': 'https://site-abc.vercel.app',
  'state': 'READY',
  'target': 'preview',
  'created': '2026-11-15T10:00:00Z',
  'ready': '2026-11-15T10:01:10Z',
  'branch': 'feature/a-very-long-branch-name-that-goes-on',
  'sha': 'abcdef1',
  'commit': 'A long commit message that should be cut nicely when it does not fit on a phone',
  'creator': 'someone',
  'project_id': 'prj_1',
  'aliases': ['site-git-feature.vercel.app'],
};

final _samples = <String, Map<String, dynamic>>{
  'vercel_account': {
    'dev': 'vercel',
    'user': {'username': 'me', 'name': 'Me', 'email': 'me@example.com', 'plan': 'pro'},
    'teams': [
      {'id': 't1', 'name': 'Team One', 'role': 'OWNER'},
    ],
    'team': 'personal account',
  },
  'vercel_projects': {
    'dev': 'vercel',
    'projects': [
      {'id': 'prj_1', 'name': 'site', 'framework': 'nextjs', 'repo': 'me/site', 'latest': _dep},
      {'id': 'prj_2', 'name': 'paused-app', 'paused': true},
    ],
  },
  'vercel_project': {
    'dev': 'vercel',
    'project': {'id': 'prj_1', 'name': 'site', 'framework': 'nextjs', 'production_url': 'https://site.example.com'},
    'domains': [
      {'name': 'site.example.com', 'verified': true},
      {'name': 'www.site.example.com', 'verified': false},
    ],
    'deployments': [_dep],
  },
  'vercel_deployments': {
    'dev': 'vercel',
    'deployments': [
      _dep,
      {..._dep, 'id': 'dpl_2', 'state': 'ERROR', 'error': 'Build failed'},
    ],
  },
  'vercel_deployment': {'dev': 'vercel', 'deployment': {..._dep, 'state': 'ERROR', 'error': 'Command "npm run build" exited with 1'}},
  'vercel_deploy': {'dev': 'vercel', 'done': true, 'deployment': {..._dep, 'state': 'READY', 'target': 'production'}, 'files': ['index.html'], 'bytes': 1200},
  'vercel_build_logs': {
    'dev': 'vercel',
    'deployment': _dep,
    'lines': [
      {'type': 'stdout', 'text': 'Installing dependencies'},
      {'type': 'stderr', 'text': 'Error: Cannot find module x'},
    ],
  },
  'vercel_runtime_logs': {
    'dev': 'vercel',
    'deployment': 'dpl_1',
    'lines': [
      {'status': 200, 'method': 'GET', 'path': '/', 'text': ''},
      {'status': 500, 'level': 'error', 'method': 'POST', 'path': '/api/x', 'text': 'TypeError: undefined'},
    ],
  },
  'vercel_env': {
    'dev': 'vercel',
    'project': 'site',
    'env': [
      {'id': 'e1', 'key': 'DATABASE_URL', 'targets': ['production', 'preview'], 'type': 'encrypted', 'value': 'postgres://x'},
      {'id': 'e2', 'key': 'SECRET', 'targets': ['production'], 'type': 'sensitive'},
    ],
  },
  'vercel_domains': {
    'dev': 'vercel',
    'domains': [
      {'name': 'example.com', 'verified': true, 'service_type': 'zeit.world'},
    ],
  },
  'vercel_dns_records': {
    'dev': 'vercel',
    'domain': 'example.com',
    'dns_records': [
      {'id': 'r1', 'type': 'A', 'name': '', 'value': '76.76.21.21', 'ttl': 60},
    ],
  },
  'vercel_usage': {
    'dev': 'vercel',
    'days': 30,
    'total': 12.5,
    'currency': 'USD',
    'by_service': [
      {'service': 'Fluid Active CPU', 'cost': 8.0},
      {'service': 'Fast Data Transfer', 'cost': 4.5},
    ],
    'by_day': [
      {'day': '2026-11-01', 'cost': 1.0},
      {'day': '2026-11-02', 'cost': 2.0},
    ],
  },
  'vercel_domain_check': {'dev': 'vercel', 'domain': 'new-name.dev', 'available': true, 'price': 15},
  'resend_send_email': {
    'dev': 'resend',
    'done': true,
    'id': 'em_1',
    'email': {'id': 'em_1', 'to': ['a@example.com'], 'from': 'Me <me@example.com>', 'subject': 'Hello there', 'last_event': 'scheduled', 'scheduled_at': 'in 1 hour', 'text': 'Hi!'},
  },
  'resend_emails': {
    'dev': 'resend',
    'emails': [
      {'id': 'em_1', 'to': ['a@example.com'], 'subject': 'Hello', 'last_event': 'delivered', 'created': '2026-11-15T10:00:00Z'},
      {'id': 'em_2', 'to': ['b@example.com'], 'subject': 'Bounce', 'last_event': 'bounced', 'created': '2026-11-14T10:00:00Z'},
    ],
  },
  'resend_domains': {
    'dev': 'resend',
    'domains': [
      {'id': 'd1', 'name': 'example.com', 'status': 'verified', 'region': 'us-east-1', 'created': '2026-01-01'},
    ],
  },
  'resend_domain': {
    'dev': 'resend',
    'domain': {'id': 'd1', 'name': 'example.com', 'status': 'pending', 'region': 'eu-west-1'},
    'records': [
      {'record': 'DKIM', 'type': 'TXT', 'name': 'resend._domainkey', 'value': 'p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQ' * 3, 'status': 'not_started', 'ttl': 'Auto'},
      {'record': 'SPF', 'type': 'MX', 'name': 'send', 'value': 'feedback-smtp.eu-west-1.amazonses.com', 'priority': 10, 'status': 'verified'},
    ],
  },
  'resend_contacts': {
    'dev': 'resend',
    'audience': 'aud_1',
    'contacts': [
      {'id': 'c1', 'email': 'a@example.com', 'first_name': 'Abebe', 'unsubscribed': false},
      {'id': 'c2', 'email': 'b@example.com', 'unsubscribed': true},
    ],
  },
  'resend_broadcasts': {
    'dev': 'resend',
    'broadcasts': [
      {'id': 'b1', 'subject': 'November news', 'status': 'draft', 'created': '2026-11-01'},
    ],
  },
  'resend_create_api_key': {'dev': 'resend', 'done': true, 'id': 'k1', 'token': 're_secret'},
  'mongodb_overview': {
    'dev': 'mongodb',
    'server': {'version': '8.0.3', 'host': 'cluster0.mongodb.net', 'topology': 'replica set atlas-x'},
    'databases': [
      {'name': 'shop', 'size': 1048576},
      {'name': 'admin', 'size': 4096},
    ],
    'total_size': 1052672,
    'default_database': 'shop',
  },
  'mongodb_collections': {
    'dev': 'mongodb',
    'database': 'shop',
    'collections': [
      {'name': 'orders', 'type': 'collection', 'count': 12000, 'size': 900000},
      {'name': 'by_country', 'type': 'view'},
    ],
  },
  'mongodb_find': {
    'dev': 'mongodb',
    'database': 'shop',
    'collection': 'orders',
    'filter': {'status': 'paid'},
    'documents': [
      {
        '_id': {r'$oid': '6553f1e2a1b2c3d4e5f60718'},
        'status': 'paid',
        'total': 42.5,
        'at': {r'$date': '2026-11-01T10:00:00Z'},
        'items': [
          {'sku': 'a', 'qty': 2},
        ],
      },
    ],
    'more': true,
  },
  'mongodb_aggregate': {
    'dev': 'mongodb',
    'database': 'shop',
    'collection': 'orders',
    'pipeline': [],
    'documents': [
      {'_id': 'ET', 'n': 10},
      {'_id': 'KE', 'n': 4},
    ],
  },
  'mongodb_count': {'dev': 'mongodb', 'database': 'shop', 'collection': 'orders', 'filter': {}, 'count': 12000},
  'mongodb_schema': {
    'dev': 'mongodb',
    'database': 'shop',
    'collection': 'orders',
    'sampled': 200,
    'fields': [
      {'field': 'status', 'types': ['string'], 'present': 1.0},
      {'field': 'address.city', 'types': ['string', 'null'], 'present': 0.4},
    ],
  },
  'mongodb_indexes': {
    'dev': 'mongodb',
    'database': 'shop',
    'collection': 'orders',
    'indexes': [
      {'name': '_id_', 'keys': {'_id': 1}, 'size': 4096, 'uses': 12},
      {'name': 'email_1', 'keys': {'email': 1}, 'unique': true, 'uses': 0},
    ],
  },
  'mongodb_explain': {
    'dev': 'mongodb',
    'database': 'shop',
    'collection': 'orders',
    'plan': 'collection scan',
    'stages': ['COLLSCAN'],
    'returned': 3,
    'docs_examined': 12000,
    'keys_examined': 0,
    'ms': 18,
  },
  'mongodb_server_status': {
    'dev': 'mongodb',
    'status': {
      'host': 'h',
      'version': '8.0',
      'uptime_seconds': 90000,
      'connections': {'current': 5, 'available': 500},
      'opcounters': {'query': 10, 'insert': 2},
      'memory_mb': {'resident': 300},
      'network_bytes': {'in': 1000, 'out': 2000, 'requests': 30},
    },
  },
  'mongodb_update': {'dev': 'mongodb', 'done': true, 'database': 'shop', 'collection': 'orders', 'matched': 3, 'modified': 2},
  'mongodb_delete': {'dev': 'mongodb', 'database': 'shop', 'collection': 'orders', 'deleted': 1},
  'track_package': {
    'parcel': {
      'number': 'RR123456785ET',
      'label': 'New phone',
      'status': 'InTransit',
      'status_label': 'In transit',
      'carrier': 'Ethiopian Postal Service',
      'latest': {'text': 'Arrived at sorting center', 'location': 'Addis Ababa', 'at': '2026-11-14T10:00:00Z'},
      'eta': '2026-11-20T00:00:00Z',
      'days_in_transit': 6,
      'from': 'CN',
      'to': 'ET',
      'events': [
        {'text': 'Arrived at sorting center', 'location': 'Addis Ababa', 'at': '2026-11-14T10:00:00Z'},
      ],
    },
    'links': [
      {'carrier': '17TRACK (any carrier)', 'url': 'https://t.17track.net/en#nums=RR123456785ET'},
    ],
    'live': true,
  },
  'tracked_packages': {
    'packages': [
      {'number': '1Z999AA10123456784', 'status': 'Delivered', 'carrier': 'UPS', 'latest': {'text': 'Delivered'}},
      {'number': 'RR123456785ET', 'label': 'New phone'},
    ],
  },
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('every Development card lays out at phone width', (tester) async {
    tester.view.physicalSize = const Size(360, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final e in _samples.entries) {
      final part = ToolPart(callId: e.key, name: e.key, status: ToolStatus.done, result: jsonEncode(e.value));
      final card = richResultFor(part);
      expect(card, isNotNull, reason: e.key);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authStateProvider.overrideWith((ref) => const Stream.empty())],
          child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: card!))),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: e.key);
    }
    // Live cards stop their timers when they leave.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the Development page shows each service and its tools', (tester) async {
    tester.view.physicalSize = const Size(360, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final service in DevService.values) {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authStateProvider.overrideWith((ref) => const Stream.empty())],
          child: MaterialApp(home: DevelopmentScreen(service: service)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull, reason: service.label);
      expect(find.text('Development'), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox());
  });
}
