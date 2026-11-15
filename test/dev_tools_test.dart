import 'package:flutter_test/flutter_test.dart';
import 'package:mongo_dart/mongo_dart.dart' show ObjectId;
import 'package:teleai/features/development/mongo_session.dart';
import 'package:teleai/features/settings/data/settings.dart';
import 'package:teleai/features/settings/presentation/tools_screen.dart' show ToolGroup;
import 'package:teleai/features/telegram/data/telegram_tools.dart';

void main() {
  final dev = [for (final t in telegramTools) if (t.category == ToolCategory.vercel || t.category == ToolCategory.resend || t.category == ToolCategory.mongodb) t];

  test('Vercel, Resend and MongoDB each have read, modify and destructive tools', () {
    for (final c in [ToolCategory.vercel, ToolCategory.resend, ToolCategory.mongodb]) {
      final tools = dev.where((t) => t.category == c);
      for (final a in ToolAccess.values) {
        expect(tools.where((t) => t.access == a), isNotEmpty, reason: '$c $a');
      }
    }
    expect(dev.length, greaterThan(90));
  });

  test('changes ask first, destructive tools start off, reads run freely', () {
    const s = AppSettings(vercelToken: 'v', resendKey: 'r', mongoUri: 'mongodb://localhost');
    for (final t in dev) {
      expect(t.needsTelegram, isFalse, reason: t.name);
      expect(t.cost, ToolCost.cloud, reason: t.name);
      if (t.modifiesData) expect(t.requiresApproval, isTrue, reason: t.name);
      if (t.access == ToolAccess.read) expect(t.requiresApproval, isFalse, reason: t.name);
      if (t.destructive) expect(t.isOn(s), isFalse, reason: t.name);
    }
    expect(toolNamed('resend_send_broadcast')!.alwaysAsk, isTrue);
    expect(toolNamed('resend_send_batch')!.alwaysAsk, isTrue);
    expect(toolNamed('mongodb_drop_database')!.destructive, isTrue);
    expect(toolNamed('vercel_api_request')!.destructive, isTrue);
    expect(toolNamed('mongodb_run_read_command')!.access, ToolAccess.read);
  });

  test('each needs its own key', () {
    const none = AppSettings();
    expect(devToolNeeds(toolNamed('vercel_projects')!, none), 'Needs a Vercel token');
    expect(devToolNeeds(toolNamed('resend_send_email')!, none), 'Needs a Resend key');
    expect(devToolNeeds(toolNamed('mongodb_find')!, none), 'Needs a MongoDB connection string');
    const keyed = AppSettings(vercelToken: 'v', resendKey: 'r', mongoUri: 'mongodb://h');
    for (final t in dev) {
      expect(devToolNeeds(t, keyed), isNull, reason: t.name);
    }
    // The AI Gateway key is not a Vercel token.
    expect(devToolNeeds(toolNamed('vercel_projects')!, const AppSettings(vercelKey: 'gateway')), isNotNull);
  });

  test('Development holds Vercel, Resend, MongoDB and Cloudflare, not Apps & web', () {
    for (final name in ['vercel_deploy', 'resend_send_email', 'mongodb_find', 'cloudflare_zones', 'r2_list']) {
      final t = toolNamed(name)!;
      expect(ToolGroup.development.has(t), isTrue, reason: name);
      expect(ToolGroup.apps.has(t), isFalse, reason: name);
      expect(ToolGroup.telegram.has(t), isFalse, reason: name);
    }
    expect(ToolGroup.apps.has(toolNamed('e2b_run_code')!), isTrue);
  });

  test('documentation points at each service', () {
    expect(toolNamed('vercel_deploy')!.documentation.referenceUrl, contains('vercel.com'));
    expect(toolNamed('resend_send_email')!.documentation.referenceUrl, contains('resend.com'));
    expect(toolNamed('mongodb_find')!.documentation.referenceUrl, contains('mongodb.com'));
    expect(toolNamed('mongodb_find')!.documentation.prerequisites, contains('MongoDB connection string'));
  });

  test('a Vercel deployment reads as state, URL, branch and commit', () {
    final d = vercelDeploymentSummary({
      'uid': 'dpl_1',
      'name': 'site',
      'url': 'site-abc.vercel.app',
      'readyState': 'BUILDING',
      'target': 'production',
      'createdAt': 1700000000000,
      'meta': {'githubCommitRef': 'main', 'githubCommitMessage': 'Fix it', 'githubCommitSha': 'abcdef1234567'},
      'creator': {'username': 'me'},
      'alias': ['site.example.com'],
    });
    expect(d['id'], 'dpl_1');
    expect(d['url'], 'https://site-abc.vercel.app');
    expect(d['state'], 'BUILDING');
    expect(d['branch'], 'main');
    expect(d['sha'], 'abcdef1');
    expect(d['aliases'], ['site.example.com']);
    expect(d.containsKey('error'), isFalse);
  });

  group('MongoDB', () {
    test('reads the database, hosts and hides the password', () {
      const uri = 'mongodb+srv://me:s3cret@cluster0.abc.mongodb.net/shop?retryWrites=true';
      expect(MongoSession.databaseIn(uri), 'shop');
      expect(MongoSession.databaseIn('mongodb://localhost:27017/'), isNull);
      expect(MongoSession.hostsOf(uri), 'cluster0.abc.mongodb.net');
      expect(MongoSession.redact(uri), isNot(contains('s3cret')));
    });

    test('Extended JSON goes both ways', () {
      final id = ObjectId();
      final doc = MongoSession.toEjson({'_id': id, 'at': DateTime.utc(2024, 1, 2), 'n': 3});
      expect(doc['_id'], {r'$oid': id.oid});
      expect((doc['at'] as Map)[r'$date'], isNotNull);
      final back = MongoSession.fromEjson({'_id': {r'$oid': id.oid}, 'at': {r'$date': '2024-01-02'}});
      expect(back['_id'], isA<ObjectId>());
      expect(back['at'], isA<DateTime>());
    });

    test('a schema says what each field is and how often', () {
      final fields = inferSchema([
        {'name': 'a', 'age': 3, 'tags': ['x']},
        {'name': 'b', 'address': {'city': 'Addis'}},
      ]);
      final byName = {for (final f in fields) f['field']: f};
      expect(byName['name']!['types'], ['string']);
      expect(byName['name']!['present'], 1.0);
      expect(byName['age']!['present'], 0.5);
      expect(byName['address.city']!['types'], ['string']);
      expect(byName['tags']!['types'], ['array']);
    });

    test('bad JSON is explained', () {
      expect(() => MongoSession.parse("{name: 'x'}", what: 'filter'), throwsA(isA<MongoProblem>()));
      expect(MongoSession.parse('{"a": 1}'), {'a': 1});
    });

    test('only reading commands pass the read tool', () {
      expect(mongoReadCommands.contains('dbstats'), isTrue);
      expect(mongoReadCommands.contains('drop'), isFalse);
      expect(mongoReadCommands.contains('insert'), isFalse);
    });
  });
}
