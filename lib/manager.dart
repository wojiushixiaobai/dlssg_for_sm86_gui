import 'dart:convert';
import 'dart:io';

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
  'winhttp.dll',
  'dxgi.dll',
];
const defaultProxy = 'version.dll';
const defaultIni =
    '; Native configuration. Restart the game after changing this file.\n[Compatibility]\nRouter=SM86\nKernelImage=PTX\nHardwareBilinear=0\n\n[FrameGeneration]\nMaxGeneratedFrames=3\n\n[Logging]\nLevel=1\n';
const catalogUrl =
    'https://raw.githubusercontent.com/wojiushixiaobai/dlssg_for_sm86_gui/main/mod-hash-catalog.json';
const releaseDownloadBase =
    'https://github.com/wojiushixiaobai/dlssg_for_sm86_gui/releases/download';
const modArchiveName = 'dlssg_for_sm86.tar.gz';

class ManagerInfo {
  const ManagerInfo({
    required this.dataDirectory,
    required this.installedVersion,
    required this.knownHashes,
    required this.globalProfile,
    required this.modAvailable,
  });
  final String dataDirectory;
  final String? installedVersion, globalProfile;
  final int knownHashes;
  final bool modAvailable;
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

  static Future<ModManager> open({
    Directory? dataDirectory,
    SteamScanner? scanner,
    http.Client? client,
  }) async {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (dataDirectory == null &&
        (localAppData == null || localAppData.trim().isEmpty)) {
      throw StateError('无法定位 %LOCALAPPDATA% 目录。');
    }
    final root =
        dataDirectory ??
        Directory(p.join(localAppData!, 'dlssg_for_sm86_gui', 'data'));
    final releaseRoot = dataDirectory == null
        ? Directory(p.join(root.parent.path, 'release'))
        : Directory(p.join(root.path, 'release'));
    await root.create(recursive: true);
    await releaseRoot.create(recursive: true);
    for (final child in ['profiles', 'backups']) {
      await Directory(p.join(root.path, child)).create(recursive: true);
    }
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
    try {
      // Re-read Steam manifests on every launch so installs, removals, and
      // newly added Steam libraries appear without a manual refresh button.
      await manager.scanSteam();
      if (!manager.db.steamInitialScanCompleted) {
        manager.db.steamInitialScanCompleted = true;
        await manager._save();
      }
    } catch (_) {
      /* Steam may simply not be installed; retry on the next launch. */
    }
    return manager;
  }

  String? get _installedReleaseTag {
    final tag = db.installedVersion;
    return tag != null && RegExp(r'^[0-9A-Za-z._-]+$').hasMatch(tag)
        ? tag
        : null;
  }

  bool get hasModPackage {
    final tag = _installedReleaseTag;
    return tag != null &&
        File(p.join(releaseRoot.path, tag, 'dlssg_sm86.ini')).existsSync();
  }

  ManagerInfo get info => ManagerInfo(
    dataDirectory: root.path,
    installedVersion: db.installedVersion,
    knownHashes: db.catalog.hashes.length,
    globalProfile: db.globalProfile,
    modAvailable: hasModPackage,
  );
  Future<void> _save() => atomicWrite(
    File(p.join(root.path, 'state.json')),
    utf8.encode(db.toJsonText()),
  );
  void _requireMod() {
    if (!hasModPackage) throw StateError('请先在“驱动程序”页面下载并验证 dlssg_for_sm86。');
  }

  File _profileFile(String name) {
    if (name.trim().isEmpty || RegExp(r'[\\/:*?"<>|]').hasMatch(name))
      throw ArgumentError('配置档名称不能为空，且不能包含路径或 Windows 非法字符');
    return File(p.join(root.path, 'profiles', '$name.ini'));
  }

