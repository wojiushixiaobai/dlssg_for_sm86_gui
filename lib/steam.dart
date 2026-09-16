import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

import 'models.dart';
import 'vdf.dart';

final _storeArtworkRequests = <int, Future<String?>>{};

enum SteamArtworkKind { card, icon }

class SteamArtworkSource {
  const SteamArtworkSource.file(this.value) : local = true;
  const SteamArtworkSource.network(this.value) : local = false;

  final String value;
  final bool local;
}

/// Persists only the selected local path or remote URL, never the image bytes.
/// A still-valid local path avoids repeatedly enumerating Steam's library
/// cache after application restarts.
class SteamArtworkCache {
  SteamArtworkCache(
    this.sourceFile, {
    List<String> Function(int appId, SteamArtworkKind kind)? findLocalPaths,
  }) : _findLocalPaths = findLocalPaths ?? findLocalArtworkPaths;

  final File sourceFile;
  final List<String> Function(int appId, SteamArtworkKind kind) _findLocalPaths;
  final _requests = <String, Future<SteamArtworkSource?>>{};
  Map<String, String>? _sources;
  Future<Map<String, String>>? _sourcesLoading;
  Future<void> _writeTail = Future.value();

  Future<SteamArtworkSource?> load(
    int appId, {
    SteamArtworkKind kind = SteamArtworkKind.card,
  }) {
    final key = _sourceKey(appId);
    final existing = _requests[key];
    if (existing != null) return existing;
    final request = _load(appId, kind);
    _requests[key] = request;
    return request;
  }

  Future<SteamArtworkSource?> _load(int appId, SteamArtworkKind kind) async {
    try {
      final saved = (await _readSources())[_sourceKey(appId)];
      if (saved != null) {
        if (await File(saved).exists()) {
          if (!_isUsableCachedArtwork(saved, kind)) {
            await _remove(appId);
          } else {
            return SteamArtworkSource.file(saved);
          }
        }
        final uri = Uri.tryParse(saved);
        if (uri != null && uri.hasScheme) {
          // A previous fallback URL must not hide artwork that Steam has
          // subsequently populated in its local library cache.
          final local = _firstLocalPath(appId, kind);
          if (local != null) {
            await _store(appId, local);
            return SteamArtworkSource.file(local);
          }
          return SteamArtworkSource.network(saved);
        }
        await _remove(appId);
      }
      final local = _firstLocalPath(appId, kind);
      if (local != null) {
        await _store(appId, local);
        return SteamArtworkSource.file(local);
      }
      final source = steamArtworkUrls(appId, kind: kind).first;
      await _store(appId, source);
      return SteamArtworkSource.network(source);
    } catch (_) {
      // The caller displays its normal fallback when artwork is unavailable.
    }
    return null;
  }

