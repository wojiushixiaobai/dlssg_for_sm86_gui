import 'dart:convert';

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
String? _string(Map<String, dynamic> map, String camel, [String? snake]) =>
    (map[camel] ?? (snake == null ? null : map[snake]))?.toString();
DateTime? _date(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString())?.toUtc();

enum GameSourceKind { steam, manual }

class GameSource {
  const GameSource.steam(this.appId, this.libraryPath)
    : kind = GameSourceKind.steam;
  const GameSource.manual()
    : kind = GameSourceKind.manual,
      appId = null,
      libraryPath = null;

  final GameSourceKind kind;
  final int? appId;
  final String? libraryPath;

  factory GameSource.fromJson(Object? value) {
    final map = _map(value);
    if (map['kind'] == 'steam') {
      return GameSource.steam(
        int.tryParse(_string(map, 'appId', 'app_id') ?? '') ?? 0,
        _string(map, 'libraryPath', 'library_path') ?? '',
      );
    }
    return const GameSource.manual();
  }

  Map<String, dynamic> toJson() => kind == GameSourceKind.steam
      ? {'kind': 'steam', 'appId': appId, 'libraryPath': libraryPath}
      : {'kind': 'manual'};
}

class BackupRecord {
  const BackupRecord({
    required this.proxy,
    required this.file,
    required this.sha256,
    required this.capturedAt,
  });
  final String proxy, file, sha256;
  final DateTime? capturedAt;
  factory BackupRecord.fromJson(Object? value) {
    final map = _map(value);
    return BackupRecord(
      proxy: _string(map, 'proxy') ?? '',
      file: _string(map, 'file') ?? '',
      sha256: _string(map, 'sha256') ?? '',
      capturedAt: _date(_string(map, 'capturedAt', 'captured_at')),
    );
  }
  Map<String, dynamic> toJson() => {
    'proxy': proxy,
    'file': file,
    'sha256': sha256,
    'capturedAt': capturedAt?.toIso8601String(),
  };
}

class ManagedInstall {
  const ManagedInstall({
    required this.proxy,
    required this.dllSha256,
    required this.version,
    this.installedAt,
  });
  final String proxy, dllSha256, version;
  final DateTime? installedAt;
  factory ManagedInstall.fromJson(Object? value) {
    final map = _map(value);
    return ManagedInstall(
      proxy: _string(map, 'proxy') ?? 'version.dll',
      dllSha256: _string(map, 'dllSha256', 'dll_sha256') ?? '',
      version: _string(map, 'version') ?? '本地包',
      installedAt: _date(_string(map, 'installedAt', 'installed_at')),
    );
  }
  Map<String, dynamic> toJson() => {
    'proxy': proxy,
    'dllSha256': dllSha256,
    'version': version,
    'installedAt': installedAt?.toIso8601String(),
  };
}

class GameEntry {
  GameEntry({
    required this.id,
    required this.name,
    required this.source,
    this.exePath,
    this.selectedProxy,
    this.appliedProfileSha256,
    this.hasCustomConfig = false,
    this.install,
    List<BackupRecord>? backups,
    this.createdAt,
    this.lastPlayedAt,
  }) : backups = backups ?? [];
  final String id;
  String name;
  GameSource source;
  String? exePath, selectedProxy, appliedProfileSha256;
  bool hasCustomConfig;
  ManagedInstall? install;
  List<BackupRecord> backups;
  DateTime? createdAt, lastPlayedAt;
  factory GameEntry.fromJson(Object? value) {
    final map = _map(value);
    return GameEntry(
      id: _string(map, 'id') ?? '',
      name: _string(map, 'name') ?? '未命名游戏',
      source: GameSource.fromJson(map['source']),
      exePath: _string(map, 'exePath', 'exe_path'),
      selectedProxy: _string(map, 'selectedProxy', 'selected_proxy'),
      appliedProfileSha256: _string(
        map,
        'appliedProfileSha256',
        'applied_profile_sha256',
      ),
      // `hasDirectConfig` was the old name for a game-specific override.
      hasCustomConfig:
          (map['hasCustomConfig'] ??
              map['has_custom_config'] ??
              map['hasDirectConfig'] ??
              map['has_direct_config'] ??
              ((map['configProfile'] ?? map['config_profile']) != null)) ==
          true,
      install: map['install'] == null
          ? null
          : ManagedInstall.fromJson(map['install']),
      backups: (map['backups'] is List ? map['backups'] as List : const [])
          .map(BackupRecord.fromJson)
          .toList(),
      createdAt: _date(_string(map, 'createdAt', 'created_at')),
      lastPlayedAt: _date(_string(map, 'lastPlayedAt', 'last_played_at')),
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'source': source.toJson(),
    'exePath': exePath,
    'selectedProxy': selectedProxy,
    'appliedProfileSha256': appliedProfileSha256,
    'has_custom_config': hasCustomConfig,
    'install': install?.toJson(),
    'backups': backups.map((x) => x.toJson()).toList(),
    'createdAt': createdAt?.toIso8601String(),
    'lastPlayedAt': lastPlayedAt?.toIso8601String(),
  };
}

class IniSetting {
  const IniSetting({required this.key, required this.value});