  File _defaultIniFile() =>
      File(p.join(releaseRoot.path, _installedReleaseTag!, 'dlssg_sm86.ini'));
  File _modDll(String proxy) =>
      File(p.join(releaseRoot.path, _installedReleaseTag!, proxy));
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
  Set<String> get _knownHashes =>
      db.catalog.hashes.keys.map((x) => x.toLowerCase()).toSet();
  ModStatus _modState(GameEntry game) {
    if (game.exePath == null) return const ModStatus(ModStateKind.notApplied);
    final dir = File(game.exePath!).parent;
    final found = proxies
        .where((proxy) => File(p.join(dir.path, proxy)).existsSync())
        .toList();
    final ini = File(p.join(dir.path, 'dlssg_sm86.ini')).existsSync();
    if (found.isEmpty && !ini) return const ModStatus(ModStateKind.notApplied);
    if (found.length != 1 || !ini)
      return ModStatus(
        ModStateKind.broken,
        detail: found.length > 1 ? '检测到多个代理 DLL' : 'DLL 或 INI 缺失',
      );
    final hash = sha256FileSync(File(p.join(dir.path, found.single)));
    final normalizedHash = hash.toLowerCase();
    if (game.install?.dllSha256.toLowerCase() == normalizedHash) {
      return ModStatus(
        ModStateKind.applied,
        version: game.install?.version ?? db.installedVersion ?? '本地包',
        proxy: found.single,
      );
    }
    if (!_knownHashes.contains(normalizedHash))
      return const ModStatus(ModStateKind.broken, detail: '代理 DLL 哈希不匹配');
    if (db.catalog.isHistorical(normalizedHash)) {
      return ModStatus(
        ModStateKind.outdated,
        version: '上游历史版本',
        proxy: found.single,
        detail: '检测到非最新 DLL，请更新驱动程序。',
      );
    }
    return ModStatus(
      ModStateKind.applied,
      version: '上游最新版本',
      proxy: found.single,
    );
  }

  ConfigStatus _configState(GameEntry game) {
    final profile = game.configProfile ?? db.globalProfile;
    if (profile == null)
      return const ConfigStatus(ConfigStateKind.defaultConfig);
    if (game.exePath != null) {
      final profileFile = _profileFile(profile),
          gameIni = File(
            p.join(File(game.exePath!).parent.path, 'dlssg_sm86.ini'),
          );
      if (profileFile.existsSync() && gameIni.existsSync()) {
        final actual = sha256FileSync(gameIni);
        if (game.appliedProfileSha256 != null &&
            game.appliedProfileSha256 != actual)
          return ConfigStatus(ConfigStateKind.externallyModified, profile);
      }
    }
    return ConfigStatus(
      game.configProfile == null
          ? ConfigStateKind.global
          : ConfigStateKind.dedicated,
      profile,
    );
  }

  Future<List<ConfigProfile>> listProfiles() async {
    final profiles = <ConfigProfile>[];
    final dir = Directory(p.join(root.path, 'profiles'));
    await for (final item in dir.list()) {
      if (item is File && p.extension(item.path).toLowerCase() == '.ini') {
        try {
          profiles.add(
            parseProfile(
              p.basenameWithoutExtension(item.path),
              await item.readAsString(),
            ),
          );
        } catch (_) {}
      }
    }
    profiles.sort((a, b) => a.name.compareTo(b.name));
    return profiles;
  }

