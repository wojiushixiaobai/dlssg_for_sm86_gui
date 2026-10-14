import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dlssg_for_sm86_manager/manager.dart';
import 'package:dlssg_for_sm86_manager/models.dart';
import 'package:dlssg_for_sm86_manager/steam.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

const ini040 = '''[General]
Enabled=1
[FrameGeneration]
Engine=DLSS
MaxGeneratedFrames=3
[DLSSG]
Optimized=2
Preset=Auto
[XeSSFG]
FlowResolution=Middle
UseHudless=1
[Logging]
Level=1
Directory=dlssg_sm86\\logs
[Runtime]
Mode=Bundled
[SuperResolution]
Mode=Off
''';

Map<String, String> releaseFiles({String prefix = '040'}) => {
  for (final proxy in proxies)
    proxy == defaultProxy ? proxy : 'alternatives/$proxy': '$prefix-$proxy',
  for (final name in runtimeDriverFiles) name: '$prefix-$name',
  'dlssg_sm86/backend/additional.dat': '$prefix-extra runtime resource',
  'dlssg_sm86.ini': ini040,
  'MANUAL.html': '<html>Install</html>',
};

List<int> zipBytes(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return ZipEncoder().encodeBytes(archive);
}

class _EmptyScanner extends SteamScanner {
  @override
  Future<List<GameEntry>> scan({required List<GameEntry> existing}) async =>
      existing;
  @override
  Future<Map<String, int>> manifestModificationTimes() async => {};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('只有明确低于 0.4.0 的已安装版本在跨越版本边界时需要重装', () {
    const cases = <(String?, String?, bool)>[
      ('0.3.5', '0.4.0', true),
      ('0.3.99', '0.5.0', true),
      ('v0.3.5', 'v1.0.0', true),
      ('0.4', '0.4.1', false),
      ('0.4.0', '0.4.1', false),
      ('0.4.1', '0.5.0', false),
      ('0.5.0', '0.10.0', false),
      ('0.10.0', '1.0.0', false),
      ('1.0.0', '2.0.0', false),
      ('v0.4.0', 'v0.5.0', false),
      (' 0.4.0 ', '0.5.0', false),
      ('0.4.0-beta.1', '0.4.0', false),
      ('0.3.5', '0.3.6', false),
      ('未知版本', '0.4.0', false),
      ('invalid', '0.5.0', false),
      (null, '0.4.0', false),
      ('0.3.5', null, false),
    ];
    for (final (installed, target, expected) in cases) {
      expect(
        requiresCleanInstall(installed, target),
        expected,
        reason: '$installed → $target',
      );
    }
  });

  late Directory root;
  late Directory drivers;
  final clients = <Client>[];
  setUp(() async {
    root = await Directory.systemTemp.createTemp('dlssg-040-');
    drivers = await Directory(p.join(root.path, 'drivers')).create();
  });
  tearDown(() async {
    for (final client in clients) {
      client.close();
    }
    clients.clear();
    await root.delete(recursive: true);
  });

  Future<ModManager> open({Client? client}) async {
    client ??= MockClient(
      (request) async => throw StateError('离线启动请求了网络：${request.url}'),
    );
    clients.add(client);
    return ModManager.open(
      dataDirectory: Directory(p.join(root.path, 'data')),
      driversDirectory: drivers,
      scanner: _EmptyScanner(),
      client: client,
    );
  }

  Future<File> bundle([Map<String, String>? files]) =>
      File(p.join(drivers.path, 'dlssg-release-0.4.0-x64.zip'))
          .writeAsBytes(zipBytes(files ?? releaseFiles()));

  Future<GameEntry> game(ModManager manager, [String name = 'game']) async {
    final exe = File(p.join(root.path, name, 'game.exe'));
    await exe.parent.create(recursive: true);
    await exe.writeAsString('exe');
    return manager.addManualGame(name, exe.path);
  }

