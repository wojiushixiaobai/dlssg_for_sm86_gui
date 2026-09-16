import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:win32/win32.dart';

import 'models.dart';
import 'steam.dart';

const proxies = [
  'version.dll',
  'winmm.dll',
  'dinput8.dll',
  'dxgi.dll',
  'd3d12.dll',
  'dbghelp.dll',
];
const defaultProxy = 'version.dll';
const latestReleaseUrl =
    'https://api.github.com/repos/sdli1995/dlssg_for_sm86/releases/latest';
const modArchiveName = 'dlssg_for_sm86.tar.gz';
const appStorageDirectoryName = 'dlssg_for_sm86_gui';

class ManagerInfo {
  const ManagerInfo({
    required this.dataDirectory,
    required this.installedVersion,
    required this.modAvailable,
  });
  final String dataDirectory;
  final String? installedVersion;
  final bool modAvailable;
}

enum DownloadPhase { downloading, verifying }

/// A snapshot emitted while the upstream driver archive is being prepared.
/// [totalBytes] is absent when the server does not send a Content-Length.
class DownloadProgress {
  const DownloadProgress({
    required this.phase,
    required this.downloadedBytes,
    this.totalBytes,
  });

  final DownloadPhase phase;
  final int downloadedBytes;
  final int? totalBytes;

  double? get fraction => totalBytes == null || totalBytes == 0
      ? null
      : (downloadedBytes / totalBytes!).clamp(0, 1).toDouble();
}

class ModManager {
  ModManager._(
    this.root,
    this.releaseRoot,
    this.db, {
    SteamScanner? scanner,
    http.Client? client,
  }) : scanner = scanner ?? SteamScanner(),
       client = client ?? http.Client();
  final Directory root;
  final Directory releaseRoot;
  Database db;
  final SteamScanner scanner;
  final http.Client client;
  final _uuid = const Uuid();
  final _fileHashCache = <String, _FileHashCacheEntry>{};

  /// Application storage under `%LOCALAPPDATA%\dlssg_for_sm86_gui`.
  ///
  /// [localAppDataDirectory] exists for tests and callers that need to supply
  /// a different LocalAppData root.
  static Directory defaultApplicationStorageDirectory([
    Directory? localAppDataDirectory,
  ]) => Directory(
    p.join(
      (localAppDataDirectory ?? _localAppDataDirectory()).path,
      appStorageDirectoryName,
    ),
  );

  static Directory defaultDataDirectory([Directory? localAppDataDirectory]) =>
      Directory(
        p.join(
          defaultApplicationStorageDirectory(localAppDataDirectory).path,
          'data',
        ),
      );

  static Directory defaultReleaseDirectory([
    Directory? localAppDataDirectory,
  ]) => Directory(
    p.join(
      defaultApplicationStorageDirectory(localAppDataDirectory).path,
      'release',
    ),
  );