  String? _firstLocalPath(int appId, SteamArtworkKind kind) {
    for (final path in _findLocalPaths(appId, kind)) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  Future<SteamArtworkSource?> nextNetworkSource(
    int appId,
    String failedUrl, {
    SteamArtworkKind kind = SteamArtworkKind.card,
  }) async {
    final candidates = steamArtworkUrls(appId, kind: kind);
    final current = candidates.indexOf(failedUrl);
    final next = current < 0
        ? candidates.firstOrNull
        : candidates.elementAtOrNull(current + 1);
    if (next == null) return null;
    await _store(appId, next);
    return SteamArtworkSource.network(next);
  }

  Future<Map<String, String>> _readSources() {
    final loaded = _sources;
    if (loaded != null) return Future.value(loaded);
    return _sourcesLoading ??= _readSourcesFromDisk();
  }

  Future<Map<String, String>> _readSourcesFromDisk() async {
    try {
      if (await sourceFile.exists()) {
        final decoded = jsonDecode(await sourceFile.readAsString());
        if (decoded is Map) {
          return _sources = {
            for (final entry in decoded.entries)
              if (entry.key is String && entry.value is String)
                entry.key as String: entry.value as String,
          };
        }
      }
    } catch (_) {
      // A corrupt source index is disposable and will be rebuilt lazily.
    }
    return _sources = {};
  }

  String _sourceKey(int appId) => '$appId';

  Future<void> _store(int appId, String value) async {
    final sources = await _readSources();
    sources[_sourceKey(appId)] = value;
    await _saveSources(sources);
  }

  Future<void> _remove(int appId) async {
    final sources = await _readSources();
    if (sources.remove(_sourceKey(appId)) != null) {
      await _saveSources(sources);
    }
  }

  Future<void> _saveSources(Map<String, String> sources) async {
    // Several game cards are resolved at once on the first frame. Serialize
    // both the index write and its fixed temporary filename so no card can
    // replace another card's in-progress write.
    final contents = jsonEncode(sources);
    _writeTail = _writeTail.then(
      (_) => _writeSources(contents),
      onError: (_, _) => _writeSources(contents),
    );
    return _writeTail;
  }

  Future<void> _writeSources(String contents) async {
    await sourceFile.parent.create(recursive: true);
    final temporary = File('${sourceFile.path}.tmp');
    await temporary.writeAsString(contents, flush: true);
    if (await sourceFile.exists()) await sourceFile.delete();
    await temporary.rename(sourceFile.path);
  }
}

Future<String?> steamArtworkUrl(int appId, {http.Client? client}) {
  if (client != null) return _fetchSteamArtworkUrl(appId, client);
  final existing = _storeArtworkRequests[appId];
  if (existing != null) return existing;
  final request = _fetchSteamArtworkUrl(
    appId,
    http.Client(),
    closeClient: true,
  );
  _storeArtworkRequests[appId] = request;
  return request;
}

Future<String?> _fetchSteamArtworkUrl(
  int appId,
  http.Client client, {
  bool closeClient = false,
}) async {
  try {
    final response = await client.get(
      Uri.https('store.steampowered.com', '/api/appdetails', {
        'appids': '$appId',
      }),
    );
    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body);
    if (body is! Map) return null;
    final app = body['$appId'];
    if (app is! Map || app['success'] != true || app['data'] is! Map) {
      return null;
    }
    final image = (app['data'] as Map)['header_image']?.toString();
    final uri = image == null ? null : Uri.tryParse(image);
    return uri != null && uri.hasScheme ? image : null;
  } catch (_) {
    return null;
  } finally {
    if (closeClient) client.close();
  }
}

List<String> findLocalArtworkPaths(
  int appId,
  SteamArtworkKind kind, {
  List<String>? steamPaths,
}) {
  final sources = <String>[];
  final seenLocalPaths = <String>{};

  void addLocal(String path) {
    if (File(path).existsSync() && seenLocalPaths.add(p.normalize(path))) {
      sources.add(path);
    }
  }

  for (final steamPath in steamPaths ?? _artworkSteamPaths()) {
    final cachePath = p.join(steamPath, 'appcache', 'librarycache');
    final appCache = Directory(p.join(cachePath, '$appId'));
    for (final name in _localArtworkNames(kind)) {
      addLocal(p.join(appCache.path, name));
    }
    if (appCache.existsSync()) {
      try {
        final nested = <String>[];
        for (final item in appCache.listSync(recursive: true)) {
          if (item is! File || !_isKnownArtworkFile(item.path, kind)) continue;
          nested.add(item.path);
        }
        nested.sort(
          (a, b) =>
              _artworkNameScore(a, kind).compareTo(_artworkNameScore(b, kind)),
        );
        for (final path in nested) {
          addLocal(path);
        }
      } on FileSystemException {
        // Steam may update this cache concurrently.
      }
    }
    for (final name in _flatArtworkNames(appId, kind)) {
      addLocal(p.join(cachePath, name));
    }
  }
  return sources;
}

const _artworkExtensions = ['jpg', 'png', 'webp'];
const _headerLanguages = [
  'schinese',
  'tchinese',
  'english',
  'japanese',
  'koreana',
  'french',
  'german',
  'spanish',
  'russian',
];

List<String> _namesWithExtensions(Iterable<String> names) => [
  for (final name in names)
    for (final extension in _artworkExtensions) '$name.$extension',
];

List<String> _localizedArtworkNames(String stem) => [
  for (final language in _headerLanguages)
    for (final extension in _artworkExtensions)
      _localizedArtworkFileName(stem, language, extension),
];