  static ConfigProfile parseProfile(String name, String text) {
    final parsed = _Ini(text);
    bool b(String section, String key, bool fallback) =>
        (parsed.value(section, key) ?? '$fallback').toLowerCase() == 'true' ||
        parsed.value(section, key) == '1' ||
        parsed.value(section, key)?.toUpperCase() == 'SM86' ||
        parsed.value(section, key)?.toUpperCase() == 'PTX';
    int number(String section, String key, int fallback) =>
        int.tryParse(parsed.value(section, key) ?? '') ?? fallback;
    return ConfigProfile(
      name: name,
      router:
          (parsed.value('Compatibility', 'Router') ?? 'SM86').toUpperCase() ==
          'SM86',
      kernelImage:
          (parsed.value('Compatibility', 'KernelImage') ?? 'PTX')
              .toUpperCase() ==
          'PTX',
      hardwareBilinear: b('Compatibility', 'HardwareBilinear', false),
      maxGeneratedFrames: number('FrameGeneration', 'MaxGeneratedFrames', 3),
      loggingLevel: number('Logging', 'Level', 1),
      advanced: AdvancedOverrides(
        loggingExtra: parsed.has('Logging', 'Extra')
            ? b('Logging', 'Extra', false)
            : null,
        debug: parsed.has('General', 'Debug')
            ? b('General', 'Debug', false)
            : null,
        enabled: parsed.has('General', 'Enabled')
            ? b('General', 'Enabled', true)
            : null,
      ),
    );
  }

  Future<void> saveProfile(ConfigProfile profile) async {
    _requireMod();
    await atomicWrite(_profileFile(profile.name), utf8.encode(profile.toIni()));
  }

  Future<void> deleteProfile(String name) async {
    _requireMod();
    final file = _profileFile(name);
    if (await file.exists()) await file.delete();
    if (db.globalProfile == name) db.globalProfile = null;
    for (final game in db.games.where((x) => x.configProfile == name)) {
      game.configProfile = null;
    }
    await _save();
  }

  Future<void> setGlobalProfile(String? name) async {
    _requireMod();
    if (name != null && !await _profileFile(name).exists())
      throw StateError('配置档不存在');
    db.globalProfile = name;
    await _save();
  }

  Future<void> setGameProfile(String id, String? profile) async {
    _requireMod();
    if (profile != null && !await _profileFile(profile).exists())
      throw StateError('配置档不存在');
    _game(id).configProfile = profile;
    await _save();
  }

  Future<GameEntry> addManualGame(String name, String exePath) async {
    final normalized = p.normalize(exePath).toLowerCase();
    final found = db.games
        .where(
          (x) =>
              x.exePath != null &&
              p.normalize(x.exePath!).toLowerCase() == normalized,
        )
        .firstOrNull;
    if (found != null) return found;
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
  }