  final String key, value;
}

class IniSection {
  const IniSection({required this.name, required this.settings});

  final String name;
  final List<IniSetting> settings;
}

/// A generic representation of the driver INI.  It deliberately does not
/// prescribe known sections or keys, so newer driver packages need no app
/// update merely to expose their configuration.
class ConfigProfile {
  const ConfigProfile({required this.name, required this.sections});

  final String name;
  final List<IniSection> sections;

  String? value(String section, String key) {
    for (final item in sections) {
      if (item.name.toLowerCase() != section.toLowerCase()) continue;
      for (final setting in item.settings) {
        if (setting.key.toLowerCase() == key.toLowerCase()) {
          return setting.value;
        }
      }
    }
    return null;
  }

  ConfigProfile withValue(String section, String key, String value) =>
      ConfigProfile(
        name: name,
        sections: [
          for (final item in sections)
            if (item.name.toLowerCase() == section.toLowerCase())
              IniSection(
                name: item.name,
                settings: [
                  for (final setting in item.settings)
                    setting.key.toLowerCase() == key.toLowerCase()
                        ? IniSetting(key: setting.key, value: value)
                        : setting,
                ],
              )
            else
              item,
        ],
      );

  String toIni() {
    final lines = <String>[];
    for (final section in sections) {
      if (lines.isNotEmpty) lines.add('');
      lines.add('[${section.name}]');
      lines.addAll(
        section.settings.map((setting) => '${setting.key}=${setting.value}'),
      );
    }
    return '${lines.join('\n')}\n';
  }
}

class Database {
  Database({
    List<GameEntry>? games,
    this.installedVersion,
    this.legacyGlobalProfile,
    this.steamInitialScanCompleted = false,
  }) : games = games ?? [];
  final List<GameEntry> games;
  String? installedVersion;

  /// One-time migration source for state files written before global.ini.
  final String? legacyGlobalProfile;
  bool steamInitialScanCompleted;
  factory Database.fromJsonText(String text) {
    final m = _map(jsonDecode(text));
    return Database(
      games: (m['games'] is List ? m['games'] as List : const [])
          .map(GameEntry.fromJson)
          .toList(),
      installedVersion: _string(m, 'installedVersion', 'installed_version'),
      legacyGlobalProfile: _string(m, 'globalProfile', 'global_profile'),
      steamInitialScanCompleted:
          (m['steamInitialScanCompleted'] ??
              m['steam_initial_scan_completed']) ==
          true,
    );
  }
  String toJsonText() => const JsonEncoder.withIndent('  ').convert({
    'games': games.map((g) => g.toJson()).toList(),
    'installed_version': installedVersion,
    'steam_initial_scan_completed': steamInitialScanCompleted,
  });
}

enum TargetState { awaitingExe, ready, missing }

enum ModStateKind { applied, notApplied }

class ModStatus {
  const ModStatus(this.kind, {this.version, this.proxy});
  final ModStateKind kind;
  final String? version, proxy;
}

enum ConfigStateKind { global, custom, externallyModified }

class ConfigStatus {
  const ConfigStatus(this.kind);
  final ConfigStateKind kind;
}

class GameView {
  const GameView(this.game, this.target, this.mod, this.config);
  final GameEntry game;
  final TargetState target;
  final ModStatus mod;
  final ConfigStatus config;
}
