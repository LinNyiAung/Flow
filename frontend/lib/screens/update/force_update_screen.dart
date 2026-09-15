import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/app_version_provider.dart';

/// Shown as a full-screen block when `force_update = true`.
/// The user cannot dismiss this screen — they must tap the download button.
class ForceUpdateScreen extends StatefulWidget {
  const ForceUpdateScreen({Key? key}) : super(key: key);

  @override
  State<ForceUpdateScreen> createState() => _ForceUpdateScreenState();
}

class _ForceUpdateScreenState extends State<ForceUpdateScreen> {
  // Real, on-device value (package_info_plus is already a project
  // dependency) — used only to render the "you have X → Y" delta. Left
  // null (and simply not shown) if it can't be read for any reason.
  String? _installedVersion;

  @override
  void initState() {
    super.initState();
    _loadInstalledVersion();
  }

  Future<void> _loadInstalledVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _installedVersion = info.version);
    } catch (_) {
      // Version-delta row is simply omitted below.
    }
  }

  Future<void> _launchDownloadUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);

    // Try each mode in order until one works
    final modes = [
      LaunchMode.externalApplication,
      LaunchMode.externalNonBrowserApplication,
      LaunchMode.inAppBrowserView,
      LaunchMode.platformDefault,
    ];

    for (final mode in modes) {
      try {
        final launched = await launchUrl(uri, mode: mode);
        if (launched) return; // success — stop trying
      } catch (_) {
        continue; // try next mode
      }
    }

    // All modes failed — show snackbar
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No browser found. Please visit manually:\n$url',
            style: const TextStyle(fontSize: 13),
          ),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Copy',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
            },
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final versionCheck = context.watch<AppVersionProvider>().versionCheck;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final downloadUrl = versionCheck?.downloadUrl ?? '';
    final latestVersion = versionCheck?.latestVersion ?? '';
    final releaseNotes = versionCheck?.releaseNotes;
    final message = versionCheck?.message;

    return PopScope(
      // Prevent back navigation from dismissing the force-update screen
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Icon
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Icon(Icons.system_update_rounded, size: 48, color: scheme.primary),
                  ),
                  const SizedBox(height: 24),

                  // Title
                  Text(
                    'Time for an update',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Why it's mandatory — the backend's own message when it
                  // sends one, otherwise a generic fallback.
                  Text(
                    (message != null && message.isNotEmpty)
                        ? message
                        : 'A new version is available. Please update to continue using the app.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
                  ),

                  // Release notes card (if available)
                  if (releaseNotes != null && releaseNotes.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: theme.cardTheme.color,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: theme.cardTheme.shadowColor ?? Colors.black12,
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            latestVersion.isNotEmpty ? "WHAT'S NEW IN $latestVersion" : "WHAT'S NEW",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurfaceVariant,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            releaseNotes,
                            style: TextStyle(fontSize: 14, color: scheme.onSurface, height: 1.5),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Version delta — only shown once the real installed
                  // version has been read from the device.
                  if (_installedVersion != null && latestVersion.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'You have $_installedVersion',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.arrow_forward_rounded, size: 14, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Text(
                          latestVersion,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: scheme.primary),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 28),

                  // Download / Update button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: downloadUrl.isNotEmpty ? () => _launchDownloadUrl(context, downloadUrl) : null,
                      icon: const Icon(Icons.download_rounded, size: 22),
                      label: const Text('Update now'),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Small helper text — reassures about data safety, per the
                  // handoff copy ("nothing is lost by updating").
                  Text(
                    'Your records stay on the device — nothing is lost by updating.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