  test('离线 ZIP 原样保留，首次启动解包，重启复用缓存，安装完整目录及单个代理', () async {
    final archive = await bundle();
    final manager = await open();
    expect(manager.info.installedVersion, '0.4.0');
    expect(manager.hasModPackage, isTrue);
    expect(await archive.readAsBytes(), zipBytes(releaseFiles()));
    expect(await drivers.list().length, 1);
    expect((await manager.loadGlobalConfig()).value('DLSSG', 'Optimized'), '2');
    final g = await game(manager);
    await manager.installMod(g.id, proxy: 'winmm.dll');
    final dir = File(g.exePath!).parent;
    for (final name in runtimeDriverFiles) {
      expect(
        await File(p.join(dir.path, name)).readAsString(),
        releaseFiles()[name],
      );
    }
    expect(await File(p.join(dir.path, 'version.dll')).exists(), isFalse);
    expect(await File(p.join(dir.path, 'MANUAL.html')).exists(), isFalse);
    expect(g.install!.runtimeFiles.length, runtimeDriverFiles.length + 1);
    final cached = File(
      p.join(manager.releaseRoot.path, 'dlssg_for_sm86', 'MANUAL.html'),
    );
    await cached.writeAsString('cached marker');
    final reopened = await open();
    expect(await cached.readAsString(), 'cached marker');
    expect(
      (await reopened.view(reopened.db.games.single)).mod.version,
      '0.4.0',
    );
    await reopened.uninstallMod(g.id);
    expect(await Directory(p.join(dir.path, 'dlssg_sm86')).exists(), isFalse);
    expect(await File(p.join(dir.path, 'winmm.dll')).exists(), isFalse);
    expect(await File(p.join(dir.path, 'dlssg_sm86.ini')).exists(), isFalse);
  });

  test('卸载恢复原始代理并保留用户修改、日志和额外文件', () async {
    await bundle();
    final manager = await open();
    final g = await game(manager);
    final dir = File(g.exePath!).parent;
    final proxy = await File(p.join(dir.path, defaultProxy))
        .writeAsString('original game DLL');
    await manager.installMod(g.id, confirmOverwrite: true);
    final modified = await File(p.join(dir.path, runtimeDriverFiles.last))
        .writeAsString('user replacement');
    final log = File(p.join(dir.path, 'dlssg_sm86/logs/backend.jsonl'));
    await log.parent.create(recursive: true);
    await log.writeAsString('log');
    await manager.uninstallMod(g.id);
    expect(await proxy.readAsString(), 'original game DLL');
    expect(await modified.readAsString(), 'user replacement');
    expect(await log.readAsString(), 'log');
    expect(
      await File(p.join(dir.path, runtimeDriverFiles.first)).exists(),
      isFalse,
    );
  });

  for (final missing in runtimeDriverFiles) {
    test('缺失运行文件时拒绝离线包：$missing', () async {
      await bundle(releaseFiles()..remove(missing));
      await expectLater(open(), throwsStateError);
      expect(
        await File(p.join(root.path, 'data/global.ini')).exists(),
        isFalse,
      );
    });
  }

  for (final unsafe in [
    '../escape.dll',
    'dlssg_sm86/../../escape.dll',
    r'C:\escape.dll',
    'dlssg_sm86/file.dll:stream',
  ]) {
    test('ZIP 路径越界被拒绝：$unsafe', () async {
      await bundle(releaseFiles()..[unsafe] = 'unsafe');
      await expectLater(open(), throwsStateError);
      expect(await File(p.join(root.path, 'escape.dll')).exists(), isFalse);
    });
  }

  test('在线仅下载完整 Release 附件，校验失败保留旧包，重试后缓存复用', () async {
    var requests = 0;
    var broken = true;
    final manager = await open(
      client: MockClient((request) async {
        if (request.url.toString() == latestReleaseUrl) {
          return Response(
            jsonEncode({
              'tag_name': '0.4.0',
              'tarball_url': 'https://example.invalid/source.tar.gz',
              'assets': [
                {
                  'name': 'unrelated.zip',
                  'browser_download_url':
                      'https://example.invalid/unrelated.zip',
                },
                {
                  'name': 'dlssg-release-0.4.0-x64.zip',
                  'browser_download_url': 'https://example.invalid/full.zip',
                },
              ],
            }),
            200,
          );
        }
        expect(request.url.toString(), 'https://example.invalid/full.zip');
        requests++;
        return Response.bytes(
          zipBytes(
            broken
                ? (releaseFiles()..remove(runtimeDriverFiles.last))
                : releaseFiles(),
          ),
          200,
        );
      }),
    );
    await expectLater(manager.refreshModFromGithub(), throwsStateError);
    expect(manager.hasModPackage, isFalse);
    broken = false;
    final progress = <DownloadProgress>[];
    expect(
      await manager.refreshModFromGithub(onProgress: progress.add),
      '0.4.0',
    );
    expect(progress.last.phase, DownloadPhase.verifying);
    expect(await manager.refreshModFromGithub(), '0.4.0');
    expect(requests, 2);
  });