  static Directory _localAppDataDirectory() {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null && localAppData.trim().isNotEmpty) {
      return Directory(localAppData);
    }
    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null && userProfile.trim().isNotEmpty) {
      return Directory(p.join(userProfile, 'AppData', 'Local'));
    }
    throw StateError('无法确定 %LOCALAPPDATA% 目录。');
  }

  static Future<ModManager> open({
    Directory? dataDirectory,
    SteamScanner? scanner,
    http.Client? client,
  }) async {
    final root = dataDirectory ?? defaultDataDirectory();
    final releaseRoot = dataDirectory == null
        ? defaultReleaseDirectory()
        : Directory(p.join(root.path, 'release'));
    await root.create(recursive: true);
    await releaseRoot.create(recursive: true);
    await Directory(p.join(root.path, 'backups')).create(recursive: true);
    final state = File(p.join(root.path, 'state.json'));
    Database db = Database();
    if (await state.exists()) {
      try {
        db = Database.fromJsonText(await state.readAsString());
      } catch (_) {
        throw StateError('无法读取 data/state.json；请修复或恢复该文件。');
      }
    }
    final manager = ModManager._(
      root,
      releaseRoot,
      db,
      scanner: scanner,
      client: client,
    );
    await manager._migrateLegacyGlobalProfile();
    try {
      await manager.scanSteam();
      if (!manager.db.steamInitialScanCompleted) {
        manager.db.steamInitialScanCompleted = true;
        await manager._save();
      }
    } catch (_) {}
    return manager;
  }

  String? get _installedReleaseTag {
    final tag = db.installedVersion;
    return tag != null && RegExp(r'^[0-9A-Za-z._-]+$').hasMatch(tag)
        ? tag
        : null;
  }

  /// The active package always lives in one disposable directory.  The tag is
  /// kept in state for display and update checks, not as a directory name.
  Directory get _packageDirectory =>
      Directory(p.join(releaseRoot.path, 'dlssg_for_sm86'));

  bool get hasModPackage {
    return _installedReleaseTag != null &&
        File(p.join(_packageDirectory.path, 'dlssg_sm86.ini')).existsSync();
  }

  ManagerInfo get info => ManagerInfo(
    dataDirectory: root.path,
    installedVersion: db.installedVersion,
    modAvailable: hasModPackage,
  );
  Future<void> _save() => atomicWrite(
    File(p.join(root.path, 'state.json')),
    utf8.encode(db.toJsonText()),
  );
  void _requireMod() {
    if (!hasModPackage) throw StateError('请先在“驱动程序”页面下载并验证 dlssg_for_sm86。');
  }

  Future<void> _migrateLegacyGlobalProfile() async {
    final name = db.legacyGlobalProfile;
    if (name == null || await _globalIniFile.exists()) return;
    if (name.trim().isEmpty || RegExp(r'[\\/:*?"<>|]').hasMatch(name)) return;
    final old = File(p.join(root.path, 'profiles', '$name.ini'));
    if (await old.exists()) await copyAtomic(old, _globalIniFile);
  }

  File get _globalIniFile => File(p.join(root.path, 'global.ini'));

  File _defaultIniFile() =>
      File(p.join(_packageDirectory.path, 'dlssg_sm86.ini'));
  File _modDll(String proxy) => _proxyDllIn(_packageDirectory, proxy);

  File _proxyDllIn(Directory package, String proxy) {
    if (proxy == defaultProxy) return File(p.join(package.path, proxy));
    final preferred = File(p.join(package.path, 'alternatives', proxy));
    if (preferred.existsSync()) return preferred;
    // Compatibility with the misspelled directory used by older packages.
    final legacy = File(p.join(package.path, 'altnative', proxy));
    if (legacy.existsSync()) return legacy;
    return preferred;
  }

  /// Creates the editable global configuration from the INI bundled with the
  /// installed driver package. Existing user settings are never replaced.
  Future<void> _ensureGlobalIniFromPackage() async {
    if (await _globalIniFile.exists()) return;
    final source = _defaultIniFile();
    if (!await source.exists()) {
      throw StateError('驱动程序包缺少 dlssg_sm86.ini。');
    }
    await copyAtomic(source, _globalIniFile);
  }

  Future<List<GameView>> listGames() async => db.games.map(view).toList();

  /// Returns the folder that should be shown first when choosing a game's EXE.
  /// Steam's app manifest remains a fallback when executable detection has not
  /// found a usable target yet.
  Future<String?> gameDirectory(GameEntry game) async {
    if (game.exePath != null) return File(game.exePath!).parent.path;
    if (game.source.kind != GameSourceKind.steam ||
        game.source.appId == null ||
        game.source.libraryPath == null) {
      return null;
    }

    final manifest = File(
      p.join(
        game.source.libraryPath!,
        'steamapps',
        'appmanifest_${game.source.appId}.acf',
      ),
    );
    if (!await manifest.exists()) {
      return null;
    }
    final installDir = SteamScanner.parseAppManifest(
      await manifest.readAsString(),
    )['installdir'];
    if (installDir == null || installDir.isEmpty) {
      return null;
    }
    final directory = Directory(
      p.join(game.source.libraryPath!, 'steamapps', 'common', installDir),
    );
    return await directory.exists() ? directory.path : null;
  }

  GameView view(GameEntry game) =>
      GameView(game, _targetState(game), _modState(game), _configState(game));
  TargetState _targetState(GameEntry game) => game.exePath == null
      ? TargetState.awaitingExe
      : File(game.exePath!).existsSync()
      ? TargetState.ready
      : TargetState.missing;
  ModStatus _modState(GameEntry game) {
    if (game.exePath == null) return const ModStatus(ModStateKind.notApplied);
    final dir = File(game.exePath!).parent;
    if (!File(p.join(dir.path, 'dlssg_sm86.ini')).existsSync()) {
      return const ModStatus(ModStateKind.notApplied);
    }

    String? proxy;
    for (final candidate in proxies) {
      if (!File(p.join(dir.path, candidate)).existsSync()) continue;
      if (proxy != null) {
        return const ModStatus(ModStateKind.applied, version: '未知版本');
      }
      proxy = candidate;
    }
    if (proxy == null) return const ModStatus(ModStateKind.notApplied);

    var version = '未知版本';
    final hash = _cachedSha256(File(p.join(dir.path, proxy))).toLowerCase();
    final packaged = _modDll(proxy);
    final currentHash = packaged.existsSync()
        ? _cachedSha256(packaged).toLowerCase()
        : null;
    if (game.install?.dllSha256.toLowerCase() == hash) {
      version = game.install?.version ?? '未知版本';
    } else if (currentHash == hash) {
      version = db.installedVersion ?? '本地包';
    }
    return ModStatus(ModStateKind.applied, proxy: proxy, version: version);
  }

  ConfigStatus _configState(GameEntry game) {
    if (game.exePath != null) {
      final gameIni = File(
        p.join(File(game.exePath!).parent.path, 'dlssg_sm86.ini'),
      );
      if (gameIni.existsSync()) {
        final actual = _cachedSha256(gameIni);
        if (game.appliedProfileSha256 != null &&
            game.appliedProfileSha256 != actual) {
          return const ConfigStatus(ConfigStateKind.externallyModified);
        }
      }
    }
    return ConfigStatus(
      game.hasCustomConfig ? ConfigStateKind.custom : ConfigStateKind.global,
    );
  }

  static ConfigProfile parseProfile(String name, String text) {
    final sections = <IniSection>[];
    IniSection? section;
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      final separator = line.indexOf('=');
      if (line.startsWith('[') && line.endsWith(']')) {
        section = IniSection(
          name: line.substring(1, line.length - 1),
          settings: [],
        );
        sections.add(section);
      } else if (section != null &&
          separator >= 0 &&
          !line.startsWith(';') &&
          !line.startsWith('#')) {
        section.settings.add(
          IniSetting(
            key: line.substring(0, separator).trim(),
            value: line.substring(separator + 1).trim(),
          ),
        );
      }
    }
    return ConfigProfile(name: name, sections: sections);
  }

  Future<ConfigProfile> loadGlobalConfig() async {
    _requireMod();
    await _ensureGlobalIniFromPackage();
    return parseProfile('全局配置', await _globalIniFile.readAsString());
  }

  Future<void> saveGlobalConfig(ConfigProfile config) async {
    _requireMod();
    await atomicWrite(_globalIniFile, utf8.encode(config.toIni()));
    for (final game in db.games.where(
      (x) =>
          !x.hasCustomConfig &&
          x.install != null &&
          x.exePath != null &&
          File(x.exePath!).existsSync(),
    )) {
      await _writeInheritedConfig(game);
    }
    await _save();
  }

  Future<GameEntry> addManualGame(String name, String exePath) async {
    final normalized = p.normalize(exePath).toLowerCase();
    for (final game in db.games) {
      if (game.exePath != null &&
          p.normalize(game.exePath!).toLowerCase() == normalized) {
        return game;
      }
    }
    final game = GameEntry(
      id: _uuid.v4(),
      name: name,
      source: const GameSource.manual(),
      exePath: exePath,
      selectedProxy: defaultProxy,
      createdAt: DateTime.now().toUtc(),
    );
    db.games.add(game);
    await _save();
    return game;
  }

  Future<void> setGameExe(String id, String exePath) async {
    _game(id).exePath = exePath;
    await _save();
  }

  Future<void> removeGame(String id) async {
    final game = _game(id);
    db.games.remove(game);
    await _save();
  }

  Future<void> launchGame(String id) async {
    final game = _game(id);
    if (game.exePath == null || !File(game.exePath!).existsSync()) {
      throw StateError('请先选择有效的游戏 EXE');
    }
    await Process.start(
      game.exePath!,
      const [],
      mode: ProcessStartMode.detached,
    );
    game.lastPlayedAt = DateTime.now().toUtc();
    await _save();
  }

  GameEntry _game(String id) {
    for (final game in db.games) {
      if (game.id == id) return game;
    }
    throw StateError('游戏不存在');
  }

  Future<void> installMod(
    String id, {
    String? proxy,
    bool confirmOverwrite = false,
  }) async {
    _requireMod();
    final game = _game(id);
    final desired = (proxy ?? game.selectedProxy ?? defaultProxy).toLowerCase();
    if (!proxies.contains(desired)) throw ArgumentError('不支持的代理 DLL');
    final source = _modDll(desired);
    if (!await source.exists()) throw StateError('未找到已缓存的驱动程序包；请先下载有效版本');
    final dir = _gameDirectory(game);
    final old = game.install?.proxy;
    final target = File(p.join(dir.path, desired));
    final hadTarget = await target.exists();
    final detected = _modState(game);
    final updatingDetectedDriver =
        detected.kind == ModStateKind.applied && detected.proxy == desired;
    // If the INI is absent, the game is not installed by definition.  Backup
    // any target DLL even when stale state metadata happens to match it.
    final needsBackup = hadTarget && !updatingDetectedDriver;
    if (needsBackup) {
      if (game.source.kind == GameSourceKind.manual && !confirmOverwrite) {
        throw StateError('目标 DLL 不是已知 DLSSG 文件。确认后将保存其原始副本并覆盖。');
      }
    }
    final rollback = File(
      p.join(dir.path, '.dlssg-$desired-${_uuid.v4()}.rollback'),
    );
    if (hadTarget) await copyAtomic(target, rollback);
    try {
      if (needsBackup) await _recordBackup(game, desired, target);
      await copyAtomic(source, target);
      if (old != null && old != desired) {
        try {
          await _restoreOrRemove(game, old);
        } catch (_) {
          if (hadTarget) {
            await copyAtomic(rollback, target);
          } else if (await target.exists()) {
            await target.delete();
          }
          rethrow;
        }
      }
      final hash = await sha256File(target);
      game.selectedProxy = desired;
      game.install = ManagedInstall(
        proxy: desired,
        dllSha256: hash,
        version: db.installedVersion ?? '本地包',
        installedAt: DateTime.now().toUtc(),
      );
      final ini = File(p.join(dir.path, 'dlssg_sm86.ini'));
      if (!await ini.exists()) {
        await atomicWrite(ini, await _configurationBytes());
        game.hasCustomConfig = false;
        game.appliedProfileSha256 = await sha256File(ini);
      } else if (game.appliedProfileSha256 == null) {
        // Keep an existing external configuration intact while recording it
        // as a game-specific configuration once its proxy is managed here.
        game.hasCustomConfig = true;
        game.appliedProfileSha256 = await sha256File(ini);
      }
      await _save();
    } finally {
      if (await rollback.exists()) await rollback.delete();
    }
  }

  Future<void> uninstallMod(String id) async {
    final game = _game(id);
    // Use the on-disk proxy when recognizing an installation that predates
    // per-game metadata, so uninstall removes the DLL that was actually found.
    final proxy =
        game.install?.proxy ?? _modState(game).proxy ?? game.selectedProxy;
    if (proxy != null) await _restoreOrRemove(game, proxy);
    final ini = File(p.join(_gameDirectory(game).path, 'dlssg_sm86.ini'));
    if (await ini.exists()) await ini.delete();
    game.install = null;
    game.appliedProfileSha256 = null;
    game.hasCustomConfig = false;
    await _save();
  }

  Future<void> applyConfigToGame(String id) async {
    _requireMod();
    final game = _game(id);
    game.hasCustomConfig = false;
    await _writeInheritedConfig(game);
    await _save();
  }

  /// Reads the configuration that is currently effective for one game.
  ///
  /// A missing game INI inherits the global configuration created from the
  /// installed driver's bundled dlssg_sm86.ini.
  Future<ConfigProfile> loadGameConfig(String id) async {
    final game = _game(id);
    final ini = game.exePath == null
        ? null
        : File(p.join(File(game.exePath!).parent.path, 'dlssg_sm86.ini'));
    if (ini != null && await ini.exists()) {
      return parseProfile(game.name, await ini.readAsString());
    }
    _requireMod();
    await _ensureGlobalIniFromPackage();
    return parseProfile(game.name, await _globalIniFile.readAsString());
  }

  /// Immediately persists a game's custom settings to its dlssg_sm86.ini.
  Future<void> saveGameConfig(String id, ConfigProfile config) async {
    final game = _game(id);
    final ini = File(p.join(_gameDirectory(game).path, 'dlssg_sm86.ini'));
    if (!await ini.exists()) _requireMod();
    await atomicWrite(ini, utf8.encode(config.toIni()));
    game.hasCustomConfig = true;
    game.appliedProfileSha256 = await sha256File(ini);
    await _save();
  }

  Future<List<int>> _configurationBytes() async {
    await _ensureGlobalIniFromPackage();
    return _globalIniFile.readAsBytes();
  }

  Future<void> _writeInheritedConfig(GameEntry game) async {
    final ini = File(p.join(_gameDirectory(game).path, 'dlssg_sm86.ini'));
    await atomicWrite(ini, await _configurationBytes());
    game.appliedProfileSha256 = await sha256File(ini);
  }

  String _cachedSha256(File file) {
    final stat = file.statSync();
    final key = p.normalize(file.path).toLowerCase();
    final cached = _fileHashCache[key];
    if (cached != null &&
        cached.size == stat.size &&
        cached.modified == stat.modified) {
      return cached.hash;
    }
    final hash = sha256FileSync(file);
    _fileHashCache[key] = _FileHashCacheEntry(stat.size, stat.modified, hash);
    return hash;
  }

  Directory _gameDirectory(GameEntry game) {
    if (game.exePath == null || !File(game.exePath!).existsSync()) {
      throw StateError('请先选择有效的游戏 EXE');
    }
    return File(game.exePath!).parent;
  }

  File _backupFile(GameEntry game, String proxy) =>
      File(p.join(root.path, 'backups', game.id, '$proxy.original.dll'));
  Future<void> _recordBackup(
    GameEntry game,
    String proxy,
    File original,
  ) async {
    final backup = _backupFile(game, proxy);
    await copyAtomic(original, backup);
    game.backups.removeWhere((b) => b.proxy == proxy);
    game.backups.add(
      BackupRecord(
        proxy: proxy,
        file: backup.path,
        sha256: await sha256File(original),
        capturedAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> _restoreOrRemove(GameEntry game, String proxy) async {
    final target = File(p.join(_gameDirectory(game).path, proxy)),
        backup = _backupFile(game, proxy);
    if (await backup.exists()) {
      await copyAtomic(backup, target);
    } else if (await target.exists()) {
      await target.delete();
    }
    game.backups.removeWhere((b) => b.proxy == proxy);
  }

  Future<int> scanSteam() async {
    final games = await scanner.scan(existing: db.games);
    final changed =
        jsonEncode(games.map((game) => game.toJson()).toList()) !=
        jsonEncode(db.games.map((game) => game.toJson()).toList());
    if (changed) {
      db = Database(
        games: games,
        installedVersion: db.installedVersion,
        legacyGlobalProfile: db.legacyGlobalProfile,
        steamInitialScanCompleted: db.steamInitialScanCompleted,
      );
      await _save();
    }
    return db.games.where((x) => x.source.kind == GameSourceKind.steam).length;
  }

  Future<String> latestDriverVersion() async =>
      (await _latestRelease()).version;

  Future<_LatestRelease> _latestRelease() async {
    final response = await client.get(
      Uri.parse(latestReleaseUrl),
      headers: {'User-Agent': 'DLSSG-SM86-Manager'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('无法获取上游最新 Release：HTTP ${response.statusCode}');
    }
    final release = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    final version = _releaseTag(release['tag_name']);
    final archiveUrl = release['tarball_url']?.toString();
    if (archiveUrl == null || archiveUrl.isEmpty) {
      throw StateError('上游最新 Release 未提供 tar.gz 下载地址。');
    }
    return _LatestRelease(version, Uri.parse(archiveUrl));
  }

  Future<String> refreshModFromGithub({
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    final release = await _latestRelease();
    final version = release.version;
    final previousVersion = _installedReleaseTag;
    final releaseDirectory = _packageDirectory;
    final archiveDirectory = Directory(p.join(releaseRoot.path, version));
    final archiveFile = File(p.join(archiveDirectory.path, modArchiveName));
    final previousCacheArchive = File(p.join(releaseRoot.path, modArchiveName));
    final previousCacheVersion = File(
      p.join(releaseRoot.path, '$modArchiveName.version'),
    );
    final legacyArchiveFile = File(
      p.join(releaseDirectory.path, modArchiveName),
    );
    List<int> archiveBytes;
    if (await archiveFile.exists()) {
      archiveBytes = await archiveFile.readAsBytes();
    } else if (await previousCacheArchive.exists() &&
        await previousCacheVersion.exists() &&
        (await previousCacheVersion.readAsString()).trim() == version) {
      archiveBytes = await previousCacheArchive.readAsBytes();
      await atomicWrite(archiveFile, archiveBytes);
    } else if (previousVersion == version && await legacyArchiveFile.exists()) {
      archiveBytes = await legacyArchiveFile.readAsBytes();
      await atomicWrite(archiveFile, archiveBytes);
    } else {
      final request = http.Request('GET', release.archiveUrl)
        ..headers['User-Agent'] = 'DLSSG-SM86-Manager';
      final download = await client.send(request);
      if (download.statusCode < 200 || download.statusCode >= 300) {
        throw StateError(
          '下载上游 Release $version 的 tar.gz 失败：HTTP ${download.statusCode}',
        );
      }
      final totalBytes = download.contentLength;
      var downloadedBytes = 0;
      final buffer = BytesBuilder(copy: false);
      onProgress?.call(
        DownloadProgress(
          phase: DownloadPhase.downloading,
          downloadedBytes: downloadedBytes,
          totalBytes: totalBytes,
        ),
      );
      await for (final chunk in download.stream) {
        buffer.add(chunk);
        downloadedBytes += chunk.length;
        onProgress?.call(
          DownloadProgress(
            phase: DownloadPhase.downloading,
            downloadedBytes: downloadedBytes,
            totalBytes: totalBytes,
          ),
        );
      }
      archiveBytes = buffer.takeBytes();
      await atomicWrite(archiveFile, archiveBytes);
    }
    onProgress?.call(
      DownloadProgress(
        phase: DownloadPhase.verifying,
        downloadedBytes: archiveBytes.length,
        totalBytes: archiveBytes.length,
      ),
    );
    if (await releaseDirectory.exists()) {
      await releaseDirectory.delete(recursive: true);
    }
    final stage = Directory(p.join(releaseRoot.path, '.stage-${_uuid.v4()}'));
    await stage.create(recursive: true);
    try {
      final archive = TarDecoder().decodeBytes(
        GZipDecoder().decodeBytes(archiveBytes, verify: true),
        verify: true,
      );
      for (final item in archive) {
        final relative = _upstreamArchivePath(item.name);
        if (!item.isFile || relative == null) continue;
        final target = File(p.join(stage.path, relative));
        await target.parent.create(recursive: true);
        await target.writeAsBytes(item.content as List<int>, flush: true);
      }
      for (final proxy in proxies) {
        final file = _proxyDllIn(stage, proxy);
        if (!await file.exists()) throw StateError('驱动程序包缺少代理 DLL：$proxy');
      }
      final ini = File(p.join(stage.path, 'dlssg_sm86.ini'));
      if (!await ini.exists()) {
        throw StateError('上游 Release 缺少 dlssg_sm86.ini。');
      }
      await stage.rename(releaseDirectory.path);
      await _ensureGlobalIniFromPackage();
      db.installedVersion = version;
      await _save();
      return version;
    } catch (_) {
      if (await stage.exists()) await stage.delete(recursive: true);
      rethrow;
    }
  }
}

class _FileHashCacheEntry {
  const _FileHashCacheEntry(this.size, this.modified, this.hash);
  final int size;
  final DateTime modified;
  final String hash;
}

class _LatestRelease {
  const _LatestRelease(this.version, this.archiveUrl);
  final String version;
  final Uri archiveUrl;
}

String _releaseTag(Object? tag) {
  final normalized = tag?.toString().trim() ?? '';
  if (!RegExp(r'^[0-9A-Za-z._-]+$').hasMatch(normalized)) {
    throw StateError('上游 latest Release 缺少可用的 tag_name。');
  }
  return normalized;
}

/// GitHub source archives wrap every file in one repository-name directory.
/// Only return a safe path below that directory, preserving the package's
/// complete file and subdirectory layout during extraction.
String? _upstreamArchivePath(String name) {
  final normalized = name.replaceAll('\\', '/');
  final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
  if (normalized.startsWith('/') ||
      parts.any((part) => part == '.' || part == '..')) {
    throw StateError('tar.gz 含有不安全路径');
  }
  if (parts.length == 1) return null;
  final relative = parts.skip(1).join('/');
  if (p.isAbsolute(relative) || RegExp(r'^[A-Za-z]:').hasMatch(relative)) {
    throw StateError('tar.gz 含有不安全路径');
  }
  return relative;
}

String _sha256(List<int> bytes) => sha256.convert(bytes).toString();
Future<String> sha256File(File file) async => _sha256(await file.readAsBytes());
String sha256FileSync(File file) => _sha256(file.readAsBytesSync());
Future<void> atomicWrite(File target, List<int> bytes) async {
  await target.parent.create(recursive: true);
  final tmp = File('${target.path}.${const Uuid().v4()}.tmp');
  await tmp.writeAsBytes(bytes, flush: true);
  if (!Platform.isWindows) {
    if (await target.exists()) await target.delete();
    await tmp.rename(target.path);
    return;
  }
  final from = tmp.path.toNativeUtf16(), to = target.path.toNativeUtf16();
  try {
    if (MoveFileEx(
          from,
          to,
          MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH,
        ) ==
        0) {
      throw FileSystemException(
        '无法原子替换文件 (Win32: ${GetLastError()})',
        target.path,
      );
    }
  } finally {
    calloc.free(from);
    calloc.free(to);
  }
}

Future<void> copyAtomic(File from, File to) async =>
    atomicWrite(to, await from.readAsBytes());