String _localizedArtworkFileName(
  String stem,
  String language,
  String extension,
) => '${stem}_$language.$extension'; // ignore: unnecessary_brace_in_string_interps

// Steam's library_hero is deliberately very wide (roughly 3:1), so fitting it
// into the homepage card leaves a dark strip under the image.  The header art
// is high-resolution and has the right landscape shape for both the card and
// the enlarged game-settings thumbnail.
final _highResolutionArtworkNames = [
  ..._localizedArtworkNames('library_header'),
  ..._namesWithExtensions(['library_header']),
  ..._localizedArtworkNames('header'),
  ..._namesWithExtensions(['header']),
];

List<String> _localArtworkNames(SteamArtworkKind kind) => switch (kind) {
  SteamArtworkKind.card || SteamArtworkKind.icon => _highResolutionArtworkNames,
};

List<String> _flatArtworkNames(int appId, SteamArtworkKind kind) => [
  for (final name in _localArtworkNames(kind)) '${appId}_$name',
  for (final extension in _artworkExtensions) '$appId/header.$extension',
];

bool _isKnownArtworkFile(String path, SteamArtworkKind kind) =>
    _localArtworkNames(kind).contains(p.basename(path).toLowerCase());

// Steam's hash-named app icons are 32×32 on this system. They were useful in
// compact Steam lists but become visibly blurred at the size used by game
// settings, so an old cached selection must never bring one back.
final _lowResolutionSteamIconName = RegExp(r'^[0-9a-f]{40}\.(jpg|png)$');

bool _isUsableCachedArtwork(String path, SteamArtworkKind kind) =>
    kind != SteamArtworkKind.icon ||
    !_lowResolutionSteamIconName.hasMatch(p.basename(path).toLowerCase());

int _artworkNameScore(String path, SteamArtworkKind kind) {
  final name = p.basename(path).toLowerCase();
  final score = _localArtworkNames(kind).indexOf(name);
  return score < 0 ? _localArtworkNames(kind).length : score;
}

List<String>? _artworkSteamPathsCache;

List<String> _artworkSteamPaths() {
  return _artworkSteamPathsCache ??= () {
    final roots = <String>[];
    for (final path in [
      SteamScanner.readSteamPathFromRegistry(),
      r'C:\Program Files (x86)\Steam',
      r'C:\Program Files\Steam',
    ]) {
      if (path == null || !Directory(path).existsSync()) continue;
      if (!roots.any((root) => p.equals(root, path))) roots.add(path);
    }
    return roots;
  }();
}

List<String> steamArtworkUrls(
  int appId, {
  SteamArtworkKind kind = SteamArtworkKind.card,
}) {
  final names = switch (kind) {
    SteamArtworkKind.card => ['header.jpg'],
    SteamArtworkKind.icon => ['header.jpg'],
  };
  return [
    for (final name in names) ...[
      'https://cdn.cloudflare.steamstatic.com/steam/apps/$appId/$name',
      'https://cdn.akamai.steamstatic.com/steam/apps/$appId/$name',
      'https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/$appId/$name',
      'https://shared.cloudflare.steamstatic.com/store_item_assets/steam/apps/$appId/$name',
    ],
  ];
}

class SteamScanner {
  SteamScanner({String? Function()? steamPath})
    : _steamPath = steamPath ?? readSteamPathFromRegistry;
  final String? Function() _steamPath;

  static String? readSteamPathFromRegistry() {
    if (!Platform.isWindows) return null;
    final subKey = r'Software\Valve\Steam'.toNativeUtf16();
    final valueName = 'SteamPath'.toNativeUtf16();
    final opened = calloc<HANDLE>();
    final size = calloc<DWORD>();
    final type = calloc<DWORD>();
    try {
      if (RegOpenKeyEx(HKEY_CURRENT_USER, subKey, 0, KEY_READ, opened) !=
          ERROR_SUCCESS) {
        return null;
      }
      if (RegQueryValueEx(
                opened.value,
                valueName,
                nullptr,
                type,
                nullptr,
                size,
              ) !=
              ERROR_SUCCESS ||
          type.value != REG_SZ) {
        return null;
      }
      final bytes = calloc<BYTE>(size.value + 2);
      try {
        if (RegQueryValueEx(
              opened.value,
              valueName,
              nullptr,
              type,
              bytes,
              size,
            ) !=
            ERROR_SUCCESS) {
          return null;
        }
        return bytes.cast<Utf16>().toDartString();
      } finally {
        calloc.free(bytes);
      }
    } finally {
      if (opened.value != 0) RegCloseKey(opened.value);
      calloc.free(subKey);
      calloc.free(valueName);
      calloc.free(opened);
      calloc.free(size);
      calloc.free(type);
    }
  }

