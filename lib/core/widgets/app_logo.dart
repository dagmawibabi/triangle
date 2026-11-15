import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/theme.dart';

/// A Composio app's logo. Composio serves SVGs, which Image.network can't
/// draw (so every app showed its fallback icon); this draws them, with
/// [fallback] while loading or if the logo is missing. Logos drawn in
/// near-black (GitHub, X…) are lightened on dark pages so they stay visible.
class AppLogo extends StatelessWidget {
  const AppLogo(this.slug, {super.key, this.size = 24, required this.fallback});
  final String slug;
  final double size;
  final Widget fallback;

  /// Apps whose logo is a single near-black shape.
  static const _dark = {'github', 'twitter', 'x', 'notion_logo', 'threads', 'tiktok', 'vercel', 'openai', 'apple'};

  @override
  Widget build(BuildContext context) => SvgPicture.network(
    'https://logos.composio.dev/api/$slug',
    width: size,
    height: size,
    fit: BoxFit.contain,
    colorFilter: !AppColors.isLight && _dark.contains(slug) ? ColorFilter.mode(AppColors.text, BlendMode.srcIn) : null,
    placeholderBuilder: (_) => SizedBox.square(dimension: size, child: Center(child: fallback)),
    errorBuilder: (_, _, _) => SizedBox.square(dimension: size, child: Center(child: fallback)),
  );
}
