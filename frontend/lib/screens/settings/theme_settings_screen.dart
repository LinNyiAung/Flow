import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/localization_service.dart';

class ThemeSettingsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(title: Text(localizations.theme)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              localizations.theme,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.primary),
            ),
          ),
          Card(
            child: Column(
              children: [
                _buildThemeOption(
                  context,
                  mode: ThemeMode.system,
                  current: themeProvider.themeMode,
                  icon: Icons.brightness_auto_rounded,
                  title: localizations.themeSystem,
                  subtitle: localizations.themeSystemDesc,
                  onTap: () => themeProvider.setThemeMode(ThemeMode.system),
                ),
                const Divider(),
                _buildThemeOption(
                  context,
                  mode: ThemeMode.light,
                  current: themeProvider.themeMode,
                  icon: Icons.light_mode_rounded,
                  title: localizations.themeLight,
                  subtitle: localizations.themeLightDesc,
                  onTap: () => themeProvider.setThemeMode(ThemeMode.light),
                ),
                const Divider(),
                _buildThemeOption(
                  context,
                  mode: ThemeMode.dark,
                  current: themeProvider.themeMode,
                  icon: Icons.dark_mode_rounded,
                  title: localizations.themeDark,
                  subtitle: localizations.themeDarkDesc,
                  onTap: () => themeProvider.setThemeMode(ThemeMode.dark),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeOption(
    BuildContext context, {
    required ThemeMode mode,
    required ThemeMode current,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final isSelected = mode == current;
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: scheme.onSurfaceVariant, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: scheme.onSurface),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isSelected) Icon(Icons.check_circle_rounded, color: scheme.primary, size: 22),
          ],
        ),
      ),
    );
  }
}
