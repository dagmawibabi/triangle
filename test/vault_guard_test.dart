import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teleai/features/settings/data/app_data.dart';
import 'package:teleai/features/vault/vault.dart';
import 'package:teleai/features/vault/vault_guard.dart';

VaultItem _item(String label, String value, VaultCategory category) => VaultItem(
  id: label,
  label: label,
  value: value,
  category: category,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  final phone = _item('Personal phone', '0911 234 567', VaultCategory.phone);
  final address = _item('Home address', 'Bole Road, House 12', VaultCategory.address);
  final passport = _item('Passport', 'EP1234567', VaultCategory.identity);
  final short = _item('Initials', 'DB', VaultCategory.personal);
  final vault = [phone, address, passport, short];

  group('vaultItemsIn', () {
    test('finds a phone number however it is written', () {
      expect(vaultItemsIn('send_message', {'text': 'Call me on +251-911-234-567'}, vault), [phone]);
      expect(vaultItemsIn('send_sms', {'body': 'my number is 0911234567'}, vault), [phone]);
    });

    test('finds text values ignoring case and spacing, in nested args', () {
      expect(
        vaultItemsIn('gmail_send_email', {
          'to': ['a@b.c'],
          'body': {'text': 'Deliver to bole road,  house 12 please'},
        }, vault),
        [address],
      );
      expect(vaultItemsIn('reply_to_message', {'text': 'passport ep1234567'}, vault), [passport]);
    });

    test('ignores tools that do not send, short values and unrelated numbers', () {
      expect(vaultItemsIn('vault_save', {'value': '0911234567'}, vault), isEmpty);
      expect(vaultItemsIn('send_message', {'text': 'DB is down, room 12 34 567'}, vault), isEmpty);
      expect(vaultItemsIn('send_message', {'text': 'order 911 and 234567'}, vault), isEmpty);
    });
  });

  group('remapAccounts', () {
    final ids = {'old1': 'new1'};

    test('maps account limits, and drops limits to accounts that are gone', () {
      final out = jsonDecode(AppData.remapAccounts(
        'watches.v1',
        jsonEncode([
          {'id': 'w1', 'accounts': ['old1', 'gone']},
          {'id': 'w2', 'accounts': ['gone']},
          {'id': 'w3', 'folder_account': 'old1'},
        ]),
        ids,
      )) as List;
      expect(out[0]['accounts'], ['new1']);
      expect((out[1] as Map).containsKey('accounts'), isFalse);
      expect(out[2]['folder_account'], 'new1');
    });

    test('drops approval rules for accounts that are not here', () {
      final out = jsonDecode(AppData.remapAccounts(
        'approval_rules.v1',
        jsonEncode([
          {'id': 'r1', 'account': 'old1'},
          {'id': 'r2', 'account': 'gone'},
          {'id': 'r3'},
        ]),
        ids,
      )) as List;
      expect([for (final r in out) r['id']], ['r1', 'r3']);
      expect(out[0]['account'], 'new1');
    });
  });
}