  GameEntry _game(String id) =>
      db.games.where((x) => x.id == id).firstOrNull ??
      (throw StateError('游戏不存在'));

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
    if (!await source.exists()) throw StateError('未找到已缓存的 Mod 包；请先下载有效版本');
    final dir = _gameDirectory(game);
    final old = game.install?.proxy;
    if (old != null && old != desired) await _restoreOrRemove(game, old);
    final target = File(p.join(dir.path, desired));
    if (await target.exists() &&
        !_knownHashes.contains(await sha256File(target))) {
      if (game.source.kind == GameSourceKind.manual && !confirmOverwrite)
        throw StateError('目标 DLL 不是已知 DLSSG 文件。确认后将保存其原始副本并覆盖。');
      await _recordBackup(game, desired, target);
    }
    await copyAtomic(source, target);
    final hash = await sha256File(target);
    game.selectedProxy = desired;
    game.install = ManagedInstall(
      proxy: desired,
      dllSha256: hash,
      version: db.installedVersion ?? '本地包',
      installedAt: DateTime.now().toUtc(),
    );
    final ini = File(p.join(dir.path, 'dlssg_sm86.ini'));
    if (!await ini.exists())
      await atomicWrite(ini, await _configurationBytes(game));
    await _save();
  }

  Future<void> uninstallMod(String id) async {
    final game = _game(id);
    final proxy = game.install?.proxy ?? game.selectedProxy;
    if (proxy != null) await _restoreOrRemove(game, proxy);
    final ini = File(p.join(_gameDirectory(game).path, 'dlssg_sm86.ini'));
    if (await ini.exists()) await ini.delete();
    game.install = null;
    game.appliedProfileSha256 = null;
    await _save();
  }

  Future<void> applyConfigToGame(String id) async {
    _requireMod();
    final game = _game(id);
    final ini = File(p.join(_gameDirectory(game).path, 'dlssg_sm86.ini'));
    await atomicWrite(ini, await _configurationBytes(game));
    game.appliedProfileSha256 = await sha256File(ini);
    await _save();
  }

  /// Reads the configuration that is currently effective for one game.
  ///
  /// A missing game INI falls back to the bundled default so the settings UI
  /// can show useful values before the Mod has been installed.
  Future<ConfigProfile> loadGameConfig(String id) async {
    final game = _game(id);
    final ini = game.exePath == null
        ? null
        : File(p.join(File(game.exePath!).parent.path, 'dlssg_sm86.ini'));
    if (ini != null && await ini.exists()) {
      return parseProfile(game.name, await ini.readAsString());
    }
    final packaged = _defaultIniFile();
    if (await packaged.exists()) {
      return parseProfile(game.name, await packaged.readAsString());
    }
    return parseProfile(game.name, defaultIni);
  }

  /// Immediately persists a game's driver settings to its dlssg_sm86.ini.
  /// Direct edits intentionally take precedence over a previously selected
  /// reusable profile, which prevents a later profile application from
  /// silently overwriting the user's game-specific choices.
  Future<void> saveGameConfig(String id, ConfigProfile config) async {
    _requireMod();
    final game = _game(id);
    final ini = File(p.join(_gameDirectory(game).path, 'dlssg_sm86.ini'));
    await atomicWrite(ini, utf8.encode(config.toIni()));
    game.configProfile = null;
    game.appliedProfileSha256 = await sha256File(ini);
    await _save();
  }

  Future<List<int>> _configurationBytes(GameEntry game) async {
    final profile = game.configProfile ?? db.globalProfile;
    if (profile != null) return _profileFile(profile).readAsBytes();
    final packaged = _defaultIniFile();
    return packaged.existsSync()
        ? packaged.readAsBytes()
        : utf8.encode(defaultIni);
  }

  Directory _gameDirectory(GameEntry game) {
    if (game.exePath == null || !File(game.exePath!).existsSync())
      throw StateError('请先选择有效的游戏 EXE');
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
    if (await backup.exists())
      await copyAtomic(backup, target);
    else if (await target.exists())
      await target.delete();
    game.backups.removeWhere((b) => b.proxy == proxy);
  }

  Future<int> scanSteam() async {
    db = Database(
      games: await scanner.scan(existing: db.games),
      globalProfile: db.globalProfile,
      catalog: db.catalog,
      installedVersion: db.installedVersion,
      steamInitialScanCompleted: db.steamInitialScanCompleted,
    );
    await _save();
    return db.games.where((x) => x.source.kind == GameSourceKind.steam).length;
  }

  Future<String> refreshModFromGithub() async {
    Future<Map<String, dynamic>> getJson(String url, String label) async {
      final response = await client.get(
        Uri.parse(url),
        headers: {'User-Agent': 'DLSSG-SM86-Manager'},
      );
      if (response.statusCode < 200 || response.statusCode >= 300)
        throw StateError('无法获取 $label：HTTP ${response.statusCode}');
      return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    }

    final catalog = ModHashCatalog.fromJson(
      await getJson(catalogUrl, 'mod-hash-catalog.json'),
    );
    final version = _shortCommit(catalog.sourceHeadCommit);
    final releaseDirectory = Directory(p.join(releaseRoot.path, version));
    final archiveFile = File(p.join(releaseDirectory.path, modArchiveName));
    List<int> archiveBytes;
    var downloaded = false;
    if (await archiveFile.exists()) {
      archiveBytes = await archiveFile.readAsBytes();
    } else {
      final download = await client.get(
        Uri.parse('$releaseDownloadBase/$version/$modArchiveName'),
        headers: {'User-Agent': 'DLSSG-SM86-Manager'},
      );
      if (download.statusCode < 200 || download.statusCode >= 300) {
        throw StateError(
          '下载 Mod $version 的 tar.gz 失败：HTTP ${download.statusCode}',
        );
      }
      archiveBytes = download.bodyBytes;
      downloaded = true;
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
        final targetName = switch (relative) {
          'version.dll' || 'dlssg_sm86.ini' => relative,
          final path
              when path.startsWith('altnative/') &&
                  proxies.contains(p.basename(path)) =>
            p.basename(path),
          _ => null,
        };
        if (targetName == null) continue;
        await File(p.join(stage.path, targetName))
            .writeAsBytes(item.content as List<int>, flush: true);
      }
      for (final proxy in proxies) {
        final sourcePath = proxy == defaultProxy ? proxy : 'altnative/$proxy';
        final expectedHash = catalog.latestFileHash(sourcePath);
        if (expectedHash == null) {
          throw StateError('哈希目录未声明上游文件：$sourcePath');
        }
        final file = File(p.join(stage.path, proxy));
        if (!await file.exists()) throw StateError('Mod 包缺少代理 DLL：$proxy');
        if ((await sha256File(file)).toLowerCase() != expectedHash) {
          throw StateError('Mod 文件哈希不匹配：$sourcePath');
        }
      }
      if (!await File(p.join(stage.path, 'dlssg_sm86.ini')).exists())
        throw StateError('Mod 包缺少 dlssg_sm86.ini');
      final stagedArchive = File(p.join(stage.path, modArchiveName));
      if (downloaded)
        await atomicWrite(stagedArchive, archiveBytes);
      else
        await archiveFile.copy(stagedArchive.path);
      final previous = Directory(
        p.join(releaseRoot.path, '.previous-${_uuid.v4()}'),
      );
      if (await releaseDirectory.exists()) {
        await releaseDirectory.rename(previous.path);
      }
      try {
        await stage.rename(releaseDirectory.path);
      } catch (_) {
        if (!await releaseDirectory.exists() && await previous.exists()) {
          await previous.rename(releaseDirectory.path);
        }
        rethrow;
      }
      db.catalog = catalog;
      db.installedVersion = version;
      await _save();
      if (await previous.exists()) await previous.delete(recursive: true);
      return version;
    } catch (_) {
      if (await stage.exists()) await stage.delete(recursive: true);
      rethrow;
    }
  }
}

