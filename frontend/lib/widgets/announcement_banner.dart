import 'package:flutter/material.dart';
import 'package:frontend/models/app_config.dart';
import 'package:frontend/providers/app_control_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// SharedPreferences key holding `"<id>@<updatedAt>"` of the announcement the
/// person closed on this device. An edited announcement has a new `updatedAt`,
/// so it shows again.
const String dismissedAnnouncementKey = 'dismissed_announcement';

String _stamp(Announcement a) => '${a.id}@${a.updatedAt}';

/// Opens the banner's link outside the app. A seam for tests.
Future<bool> Function(Uri uri) announcementLinkLauncher =
    (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

/// Only `http(s)` links are opened (the server checks too, this is the second
/// lock: never a `javascript:`, `tel:` or `intent:` link).
Uri? _safeLink(String? url) {
  if (url == null) return null;
  final uri = Uri.tryParse(url);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return null;
  return uri;
}

/// The owner's announcement (`AppConfig.announcement`) at the top of the
/// dashboard, with a close button and an optional link that opens outside the
/// app. Shows nothing when there is none or the person closed this version.
class AnnouncementBanner extends StatefulWidget {
  const AnnouncementBanner({super.key, this.padding = EdgeInsets.zero});

  /// Space around the banner; only taken when a banner shows (nothing when
  /// there is none).
  final EdgeInsetsGeometry padding;

  @override
  State<AnnouncementBanner> createState() => _AnnouncementBannerState();
}

class _AnnouncementBannerState extends State<AnnouncementBanner> {
  /// What this device closed; null until read (nothing shows before that, so a
  /// closed announcement does not flash).
  String? _dismissed;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    String? stored;
    try {
      final prefs = await SharedPreferences.getInstance();
      stored = prefs.getString(dismissedAnnouncementKey);
    } catch (_) {
      // Unreadable storage: show the announcement.
    }
    if (!mounted) return;
    setState(() {
      _dismissed = stored;
      _loaded = true;
    });
  }

  Future<void> _close(Announcement a) async {
    final stamp = _stamp(a);
    setState(() => _dismissed = stamp);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(dismissedAnnouncementKey, stamp);
    } catch (_) {
      // Closed for this session only.
    }
  }

  Future<void> _open(Uri uri) async {
    try {
      await announcementLinkLauncher(uri);
    } catch (_) {
      // Nothing can open it: the banner stays as it is.
    }
  }

  @override
  Widget build(BuildContext context) {
    final announcement = AppControlProvider.maybeOf(context)?.config.announcement;
    if (!_loaded || announcement == null || _dismissed == _stamp(announcement)) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final warning = announcement.style == 'warning';
    final background = warning ? scheme.errorContainer : scheme.secondaryContainer;
    final foreground = warning ? scheme.onErrorContainer : scheme.onSecondaryContainer;
    final linkUri = _safeLink(announcement.linkUrl);
    final hasLink = linkUri != null && announcement.linkLabel.isNotEmpty;

    return Padding(
      padding: widget.padding,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  warning ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
                  size: 20,
                  color: foreground,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      announcement.text,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: foreground),
                    ),
                    if (hasLink)
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: foreground,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          alignment: Alignment.centerLeft,
                        ),
                        onPressed: () => _open(linkUri),
                        child: Text(
                          announcement.linkLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded, size: 20, color: foreground),
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => _close(announcement),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
