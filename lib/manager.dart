import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:win32/win32.dart';

import 'models.dart';
import 'dll_signature.dart';
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
  // Increment when executable selection changes so existing state files are
  // refreshed even if Steam's manifests have not changed.
  static const _steamExecutableDetectionVersion = 1;

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
  final _signatureCache = <String, bool>{};

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
    Future<void> Function()? onFirstLaunch,
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
    final firstLaunch = !db.steamInitialScanCompleted;
    if (firstLaunch) await onFirstLaunch?.call();
    try {
      if (scanner == null) {
        final dataPath = root.path;
        final releasePath = releaseRoot.path;
        final stateText = db.toJsonText();
        manager.db = Database.fromJsonText(
          await Isolate.run(
            () => _refreshSteamInBackground(dataPath, releasePath, stateText),
          ),
        );
      } else {
        await manager._refreshSteamOnStartup();
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
  File get artworkSourcesFile =>
      File(p.join(root.path, 'artwork-sources.json'));
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

  Future<List<GameView>> listGames() async {
    final dataPath = root.path;
    final releasePath = releaseRoot.path;
    final database = db;
    final cachedHashes = Map<String, _FileHashCacheEntry>.of(_fileHashCache);
    final cachedSignatures = Map<String, bool>.of(_signatureCache);
    final result = await Isolate.run(
      () => _listGamesInBackground(
        dataPath,
        releasePath,
        database,
        cachedHashes,
        cachedSignatures,
      ),
    );
    _fileHashCache.addAll(result.hashes);
    _signatureCache.addAll(result.signatures);
    return result.games;
  }

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
      GameView(game, _targetState(game), _modState(game));
  TargetState _targetState(GameEntry game) => game.exePath == null
      ? TargetState.awaitingExe
      : File(game.exePath!).existsSync()
      ? TargetState.ready
      : TargetState.missing;
  ModStatus _modState(GameEntry game) {
    if (game.exePath == null) return const ModStatus(ModStateKind.notApplied);
    final dir = File(game.exePath!).parent;
    final recorded = game.install;
    final candidates = _candidateProxies(game);
    if (candidates.isEmpty ||
        !File(p.join(dir.path, 'dlssg_sm86.ini')).existsSync()) {
      return const ModStatus(ModStateKind.notApplied);
    }
    final preferred = candidates.first;
    final unrecognized = <String, String>{};
    for (final proxy in candidates) {
      final installed = File(p.join(dir.path, proxy));
      if (!installed.existsSync()) continue;
      final version = _identifyProxyDll(
        installed,
        proxy,
        recorded,
        _modDll(proxy),
        db.installedVersion,
        _cachedSha256,
        _signatureCache,
      );
      if (version != null) {
        return ModStatus(
          ModStateKind.applied,
          proxy: proxy,
          version: version,
          canUninstall: true,
        );
      }
      unrecognized[proxy] = _cachedSha256(installed);
    }
    final hasProxy = unrecognized.isNotEmpty;
    return ModStatus(
      hasProxy ? ModStateKind.applied : ModStateKind.notApplied,
      proxy: unrecognized.containsKey(preferred)
          ? preferred
          : (hasProxy ? unrecognized.keys.first : preferred),
      version: hasProxy ? '未知版本' : null,
      canUninstall: hasProxy && recorded == null,
      unrecognizedProxyHashes: recorded == null
          ? Map.unmodifiable(unrecognized)
          : const {},
    );
  }

  // Destructive operations always re-check the actual bytes, without reusing
  // the display cache. No WinTrust or file hashing work runs on the UI isolate.
  Future<String?> _identifyProxyFresh(
    GameEntry game,
    String proxy,
    File target,
  ) {
    final targetPath = target.path;
    final packagePath = _modDll(proxy).path;
    final installedVersion = db.installedVersion;
    final recorded = game.install;
    return Isolate.run(
      () => _identifyProxyDll(
        File(targetPath),
        proxy,
        recorded,
        File(packagePath),
        installedVersion,
        sha256FileSync,
        {},
      ),
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
    final executable = File(game.exePath!).absolute;
    try {
      await Process.start(
        executable.path,
        const [],
        workingDirectory: executable.parent.path,
        mode: ProcessStartMode.detached,
      );
    } on ProcessException catch (error) {
      // Process.start cannot display UAC. Ask Windows to elevate only when the
      // game itself requires it; the manager stays at its current privilege.
      if (Platform.isWindows && error.errorCode == 740) {
        _launchElevated(executable.path);
      } else {
        rethrow;
      }
    }
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
    final status = _modState(game);
    if (game.install == null &&
        status.unrecognizedProxyHashes.length > 1 &&
        proxy == null) {
      throw StateError('存在多个无法识别的代理 DLL，请先选择要更新的文件。');
    }
    final desired =
        (proxy ??
                game.install?.proxy ??
                (status.kind == ModStateKind.applied ? status.proxy : null) ??
                game.selectedProxy ??
                defaultProxy)
            .toLowerCase();
    if (!proxies.contains(desired)) throw ArgumentError('不支持的代理 DLL');
    final source = _modDll(desired);
    if (!await source.exists()) throw StateError('未找到已缓存的驱动程序包；请先下载有效版本');
    final dir = _gameDirectory(game);
    final old = game.install?.proxy;
    final target = File(p.join(dir.path, desired));
    final hadTarget = await target.exists();
    final hasIni = await File(p.join(dir.path, 'dlssg_sm86.ini')).exists();
    final hasBackup = await _backupFile(game, desired).exists();
    final knownTarget =
        hadTarget && await _identifyProxyFresh(game, desired, target) != null;
    final isGameDll = hadTarget && !hasIni && !knownTarget;
    final needsBackup = isGameDll && !hasBackup;
    if (isGameDll) {
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
        version: db.installedVersion ?? '未知版本',
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

  Future<void> uninstallMod(
    String id, {
    String? proxy,
    bool confirmUnrecognized = false,
    String? expectedSha256,
  }) async {
    final game = _game(id);
    final dir = _gameDirectory(game);
    final requested = proxy?.toLowerCase();
    if (requested != null && !proxies.contains(requested)) {
      throw ArgumentError('不支持的代理 DLL');
    }
    var selected = game.install?.proxy;
    if (selected != null && requested != null && requested != selected) {
      throw StateError('所选代理与安装记录不一致。');
    }
    if (selected == null && requested != null) selected = requested;
    if (selected == null) {
      for (final candidate in _candidateProxies(game)) {
        final target = File(p.join(dir.path, candidate));
        if (await target.exists() &&
            await _identifyProxyFresh(game, candidate, target) != null) {
          selected = candidate;
          break;
        }
      }
    }
    if (selected == null) {
      final existing = <String>[];
      for (final candidate in _candidateProxies(game)) {
        if (await File(p.join(dir.path, candidate)).exists()) {
          existing.add(candidate);
        }
      }
      if (existing.length == 1) selected = existing.single;
    }
    if (selected == null) {
      throw StateError('无法确认目标 DLL 属于 DLSSG，已保留 DLL 和配置文件。');
    }
    final target = File(p.join(dir.path, selected));
    if (game.install == null && !await target.exists()) {
      throw StateError('所选代理 DLL 不存在，已保留配置文件。');
    }
    final ini = File(p.join(dir.path, 'dlssg_sm86.ini'));
    if (game.install == null &&
        await _identifyProxyFresh(game, selected, target) == null) {
      if (!await ini.exists() ||
          !confirmUnrecognized ||
          expectedSha256 == null ||
          (await sha256File(target)).toLowerCase() !=
              expectedSha256.toLowerCase()) {
        throw StateError('无法确认目标 DLL 属于 DLSSG，已保留 DLL 和配置文件。');
      }
      final backup = _backupFile(game, selected);
      if (await backup.exists()) {
        await copyAtomic(backup, target);
      } else {
        await target.delete();
      }
      game.backups.removeWhere((entry) => entry.proxy == selected);
    } else {
      await _restoreOrRemove(game, selected);
    }
    if (await ini.exists()) await ini.delete();
    game.install = null;
    game.appliedProfileSha256 = null;
    game.hasCustomConfig = false;
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
    if (!proxies.contains(proxy)) throw StateError('不支持的代理 DLL');
    final target = File(p.join(_gameDirectory(game).path, proxy)),
        backup = _backupFile(game, proxy);
    if (await target.exists() &&
        await _identifyProxyFresh(game, proxy, target) == null) {
      throw StateError('目标 DLL 已变更或无法确认属于 DLSSG，已保留原文件。');
    }
    if (await backup.exists()) {
      await copyAtomic(backup, target);
    } else if (await target.exists()) {
      await target.delete();
    }
    game.backups.removeWhere((b) => b.proxy == proxy);
  }

  Future<int> refreshSteamIfChanged() async {
    final snapshot = await scanner.manifestModificationTimes();
    if (_sameModificationTimes(db.steamManifestModificationTimes, snapshot)) {
      return db.games
          .where((x) => x.source.kind == GameSourceKind.steam)
          .length;
    }
    return scanSteam(snapshot: snapshot);
  }

  Future<void> _refreshSteamOnStartup() async {
    if (db.steamExecutableDetectionVersion < _steamExecutableDetectionVersion) {
      await scanSteam();
    } else {
      await refreshSteamIfChanged();
    }
    if (!db.steamInitialScanCompleted) {
      db.steamInitialScanCompleted = true;
      await _save();
    }
  }

  Future<int> scanSteam({Map<String, int>? snapshot}) async {
    final games = await scanner.scan(existing: db.games);
    final modificationTimes =
        snapshot ?? await scanner.manifestModificationTimes();
    final snapshotChanged = !_sameModificationTimes(
      db.steamManifestModificationTimes,
      modificationTimes,
    );
    final changed =
        jsonEncode(games.map((game) => game.toJson()).toList()) !=
        jsonEncode(db.games.map((game) => game.toJson()).toList());
    final executableDetectionChanged =
        db.steamExecutableDetectionVersion != _steamExecutableDetectionVersion;
    if (changed) {
      db = Database(
        games: games,
        installedVersion: db.installedVersion,
        legacyGlobalProfile: db.legacyGlobalProfile,
        steamInitialScanCompleted: db.steamInitialScanCompleted,
        steamExecutableDetectionVersion: _steamExecutableDetectionVersion,
        steamManifestModificationTimes: modificationTimes,
      );
    } else {
      db.steamManifestModificationTimes = Map.unmodifiable(modificationTimes);
      db.steamExecutableDetectionVersion = _steamExecutableDetectionVersion;
    }
    if (changed || snapshotChanged || executableDetectionChanged) {
      await _save();
    }
    return db.games.where((x) => x.source.kind == GameSourceKind.steam).length;
  }

  static bool _sameModificationTimes(
    Map<String, int>? previous,
    Map<String, int> current,
  ) {
    if (previous == null || previous.length != current.length) return false;
    for (final entry in current.entries) {
      if (previous[entry.key] != entry.value) return false;
    }
    return true;
  }

  Future<String> latestDriverVersion() async =>
      (await _latestRelease()).version;

  Future<_LatestRelease> _latestRelease() async {
    final response = await client
        .get(
          Uri.parse(latestReleaseUrl),
          headers: {'User-Agent': 'DLSSG-SM86-Manager'},
        )
        .timeout(const Duration(seconds: 15));
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
    File? importedArchive;
    await archiveDirectory.create(recursive: true);
    if (await archiveFile.exists()) {
    } else if (await previousCacheArchive.exists() &&
        await previousCacheVersion.exists() &&
        (await previousCacheVersion.readAsString()).trim() == version) {
      await copyAtomic(previousCacheArchive, archiveFile);
      importedArchive = previousCacheArchive;
    } else if (previousVersion == version && await legacyArchiveFile.exists()) {
      await copyAtomic(legacyArchiveFile, archiveFile);
      importedArchive = legacyArchiveFile;
    } else {
      final request = http.Request('GET', release.archiveUrl)
        ..headers['User-Agent'] = 'DLSSG-SM86-Manager';
      final download = await client
          .send(request)
          .timeout(const Duration(seconds: 30));
      if (download.statusCode < 200 || download.statusCode >= 300) {
        throw StateError(
          '下载上游 Release $version 的 tar.gz 失败：HTTP ${download.statusCode}',
        );
      }
      final totalBytes = download.contentLength;
      var downloadedBytes = 0;
      final temporaryArchive = File(
        '${archiveFile.path}.${_uuid.v4()}.download',
      );
      final sink = temporaryArchive.openWrite();
      var sinkClosed = false;
      onProgress?.call(
        DownloadProgress(
          phase: DownloadPhase.downloading,
          downloadedBytes: downloadedBytes,
          totalBytes: totalBytes,
        ),
      );
      try {
        await sink.addStream(
          download.stream.timeout(const Duration(seconds: 30)).map((chunk) {
            downloadedBytes += chunk.length;
            onProgress?.call(
              DownloadProgress(
                phase: DownloadPhase.downloading,
                downloadedBytes: downloadedBytes,
                totalBytes: totalBytes,
              ),
            );
            return chunk;
          }),
        );
        await sink.flush();
        await sink.close();
        sinkClosed = true;
        await _replaceFileAtomically(temporaryArchive, archiveFile);
      } catch (_) {
        if (!sinkClosed) {
          try {
            await sink.close();
          } catch (_) {}
        }
        try {
          if (await temporaryArchive.exists()) await temporaryArchive.delete();
        } catch (_) {}
        rethrow;
      }
    }
    final archiveSize = await archiveFile.length();
    onProgress?.call(
      DownloadProgress(
        phase: DownloadPhase.verifying,
        downloadedBytes: archiveSize,
        totalBytes: archiveSize,
      ),
    );
    final stage = Directory(p.join(releaseRoot.path, '.stage-${_uuid.v4()}'));
    final rollback = Directory(
      p.join(releaseRoot.path, '.previous-${_uuid.v4()}'),
    );
    final temporaryTar = File(
      p.join(releaseRoot.path, '.archive-${_uuid.v4()}.tar'),
    );
    await stage.create(recursive: true);
    final originalVersion = db.installedVersion;
    var validated = false;
    var movedPrevious = false;
    var activated = false;
    var committed = false;
    try {
      final compressedInput = InputFileStream(archiveFile.path);
      final tarOutput = OutputFileStream(temporaryTar.path);
      try {
        final valid = GZipDecoder().decodeStream(
          compressedInput,
          tarOutput,
          verify: true,
        );
        if (!valid) throw StateError('下载的 tar.gz 文件不完整或已损坏。');
      } finally {
        await compressedInput.close();
        await tarOutput.close();
      }

      final tarInput = InputFileStream(temporaryTar.path);
      Archive? archive;
      try {
        archive = TarDecoder().decodeStream(tarInput, verify: true);
        for (final item in archive) {
          final relative = _upstreamArchivePath(item.name);
          if (!item.isFile || relative == null) continue;
          final target = File(p.join(stage.path, relative));
          await target.parent.create(recursive: true);
          final output = OutputFileStream(target.path);
          try {
            item.writeContent(output);
          } finally {
            await output.close();
          }
        }
      } finally {
        if (archive != null) {
          await archive.clear();
        } else {
          await tarInput.close();
        }
      }
      for (final proxy in proxies) {
        final file = _proxyDllIn(stage, proxy);
        if (!await file.exists()) throw StateError('驱动程序包缺少代理 DLL：$proxy');
      }
      final ini = File(p.join(stage.path, 'dlssg_sm86.ini'));
      if (!await ini.exists()) {
        throw StateError('上游 Release 缺少 dlssg_sm86.ini。');
      }
      validated = true;
      if (await releaseDirectory.exists()) {
        await releaseDirectory.rename(rollback.path);
        movedPrevious = true;
      }
      await stage.rename(releaseDirectory.path);
      activated = true;
      await _ensureGlobalIniFromPackage();
      db.installedVersion = version;
      await _save();
      committed = true;
      return version;
    } catch (error) {
      db.installedVersion = originalVersion;
      if (activated) await releaseDirectory.delete(recursive: true);
      if (movedPrevious) await rollback.rename(releaseDirectory.path);
      // Discard malformed or incomplete packages so retry can download again.
      // Filesystem errors may be transient and do not prove a bad archive.
      if (!validated && error is! FileSystemException) {
        if (await archiveFile.exists()) await archiveFile.delete();
        if (importedArchive != null && await importedArchive.exists()) {
          await importedArchive.delete();
        }
      }
      rethrow;
    } finally {
      // Cleanup must not turn a committed update into a reported failure.
      for (final disposable in <FileSystemEntity>[
        stage,
        temporaryTar,
        if (committed) rollback,
      ]) {
        try {
          if (await disposable.exists()) {
            await disposable.delete(recursive: true);
          }
        } on FileSystemException catch (_) {}
      }
    }
  }
}

List<String> _candidateProxies(GameEntry game) {
  final preferred = (game.install?.proxy ?? game.selectedProxy ?? defaultProxy)
      .toLowerCase();
  if (!proxies.contains(preferred)) return const [];
  return [
    preferred,
    if (game.install == null) ...proxies.where((proxy) => proxy != preferred),
  ];
}

class _FileHashCacheEntry {
  const _FileHashCacheEntry(this.size, this.modified, this.hash);
  final int size;
  final DateTime modified;
  final String hash;
}

class _GameViewsResult {
  const _GameViewsResult(this.games, this.hashes, this.signatures);
  final List<GameView> games;
  final Map<String, _FileHashCacheEntry> hashes;
  final Map<String, bool> signatures;
}

// All display/install/uninstall decisions use this function. A signed proxy
// can be recognized without a version catalog, but a certificate cannot tell
// us its release version. Unknown files never count as an installed driver.
String? _identifyProxyDll(
  File target,
  String proxy,
  ManagedInstall? recorded,
  File packaged,
  String? packageVersion,
  String Function(File) hashFile,
  Map<String, bool> signatureCache,
) {
  final hash = hashFile(target).toLowerCase();
  if (recorded?.proxy == proxy && recorded!.dllSha256.toLowerCase() == hash) {
    return recorded.version == '本地包' ? '未知版本' : recorded.version;
  }
  if (packaged.existsSync() && hashFile(packaged).toLowerCase() == hash) {
    return packageVersion ?? '未知版本';
  }
  final historicalVersion = _unsignedProxyVersions[hash];
  if (historicalVersion != null) return historicalVersion;
  final signed = signatureCache.putIfAbsent(
    hash,
    () => verifyDllSignature(target.path).isDlssg,
  );
  return signed ? '未知版本' : null;
}

// Only unsigned historical releases need individual hashes. Provenance and
// upstream Git blob verification are documented in docs/dll-identification.md.
const _unsignedProxyVersions = {
  '03d445237d519ac48cd9226278a0f07aecd7ac597697697eb64404e1d51b3c5a': '0.1.0',
};

Future<String> _refreshSteamInBackground(
  String dataPath,
  String releasePath,
  String stateText,
) async {
  final manager = ModManager._(
    Directory(dataPath),
    Directory(releasePath),
    Database.fromJsonText(stateText),
  );
  try {
    await manager._refreshSteamOnStartup();
    return manager.db.toJsonText();
  } finally {
    manager.client.close();
  }
}

_GameViewsResult _listGamesInBackground(
  String dataPath,
  String releasePath,
  Database database,
  Map<String, _FileHashCacheEntry> cachedHashes,
  Map<String, bool> cachedSignatures,
) {
  final manager = ModManager._(
    Directory(dataPath),
    Directory(releasePath),
    database,
  );
  try {
    manager._fileHashCache.addAll(cachedHashes);
    manager._signatureCache.addAll(cachedSignatures);
    final games = database.games.map(manager.view).toList();
    return _GameViewsResult(
      games,
      manager._fileHashCache,
      manager._signatureCache,
    );
  } finally {
    manager.client.close();
  }
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

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

void _launchElevated(String executablePath) {
  final executable = File(executablePath).absolute;
  final operation = 'runas'.toNativeUtf16();
  final file = executable.path.toNativeUtf16();
  final directory = executable.parent.path.toNativeUtf16();
  final launch = calloc<SHELLEXECUTEINFO>();
  try {
    launch.ref
      ..cbSize = sizeOf<SHELLEXECUTEINFO>()
      ..lpVerb = operation
      ..lpFile = file
      ..lpDirectory = directory
      ..nShow = SW_SHOWNORMAL;
    if (ShellExecuteEx(launch) != 0) return;

    final error = GetLastError();
    throw ProcessException(
      executable.path,
      const [],
      '无法以管理员权限启动游戏 (Win32: $error)',
      error,
    );
  } finally {
    calloc.free(launch);
    calloc.free(operation);
    calloc.free(file);
    calloc.free(directory);
  }
}

Future<String> sha256File(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();
String sha256FileSync(File file) {
  final output = _DigestSink();
  final hashSink = sha256.startChunkedConversion(output);
  final input = file.openSync();
  try {
    while (true) {
      final chunk = input.readSync(64 * 1024);
      if (chunk.isEmpty) break;
      hashSink.add(chunk);
    }
  } finally {
    try {
      hashSink.close();
    } finally {
      input.closeSync();
    }
  }
  return output.value!.toString();
}

Future<void> atomicWrite(File target, List<int> bytes) async {
  await target.parent.create(recursive: true);
  final tmp = File('${target.path}.${const Uuid().v4()}.tmp');
  await tmp.writeAsBytes(bytes, flush: true);
  await _replaceFileAtomically(tmp, target);
}

Future<void> _replaceFileAtomically(File tmp, File target) async {
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

Future<void> copyAtomic(File from, File to) async {
  await to.parent.create(recursive: true);
  final tmp = File('${to.path}.${const Uuid().v4()}.tmp');
  final sink = tmp.openWrite();
  var sinkClosed = false;
  try {
    await sink.addStream(from.openRead());
    await sink.flush();
    await sink.close();
    sinkClosed = true;
    await _replaceFileAtomically(tmp, to);
  } catch (_) {
    if (!sinkClosed) {
      try {
        await sink.close();
      } catch (_) {}
    }
    try {
      if (await tmp.exists()) await tmp.delete();
    } catch (_) {}
    rethrow;
  }
}