String _shortCommit(String? commit) {
  final normalized = commit?.trim().toLowerCase() ?? '';
  if (!RegExp(r'^[0-9a-f]{7,40}$').hasMatch(normalized)) {
    throw StateError('mod-hash-catalog.json 缺少有效的上游 main commit。');
  }
  return normalized.substring(0, 7);
}

/// GitHub source archives wrap every file in one repository-name directory.
/// Only return a safe path below that directory; callers deliberately extract
/// the small runtime subset rather than materializing arbitrary source files.
String? _upstreamArchivePath(String name) {
  final normalized = name.replaceAll('\\', '/');
  final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
  if (normalized.startsWith('/') ||
      parts.any((part) => part == '.' || part == '..')) {
    throw StateError('tar.gz 含有不安全路径');
  }
  if (parts.length == 1) return null;
  return parts.skip(1).join('/');
}

class _Ini {
  _Ini(String input) {
    String? section;
    for (final raw in input.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.startsWith('[') && line.endsWith(']')) {
        section = line.substring(1, line.length - 1).toLowerCase();
      } else if (section != null &&
          line.contains('=') &&
          !line.startsWith(';')) {
        final at = line.indexOf('=');
        _values['$section/${line.substring(0, at).trim().toLowerCase()}'] = line
            .substring(at + 1)
            .trim();
      }
    }
  }
  final _values = <String, String>{};
  String? value(String section, String key) =>
      _values['${section.toLowerCase()}/${key.toLowerCase()}'];
  bool has(String section, String key) => value(section, key) != null;
}

extension FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
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
