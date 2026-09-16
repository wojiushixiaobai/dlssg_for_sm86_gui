import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
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

Uint8List _steamAppInfoLaunchFixture({
  String windowsExecutable =
      r'Spacewar\Binaries\Win64\Spacewar-Win64-Shipping.exe',
}) {
  // appinfo.vdf v41 uses a shared string table for every binary VDF key.
  final keys = <String>[
    'config',
    'launch',
    '0',
    'executable',
    'type',
    'oslist',
    '1',
  ];
  final keyIndexes = {
    for (var index = 0; index < keys.length; index++) keys[index]: index,
  };
  final vdf = BytesBuilder();
  void addUint32(int value) {
    vdf.add([
      value & 0xff,
      (value >> 8) & 0xff,
      (value >> 16) & 0xff,
      (value >> 24) & 0xff,
    ]);
  }

  void addKey(String key) => addUint32(keyIndexes[key]!);
  void addString(String key, String value) {
    vdf.addByte(0x01);
    addKey(key);
    vdf.add(utf8.encode(value));
    vdf.addByte(0);
  }

  void begin(String key) {
    vdf.addByte(0x00);
    addKey(key);
  }

  begin('config');
  begin('launch');
  begin('0');
  addString('executable', windowsExecutable);
  addString('type', 'default');
  begin('config');
  addString('oslist', 'windows');
  vdf.addByte(0x08);
  vdf.addByte(0x08);
  begin('1');
  addString('executable', 'bin/LinuxGame');
  begin('config');
  addString('oslist', 'linux');
  vdf.addByte(0x08);
  vdf.addByte(0x08);
  vdf.addByte(0x08);
  vdf.addByte(0x08);
  vdf.addByte(0x08);

  final payload = vdf.toBytes();
  final entrySize = 60 + payload.length;
  final stringTableOffset = 16 + 8 + entrySize + 4;
  final result = BytesBuilder();
  void writeUint32(int value) {
    result.add([
      value & 0xff,
      (value >> 8) & 0xff,
      (value >> 16) & 0xff,
      (value >> 24) & 0xff,
    ]);
  }

  void writeInt64(int value) {
    for (var shift = 0; shift < 64; shift += 8) {
      result.addByte((value >> shift) & 0xff);
    }
  }

  writeUint32(0x07564429);
  writeUint32(1);
  writeInt64(stringTableOffset);
  writeUint32(480);
  writeUint32(entrySize);
  result.add(List<int>.filled(60, 0));
  result.add(payload);
  writeUint32(0);
  writeUint32(keys.length);
  for (final key in keys) {
    result.add(utf8.encode(key));
    result.addByte(0);
  }
  return result.toBytes();
}

class _CountingSteamScanner extends SteamScanner {
  _CountingSteamScanner(this.snapshot) : super(steamPath: () => null);

  Map<String, int> snapshot;
  var scanCount = 0;

  @override
  Future<Map<String, int>> manifestModificationTimes() async => snapshot;

