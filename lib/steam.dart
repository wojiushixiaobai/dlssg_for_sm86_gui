import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

import 'models.dart';
import 'vdf.dart';

final _storeArtworkRequests = <int, Future<String?>>{};

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
  request.then((url) {
    if (url == null) _storeArtworkRequests.remove(appId);
  });
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

  Future<List<GameEntry>> scan({required List<GameEntry> existing}) async {
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
    final lastPlayed = await readLastPlayed(roots);
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
        if (appId == null) continue;
        final name = manifest['name'] ?? 'Steam App $appId';
        final installDir = manifest['installdir'] ?? '';
        final gameFolder = Directory(p.join(apps.path, 'common', installDir));
        final scanned = scannedSteam[appId];
        final previous = scanned ?? existingSteam[appId];
        final detectedExe =
            previous?.exePath != null &&
                File(previous!.exePath!).existsSync() &&
                _isWithin(previous.exePath!, gameFolder.path)
            ? previous.exePath
            : await _findGameExecutable(
                gameFolder,
                gameName: name,
                installDir: installDir,
              );
        if (scanned != null) {
          scanned.name = name;
          scanned.source = GameSource.steam(appId, library.path);
          if (lastPlayed[appId] != null) {
            scanned.lastPlayedAt = lastPlayed[appId];
          }
          if (scanned.exePath == null || !File(scanned.exePath!).existsSync()) {
            scanned.exePath = detectedExe;
          }
          continue;
        }
        final previousSteam = existingSteam.remove(appId);
        if (previousSteam != null) {
          previousSteam.name = name;
          previousSteam.source = GameSource.steam(appId, library.path);
          if (lastPlayed[appId] != null) {
            previousSteam.lastPlayedAt = lastPlayed[appId];
          }
          if (previousSteam.exePath == null ||
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
          source: GameSource.steam(appId, library.path),
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
    }
    return result;
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