  test('0.4.0 没有完整附件时不接受源码 tarball', () async {
    final manager = await open(
      client: MockClient((request) async {
        expect(request.url.toString(), latestReleaseUrl);
        return Response(
          jsonEncode({
            'tag_name': '0.4.0',
            'tarball_url': 'https://example.invalid/source.tar.gz',
          }),
          200,
        );
      }),
    );
    await expectLater(manager.refreshModFromGithub(), throwsStateError);
  });

  test('CRC 不匹配时拒绝 ZIP，不激活损坏的运行包', () async {
    final bytes = zipBytes(releaseFiles());
    bytes[14] ^= 0xff; // First local file header CRC.
    for (var index = 0; index < bytes.length - 20; index++) {
      if (bytes[index] == 0x50 &&
          bytes[index + 1] == 0x4b &&
          bytes[index + 2] == 0x01 &&
          bytes[index + 3] == 0x02) {
        bytes[index + 16] ^= 0xff; // Matching central directory CRC.
        break;
      }
    }
    await File(p.join(drivers.path, 'dlssg-release-0.4.0-x64.zip'))
        .writeAsBytes(bytes);
    await expectLater(open(), throwsStateError);
    expect(await File(p.join(root.path, 'data/global.ini')).exists(), isFalse);
  });

  test('旧缓存由离线包适配，旧游戏必须卸载重装，配置使用新版默认值', () async {
    var manager = await open();
    final cache = Directory(p.join(manager.releaseRoot.path, 'dlssg_for_sm86'));
    await cache.create();
    await File(p.join(cache.path, defaultProxy)).writeAsString('old proxy');
    const oldIni =
        '[General]\nEnabled=1\n[FrameGeneration]\nOptimized=3\n[Compatibility]\nPreset=B\n';
    await File(p.join(cache.path, 'dlssg_sm86.ini')).writeAsString(oldIni);
    manager.db.installedVersion = '0.3.5';
    final g = await game(manager);
    await manager.installMod(g.id);
    await bundle();
    manager = await open();
    final dir = File(g.exePath!).parent;
    final target = File(p.join(dir.path, defaultProxy));
    await expectLater(manager.installMod(g.id), throwsStateError);
    expect(await target.readAsString(), 'old proxy');
    expect(
      await File(p.join(dir.path, 'dlssg_sm86.ini')).readAsString(),
      oldIni,
    );
    expect(
      await File(p.join(manager.root.path, 'global.ini.pre-0.4.0'))
          .readAsString(),
      oldIni,
    );
    final config = await manager.loadGlobalConfig();
    expect(config.value('DLSSG', 'Optimized'), '2');
    expect(config.value('Compatibility', 'Preset'), isNull);
    await manager.saveGlobalConfig(config.withValue('DLSSG', 'Optimized', '1'));
    expect(
      await File(p.join(dir.path, 'dlssg_sm86.ini')).readAsString(),
      oldIni,
    );
    await manager.uninstallMod(g.id);
    await manager.installMod(g.id);
    expect(await target.readAsString(), '040-version.dll');
    expect(
      (await manager.loadGameConfig(g.id)).value('DLSSG', 'Optimized'),
      '1',
    );
  });

