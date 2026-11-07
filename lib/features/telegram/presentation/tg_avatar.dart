import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../../app/theme.dart';
import '../data/telegram_store.dart';

/// A chat's or person's profile picture: the real photo once downloaded,
/// TDLib's blurry preview meanwhile, initials when there is no photo.
class TgAvatar extends ConsumerStatefulWidget {
  const TgAvatar({super.key, this.chatId, this.userId, required this.title, this.size = 40, this.accountId});

  final int? chatId;
  final int? userId;

  /// The account whose copy of the photo to show; the active one when null.
  /// TDLib's file ids belong to one account, so the right store matters.
  final String? accountId;
  final String title;
  final double size;

  @override
  ConsumerState<TgAvatar> createState() => _TgAvatarState();
}

class _TgAvatarState extends ConsumerState<TgAvatar> {
  String? _path;
  int? _requested;
  TelegramStore? _from;

  static const _palette = [
    Color(0xFF8AB4FF),
    Color(0xFFB69CFF),
    Color(0xFF6FCF97),
    Color(0xFFF2C46D),
    Color(0xFFFF9B85),
    Color(0xFF7FD6E8),
  ];

  td.File? _file(TelegramStore store) {
    if (widget.chatId != null) return store.chatPhotoFile(widget.chatId!);
    if (widget.userId != null) return store.userPhotoFile(widget.userId!);
    return null;
  }

  void _ensure(TelegramStore store, td.File? file) {
    if (file == null || _requested == file.id) return;
    _requested = file.id;
    final cached = store.cachedPhotoPath(file);
    if (cached != null) {
      _path = cached;
      return;
    }
    store.photoPath(file).then((p) {
      if (mounted && p != null && identical(_from, store)) setState(() => _path = p);
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.accountId == null
        ? ref.watch(telegramStoreProvider)
        : ref.watch(accountStoreProvider(widget.accountId!));
    // Another account's store: its file ids mean other files.
    if (!identical(store, _from)) {
      _from = store;
      _path = null;
      _requested = null;
    }
    final file = _file(store);
    _ensure(store, file);
    final size = widget.size;
    final title = widget.title.trim();
    final color = _palette[title.hashCode.abs() % _palette.length];

    Widget child;
    if (_path != null && file != null) {
      child = Image.file(
        File(_path!),
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        // Decoded at the size shown, not the photo's full size.
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
      );
    } else {
      final mini = widget.chatId == null ? null : store.chatMinithumbnail(widget.chatId!);
      if (mini != null) {
        child = Image.memory(
          base64Decode(mini.data),
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        );
      } else {
        final words = title.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
        final initials = words.isEmpty
            ? '?'
            : (words.first.characters.first + (words.length > 1 ? words[1].characters.first : '')).toUpperCase();
        child = Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          color: color.withValues(alpha: 0.18),
          child: Text(
            initials,
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: size * (initials.length > 1 ? 0.36 : 0.42)),
          ),
        );
      }
    }
    return ClipOval(child: SizedBox.square(dimension: size, child: child));
  }
}

/// The saved-messages bookmark, Telegram's way.
class SavedAvatar extends StatelessWidget {
  const SavedAvatar({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: AppColors.accentDim, shape: BoxShape.circle),
    child: Icon(Icons.bookmark_outline_rounded, size: size * 0.5, color: AppColors.accent),
  );
}