  /// A snapshot of files whose changes can add, remove, or relocate games.
  /// Missing libraryfolders files are recorded as well, so creating one later
  /// triggers a scan on the next launch.
  Future<Map<String, int>> manifestModificationTimes() async {
    final roots = _steamRoots();
    final result = <String, int>{};
    for (final root in roots) {
      final folders = File(
        p.join(root.path, 'steamapps', 'libraryfolders.vdf'),
      );
      result[p.normalize(folders.path)] = await _modifiedTime(folders);
      final appInfo = File(p.join(root.path, 'appcache', 'appinfo.vdf'));
      result[p.normalize(appInfo.path)] = await _modifiedTime(appInfo);
    }
    for (final library in await _steamLibraries(roots)) {
      final apps = Directory(p.join(library.path, 'steamapps'));
      if (!await apps.exists()) continue;
      try {
        await for (final item in apps.list()) {
          if (item is File &&
              p.basename(item.path).startsWith('appmanifest_') &&
              p.extension(item.path).toLowerCase() == '.acf') {
            result[p.normalize(item.path)] = await _modifiedTime(item);
          }
        }
      } on FileSystemException {
        // Steam may update its manifests while the application starts.
      }
    }
    return result;
  }

  Future<int> _modifiedTime(File file) async {
    if (!await file.exists()) return -1;
    return (await file.stat()).modified.microsecondsSinceEpoch;
  }

  List<Directory> _steamRoots() {
    final roots = <Directory>[];
    final registryRoot = _steamPath();
    if (registryRoot != null && Directory(registryRoot).existsSync()) {
      roots.add(Directory(registryRoot));
    }
    for (final candidate in [
      r'C:\Program Files (x86)\Steam',
      r'C:\Program Files\Steam',
    ]) {
      final directory = Directory(candidate);
      if (directory.existsSync() &&
          !roots.any((x) => _samePath(x.path, directory.path))) {
        roots.add(directory);
      }
    }
    return roots;
  }

  Future<List<Directory>> _steamLibraries(List<Directory> roots) async {
    final libraries = <Directory>[...roots];
    for (final root in roots) {
      final file = File(p.join(root.path, 'steamapps', 'libraryfolders.vdf'));
      if (!file.existsSync()) continue;
      for (final path in parseLibraryFolders(await file.readAsString())) {
        final dir = Directory(path);
        if (dir.existsSync() &&
            !libraries.any((x) => _samePath(x.path, dir.path))) {
          libraries.add(dir);
        }
      }
    }
    return libraries;
  }

