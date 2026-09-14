import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:dlssg_for_sm86_manager/manager.dart';
import 'package:dlssg_for_sm86_manager/models.dart';
import 'package:dlssg_for_sm86_manager/steam.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('Valve 格式', () {
    test('解析 libraryfolders 和 ACF', () {
      const libraries =
          '"libraryfolders" { "0" { "path" "D:\\\\Steam Library" } "1" { "path" "E:\\\\Games" } }';
      expect(
        SteamScanner.parseLibraryFolders(libraries),
        containsAll(['D:\\Steam Library', 'E:\\Games']),
      );
      expect(
        SteamScanner.parseAppManifest(
          '"AppState" { "appid" "480" "name" "Spacewar" "installdir" "spacewar" }',
        ),
        {'appid': '480', 'name': 'Spacewar', 'installdir': 'spacewar'},
      );
    });
    test('采集每个 Steam 用户的最近游玩时间', () async {
      final root = await Directory.systemTemp.createTemp('dlssg-steam-');
      addTearDown(() => root.delete(recursive: true));
      final config = File(
        p.join(root.path, 'userdata', '1', 'config', 'localconfig.vdf'),
      );
      await config.parent.create(recursive: true);
      await config.writeAsString(
        '"UserLocalConfigStore" { "Software" { "Valve" { "Steam" { "apps" { "480" { "LastPlayed" "100" } } } } } }',
      );
      expect(await SteamScanner.readLastPlayed([root]), {
        480: DateTime.fromMillisecondsSinceEpoch(100000, isUtc: true),
      });
    });
    test('扫描 Steam 游戏时自动识别游戏 EXE', () async {
      final root = await Directory.systemTemp.createTemp('dlssg-steam-scan-');
      addTearDown(() => root.delete(recursive: true));
      final manifest = File(
        p.join(root.path, 'steamapps', 'appmanifest_480.acf'),
      );
      await manifest.parent.create(recursive: true);
      await manifest.writeAsString(
        '"AppState" { "appid" "480" "name" "Spacewar" "installdir" "spacewar" }',
      );
      final gameDir = Directory(
        p.join(root.path, 'steamapps', 'common', 'spacewar'),
      );
      await gameDir.create(recursive: true);
      final exe = File(p.join(gameDir.path, 'spacewar.exe'));
      await exe.writeAsString('exe');
      await File(p.join(gameDir.path, 'launcher.exe'))
          .writeAsString('launcher');

      final games = await SteamScanner(steamPath: () => root.path)
          .scan(existing: const []);

      final spacewar = games.singleWhere((game) => game.source.appId == 480);
      expect(spacewar.exePath, exe.path);
    });
  });

  group('配置和便携文件', () {
    test('哈希目录将上游最新 DLL 与历史 DLL 分开识别', () {
      final catalog = ModHashCatalog.fromJson({
        'schema_version': 2,
        'latest': {
          'files': [
            {
              'path': 'version.dll',
              'file_name': 'version.dll',
              'sha256': 'LATEST',
            },
          ],
        },
        'historical': {
          'files': [
            {
              'path': 'archive/version.dll',
              'file_name': 'version.dll',
              'sha256': 'OLD',
            },
          ],
        },
        'hashes': {'latest': 'version.dll', 'old': 'version.dll'},
      });

      expect(catalog.isLatest('LATEST'), isTrue);
      expect(catalog.isHistorical('OLD'), isTrue);
      expect(catalog.isHistorical('LATEST'), isFalse);
      expect(catalog.contains('unknown'), isFalse);
    });
    test('哈希目录保留上游 main commit 与运行包文件哈希', () {
      final catalog = ModHashCatalog.fromJson({
        'source': {'head_commit': 'abcdef0123456789abcdef0123456789abcdef01'},
        'latest': {
          'files': [
            {
              'path': 'version.dll',
              'file_name': 'version.dll',
              'sha256': 'LATEST',
            },
          ],
        },
      });

      expect(
        catalog.sourceHeadCommit,
        'abcdef0123456789abcdef0123456789abcdef01',
      );
      expect(catalog.latestFileHash('version.dll'), 'latest');
    });

    test('INI 仅输出固定字段与实际启用的高级字段', () {
      const profile = ConfigProfile(
        name: 'Test',
        router: true,
        kernelImage: true,
        hardwareBilinear: false,
        maxGeneratedFrames: 3,
        loggingLevel: 1,
        advanced: AdvancedOverrides(debug: true),
      );
      final ini = profile.toIni();
      expect(ini, contains('Router=SM86'));
      expect(ini, contains('Debug=true'));
      expect(ini, isNot(contains('Extra=')));
      expect(ini, isNot(contains('Enabled=')));
    });
    test('兼容 Tauri state.json 的 snake_case 顶层和 camelCase 游戏字段', () {
      final db = Database.fromJsonText(
        jsonEncode({
          'games': [
            {
              'id': 'x',
              'name': 'Game',
              'source': {
                'kind': 'steam',
                'app_id': 1,
                'library_path': 'D:\\Steam',
              },
              'selectedProxy': 'version.dll',
            },
          ],
          'global_profile': 'quality',
          'installed_version': 'v1',
          'steam_initial_scan_completed': true,
        }),
      );
      expect(db.games.single.source.appId, 1);
      expect(db.globalProfile, 'quality');
      expect(db.installedVersion, 'v1');
      expect(db.steamInitialScanCompleted, isTrue);
    });
    test('原子替换覆盖已有文件', () async {
      final root = await Directory.systemTemp.createTemp('dlssg-write-');
      addTearDown(() => root.delete(recursive: true));
      final target = File(p.join(root.path, 'state.json'));
      await target.writeAsString('old');
      await atomicWrite(target, utf8.encode('new'));
      expect(await target.readAsString(), 'new');
    });
  });

  test('按上游短 commit 下载 tar.gz，并在本地复用快照', () async {
    final root = await Directory.systemTemp.createTemp('dlssg-refresh-');
    addTearDown(() => root.delete(recursive: true));
    const commit = 'abcdef0123456789abcdef0123456789abcdef01';
    const version = 'abcdef0';
    final files = {
      'version.dll': 'mod-version.dll',
      'altnative/dinput8.dll': 'mod-dinput8.dll',
      'altnative/dxgi.dll': 'mod-dxgi.dll',
      'altnative/winhttp.dll': 'mod-winhttp.dll',
      'altnative/winmm.dll': 'mod-winmm.dll',
      'dlssg_sm86.ini': defaultIni,
    };
    final catalog = {
      'source': {'head_commit': commit},
      'latest': {
        'commit': commit,
        'files': [
          for (final entry in files.entries.where(
            (x) => x.key.endsWith('.dll'),
          ))
            {
              'path': entry.key,
              'file_name': p.basename(entry.key),
              'sha256': crypto.sha256
                  .convert(utf8.encode(entry.value))
                  .toString(),
            },
        ],
      },
    };
    final archive = Archive();
    for (final entry in files.entries) {
      final content = utf8.encode(entry.value);
      archive.addFile(
        ArchiveFile(
          'dlssg_for_sm86-$commit/${entry.key}',
          content.length,
          content,
        ),
      );
    }
    final tarGz = GZipEncoder().encodeBytes(TarEncoder().encodeBytes(archive));
    var archiveRequests = 0;
    final manager = await ModManager.open(
      dataDirectory: root,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/mod-hash-catalog.json')) {
          return Response(jsonEncode(catalog), 200);
        }
        if (request.url.path.endsWith('/$version/$modArchiveName')) {
          archiveRequests++;
          return Response.bytes(tarGz, 200);
        }
        return Response('not found', 404);
      }),
    );

    expect(await manager.refreshModFromGithub(), version);
    expect(archiveRequests, 1);
    expect(
      await File(p.join(root.path, 'release', version, 'winmm.dll'))
          .readAsString(),
      'mod-winmm.dll',
    );
    expect(
      await File(p.join(root.path, 'release', version, modArchiveName))
          .exists(),
      isTrue,
    );

    expect(await manager.refreshModFromGithub(), version);
    expect(archiveRequests, 1);
  });

  test('每个代理入口只保留最新非 Mod 原始 DLL 备份，并可静默恢复', () async {
    final root = await Directory.systemTemp.createTemp('dlssg-install-');
    addTearDown(() => root.delete(recursive: true));
    final manager = await ModManager.open(dataDirectory: root);
    final cache = Directory(p.join(root.path, 'release', 'test'));
    await cache.create(recursive: true);
    for (final proxy in proxies) {
      await File(p.join(cache.path, proxy)).writeAsString('mod-$proxy');
    }
    await File(p.join(cache.path, 'dlssg_sm86.ini')).writeAsString(defaultIni);
    manager.db.installedVersion = 'test';
    manager.db.catalog = ModHashCatalog({});
    final gameDir = Directory(p.join(root.path, 'game'));
    await gameDir.create();
    final exe = File(p.join(gameDir.path, 'game.exe'));
    await exe.writeAsString('exe');
    final original = File(p.join(gameDir.path, defaultProxy));
    await original.writeAsString('original-v1');
    final game = await manager.addManualGame('Game', exe.path);
    await manager.installMod(game.id, confirmOverwrite: true);
    expect(
      manager.db.games.firstWhere((x) => x.id == game.id).backups,
      hasLength(1),
    );
    expect(await original.readAsString(), 'mod-version.dll');
    await manager.uninstallMod(game.id);
    expect(await original.readAsString(), 'original-v1');
    await original.writeAsString('original-v2');
    await manager.installMod(game.id, confirmOverwrite: true);
    expect(
      manager.db.games.firstWhere((x) => x.id == game.id).backups,
      hasLength(1),
    );
    await manager.uninstallMod(game.id);
    expect(await original.readAsString(), 'original-v2');
  });

  test('游戏目录中的上游历史 DLL 标记为需要更新', () async {
    final root = await Directory.systemTemp.createTemp('dlssg-version-check-');
    addTearDown(() => root.delete(recursive: true));
    final manager = await ModManager.open(dataDirectory: root);
    final gameDir = Directory(p.join(root.path, 'game'));
    await gameDir.create();
    final exe = File(p.join(gameDir.path, 'game.exe'));
    final dll = File(p.join(gameDir.path, defaultProxy));
    await exe.writeAsString('exe');
    await dll.writeAsString('old upstream DLL');
    await File(p.join(gameDir.path, 'dlssg_sm86.ini'))
        .writeAsString(defaultIni);
    final hash = sha256FileSync(dll);
    manager.db.catalog = ModHashCatalog({hash: defaultProxy});
    final game = await manager.addManualGame('Game', exe.path);

    expect(manager.view(game).mod.kind, ModStateKind.outdated);

    manager.db.catalog = ModHashCatalog(
      {hash: defaultProxy},
      {hash: defaultProxy},
    );
    expect(manager.view(game).mod.kind, ModStateKind.applied);
  });

  test('游戏驱动设置立即写入游戏 INI，并解除旧配置档关联', () async {
    final root = await Directory.systemTemp.createTemp('dlssg-game-config-');
    addTearDown(() => root.delete(recursive: true));
    final manager = await ModManager.open(dataDirectory: root);
    final cache = Directory(p.join(root.path, 'release', 'test'));
    await cache.create(recursive: true);
    await File(p.join(cache.path, 'dlssg_sm86.ini')).writeAsString(defaultIni);
    manager.db.installedVersion = 'test';
    final gameDir = Directory(p.join(root.path, 'game'));
    await gameDir.create();
    final exe = File(p.join(gameDir.path, 'game.exe'));
    await exe.writeAsString('exe');
    final game = await manager.addManualGame('Game', exe.path);
    manager.db.games.firstWhere((x) => x.id == game.id).configProfile = '旧配置档';

    const config = ConfigProfile(
      name: 'Game',
      router: false,
      kernelImage: false,
      hardwareBilinear: true,
      maxGeneratedFrames: 2,
      loggingLevel: 3,
      advanced: AdvancedOverrides(debug: true),
    );
    await manager.saveGameConfig(game.id, config);

    final ini = await File(p.join(gameDir.path, 'dlssg_sm86.ini'))
        .readAsString();
    expect(ini, contains('Router=SM75'));
    expect(ini, contains('KernelImage=Auto'));
    expect(ini, contains('MaxGeneratedFrames=2'));
    expect(ini, contains('Debug=true'));
    expect(
      manager.db.games.firstWhere((x) => x.id == game.id).configProfile,
      isNull,
    );
    expect((await manager.loadGameConfig(game.id)).loggingLevel, 3);
  });

  test('Steam 游戏选择 EXE 时定位到其安装目录', () async {
    final root = await Directory.systemTemp.createTemp('dlssg-game-dir-');
    addTearDown(() => root.delete(recursive: true));
    final manager = await ModManager.open(dataDirectory: root);
    final library = Directory(p.join(root.path, 'SteamLibrary'));
    final manifest = File(
      p.join(library.path, 'steamapps', 'appmanifest_480.acf'),
    );
    await manifest.parent.create(recursive: true);
    await manifest.writeAsString(
      '"AppState" { "appid" "480" "installdir" "Spacewar" }',
    );
    final gameDir = Directory(
      p.join(library.path, 'steamapps', 'common', 'Spacewar'),
    );
    await gameDir.create(recursive: true);
    final game = GameEntry(
      id: '480',
      name: 'Spacewar',
      source: GameSource.steam(480, library.path),
    );

    expect(await manager.gameDirectory(game), gameDir.path);
  });
}
