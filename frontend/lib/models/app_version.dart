enum Platform {
  android,
  ios,
  all;

  static Platform fromString(String value) {
    return Platform.values.firstWhere(
      (e) => e.name == value.toLowerCase(),
      orElse: () => Platform.all,
    );
  }
}

class AppVersion {
  final String id;
  final String version;
  final Platform platform;
  final String downloadUrl;
  final String? releaseNotes;
  final bool isForceUpdate;
  final String? minSupportedVersion;
  final bool isActive;
  final DateTime createdAt;

  AppVersion({
    required this.id,
    required this.version,
    required this.platform,
    required this.downloadUrl,
    this.releaseNotes,
    required this.isForceUpdate,
    this.minSupportedVersion,
    required this.isActive,
    required this.createdAt,
  });

  factory AppVersion.fromJson(Map<String, dynamic> json) {
    return AppVersion(
      id: json['id'],
      version: json['version'],
      platform: Platform.fromString(json['platform'] ?? 'all'),
      downloadUrl: json['download_url'],
      releaseNotes: json['release_notes'],
      isForceUpdate: json['is_force_update'] ?? false,
      minSupportedVersion: json['min_supported_version'],
      isActive: json['is_active'] ?? true,
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class VersionCheckResponse {
  final bool isUpToDate;
  final bool forceUpdate;
  final String latestVersion;
  final String? downloadUrl;
  final String? releaseNotes;
  final String message;

  VersionCheckResponse({
    required this.isUpToDate,
    required this.forceUpdate,
    required this.latestVersion,
    this.downloadUrl,
    this.releaseNotes,
    required this.message,
  });

  factory VersionCheckResponse.fromJson(Map<String, dynamic> json) {
    return VersionCheckResponse(
      isUpToDate: json['is_up_to_date'] ?? true,
      forceUpdate: json['force_update'] ?? false,
      latestVersion: json['latest_version'] ?? '',
      downloadUrl: json['download_url'],
      releaseNotes: json['release_notes'],
      message: json['message'] ?? '',
    );
  }
}