  Future<List<GameEntry>> scan({required List<GameEntry> existing}) async {
    final roots = _steamRoots();
    final libraries = await _steamLibraries(roots);
    final lastPlayed = await readLastPlayed(roots);
    final installedApps = await _installedApps(libraries);
    final steamLaunchExecutables = await _readSteamLaunchExecutables(
      roots,
      installedApps.map((app) => app.appId).toSet(),
    );
    final result = existing
        .where((game) => game.source.kind == GameSourceKind.manual)
        .map(_copyGame)
        .toList();
    final scannedSteam = <int, GameEntry>{};
    final existingSteam = {
      for (final game in existing)
        if (game.source.kind == GameSourceKind.steam &&
            game.source.appId != null)
          game.source.appId!: _copyGame(game),
    };
    for (final installed in installedApps) {
      final appId = installed.appId;
      final manifest = installed.manifest;
      final name = manifest['name'] ?? 'Steam App $appId';
      final installDir = manifest['installdir'] ?? '';
      final gameFolder = Directory(
        p.join(installed.library.path, 'steamapps', 'common', installDir),
      );
      final scanned = scannedSteam[appId];
      final previous = scanned ?? existingSteam[appId];
      final steamDefinedExe = _resolveSteamDefinedExecutable(
        gameFolder,
        steamLaunchExecutables[appId] ?? const [],
      );
      final detectedExe =
          steamDefinedExe ??
          (previous?.exePath != null &&
                  File(previous!.exePath!).existsSync() &&
                  _isWithin(previous.exePath!, gameFolder.path)
              ? previous.exePath
              : await _findGameExecutable(
                  gameFolder,
                  gameName: name,
                  installDir: installDir,
                ));
      if (scanned != null) {
        scanned.name = name;
        scanned.source = GameSource.steam(appId, installed.library.path);
        if (lastPlayed[appId] != null) {
          scanned.lastPlayedAt = lastPlayed[appId];
        }
        if (steamDefinedExe != null ||
            scanned.exePath == null ||
            !File(scanned.exePath!).existsSync()) {
          scanned.exePath = detectedExe;
        }
        continue;
      }
      final previousSteam = existingSteam.remove(appId);
      if (previousSteam != null) {
        previousSteam.name = name;
        previousSteam.source = GameSource.steam(appId, installed.library.path);
        if (lastPlayed[appId] != null) {
          previousSteam.lastPlayedAt = lastPlayed[appId];
        }
        if (steamDefinedExe != null ||
            previousSteam.exePath == null ||
            !File(previousSteam.exePath!).existsSync()) {
          previousSteam.exePath = detectedExe;
        }
        result.add(previousSteam);
        scannedSteam[appId] = previousSteam;
        continue;
      }
      final manual = result.indexWhere(
        (game) =>
            game.source.kind == GameSourceKind.manual &&
            game.exePath != null &&
            _isWithin(game.exePath!, gameFolder.path),
      );
      final game = GameEntry(
        id: _id(),
        name: name,
        source: GameSource.steam(appId, installed.library.path),
        exePath: detectedExe,
        selectedProxy: 'version.dll',
        createdAt: DateTime.now().toUtc(),
        lastPlayedAt: lastPlayed[appId],
      );
      if (manual >= 0) {
        final old = result.removeAt(manual);
        old.name = name;
        old.source = game.source;
        old.lastPlayedAt = game.lastPlayedAt;
        result.add(old);
        scannedSteam[appId] = old;
      } else {
        result.add(game);
        scannedSteam[appId] = game;
      }
    }
    return result;
  }

  Future<List<_InstalledSteamApp>> _installedApps(
    List<Directory> libraries,
  ) async {
    final result = <_InstalledSteamApp>[];
    for (final library in libraries) {
      final apps = Directory(p.join(library.path, 'steamapps'));
      if (!apps.existsSync()) continue;
      await for (final item in apps.list()) {
        if (item is! File ||
            !p.basename(item.path).startsWith('appmanifest_') ||
            p.extension(item.path).toLowerCase() != '.acf') {
          continue;
        }
        final manifest = parseAppManifest(await item.readAsString());
        final appId = int.tryParse(manifest['appid'] ?? '');
        if (appId == null || _ignoredAppIds.contains(appId)) continue;
        result.add(_InstalledSteamApp(library, appId, manifest));
      }
    }
    return result;
  }

  Future<Map<int, List<String>>> _readSteamLaunchExecutables(
    List<Directory> roots,
    Set<int> appIds,
  ) async {
    final result = <int, List<String>>{};
    if (appIds.isEmpty) return result;
    for (final root in roots) {
      final appInfo = File(p.join(root.path, 'appcache', 'appinfo.vdf'));
      if (!await appInfo.exists()) continue;
      try {
        final bytes = await appInfo.readAsBytes();
        final missingAppIds = appIds
            .where((id) => !result.containsKey(id))
            .toSet();
        result.addAll(
          _SteamAppInfoReader(bytes).windowsLaunchExecutableMap(missingAppIds),
        );
      } on FileSystemException {
        // Steam may replace appinfo.vdf while its cache is being read.
      } on FormatException {
        // Use the regular executable discovery if Steam's binary cache is
        // incomplete or changes while it is being parsed.
      }
    }
    return result;
  }