  test('完整安装在保存状态失败时回滚 DLL、运行目录、INI 和安装记录', () async {
    await bundle();
    final manager = await open();
    final g = await game(manager);
    final dir = File(g.exePath!).parent;
    final target = await File(p.join(dir.path, defaultProxy))
        .writeAsString('original');
    final state = File(p.join(manager.root.path, 'state.json'));
    await state.delete();
    await Directory(state.path).create();
    await expectLater(
      manager.installMod(g.id, confirmOverwrite: true),
      throwsA(isA<FileSystemException>()),
    );
    expect(await target.readAsString(), 'original');
    expect(await Directory(p.join(dir.path, 'dlssg_sm86')).exists(), isFalse);
    expect(await File(p.join(dir.path, 'dlssg_sm86.ini')).exists(), isFalse);
    expect(g.install, isNull);
    expect(g.backups, isEmpty);
    await Directory(state.path).delete();
    await manager.installMod(g.id, confirmOverwrite: true);
    await manager.uninstallMod(g.id);
    expect(await target.readAsString(), 'original');
  });

  test('旧版安装记录在 INI 缺失时仍禁止覆盖升级', () async {
    await bundle();
    final manager = await open();
    final g = await game(manager);
    final target = await File(
      p.join(File(g.exePath!).parent.path, defaultProxy),
    ).writeAsString('legacy proxy');
    g.install = ManagedInstall(
      proxy: defaultProxy,
      dllSha256: await sha256File(target),
      version: '0.3.5',
    );
    await expectLater(manager.installMod(g.id), throwsStateError);
    expect(await target.readAsString(), 'legacy proxy');
    await manager.uninstallMod(g.id);
    await manager.installMod(g.id);
    expect(await target.readAsString(), '040-version.dll');
  });

  test('代理切换仅保留一个代理，0.4 及后续版本正常升级并保留配置', () async {
    await bundle();
    var nextVersion = '0.4.1';
    final manager = await open(
      client: MockClient((request) async {
        if (request.url.toString() == latestReleaseUrl) {
          return Response(
            jsonEncode({
              'tag_name': nextVersion,
              'assets': [
                {
                  'name': 'dlssg-release-$nextVersion-x64.zip',
                  'browser_download_url': 'https://example.invalid/041.zip',
                },
              ],
            }),
            200,
          );
        }
        return Response.bytes(zipBytes(releaseFiles(prefix: nextVersion)), 200);
      }),
    );
    final g = await game(manager);
    final dir = File(g.exePath!).parent;
    await manager.installMod(g.id);
    await manager.installMod(g.id, proxy: 'winmm.dll');
    expect(await File(p.join(dir.path, defaultProxy)).exists(), isFalse);
    final config = (await manager.loadGameConfig(g.id))
        .withValue('DLSSG', 'Preset', 'C');
    await manager.saveGameConfig(g.id, config);
    for (final version in ['0.4.1', '0.5.0', '0.10.0', '1.0.0']) {
      nextVersion = version;
      await manager.refreshModFromGithub();
      await manager.installMod(g.id);
      expect(g.install?.version, version);
      expect(
        await File(p.join(dir.path, 'winmm.dll')).readAsString(),
        '$version-winmm.dll',
      );
      expect(
        (await manager.loadGameConfig(g.id)).value('DLSSG', 'Preset'),
        'C',
      );
    }
    await manager.uninstallMod(g.id);
    expect(await Directory(p.join(dir.path, 'dlssg_sm86')).exists(), isFalse);
  });

  final realArchive = Platform.environment['DLSSG_RELEASE_ZIP'];
  test('真实 0.4.0 完整包：离线解包、安装、卸载冒烟验证', () async {
    await File(realArchive!)
        .copy(p.join(drivers.path, 'dlssg-release-0.4.0-x64.zip'));
    final manager = await open();
    final g = await game(manager);
    await manager.installMod(g.id);
    final dir = File(g.exePath!).parent;
    for (final name in runtimeDriverFiles) {
      expect(await File(p.join(dir.path, name)).length(), greaterThan(1000));
    }
    expect(
      (await manager.loadGameConfig(g.id)).value('SuperResolution', 'Mode'),
      'Off',
    );
    await manager.uninstallMod(g.id);
    expect(await Directory(p.join(dir.path, 'dlssg_sm86')).exists(), isFalse);
  }, skip: realArchive == null ? '设置 DLSSG_RELEASE_ZIP 可验证真实上游包' : false);
}