  @override
  Future<List<GameEntry>> scan({required List<GameEntry> existing}) async {
    scanCount++;
    return existing;
  }
}

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
    test('按 Steam appinfo 的 Windows 启动配置识别 EXE', () async {
      final root = await Directory.systemTemp.createTemp(
        'dlssg-steam-appinfo-',
      );
      addTearDown(() => root.delete(recursive: true));
      expect(
        SteamScanner.parseAppInfoLaunchExecutables(
          _steamAppInfoLaunchFixture(),
          480,
        ),
        [r'Spacewar\Binaries\Win64\Spacewar-Win64-Shipping.exe'],
      );
      expect(
        SteamScanner.isUnrealEngineLaunchExecutable(
          r'Spacewar\Binaries\Win64\Spacewar-Win64-Shipping.exe',
        ),
        isTrue,
      );
      expect(
        SteamScanner.isUnrealEngineLaunchExecutable(
          r'Engine\Binaries\Win64\UnrealEditor.exe',
        ),
        isFalse,
      );

      final manifest = File(
        p.join(root.path, 'steamapps', 'appmanifest_480.acf'),
      );
      await manifest.parent.create(recursive: true);
      await manifest.writeAsString(
        '"AppState" { "appid" "480" "name" "Spacewar" "installdir" "spacewar" }',
      );
      final configuredExe = File(
        p.join(
          root.path,
          'steamapps',
          'common',
          'spacewar',
          'Spacewar',
          'Binaries',
          'Win64',
          'Spacewar-Win64-Shipping.exe',
        ),
      );
      await configuredExe.parent.create(recursive: true);
      await configuredExe.writeAsString('exe');
      await File(
        p.join(root.path, 'steamapps', 'common', 'spacewar', 'spacewar.exe'),
      ).writeAsString('heuristic fallback');
      final appInfo = File(p.join(root.path, 'appcache', 'appinfo.vdf'));
      await appInfo.parent.create(recursive: true);
      await appInfo.writeAsBytes(_steamAppInfoLaunchFixture());

      final games = await SteamScanner(steamPath: () => root.path)
          .scan(existing: const []);

      final spacewar = games.singleWhere((game) => game.source.appId == 480);
      expect(spacewar.exePath, configuredExe.path);
    });
    test('识别 Engine/Binaries/Win64* 中非标准命名的虚幻游戏 EXE', () async {
      final root = await Directory.systemTemp.createTemp(
        'dlssg-steam-unreal-engine-bin-',
      );
      addTearDown(() => root.delete(recursive: true));
      final manifest = File(
        p.join(root.path, 'steamapps', 'appmanifest_480.acf'),
      );
      await manifest.parent.create(recursive: true);
      await manifest.writeAsString(
        '"AppState" { "appid" "480" "name" "Yysls" "installdir" "yysls" }',
      );
      final gameDir = Directory(
        p.join(root.path, 'steamapps', 'common', 'yysls'),
      );
      await gameDir.create(recursive: true);
      final launcher = File(p.join(gameDir.path, 'launcher.exe'));
      await launcher.writeAsString('launcher');
      final gameExe = File(
        p.join(
          gameDir.path,
          'yysls_medium',
          'Engine',
          'Binaries',
          'Win64rh',
          'yysls.exe',
        ),
      );
      await gameExe.parent.create(recursive: true);
      await gameExe.writeAsString('game');
      await Directory(p.join(gameDir.path, 'yysls_medium', 'Engine', 'Content'))
          .create();
      final crashReporter = File(
        p.join(gameExe.parent.path, 'UniCrashReporter.exe'),
      );
      await crashReporter.writeAsString('helper');
      final patchCopy = File(
        p.join(
          gameDir.path,
          'yysls_medium',
          'LocalData',
          'Patch',
          'BinPatch',
          'Engine',
          'Binaries',
          'Win64rh',
          'yysls.exe',
        ),
      );
      await patchCopy.parent.create(recursive: true);
      await patchCopy.writeAsString('patch copy');
      final appInfo = File(p.join(root.path, 'appcache', 'appinfo.vdf'));
      await appInfo.parent.create(recursive: true);
      await appInfo.writeAsBytes(
        _steamAppInfoLaunchFixture(windowsExecutable: r'launcher.exe'),
      );

      final games = await SteamScanner(steamPath: () => root.path)
          .scan(existing: const []);

      final yysls = games.singleWhere((game) => game.source.appId == 480);
      expect(
        SteamScanner.isUnrealEngineLaunchExecutable(
          r'yysls_medium\Engine\Binaries\Win64rh\yysls.exe',
        ),
        isTrue,
      );
      expect(yysls.exePath, gameExe.path);
      expect(yysls.exePath, isNot(launcher.path));
      expect(yysls.exePath, isNot(patchCopy.path));
    });
    test('只在识别到 UE 目录组合后扫描 Engine/Binaries/Win64*', () async {
      final root = await Directory.systemTemp.createTemp(
        'dlssg-steam-non-unreal-engine-bin-',
      );
      addTearDown(() => root.delete(recursive: true));
      final manifest = File(
        p.join(root.path, 'steamapps', 'appmanifest_480.acf'),
      );
      await manifest.parent.create(recursive: true);
      await manifest.writeAsString(
        '"AppState" { "appid" "480" "name" "Other Game" "installdir" "other-game" }',
      );
      final gameDir = Directory(
        p.join(root.path, 'steamapps', 'common', 'other-game'),
      );
      await gameDir.create(recursive: true);
      final launcher = File(p.join(gameDir.path, 'launcher.exe'));
      await launcher.writeAsString('launcher');
      final lookalike = File(
        p.join(gameDir.path, 'Engine', 'Binaries', 'Win64', 'other-game.exe'),
      );
      await lookalike.parent.create(recursive: true);
      await lookalike.writeAsString('not a UE installation');
      final appInfo = File(p.join(root.path, 'appcache', 'appinfo.vdf'));
      await appInfo.parent.create(recursive: true);
      await appInfo.writeAsBytes(
        _steamAppInfoLaunchFixture(windowsExecutable: r'launcher.exe'),
      );

      final games = await SteamScanner(steamPath: () => root.path)
          .scan(existing: const []);

      expect(
        games.singleWhere((game) => game.source.appId == 480).exePath,
        launcher.path,
      );
    });
    test('忽略剑星 Engine 目录中的 Unreal CEF 子进程', () async {
      final root = await Directory.systemTemp.createTemp(
        'dlssg-steam-stellar-blade-',
      );
      addTearDown(() => root.delete(recursive: true));
      final manifest = File(
        p.join(root.path, 'steamapps', 'appmanifest_3489700.acf'),
      );
      await manifest.parent.create(recursive: true);
      await manifest.writeAsString(
        '"AppState" { "appid" "3489700" "name" "Stellar Blade" "installdir" "StellarBlade" }',
      );
      final gameDir = Directory(
        p.join(root.path, 'steamapps', 'common', 'StellarBlade'),
      );
      await gameDir.create(recursive: true);
      final launcher = File(p.join(gameDir.path, 'SB.exe'));
      await launcher.writeAsString('launcher');
      final cefProcess = File(
        p.join(
          gameDir.path,
          'Engine',
          'Binaries',
          'Win64',
          'UnrealCEFSubProcess.exe',
        ),
      );
      await cefProcess.parent.create(recursive: true);
      await cefProcess.writeAsString('browser helper');
      final shippingExe = File(
        p.join(
          gameDir.path,
          'SB',
          'Binaries',
          'Win64',
          'SB-Win64-Shipping.exe',
        ),
      );
      await shippingExe.parent.create(recursive: true);
      await shippingExe.writeAsString('game');
      final appInfo = File(p.join(root.path, 'appcache', 'appinfo.vdf'));
      await appInfo.parent.create(recursive: true);
      await appInfo.writeAsBytes(
        _steamAppInfoLaunchFixture(windowsExecutable: r'SB.exe'),
      );

      final games = await SteamScanner(steamPath: () => root.path)
          .scan(existing: const []);

      final stellarBlade = games.singleWhere(
        (game) => game.source.appId == 3489700,
      );
      expect(stellarBlade.exePath, shippingExe.path);
      expect(stellarBlade.exePath, isNot(cefProcess.path));
    });
    test('优先识别虚幻引擎游戏 EXE，而非 Steam 配置的启动器', () async {
      final root = await Directory.systemTemp.createTemp(
        'dlssg-steam-unreal-exe-',
      );
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
      final launcher = File(p.join(gameDir.path, 'SpacewarLauncher.exe'));
      await launcher.writeAsString('launcher');
      final unrealExe = File(
        p.join(
          gameDir.path,
          'Spacewar',
          'Binaries',
          'Win64',
          'Spacewar-Win64-Shipping.exe',
        ),
      );
      await unrealExe.parent.create(recursive: true);
      await unrealExe.writeAsString('game');
      final appInfo = File(p.join(root.path, 'appcache', 'appinfo.vdf'));
      await appInfo.parent.create(recursive: true);
      await appInfo.writeAsBytes(
        _steamAppInfoLaunchFixture(windowsExecutable: r'SpacewarLauncher.exe'),
      );

      final games = await SteamScanner(steamPath: () => root.path)
          .scan(existing: const []);

      final spacewar = games.singleWhere((game) => game.source.appId == 480);
      expect(spacewar.exePath, unrealExe.path);
      expect(spacewar.exePath, isNot(launcher.path));
    });
    test('忽略 Steam 安装目录自带的应用库', () async {
      final root = await Directory.systemTemp.createTemp('dlssg-steam-root-');
      addTearDown(() => root.delete(recursive: true));
      final manifest = File(
        p.join(root.path, 'steamapps', 'appmanifest_228980.acf'),
      );
      await manifest.parent.create(recursive: true);
      await manifest.writeAsString(
        '"AppState" { "appid" "228980" "name" "Steamworks Common Redistributables" "installdir" "_CommonRedist" }',
      );

      final games = await SteamScanner(steamPath: () => root.path)
          .scan(existing: const []);

      expect(games.where((game) => game.source.appId == 228980), isEmpty);
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
    test('Steam 清单快照会记录 libraryfolders 和 appmanifest 的修改时间', () async {
      final root = await Directory.systemTemp.createTemp('dlssg-steam-stamp-');
      addTearDown(() => root.delete(recursive: true));
      final folders = File(
        p.join(root.path, 'steamapps', 'libraryfolders.vdf'),
      );
      final manifest = File(
        p.join(root.path, 'steamapps', 'appmanifest_480.acf'),
      );
      await folders.parent.create(recursive: true);
      await folders.writeAsString('"libraryfolders" {}');
      await manifest.writeAsString('"AppState" { "appid" "480" }');
      final scanner = SteamScanner(steamPath: () => root.path);

      final before = await scanner.manifestModificationTimes();
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await manifest.writeAsString(
        '"AppState" { "appid" "480" "StateFlags" "4" }',
      );
      final after = await scanner.manifestModificationTimes();

      expect(before[p.normalize(folders.path)], isNotNull);
      expect(
        after[p.normalize(manifest.path)],
        isNot(before[p.normalize(manifest.path)]),
      );
    });
    test('logo 索引复用有效本地路径且不保存图片副本', () async {
      final root = await Directory.systemTemp.createTemp(
        'dlssg-artwork-index-',
      );
      addTearDown(() => root.delete(recursive: true));
      final logo = File(p.join(root.path, 'steam-header.jpg'));
      final index = File(p.join(root.path, 'artwork-sources.json'));
      await logo.writeAsBytes([1, 2, 3]);
      await index.writeAsString(jsonEncode({'480': logo.path}));

      final source = await SteamArtworkCache(index).load(480);

      expect(source?.local, isTrue);
      expect(source?.value, logo.path);
      expect(
        await root
            .list()
            .where(
              (item) =>
                  item is File &&
                  item.path != logo.path &&
                  item.path != index.path,
            )
            .isEmpty,
        isTrue,
      );
    });
    test('网络 logo 索引会优先切换为 Steam 本地缓存', () async {
      final root = await Directory.systemTemp.createTemp(
        'dlssg-artwork-local-first-',
      );
      addTearDown(() => root.delete(recursive: true));
      final logo = File(p.join(root.path, 'library_600x900.jpg'));
      final index = File(p.join(root.path, 'artwork-sources.json'));
      await logo.writeAsBytes([1, 2, 3]);
      await index.writeAsString(
        jsonEncode({'480': 'https://cdn.example.invalid/480/header.jpg'}),
      );
      final cache = SteamArtworkCache(
        index,
        findLocalPaths: (_, _) => [logo.path],
      );

      final source = await cache.load(480);

      expect(source?.local, isTrue);
      expect(source?.value, logo.path);
      expect(jsonDecode(await index.readAsString()), {'480': logo.path});
    });
    test('Steam librarycache 识别语言和库封面变体', () async {
      final root = await Directory.systemTemp.createTemp(
        'dlssg-artwork-variants-',
      );
      addTearDown(() => root.delete(recursive: true));
      final cache = Directory(
        p.join(root.path, 'appcache', 'librarycache', '480'),
      );
      await cache.create(recursive: true);
      final localizedHeader = File(
        p.join(cache.path, 'library_header_schinese.jpg'),
      );
      final header = File(p.join(cache.path, 'header_tchinese.png'));
      await localizedHeader.writeAsBytes([1]);
      await header.writeAsBytes([2]);

      final paths = findLocalArtworkPaths(
        480,
        SteamArtworkKind.card,
        steamPaths: [root.path],
      );

      expect(paths, containsAll([localizedHeader.path, header.path]));
      expect(paths.first, localizedHeader.path);
    });
    test('主页和游戏设置优先使用高分辨率 Steam 横幅', () async {
      final root = await Directory.systemTemp.createTemp(
        'dlssg-artwork-kinds-',
      );
      addTearDown(() => root.delete(recursive: true));
      final cache = Directory(
        p.join(root.path, 'appcache', 'librarycache', '480'),
      );
      await cache.create(recursive: true);
      final card = File(p.join(cache.path, 'library_header_schinese.jpg'));
      final icon = File(p.join(cache.path, 'header_schinese.jpg'));
      final lowResolutionIcon = File(
        p.join(cache.path, '7e6eb68967f8d7c39b81ff9525925d6d1f212598.jpg'),
      );
      await card.writeAsBytes([1]);
      await icon.writeAsBytes([2]);
      await lowResolutionIcon.writeAsBytes([3]);

      final backgrounds = findLocalArtworkPaths(
        480,
        SteamArtworkKind.card,
        steamPaths: [root.path],
      );
      final icons = findLocalArtworkPaths(
        480,
        SteamArtworkKind.icon,
        steamPaths: [root.path],
      );

      expect(backgrounds.first, card.path);
      expect(icons.first, card.path);
      expect(icons, isNot(contains(lowResolutionIcon.path)));
    });
    test('游戏设置不会复用缓存的 32px Steam 哈希图标', () async {
      final root = await Directory.systemTemp.createTemp(
        'dlssg-artwork-low-resolution-cache-',
      );
      addTearDown(() => root.delete(recursive: true));
      final lowResolutionIcon = File(
        p.join(root.path, '7e6eb68967f8d7c39b81ff9525925d6d1f212598.jpg'),
      );
      final header = File(p.join(root.path, 'header.jpg'));
      final index = File(p.join(root.path, 'artwork-sources.json'));
      await lowResolutionIcon.writeAsBytes([1]);
      await header.writeAsBytes([2]);
      await index.writeAsString(jsonEncode({'480': lowResolutionIcon.path}));
      final cache = SteamArtworkCache(
        index,
        findLocalPaths: (_, _) => [header.path],
      );

      final source = await cache.load(480, kind: SteamArtworkKind.icon);

      expect(source?.value, header.path);
      expect(jsonDecode(await index.readAsString()), {'480': header.path});
    });
    test('Steam librarycache 忽略非封面辅助图片', () async {
      final root = await Directory.systemTemp.createTemp(
        'dlssg-artwork-filter-',
      );
      addTearDown(() => root.delete(recursive: true));
      final cache = Directory(
        p.join(root.path, 'appcache', 'librarycache', '480'),
      );
      await cache.create(recursive: true);
      final unrelated = File(p.join(cache.path, 'broadcast_background.jpg'));
      final header = File(p.join(cache.path, 'header.jpg'));
      await unrelated.writeAsBytes([1]);
      await header.writeAsBytes([2]);

      final paths = findLocalArtworkPaths(
        480,
        SteamArtworkKind.card,
        steamPaths: [root.path],
      );

      expect(paths, contains(header.path));
      expect(paths, isNot(contains(unrelated.path)));
    });
    test('并发解析多个 logo 时完整保存来源索引', () async {
      final root = await Directory.systemTemp.createTemp(
        'dlssg-artwork-parallel-',
      );
      addTearDown(() => root.delete(recursive: true));
      final index = File(p.join(root.path, 'artwork-sources.json'));
      final cache = SteamArtworkCache(index);

      await Future.wait([
        cache.nextNetworkSource(1, 'https://invalid.example/one'),
        cache.nextNetworkSource(2, 'https://invalid.example/two'),
        cache.nextNetworkSource(3, 'https://invalid.example/three'),
      ]);

      final saved = jsonDecode(await index.readAsString()) as Map;
      expect(saved.keys, containsAll(['1', '2', '3']));
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
    test('大文件复制和哈希保持内容完整', () async {
      final root = await Directory.systemTemp.createTemp('dlssg-copy-');
      addTearDown(() => root.delete(recursive: true));
      final source = File(p.join(root.path, 'source.bin'));
      final target = File(p.join(root.path, 'nested', 'target.bin'));
      final bytes = List<int>.generate(
        2 * 1024 * 1024 + 17,
        (index) => index % 251,
        growable: false,
      );
      await source.writeAsBytes(bytes);

      await copyAtomic(source, target);

      expect(await target.readAsBytes(), bytes);
      expect(await sha256File(target), sha256.convert(bytes).toString());
      expect(sha256FileSync(target), sha256.convert(bytes).toString());
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
    oldGame.selectedProxy = 'winmm.dll';
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
    await File(p.join(gameDir.path, 'dbghelp.dll'))
        .writeAsString('game-debug-helper');
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

  test('已有 INI 的未知代理 DLL 会视为已部署且不备份', () async {
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

  test('已有原始 DLL 备份时不会被后续安装覆盖', () async {
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
    final backup = File(
      manager.db.games.firstWhere((x) => x.id == game.id).backups.single.file,
    );
    expect(await backup.readAsString(), 'original-v1');
    expect(await original.readAsString(), 'mod-version.dll');
    await manager.uninstallMod(game.id);
    expect(await original.readAsString(), 'original-v1');
    await original.writeAsString('original-v2');
    await manager.installMod(game.id, confirmOverwrite: true);
    expect(await backup.readAsString(), 'original-v1');
    expect(
      manager.db.games.firstWhere((x) => x.id == game.id).backups,
      isEmpty,
    );
    await manager.uninstallMod(game.id);
    expect(await original.readAsString(), 'original-v1');
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

  test('Steam 清单未变化时重启不会重复扫描', () async {
    final root = await Directory.systemTemp.createTemp('dlssg-steam-skip-');
    addTearDown(() => root.delete(recursive: true));
    final firstScanner = _CountingSteamScanner({'manifest': 1});
    await ModManager.open(dataDirectory: root, scanner: firstScanner);
    expect(firstScanner.scanCount, 1);

    final unchangedScanner = _CountingSteamScanner({'manifest': 1});
    await ModManager.open(dataDirectory: root, scanner: unchangedScanner);
    expect(unchangedScanner.scanCount, 0);

    final changedScanner = _CountingSteamScanner({'manifest': 2});
    await ModManager.open(dataDirectory: root, scanner: changedScanner);
    expect(changedScanner.scanCount, 1);
  });

  test('升级 EXE 识别规则后会重新扫描未变化的 Steam 清单', () async {
    final root = await Directory.systemTemp.createTemp('dlssg-steam-upgrade-');
    addTearDown(() => root.delete(recursive: true));
    final firstScanner = _CountingSteamScanner({'manifest': 1});
    await ModManager.open(dataDirectory: root, scanner: firstScanner);

    final state = File(p.join(root.path, 'state.json'));
    final saved =
        jsonDecode(await state.readAsString()) as Map<String, dynamic>;
    saved['steam_executable_detection_version'] = 0;
    await state.writeAsString(jsonEncode(saved));

    final upgradedScanner = _CountingSteamScanner({'manifest': 1});
    await ModManager.open(dataDirectory: root, scanner: upgradedScanner);

    expect(upgradedScanner.scanCount, 1);
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
