import 'package:flutter/material.dart';

/// The Toe Pwar app icon (seedling on coins), with the same rounded corners
/// at every size. Used wherever the app shows its own brand: login, the
/// startup screen, the home app bar and the About dialog.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 88});

  static const String assetPath = 'assets/icon/toepwar.png';

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.24),
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        semanticLabel: 'Toe Pwar',
      ),
    );
  }
}