  static String? _resolveSteamDefinedExecutable(
    Directory gameFolder,
    List<String> relativeExecutables,
  ) {
    // Steam may offer a launcher as the default plus the actual UE Shipping
    // executable as another Windows launch option. For proxy deployment the
    // latter is the process that loads the renderer DLLs.
    final candidates = [
      ...relativeExecutables.where(isUnrealEngineLaunchExecutable),
      ...relativeExecutables.where(
        (executable) => !isUnrealEngineLaunchExecutable(executable),
      ),
    ];
    for (final executable in candidates) {
      final candidate = p.normalize(
        p.join(gameFolder.path, executable.trim().replaceAll('/', '\\')),
      );
      if (p.extension(candidate).toLowerCase() == '.exe' &&
          _isWithin(candidate, gameFolder.path) &&
          File(candidate).existsSync()) {
        return candidate;
      }
    }
    return null;
  }

  /// Whether a Steam launch executable explicitly identifies a packaged
  /// Unreal game binary. appinfo.vdf has no engine field, so this intentionally
  /// uses only UE's standard Shipping binary layout.
  static bool isUnrealEngineLaunchExecutable(String executable) {
    final normalized = executable.replaceAll('/', '\\').toLowerCase();
    if (normalized.contains(r'\engine\binaries\win64\')) return false;
    return RegExp(
      r'(?:^|\\)binaries\\win64\\[^\\]+-win64-(?:shipping|development|test|debug)(?:-[^\\]+)?\.exe$',
    ).hasMatch(normalized);
  }

  static List<String> parseLibraryFolders(String text) {
    final root = VdfParser(text).parse();
    final libraries = root.child('libraryfolders') ?? root;
    final paths = <String>{};
    void visit(VdfNode node) {
      for (final entry in node.values.entries) {
        if (entry.value is VdfNode) visit(entry.value as VdfNode);
        if (entry.key.toLowerCase() == 'path' && entry.value is String) {
          final path = (entry.value as String).replaceAll('\\\\', '\\');
          if (path.isNotEmpty) paths.add(path);
        }
      }
    }

    visit(libraries);
    return paths.toList();
  }

  static Map<String, String> parseAppManifest(String text) {
    final root = VdfParser(text).parse();
    final node = root.child('AppState') ?? root;
    return node.values.map(
      (key, value) => MapEntry(key.toLowerCase(), value is String ? value : ''),
    );
  }

  /// Reads Steam's Windows launch entries from the binary appinfo cache.
  ///
  /// App manifests deliberately do not store an executable. Steam keeps the
  /// authoritative launch configuration at `config/launch` in appinfo.vdf.
  /// The returned entries are ordered with the Windows default first.
  static List<String> parseAppInfoLaunchExecutables(
    Uint8List bytes,
    int appId,
  ) {
    try {
      return _SteamAppInfoReader(bytes).windowsLaunchExecutables(appId);
    } on FormatException {
      // The Steam client can rewrite this cache while it is being read. The
      // regular executable discovery remains a safe fallback in that case.
      return const [];
    }
  }

  static Future<String?> _findGameExecutable(
    Directory gameFolder, {
    required String gameName,
    required String installDir,
  }) async {
    if (!await gameFolder.exists()) return null;
    final normalizedInstallDir = _normalizedName(installDir);
    final normalizedGameName = _normalizedName(gameName);
    File? best;
    var bestScore = -1 << 30;
    try {
      await for (final item in gameFolder.list(
        recursive: true,
        followLinks: false,
      )) {
        if (item is! File || p.extension(item.path).toLowerCase() != '.exe') {
          continue;
        }
        final stem = p.basenameWithoutExtension(item.path);
        if (_ignoredExecutableNames.contains(_normalizedName(stem))) continue;
        final relative = p.relative(item.path, from: gameFolder.path);
        final depth = p.split(relative).length - 1;
        final normalizedStem = _normalizedName(stem);
        var score = 0;
        if (normalizedStem == normalizedInstallDir) score += 100;
        if (normalizedStem == normalizedGameName) score += 90;
        if (depth == 0) score += 30;
        if (installDir.isNotEmpty &&
            normalizedStem.contains(normalizedInstallDir)) {
          score += 20;
        }
        score -= depth * 4;
        if (score > bestScore) {
          best = item;
          bestScore = score;
        }
      }
    } on FileSystemException {
      return null;
    }
    return best?.path;
  }

  static String _normalizedName(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]'), '');

  static const _ignoredExecutableNames = {
    'uninstall',
    'unins000',
    'setup',
    'dxsetup',
    'vcredistx64',
    'vcredistx86',
    'unitycrashhandler32',
    'unitycrashhandler64',
    'crashreportclient',
    'eosbootstrapper',
    'launcher',
  };

  // Steamworks Common Redistributables is a Steam support component, not a
  // game that can be managed by this application.
  static const _ignoredAppIds = {228980};

  static Future<Map<int, DateTime>> readLastPlayed(
    List<Directory> roots,
  ) async {
    final result = <int, DateTime>{};
    for (final root in roots) {
      final users = Directory(p.join(root.path, 'userdata'));
      if (!users.existsSync()) continue;
      await for (final user in users.list()) {
        if (user is! Directory) continue;
        final localConfig = File(
          p.join(user.path, 'config', 'localconfig.vdf'),
        );
        if (!localConfig.existsSync()) continue;
        final rootNode = VdfParser(await localConfig.readAsString()).parse();
        _collectLastPlayed(rootNode, result);
      }
    }
    return result;
  }

  static void _collectLastPlayed(
    VdfNode node,
    Map<int, DateTime> result, [
    int? appId,
  ]) {
    for (final entry in node.values.entries) {
      if (entry.value is! VdfNode) continue;
      final id = int.tryParse(entry.key) ?? appId;
      final child = entry.value as VdfNode;
      final epoch = int.tryParse(child.string('LastPlayed') ?? '');
      if (id != null && epoch != null) {
        final date = DateTime.fromMillisecondsSinceEpoch(
          epoch * 1000,
          isUtc: true,
        );
        if (result[id] == null || date.isAfter(result[id]!)) result[id] = date;
      }
      _collectLastPlayed(child, result, id);
    }
  }

  static bool _samePath(String a, String b) =>
      p.normalize(a).toLowerCase() == p.normalize(b).toLowerCase();
  static bool _isWithin(String file, String directory) =>
      p.isWithin(p.normalize(directory), p.normalize(file));
  static int _serial = 0;
  static String _id() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${_serial++}';
}

GameEntry _copyGame(GameEntry game) => GameEntry.fromJson(game.toJson());

class _InstalledSteamApp {
  const _InstalledSteamApp(this.library, this.appId, this.manifest);

  final Directory library;
  final int appId;
  final Map<String, String> manifest;
}

class _SteamAppInfoReader {
  _SteamAppInfoReader(this._bytes) : _data = ByteData.sublistView(_bytes);

  static const _magicV39 = 0x07564427;
  static const _magicV40 = 0x07564428;
  static const _magicV41 = 0x07564429;

  final Uint8List _bytes;
  final ByteData _data;
  int _position = 0;
  List<String> _stringTable = const [];
  var _usesStringTable = false;

  List<String> windowsLaunchExecutables(int targetAppId) {
    return windowsLaunchExecutableMap({targetAppId})[targetAppId] ?? const [];
  }

  Map<int, List<String>> windowsLaunchExecutableMap(Set<int> targetAppIds) {
    if (targetAppIds.isEmpty) return const {};
    final magic = _readUint32();
    if (magic != _magicV39 && magic != _magicV40 && magic != _magicV41) {
      throw const FormatException('Unsupported Steam appinfo format');
    }
    _readUint32(); // Steam universe
    if (magic == _magicV41) {
      final stringTableOffset = _readInt64();
      if (stringTableOffset < 0 || stringTableOffset >= _bytes.length) {
        throw const FormatException(
          'Invalid Steam appinfo string table offset',
        );
      }
      final entriesPosition = _position;
      _position = stringTableOffset;
      final stringCount = _readUint32();
      _stringTable = List.generate(stringCount, (_) => _readNullString());
      _usesStringTable = true;
      _position = entriesPosition;
    }

    final result = <int, List<String>>{};
    while (_position + 4 <= _bytes.length) {
      final appId = _readUint32();
      if (appId == 0) return result;
      final size = _readUint32();
      final entryEnd = _position + size;
      if (entryEnd > _bytes.length || size < 40) {
        throw const FormatException('Invalid Steam appinfo entry size');
      }

      // App entry metadata preceding the binary VDF payload.
      _skip(4 + 4 + 8 + 20 + 4);
      if (magic == _magicV40 || magic == _magicV41) _skip(20);
      if (_position > entryEnd) {
        throw const FormatException('Invalid Steam appinfo entry metadata');
      }
      if (targetAppIds.contains(appId)) {
        final root = _readObject(entryEnd);
        final executables = _extractWindowsLaunchExecutables(root);
        if (executables.isNotEmpty) result[appId] = executables;
      }
      _position = entryEnd;
      if (result.length == targetAppIds.length) return result;
    }
    throw const FormatException('Steam appinfo entry is truncated');
  }

  List<String> _extractWindowsLaunchExecutables(Map<String, Object?> root) {
    final config = root['config'];
    if (config is! Map<String, Object?>) return const [];
    final launch = config['launch'];
    if (launch is! Map<String, Object?>) return const [];

    final defaults = <String>[];
    final alternatives = <String>[];
    for (final entry in launch.values) {
      if (entry is! Map<String, Object?>) continue;
      final executable = entry['executable'];
      if (executable is! String || executable.isEmpty) continue;
      final entryConfig = entry['config'];
      final osList = entryConfig is Map<String, Object?>
          ? entryConfig['oslist']
          : entry['oslist'];
      if (osList is String && !_targetsWindows(osList)) continue;
      final type = entry['type'];
      if (type is! String || type.isEmpty || type.toLowerCase() == 'default') {
        defaults.add(executable);
      } else {
        alternatives.add(executable);
      }
    }
    return [...defaults, ...alternatives];
  }

  bool _targetsWindows(String osList) =>
      osList.toLowerCase().split(RegExp(r'[,;\s]+')).contains('windows');

  Map<String, Object?> _readObject(int entryEnd) {
    final result = <String, Object?>{};
    while (_position < entryEnd) {
      final type = _readByte();
      if (type == 0x08) return result;
      final key = _readKey().toLowerCase();
      switch (type) {
        case 0x00:
          result[key] = _readObject(entryEnd);
          break;
        case 0x01:
          result[key] = _readNullString();
          break;
        case 0x02:
        case 0x03:
        case 0x04:
        case 0x06:
          _skip(4);
          break;
        case 0x05:
          _skipWideString();
          break;
        case 0x07:
          _skip(8);
          break;
        case 0x09:
        case 0x0A:
          // Compiled integer constants carry no payload.
          break;
        default:
          throw FormatException('Unsupported Steam binary VDF type: $type');
      }
    }
    throw const FormatException('Unterminated Steam binary VDF object');
  }

  String _readKey() {
    if (!_usesStringTable) return _readNullString();
    final index = _readUint32();
    if (index >= _stringTable.length) {
      throw const FormatException('Invalid Steam appinfo string table index');
    }
    return _stringTable[index];
  }

  int _readByte() {
    if (_position >= _bytes.length) {
      throw const FormatException('Unexpected end of Steam appinfo');
    }
    return _bytes[_position++];
  }

  int _readUint32() {
    _require(4);
    final value = _data.getUint32(_position, Endian.little);
    _position += 4;
    return value;
  }

  int _readInt64() {
    _require(8);
    final value = _data.getInt64(_position, Endian.little);
    _position += 8;
    return value;
  }

  String _readNullString() {
    final start = _position;
    while (_position < _bytes.length && _bytes[_position] != 0) {
      _position++;
    }
    if (_position >= _bytes.length) {
      throw const FormatException('Unterminated Steam appinfo string');
    }
    final value = utf8.decode(
      _bytes.sublist(start, _position),
      allowMalformed: true,
    );
    _position++;
    return value;
  }

  void _skipWideString() {
    while (true) {
      _require(2);
      final value = _data.getUint16(_position, Endian.little);
      _position += 2;
      if (value == 0) return;
    }
  }

  void _skip(int bytes) {
    _require(bytes);
    _position += bytes;
  }

  void _require(int count) {
    if (_position + count > _bytes.length) {
      throw const FormatException('Unexpected end of Steam appinfo');
    }
  }
}
