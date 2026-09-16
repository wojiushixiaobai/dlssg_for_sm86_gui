import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dlssg_for_sm86_manager/manager.dart';
import 'package:dlssg_for_sm86_manager/models.dart';
import 'package:dlssg_for_sm86_manager/steam.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const releaseIni = '''; Release-owned configuration
[General]
Enabled=1

[FrameGeneration]
Optimized=1
MaxGeneratedFrames=5

[Compatibility]
Preset=Auto

[Logging]
Level=1
Directory=dlssg_sm86\\logs

[Runtime]
Mode=Bundled
CacheDirectory=
''';

ConfigProfile testProfile(
  String name, {
  int maxGeneratedFrames = 5,
  int loggingLevel = 1,
  String preset = 'Auto',
}) => ConfigProfile(
  name: name,
  sections: [
    const IniSection(
      name: 'General',
      settings: [IniSetting(key: 'Enabled', value: '1')],
    ),
    IniSection(
      name: 'FrameGeneration',
      settings: [
        const IniSetting(key: 'Optimized', value: '1'),
        IniSetting(key: 'MaxGeneratedFrames', value: '$maxGeneratedFrames'),
      ],
    ),
    IniSection(
      name: 'Compatibility',
      settings: [IniSetting(key: 'Preset', value: preset)],
    ),
    IniSection(
      name: 'Logging',
      settings: [
        IniSetting(key: 'Level', value: '$loggingLevel'),
        const IniSetting(key: 'Directory', value: 'dlssg_sm86\\logs'),
      ],
    ),
    const IniSection(
      name: 'Runtime',
      settings: [
        IniSetting(key: 'Mode', value: 'Bundled'),
        IniSetting(key: 'CacheDirectory', value: ''),
      ],
    ),
  ],
);

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
    test('通过 Steam 元数据读取带哈希的封面 URL', () async {
      final url = await steamArtworkUrl(
        4570720,
        client: MockClient(
          (_) async => Response(
            jsonEncode({
              '4570720': {
                'success': true,
                'data': {
                  'header_image': 'https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/4570720/hash/header.jpg',
                },
              },
            }),
            200,
          ),
        ),
      );

      expect(url, contains('/4570720/hash/header.jpg'));
    });
  });

  group('配置和便携文件', () {
    test('默认数据和驱动程序缓存位于 LocalAppData 应用目录', () {
      final localAppDataDirectory = Directory(
        p.join('C:', 'Users', 'tester', 'AppData', 'Local'),
      );
      expect(
        ModManager.defaultDataDirectory(localAppDataDirectory).path,
        p.join(localAppDataDirectory.path, 'dlssg_for_sm86_gui', 'data'),
      );
      expect(
        ModManager.defaultReleaseDirectory(localAppDataDirectory).path,
        p.join(localAppDataDirectory.path, 'dlssg_for_sm86_gui', 'release'),
      );
    });

    test('INI 按原始 Section 和键动态序列化', () {
      const profile = ConfigProfile(
        name: 'Test',
        sections: [
          IniSection(
            name: 'Experimental',
            settings: [
              IniSetting(key: 'Toggle', value: '0'),
              IniSetting(key: 'CustomPath', value: 'cache'),
            ],
          ),
        ],
      );
      final ini = profile.toIni();
      expect(ini, '[Experimental]\nToggle=0\nCustomPath=cache\n');
      final parsed = ModManager.parseProfile('Test', ini);
      expect(parsed.value('Experimental', 'Toggle'), '0');
      expect(
        parsed.withValue('Experimental', 'CustomPath', 'new').toIni(),
        contains('CustomPath=new'),
      );
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
          'installed_version': 'v1',
          'steam_initial_scan_completed': true,
        }),
      );
      expect(db.games.single.source.appId, 1);
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

  test('通过上游 latest Release API 下载 tar.gz，并在本地复用缓存', () async {
    final root = await Directory.systemTemp.createTemp('dlssg-refresh-');
    addTearDown(() => root.delete(recursive: true));
    var version = '0.3.0';
    final files = {
      'version.dll': 'mod-version.dll',
      'alternatives/dinput8.dll': 'mod-dinput8.dll',
      'alternatives/dxgi.dll': 'mod-dxgi.dll',
      'alternatives/winmm.dll': 'mod-winmm.dll',
      'alternatives/d3d12.dll': 'mod-d3d12.dll',
      'alternatives/dbghelp.dll': 'mod-dbghelp.dll',
      'alternatives/README.md': '# 备用代理 DLL',
      'archive/0.2.4/altnative/winmm.dll': 'old-winmm.dll',
      'docs/advanced.md': '# Advanced keys',
      'dlssg_sm86.ini': releaseIni,
    };
    final archive = Archive();
    for (final entry in files.entries) {
      final content = utf8.encode(entry.value);
      archive.addFile(
        ArchiveFile(
          'dlssg_for_sm86-$version/${entry.key}',
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
        if (request.url.path.endsWith('/releases/latest')) {
          return Response(
            jsonEncode({
              'tag_name': version,
              'tarball_url': 'https://upstream.example/$version.tar.gz',
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/$version.tar.gz')) {
          archiveRequests++;
          return Response.bytes(tarGz, 200);
        }
        return Response('not found', 404);
      }),
    );

    final progress = <DownloadProgress>[];
    expect(
      await manager.refreshModFromGithub(onProgress: progress.add),
      version,
    );
    expect(archiveRequests, 1);
    expect(progress.first.phase, DownloadPhase.downloading);
    expect(
      progress.any(
        (snapshot) =>
            snapshot.phase == DownloadPhase.downloading &&
            snapshot.downloadedBytes == tarGz.length,
      ),
      isTrue,
    );
    expect(progress.last.phase, DownloadPhase.verifying);
    expect(
      await File(
        p.join(
          root.path,
          'release',
          'dlssg_for_sm86',
          'alternatives',
          'winmm.dll',
        ),
      ).readAsString(),
      'mod-winmm.dll',
    );
    expect(
      await File(
        p.join(
          root.path,
          'release',
          'dlssg_for_sm86',
          'alternatives',
          'README.md',
        ),
      ).readAsString(),
      '# 备用代理 DLL',
    );
    expect(
      await File(
        p.join(root.path, 'release', 'dlssg_for_sm86', 'docs', 'advanced.md'),
      ).readAsString(),
      '# Advanced keys',
    );
    expect(
      await File(p.join(root.path, 'release', version, modArchiveName))
          .exists(),
      isTrue,
    );
    expect(
      await File(
        p.join(root.path, 'release', 'dlssg_for_sm86', 'dlssg_sm86.ini'),
      ).readAsString(),
      releaseIni,
    );
    expect(
      await File(p.join(root.path, 'global.ini')).readAsString(),
      releaseIni,
    );
    expect(
      (await manager.loadGlobalConfig()).value(
        'FrameGeneration',
        'MaxGeneratedFrames',
      ),
      '5',
    );

    final gameDir = Directory(p.join(root.path, 'nested-proxy-game'));
    await gameDir.create();
    final exe = File(p.join(gameDir.path, 'game.exe'));
    await exe.writeAsString('exe');
    final game = await manager.addManualGame('Nested proxy game', exe.path);
    await manager.installMod(game.id, proxy: 'winmm.dll');
    expect(
      await File(p.join(gameDir.path, 'winmm.dll')).readAsString(),
      'mod-winmm.dll',
    );

    final oldGameDir = Directory(p.join(root.path, 'historical-proxy-game'));
    await oldGameDir.create();
    final oldExe = File(p.join(oldGameDir.path, 'game.exe'));
    await oldExe.writeAsString('exe');
    await File(p.join(oldGameDir.path, 'dlssg_sm86.ini'))
        .writeAsString(releaseIni);
    await File(p.join(oldGameDir.path, 'winmm.dll'))
        .writeAsString('old-winmm.dll');
    final oldGame = await manager.addManualGame(
      'Historical proxy game',
      oldExe.path,
    );
    expect(manager.view(oldGame).mod.kind, ModStateKind.applied);
    await manager.installMod(
      oldGame.id,
      proxy: 'winmm.dll',
      confirmOverwrite: true,
    );
    expect(manager.view(oldGame).mod.kind, ModStateKind.applied);
    expect(
      await File(p.join(oldGameDir.path, 'winmm.dll')).readAsString(),
      'mod-winmm.dll',
    );

    final staleFile = File(
      p.join(root.path, 'release', 'dlssg_for_sm86', 'removed-upstream.dll'),
    );
    await staleFile.writeAsString('stale');
    // A cached archive remains reusable even if state was not persisted (for
    // example, after an interrupted first installation).
    manager.db.installedVersion = null;
    expect(await manager.refreshModFromGithub(), version);
    expect(archiveRequests, 1);
    expect(await staleFile.exists(), isFalse);

    version = '0.4.0';
    expect(await manager.refreshModFromGithub(), version);
    expect(archiveRequests, 2);
    expect(
      await File(
        p.join(
          root.path,
          'release',
          'dlssg_for_sm86',
          'alternatives',
          'winmm.dll',
        ),
      ).exists(),
      isTrue,
    );
  });

  test('只有 dlssg_sm86.ini 时视为未安装', () async {
    final root = await Directory.systemTemp.createTemp('dlssg-existing-ini-');
    addTearDown(() => root.delete(recursive: true));
    final manager = await ModManager.open(dataDirectory: root);
    final gameDir = Directory(p.join(root.path, 'game'));
    await gameDir.create();
    final exe = File(p.join(gameDir.path, 'game.exe'));
    await exe.writeAsString('exe');
    await File(p.join(gameDir.path, 'dlssg_sm86.ini'))
        .writeAsString(releaseIni);
    final game = await manager.addManualGame(
      'Existing configuration',
      exe.path,
    );

    expect(manager.view(game).mod.kind, ModStateKind.notApplied);
    expect(
      (await manager.loadGameConfig(game.id))
          .value('FrameGeneration', 'MaxGeneratedFrames'),
      '5',
    );

    await manager.saveGameConfig(
      game.id,
      testProfile(
        'Existing configuration',
        maxGeneratedFrames: 2,
        loggingLevel: 1,
      ),
    );
    expect(
      await File(p.join(gameDir.path, 'dlssg_sm86.ini')).readAsString(),
      contains('MaxGeneratedFrames=2'),
    );
    expect(manager.view(game).config.kind, ConfigStateKind.custom);
  });

  test('缺少 dlssg_sm86.ini 时视为未安装', () async {
    final root = await Directory.systemTemp.createTemp('dlssg-missing-ini-');
    addTearDown(() => root.delete(recursive: true));
    final manager = await ModManager.open(dataDirectory: root);
    final gameDir = Directory(p.join(root.path, 'game'));
    await gameDir.create();
    final exe = File(p.join(gameDir.path, 'game.exe'));
    await exe.writeAsString('exe');
    await File(p.join(gameDir.path, defaultProxy)).writeAsString('driver');
    final game = await manager.addManualGame('Missing INI', exe.path);

    expect(manager.view(game).mod.kind, ModStateKind.notApplied);
  });

  test('缺少 INI 时即使有旧记录也会备份现有代理 DLL', () async {
    final root = await Directory.systemTemp.createTemp('dlssg-stale-ini-');
    addTearDown(() => root.delete(recursive: true));
    final manager = await ModManager.open(dataDirectory: root);
    final cache = Directory(p.join(root.path, 'release', 'dlssg_for_sm86'));
    await cache.create(recursive: true);
    await File(p.join(cache.path, defaultProxy)).writeAsString('new-driver');
    await File(p.join(cache.path, 'dlssg_sm86.ini')).writeAsString(releaseIni);
    manager.db.installedVersion = 'current';
    final gameDir = Directory(p.join(root.path, 'game'));
    await gameDir.create();
    final exe = File(p.join(gameDir.path, 'game.exe'));
    await exe.writeAsString('exe');
    final proxy = File(p.join(gameDir.path, defaultProxy));
    await proxy.writeAsString('original-driver');
    final game = await manager.addManualGame('Stale record', exe.path);
    final entry = manager.db.games.firstWhere((x) => x.id == game.id);
    entry.install = ManagedInstall(
      proxy: defaultProxy,
      dllSha256: await sha256File(proxy),
      version: 'old',
    );

    await manager.installMod(game.id, confirmOverwrite: true);

    expect(entry.backups, hasLength(1));
    expect(
      await File(entry.backups.single.file).readAsString(),
      'original-driver',
    );
  });

  test('当前驱动代理在没有安装记录时仍显示为已安装并可卸载', () async {
    final root = await Directory.systemTemp.createTemp(
      'dlssg-existing-driver-',
    );
    addTearDown(() => root.delete(recursive: true));
    final manager = await ModManager.open(dataDirectory: root);
    final cache = Directory(p.join(root.path, 'release', 'dlssg_for_sm86'));
    await cache.create(recursive: true);
    await File(p.join(cache.path, defaultProxy))
        .writeAsString('mod-version.dll');
    await File(p.join(cache.path, 'dlssg_sm86.ini')).writeAsString(releaseIni);
    manager.db.installedVersion = 'test';
    final gameDir = Directory(p.join(root.path, 'game'));
    await gameDir.create();
    final exe = File(p.join(gameDir.path, 'game.exe'));
    await exe.writeAsString('exe');
    await File(p.join(gameDir.path, defaultProxy))
        .writeAsString('mod-version.dll');
    await File(p.join(gameDir.path, 'dlssg_sm86.ini'))
        .writeAsString(releaseIni);
    final game = await manager.addManualGame('Existing driver', exe.path);

    final status = manager.view(game).mod;
    expect(status.kind, ModStateKind.applied);
    expect(status.version, 'test');

    await manager.uninstallMod(game.id);
    expect(await File(p.join(gameDir.path, defaultProxy)).exists(), isFalse);
    expect(
      await File(p.join(gameDir.path, 'dlssg_sm86.ini')).exists(),
      isFalse,
    );
  });

  test('未知版本的既有驱动可以直接更新而不备份驱动 DLL', () async {
    final root = await Directory.systemTemp.createTemp('dlssg-update-driver-');
    addTearDown(() => root.delete(recursive: true));
    final manager = await ModManager.open(dataDirectory: root);
    final cache = Directory(p.join(root.path, 'release', 'dlssg_for_sm86'));
    await cache.create(recursive: true);
    await File(p.join(cache.path, defaultProxy))
        .writeAsString('current-driver');
    await File(p.join(cache.path, 'dlssg_sm86.ini')).writeAsString(releaseIni);
    manager.db.installedVersion = 'current';
    final gameDir = Directory(p.join(root.path, 'game'));
    await gameDir.create();
    final exe = File(p.join(gameDir.path, 'game.exe'));
    await exe.writeAsString('exe');
    final proxy = File(p.join(gameDir.path, defaultProxy));
    await proxy.writeAsString('old-driver');
    await File(p.join(gameDir.path, 'dlssg_sm86.ini'))
        .writeAsString(releaseIni);
    final game = await manager.addManualGame('Unknown driver', exe.path);

    await manager.installMod(game.id);

    expect(await proxy.readAsString(), 'current-driver');
    expect(
      manager.db.games.firstWhere((x) => x.id == game.id).backups,
      isEmpty,
    );
  });

  test('每个代理入口只保留最新非 Mod 原始 DLL 备份，并可静默恢复', () async {
    final root = await Directory.systemTemp.createTemp('dlssg-install-');
    addTearDown(() => root.delete(recursive: true));
    final manager = await ModManager.open(dataDirectory: root);
    final cache = Directory(p.join(root.path, 'release', 'dlssg_for_sm86'));
    await cache.create(recursive: true);
    for (final proxy in proxies) {
      await File(p.join(cache.path, proxy)).writeAsString('mod-$proxy');
    }
    await File(p.join(cache.path, 'dlssg_sm86.ini')).writeAsString(releaseIni);
    manager.db.installedVersion = 'test';
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

  test('游戏驱动设置立即写入游戏自定义 INI', () async {
    final root = await Directory.systemTemp.createTemp('dlssg-game-config-');
    addTearDown(() => root.delete(recursive: true));
    final manager = await ModManager.open(dataDirectory: root);
    final cache = Directory(p.join(root.path, 'release', 'dlssg_for_sm86'));
    await cache.create(recursive: true);
    await File(p.join(cache.path, 'dlssg_sm86.ini')).writeAsString(releaseIni);
    manager.db.installedVersion = 'test';
    final gameDir = Directory(p.join(root.path, 'game'));
    await gameDir.create();
    final exe = File(p.join(gameDir.path, 'game.exe'));
    await exe.writeAsString('exe');
    final game = await manager.addManualGame('Game', exe.path);

    final config =
        testProfile('Game', maxGeneratedFrames: 2, loggingLevel: 3, preset: 'A')
            .withValue('General', 'Enabled', '0')
            .withValue('FrameGeneration', 'Optimized', '0');
    await manager.saveGameConfig(game.id, config);

    final ini = await File(p.join(gameDir.path, 'dlssg_sm86.ini'))
        .readAsString();
    expect(ini, contains('Enabled=0'));
    expect(ini, contains('Optimized=0'));
    expect(ini, contains('Preset=A'));
    expect(ini, contains('MaxGeneratedFrames=2'));
    expect(
      manager.db.games.firstWhere((x) => x.id == game.id).hasCustomConfig,
      isTrue,
    );
    expect(manager.view(game).config.kind, ConfigStateKind.custom);
    expect(
      (await manager.loadGameConfig(game.id)).value('Logging', 'Level'),
      '3',
    );
  });

  test('安装继承全局配置，游戏自定义配置不受全局更新影响', () async {
    final root = await Directory.systemTemp.createTemp('dlssg-global-config-');
    addTearDown(() => root.delete(recursive: true));
    final manager = await ModManager.open(dataDirectory: root);
    final cache = Directory(p.join(root.path, 'release', 'dlssg_for_sm86'));
    await cache.create(recursive: true);
    for (final proxy in proxies) {
      await File(p.join(cache.path, proxy)).writeAsString('mod-$proxy');
    }
    await File(p.join(cache.path, 'dlssg_sm86.ini')).writeAsString(releaseIni);
    manager.db.installedVersion = 'test';
    final gameDir = Directory(p.join(root.path, 'game'));
    await gameDir.create();
    final exe = File(p.join(gameDir.path, 'game.exe'));
    await exe.writeAsString('exe');
    final game = await manager.addManualGame('Game', exe.path);
    final global = testProfile('全局配置', maxGeneratedFrames: 2, loggingLevel: 1);
    await manager.saveGlobalConfig(global);
    await manager.installMod(game.id);
    expect(
      await File(p.join(gameDir.path, 'dlssg_sm86.ini')).readAsString(),
      contains('MaxGeneratedFrames=2'),
    );
    expect(manager.view(game).config.kind, ConfigStateKind.global);

    final custom = testProfile('Game', maxGeneratedFrames: 1, loggingLevel: 3);
    await manager.saveGameConfig(game.id, custom);
    await manager.saveGlobalConfig(
      testProfile('全局配置', maxGeneratedFrames: 3, loggingLevel: 1),
    );
    expect(
      await File(p.join(gameDir.path, 'dlssg_sm86.ini')).readAsString(),
      contains('MaxGeneratedFrames=1'),
    );
  });

  test('拒绝覆盖新代理时保留已经安装的旧代理', () async {
    final root = await Directory.systemTemp.createTemp('dlssg-switch-proxy-');
    addTearDown(() => root.delete(recursive: true));
    final manager = await ModManager.open(dataDirectory: root);
    final cache = Directory(p.join(root.path, 'release', 'dlssg_for_sm86'));
    await cache.create(recursive: true);
    for (final proxy in proxies) {
      await File(p.join(cache.path, proxy)).writeAsString('mod-$proxy');
    }
    await File(p.join(cache.path, 'dlssg_sm86.ini')).writeAsString(releaseIni);
    manager.db.installedVersion = 'test';
    final gameDir = Directory(p.join(root.path, 'game'));
    await gameDir.create();
    final exe = File(p.join(gameDir.path, 'game.exe'));
    await exe.writeAsString('exe');
    await File(p.join(gameDir.path, defaultProxy)).writeAsString('original');
    await File(p.join(gameDir.path, 'winmm.dll')).writeAsString('foreign');
    final game = await manager.addManualGame('Game', exe.path);
    await manager.installMod(game.id, confirmOverwrite: true);

    await expectLater(
      manager.installMod(game.id, proxy: 'winmm.dll'),
      throwsStateError,
    );

    expect(
      await File(p.join(gameDir.path, defaultProxy)).readAsString(),
      'mod-version.dll',
    );
    expect(
      manager.db.games.firstWhere((x) => x.id == game.id).install?.proxy,
      defaultProxy,
    );
  });

  test('Steam 扫描会移除已卸载游戏的过期条目', () async {
    final root = await Directory.systemTemp.createTemp('dlssg-steam-remove-');
    addTearDown(() => root.delete(recursive: true));
    final manager = await ModManager.open(
      dataDirectory: root,
      scanner: SteamScanner(steamPath: () => root.path),
    );
    manager.db.games.add(
      GameEntry(
        id: '987654321',
        name: 'Removed game',
        source: GameSource.steam(987654321, root.path),
      ),
    );

    await manager.scanSteam();

    expect(manager.db.games.where((game) => game.id == '987654321'), isEmpty);
  });

  test('移除游戏只删除管理列表记录', () async {
    final root = await Directory.systemTemp.createTemp('dlssg-remove-game-');
    addTearDown(() => root.delete(recursive: true));
    final manager = await ModManager.open(dataDirectory: root);
    final directory = Directory(p.join(root.path, 'game'));
    await directory.create();
    final executable = File(p.join(directory.path, 'game.exe'));
    await executable.writeAsString('exe');
    final game = await manager.addManualGame('Game', executable.path);

    await manager.removeGame(game.id);

    expect(manager.db.games.where((entry) => entry.id == game.id), isEmpty);
    expect(await executable.exists(), isTrue);
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
