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
    this.configProfile,
    this.appliedProfileSha256,
    this.hasDirectConfig = false,
    this.install,
    List<BackupRecord>? backups,
    this.createdAt,
    this.lastPlayedAt,
  }) : backups = backups ?? [];
  final String id;
  String name;
  GameSource source;
  String? exePath, selectedProxy, configProfile, appliedProfileSha256;
  bool hasDirectConfig;
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
      configProfile: _string(map, 'configProfile', 'config_profile'),
      appliedProfileSha256: _string(
        map,
        'appliedProfileSha256',
        'applied_profile_sha256',
      ),
      hasDirectConfig:
          (map['hasDirectConfig'] ?? map['has_direct_config']) == true,
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
    'configProfile': configProfile,
    'appliedProfileSha256': appliedProfileSha256,
    'hasDirectConfig': hasDirectConfig,
    'install': install?.toJson(),
    'backups': backups.map((x) => x.toJson()).toList(),
    'createdAt': createdAt?.toIso8601String(),
    'lastPlayedAt': lastPlayedAt?.toIso8601String(),
  };
}

class AdvancedOverrides {
  const AdvancedOverrides({this.loggingExtra, this.debug, this.enabled});
  final bool? loggingExtra, debug, enabled;
}

class ConfigProfile {
  const ConfigProfile({
    required this.name,
    required this.router,
    required this.kernelImage,
    required this.hardwareBilinear,
    required this.maxGeneratedFrames,
    required this.loggingLevel,
    this.advanced = const AdvancedOverrides(),
  });
  final String name;
  final bool router, kernelImage, hardwareBilinear;
  final int maxGeneratedFrames, loggingLevel;
  final AdvancedOverrides advanced;
  String toIni() {
    final lines = <String>[
      '[Compatibility]',
      'Router=${router ? 'SM86' : 'SM75'}',
      'KernelImage=${kernelImage ? 'PTX' : 'Auto'}',
      'HardwareBilinear=${hardwareBilinear ? 1 : 0}',
      '',
      '[FrameGeneration]',
      'MaxGeneratedFrames=$maxGeneratedFrames',
      '',
      '[Logging]',
      'Level=$loggingLevel',
    ];
    if (advanced.loggingExtra != null)
      lines.add('Extra=${advanced.loggingExtra}');
    if (advanced.debug != null || advanced.enabled != null) {
      lines.addAll(['', '[General]']);
      if (advanced.enabled != null) lines.add('Enabled=${advanced.enabled}');
      if (advanced.debug != null) lines.add('Debug=${advanced.debug}');
    }
    return '${lines.join('\n')}\n';
  }
}

class ModHashCatalog {
  ModHashCatalog([
    Map<String, String>? hashes,
    Map<String, String>? latestHashes,
    this.sourceHeadCommit,
    Map<String, String>? latestFileHashes,
  ]) : hashes = hashes ?? {},
       latestHashes = latestHashes ?? {},
       latestFileHashes = latestFileHashes ?? {};

  /// All recognized upstream DLLs, including retired versions.
  final Map<String, String> hashes;

  /// DLL hashes present in the upstream repository's current HEAD commit.
  final Map<String, String> latestHashes;

  /// Full SHA of upstream's `main` commit from which this catalog was built.
  final String? sourceHeadCommit;

  /// SHA-256 values keyed by their upstream repository path.
  final Map<String, String> latestFileHashes;

  bool contains(String hash) => hashes.containsKey(hash.toLowerCase());
  bool isLatest(String hash) => latestHashes.containsKey(hash.toLowerCase());
  bool isHistorical(String hash) => contains(hash) && !isLatest(hash);
  String? latestFileHash(String path) => latestFileHashes[path];

  factory ModHashCatalog.fromJson(Object? value) {
    final root = _map(value);
    Map<String, String> index(Object? section) {
      final files = _map(section)['files'];
      if (files is! List) return {};
      return {
        for (final raw in files)
          if (_string(_map(raw), 'sha256') case final hash?)
            hash.toLowerCase():
                (_string(_map(raw), 'file_name', 'fileName') ??
                _string(_map(raw), 'path') ??
                ''),
      };
    }

    final latest = index(root['latest']);
    final historical = index(root['historical']);
    final latestFileHashes = <String, String>{
      for (final raw in (_map(root['latest'])['files'] as List? ?? const []))
        if (_string(_map(raw), 'path') case final path?)
          if (_string(_map(raw), 'sha256') case final hash?)
            path: hash.toLowerCase(),
    };
    final flat = _map(root['hashes'])
        .map((key, value) => MapEntry(key.toLowerCase(), value.toString()));
    // Version 1 catalogs only had the flat index.  Treat them as known
    // historical values instead of falsely declaring an old catalog current.
    return ModHashCatalog(
      {...flat, ...historical, ...latest},
      latest,
      _string(_map(root['source']), 'headCommit', 'head_commit') ??
          _string(_map(root['latest']), 'commit'),
      latestFileHashes,
    );
  }
  Map<String, dynamic> toJson() => {
    'hashes': hashes,
    if (latestHashes.isNotEmpty)
      'latest': {
        'files': [
          for (final entry in latestHashes.entries)
            {
              'sha256': entry.key,
              'file_name': entry.value,
              if (latestFileHashes.entries
                  .any((file) => file.value == entry.key))
                'path': latestFileHashes.entries
                    .firstWhere((file) => file.value == entry.key)
                    .key,
            },
        ],
      },
    if (sourceHeadCommit != null) 'source': {'head_commit': sourceHeadCommit},
  };
}

class Database {
  Database({
    List<GameEntry>? games,
    this.globalProfile,
    ModHashCatalog? catalog,
    this.installedVersion,
    this.steamInitialScanCompleted = false,
  }) : games = games ?? [],
       catalog = catalog ?? ModHashCatalog();
  final List<GameEntry> games;
  String? globalProfile, installedVersion;
  ModHashCatalog catalog;
  bool steamInitialScanCompleted;
  factory Database.fromJsonText(String text) {
    final m = _map(jsonDecode(text));
    return Database(
      games: (m['games'] is List ? m['games'] as List : const [])
          .map(GameEntry.fromJson)
          .toList(),
      globalProfile: _string(m, 'globalProfile', 'global_profile'),
      catalog: ModHashCatalog.fromJson(m['catalog']),
      installedVersion: _string(m, 'installedVersion', 'installed_version'),
      steamInitialScanCompleted:
          (m['steamInitialScanCompleted'] ??
              m['steam_initial_scan_completed']) ==
          true,
    );
  }
  String toJsonText() => const JsonEncoder.withIndent('  ').convert({
    'games': games.map((g) => g.toJson()).toList(),
    'global_profile': globalProfile,
    'catalog': catalog.toJson(),
    'installed_version': installedVersion,
    'steam_initial_scan_completed': steamInitialScanCompleted,
  });
}

enum TargetState { awaitingExe, ready, missing }

enum ModStateKind { applied, outdated, notApplied, broken }

class ModStatus {
  const ModStatus(this.kind, {this.version, this.proxy, this.detail});
  final ModStateKind kind;
  final String? version, proxy, detail;
}

enum ConfigStateKind {
  defaultConfig,
  global,
  dedicated,
  direct,
  externallyModified,
}

class ConfigStatus {
  const ConfigStatus(this.kind, [this.profile]);
  final ConfigStateKind kind;
  final String? profile;
}

class GameView {
  const GameView(this.game, this.target, this.mod, this.config);
  final GameEntry game;
  final TargetState target;
  final ModStatus mod;
  final ConfigStatus config;
}
