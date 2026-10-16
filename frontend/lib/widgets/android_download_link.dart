import 'package:flutter/material.dart';
import 'package:frontend/platform/platform_info.dart';
import 'package:frontend/platform/user_agent.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:url_launcher/url_launcher.dart';

/// Whether to show the "Get the Android app" link: only in a browser, and not
/// on iPhone/iPad/iPod, which cannot install an APK.
bool shouldOfferAndroidDownload({
  required bool isWeb,
  required String userAgent,
}) {
  return isWeb &&
      !RegExp('iPhone|iPad|iPod', caseSensitive: false).hasMatch(userAgent);
}

/// A link to the latest Android APK. Renders nothing inside the Android app,
/// on iOS browsers, or when no version is published.
class AndroidDownloadLink extends StatefulWidget {
  const AndroidDownloadLink({super.key, this.inDrawer = false});

  /// Draw as a drawer row (icon + label) instead of a centred text link.
  final bool inDrawer;

  @override
  State<AndroidDownloadLink> createState() => _AndroidDownloadLinkState();
}

class _AndroidDownloadLinkState extends State<AndroidDownloadLink> {
  AndroidDownload? _download;

  @override
  void initState() {
    super.initState();
    if (shouldOfferAndroidDownload(
      isWeb: PlatformInfo.isWeb,
      userAgent: currentUserAgent(),
    )) {
      _load();
    }
  }

  Future<void> _load() async {
    final download = await ApiService.getLatestAndroidDownload();
    if (!mounted || download == null) return;
    setState(() => _download = download);
  }

  Future<void> _open(AndroidDownload download) async {
    final uri = Uri.tryParse(download.url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final download = _download;
    if (download == null) return const SizedBox.shrink();

    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final versionText =
        localizations.androidAppVersion.replaceAll('{version}', download.version);

    if (widget.inDrawer) {
      return InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: () => _open(download),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.android_rounded, size: 22, color: scheme.onSurfaceVariant),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localizations.getAndroidApp,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      versionText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _open(download),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.android_rounded, size: 20, color: scheme.primary),
                const SizedBox(width: 6),
                Text(
                  localizations.getAndroidApp,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
            Text(
              versionText,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
