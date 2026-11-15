import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../brief/brief_store.dart';
import '../../canvas/canvas_store.dart';
import '../../chat/data/chat_controller.dart';
import '../../telegram/presentation/chat_actions.dart' show confirmAction;
import 'package:handy_tdlib/api.dart' as td;
import 'package:path_provider/path_provider.dart';
import '../../../infrastructure/telegram/accounts.dart';
import '../../../infrastructure/telegram/td_compat.dart' show inputDocument;
import '../../auth/data/auth_controller.dart' show telegramConnectedProvider;
import '../../telegram/data/telegram_tools.dart' show toolRunnerFamily;
import '../data/app_data.dart';
import '../data/settings.dart';

/// Back up the app's setup to a file, bring it back after a reinstall, or
/// wipe everything the assistant keeps on this phone.
class DataScreen extends ConsumerStatefulWidget {
  const DataScreen({super.key});

  @override
  ConsumerState<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends ConsumerState<DataScreen> {
  bool _keys = true;
  bool _chats = false;
  bool _vault = true;
  bool _media = true;

  /// Also sends the file to the person's Saved Messages in Telegram.
  bool _toSaved = false;
  bool _busy = false;

  /// Sends [bytes] as [name] to the open account's Saved Messages.
  Future<void> _sendToSaved(String name, List<int> bytes) async {
    final account = ref.read(activeAccountIdProvider);
    final client = ref.read(telegramClientFamily(account));
    final me = await client.send<td.User>(const td.GetMe());
    final chat = await client.send<td.Chat>(td.CreatePrivateChat(userId: me.id, force: false));
    final f = File('${(await getTemporaryDirectory()).path}/$name');
    await f.writeAsBytes(bytes);
    await ref.read(toolRunnerFamily(account)).sendAndSettle(
      td.SendMessage(
        chatId: chat.id,
        inputMessageContent: td.InputMessageDocument(
          document: inputDocument(f.path, keepAsFile: true),
          caption: td.FormattedText(text: '🔺 Triangle profile backup · ${DateFormat('d MMM y, HH:mm').format(DateTime.now())}\nRestore it in Settings → Data → Import profile.', entities: const []),
        ),
      ),
    );
  }

  Future<void> _guard(Future<void> Function() work) async {
    setState(() => _busy = true);
    try {
      await work();
    } catch (e) {
      if (mounted) showSnack(context, '$e', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() => _guard(() async {
    final profile = await AppData.export(keys: _keys, chats: _chats, vault: _vault, media: _media);
    final name = 'triangle-profile-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.json';
    if (_toSaved) {
      await _sendToSaved(name, AppData.encode(profile));
      await (await SharedPreferences.getInstance()).setString(AppData.lastBackupKey, DateTime.now().toIso8601String());
      if (mounted) showSnack(context, 'Sent to your Saved Messages', icon: Icons.bookmark_rounded);
      return;
    }
    final path = await FilePicker.saveFile(
      dialogTitle: 'Save your Triangle profile',
      fileName: name,
      type: FileType.custom,
      allowedExtensions: const ['json'],
      mimeType: 'application/json',
      bytes: Uint8List.fromList(AppData.encode(profile)),
    );
    if (path == null || !mounted) return;
    // For System check's "last backup".
    await (await SharedPreferences.getInstance()).setString(AppData.lastBackupKey, DateTime.now().toIso8601String());
    if (mounted) showSnack(context, 'Profile saved');
  });

  Future<void> _import() => _guard(() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    final file = picked.singleOrNull;
    if (file?.path == null) return;
    final bytes = await File(file!.path!).readAsBytes();
    final profile = jsonDecode(utf8.decode(bytes));
    if (profile is! Map<String, dynamic> || profile['format'] != AppData.format) {
      throw const FormatException('That file is not a Triangle profile.');
    }
    final counts = AppData.describe(profile);
    final date = DateTime.tryParse('${profile['exported_at'] ?? ''}');
    if (!mounted) return;
    final ok = await showFormSheet<bool>(
      context,
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.settings_backup_restore_rounded, size: 32, color: AppColors.accent),
          const SizedBox(height: Space.m),
          Text('Restore this profile?', style: context.text.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: Space.s),
          Text(
            [
              if (date != null) 'Saved ${DateFormat('d MMM y, HH:mm').format(date)}',
              '${counts['settings']} settings and memories',
              '${counts['keys']} keys',
              if (counts['chats']! > 0) '${counts['chats']} AI chats',
              if (counts['vault']! > 0) '${counts['vault']} vault items',
              if (counts['watches']! > 0) '${counts['watches']} watches',
              if (counts['routines']! > 0) '${counts['routines']} routines',
              if (counts['rules']! > 0) '${counts['rules']} approval rules',
              if (counts['transactions']! > 0) '${counts['transactions']} transactions',
              if (counts['widgets']! > 0) '${counts['widgets']} widgets',
              if (counts['skills']! > 0) '${counts['skills']} skills',
              if ((counts['folders'] ?? 0) > 0) '${counts['folders']} folders',
              if ((counts['packages'] ?? 0) > 0) '${counts['packages']} tracked packages',
              if ((counts['playlists'] ?? 0) > 0) '${counts['playlists']} playlists',
              if ((counts['stores'] ?? 0) > 0) '${counts['stores']} stores',
              if ((counts['video_channels'] ?? 0) > 0) '${counts['video_channels']} video channels',
              if ((counts['books'] ?? 0) > 0) '${counts['books']} books',
              if ((counts['gallery_sources'] ?? 0) > 0) '${counts['gallery_sources']} gallery sources',
              if (counts['mcp']! > 0) '${counts['mcp']} MCP servers${counts['keys'] == 0 ? ' (add their keys again)' : ''}',
            ].join(' · '),
            style: context.text.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.s),
          Text(
            'Its settings and keys replace the ones here. Telegram stays signed in as it is, and each account\'s '
            'assistant settings go to the same account here. The app lock stays as it is.',
            style: context.text.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.xl),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Restore')),
          const SizedBox(height: Space.s),
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(appDataProvider).restore(profile);
    if (mounted) showSnack(context, 'Profile restored');
  });

  /// Deletes one kind of thing after the person confirms.
  Future<void> _clearOne({
    required String title,
    required String message,
    required String action,
    required String done,
    required Future<void> Function() work,
  }) async {
    if (!await confirmAction(context, title: title, message: message, action: action)) return;
    await _guard(() async {
      await work();
      if (mounted) showSnack(context, done);
    });
  }

  Future<void> _clear() async {
    var settings = false;
    final ok = await showFormSheet<bool>(
      context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.delete_forever_outlined, size: 32, color: AppColors.danger),
            const SizedBox(height: Space.m),
            Text('Clear all data?', style: context.text.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: Space.s),
            Text(
              'AI chats, memories, the vault, money records, files the assistant made or downloaded, briefs, '
              'the Content Canvas, watches, routines, reminders, the activity log and usage are deleted from '
              'this phone. This can\'t be undone. Telegram stays signed in and the app lock stays on.',
              style: context.text.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.m),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: settings,
              onChanged: (v) => setSheet(() => settings = v ?? false),
              title: const Text('Also reset settings and remove API keys'),
            ),
            const SizedBox(height: Space.m),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Clear everything'),
            ),
            const SizedBox(height: Space.s),
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _guard(() async {
      await ref.read(appDataProvider).clearAll(settings: settings);
      if (mounted) showSnack(context, 'All data cleared');
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget card(List<Widget> children) => Container(
      margin: const EdgeInsets.only(top: Space.s),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.l),
        border: Border.all(color: AppColors.line),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    );
    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(Space.xs, Space.xl, Space.xs, Space.xs),
      child: Text(text, style: context.text.labelSmall),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data & backup'),
        bottom: _busy ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2)) : null,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.xxl),
            children: [
              header('PROFILE'),
              card([
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.s),
                  child: Text(
                    'One file with your setup: settings, memories, instructions, watches, routines, reminders, '
                    'brief settings, approval rules, spend limits, Block & mute, money records, the Content Canvas, '
                    'the activity log and usage. Restore it after reinstalling to carry on where you were. '
                    'The app lock and Telegram sign-ins stay on this phone.',
                    style: context.text.bodySmall?.copyWith(height: 1.4),
                  ),
                ),
                SwitchListTile(
                  secondary: lead(const Icon(Icons.key_outlined)),
                  title: const Text('Include API keys'),
                  subtitle: Text(
                    _keys
                        ? 'Keys and MCP server headers are in the file as plain text: keep it somewhere private.'
                        : 'Add your keys again after restoring. MCP servers come along without their headers.',
                    style: context.text.bodySmall?.copyWith(color: _keys ? AppColors.warning : null),
                  ),
                  value: _keys,
                  onChanged: (v) => setState(() => _keys = v),
                ),
                SwitchListTile(
                  secondary: lead(const Icon(Icons.lock_outline_rounded)),
                  title: const Text('Include vault'),
                  subtitle: Text(
                    _vault
                        ? 'Your vault items are in the file as plain text: keep it somewhere private.'
                        : 'Vault items stay on this phone only.',
                    style: context.text.bodySmall?.copyWith(color: _vault ? AppColors.warning : null),
                  ),
                  value: _vault,
                  onChanged: (v) => setState(() => _vault = v),
                ),
                SwitchListTile(
                  secondary: lead(const Icon(Icons.forum_outlined)),
                  title: const Text('Include AI chats'),
                  subtitle: Text('Makes the file larger', style: context.text.bodySmall),
                  value: _chats,
                  onChanged: (v) => setState(() => _chats = v),
                ),
                SwitchListTile(
                  secondary: lead(const Icon(Icons.image_outlined)),
                  title: const Text('Include covers'),
                  subtitle: Text(
                    'Playlist and book cover pictures. Playlists, Marketplace, Movies, Books and Gallery always come along; books and media stay in their chats.',
                    style: context.text.bodySmall,
                  ),
                  value: _media,
                  onChanged: (v) => setState(() => _media = v),
                ),
                if (ref.watch(telegramConnectedProvider))
                  SwitchListTile(
                    secondary: lead(const Icon(Icons.bookmark_outline_rounded)),
                    title: const Text('Send to Saved Messages'),
                    subtitle: Text(
                      _toSaved ? 'The file goes to your Telegram Saved Messages instead of a folder.' : 'Off: you pick where to save the file.',
                      style: context.text.bodySmall,
                    ),
                    value: _toSaved,
                    onChanged: (v) => setState(() => _toSaved = v),
                  ),
                const Divider(indent: Space.l, endIndent: Space.l),
                ListTile(
                  leading: lead(const Icon(Icons.upload_file_rounded)),
                  title: const Text('Export profile'),
                  subtitle: Text(_toSaved ? 'Send it to your Saved Messages' : 'Save it as a .json file', style: context.text.bodySmall),
                  enabled: !_busy,
                  onTap: _export,
                ),
                const Divider(indent: 56),
                ListTile(
                  leading: lead(const Icon(Icons.settings_backup_restore_rounded)),
                  title: const Text('Import profile'),
                  subtitle: Text('Restore from a file you exported', style: context.text.bodySmall),
                  enabled: !_busy,
                  onTap: _import,
                ),
              ]),
              header('CLEAR'),
              card([
                ListTile(
                  leading: lead(Icon(Icons.delete_sweep_outlined, color: AppColors.danger)),
                  title: const Text('Delete all AI conversations'),
                  subtitle: Text('Your Telegram is not touched', style: context.text.bodySmall),
                  enabled: !_busy,
                  onTap: () => _clearOne(
                    title: 'Delete every AI conversation?',
                    message: 'All chats with the assistant on this phone go. Watches keep running.',
                    action: 'Delete all',
                    done: 'Conversations deleted',
                    work: () => ref.read(chatControllerProvider.notifier).deleteAll(),
                  ),
                ),
                const Divider(indent: 56),
                ListTile(
                  leading: lead(Icon(Icons.wb_twilight_rounded, color: AppColors.danger)),
                  title: const Text('Delete all briefs'),
                  enabled: !_busy,
                  onTap: () => _clearOne(
                    title: 'Delete every brief?',
                    message: 'Saved briefs go.',
                    action: 'Delete',
                    done: 'Briefs deleted',
                    work: () => ref.read(briefStoreProvider.notifier).deleteAll(),
                  ),
                ),
                const Divider(indent: 56),
                ListTile(
                  leading: lead(Icon(Icons.dashboard_customize_outlined, color: AppColors.danger)),
                  title: const Text('Empty the Content Canvas'),
                  enabled: !_busy,
                  onTap: () => _clearOne(
                    title: 'Empty the canvas?',
                    message: 'Every folder and saved item goes. Telegram is not touched.',
                    action: 'Empty',
                    done: 'Canvas emptied',
                    work: () => ref.read(canvasProvider.notifier).clear(),
                  ),
                ),
                const Divider(indent: 56),
                ListTile(
                  leading: lead(const Icon(Icons.restart_alt_rounded)),
                  title: const Text('Reset preferences'),
                  subtitle: Text('Every setting back to its default. Keys, models and instructions stay.', style: context.text.bodySmall),
                  enabled: !_busy,
                  onTap: () => _clearOne(
                    title: 'Reset all preferences?',
                    message: 'Tools, appearance, voice and automation settings go back to their defaults.',
                    action: 'Reset',
                    done: 'Preferences reset',
                    work: () => ref.read(settingsProvider.notifier).resetPreferences(),
                  ),
                ),
                const Divider(indent: 56),
                ListTile(
                  leading: lead(Icon(Icons.delete_forever_outlined, color: AppColors.danger)),
                  title: Text('Clear all data', style: TextStyle(color: AppColors.danger)),
                  subtitle: Text(
                    'Chats, memories, vault, money, files, briefs, canvas, watches, routines and reminders on this phone',
                    style: context.text.bodySmall,
                  ),
                  enabled: !_busy,
                  onTap: _clear,
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
