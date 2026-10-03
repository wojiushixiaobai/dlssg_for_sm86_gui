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

class _EmptyScanner extends SteamScanner {
  @override
  Future<List<GameEntry>> scan({required List<GameEntry> existing}) async =>
      existing;

  @override
  Future<Map<String, int>> manifestModificationTimes() async => {};
}

List<int> _archive({String? omit}) {
  final archive = Archive();
  final files = {
    for (final proxy in proxies)
      proxy == defaultProxy ? proxy : 'alternatives/$proxy': 'new-$proxy',
    'dlssg_sm86.ini': '[General]\nEnabled=1\n',
  };
  for (final entry in files.entries) {
    if (entry.key == omit) continue;
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile('release/${entry.key}', bytes.length, bytes));
  }
  return GZipEncoder().encodeBytes(TarEncoder().encodeBytes(archive));
}

void main() {
  late Directory root;
  final clients = <Client>[];

  setUp(() async {
    root = await Directory.systemTemp.createTemp('dlssg-reliability-');
  });
  tearDown(() async {
    for (final client in clients) {
      client.close();
    }
    clients.clear();
    await root.delete(recursive: true);
  });

  Future<ModManager> openWithOldPackage(Client client) async {
    clients.add(client);
    final manager = await ModManager.open(
      dataDirectory: root,
      scanner: _EmptyScanner(),
      client: client,
    );
    final package = Directory(p.join(root.path, 'release', 'dlssg_for_sm86'));
    await package.create(recursive: true);
    await File(p.join(package.path, defaultProxy)).writeAsString('old-driver');
    await File(p.join(package.path, 'dlssg_sm86.ini'))
        .writeAsString('[General]\nEnabled=0\n');
    await File(p.join(root.path, 'global.ini'))
        .writeAsString('[General]\nEnabled=0\n');
    manager.db.installedVersion = 'old';
    await File(p.join(root.path, 'state.json'))
        .writeAsString(manager.db.toJsonText());
    return manager;
  }

  Client releaseClient(Future<Response> Function() download) =>
      MockClient((request) async {
        if (request.url.toString() == latestReleaseUrl) {
          return Response(
            jsonEncode({
              'tag_name': 'new',
              'tarball_url': 'https://example.invalid/release.tar.gz',
            }),
            200,
          );
        }
        return download();
      });

  for (final invalid in ['gzip', 'missing-dll', 'missing-ini']) {
    test('更新包校验失败保留旧包并允许重新下载：$invalid', () async {
      var requests = 0;
      final badBytes = switch (invalid) {
        'gzip' => [1, 2, 3],
        'missing-dll' => _archive(omit: 'alternatives/winmm.dll'),
        _ => _archive(omit: 'dlssg_sm86.ini'),
      };
      final manager = await openWithOldPackage(
        releaseClient(() async {
          requests++;
          return Response.bytes(requests == 1 ? badBytes : _archive(), 200);
        }),
      );
      final driver = File(
        p.join(root.path, 'release', 'dlssg_for_sm86', defaultProxy),
      );

      await expectLater(manager.refreshModFromGithub(), throwsA(anything));
      expect(manager.hasModPackage, isTrue);
      expect(manager.db.installedVersion, 'old');
      expect(await driver.readAsString(), 'old-driver');
      expect(
        Database.fromJsonText(
          await File(p.join(root.path, 'state.json')).readAsString(),
        ).installedVersion,
        'old',
      );
      expect(
        await File(p.join(root.path, 'release', 'new', modArchiveName))
            .exists(),
        isFalse,
      );

      expect(await manager.refreshModFromGithub(), 'new');
      expect(requests, 2);
      expect(await driver.readAsString(), 'new-version.dll');
      expect(
        await File(p.join(root.path, 'global.ini')).readAsString(),
        contains('Enabled=0'),
      );
      final leftovers = await Directory(p.join(root.path, 'release'))
          .list()
          .toList();
      expect(
        leftovers.where((file) => p.basename(file.path).startsWith('.')),
        isEmpty,
      );
    });
  }

  test('保存新版本状态失败会恢复旧目录和版本，已验证缓存仍可复用', () async {
    var requests = 0;
    final manager = await openWithOldPackage(
      releaseClient(() async {
        requests++;
        return Response.bytes(_archive(), 200);
      }),
    );
    final state = File(p.join(root.path, 'state.json'));
    await state.delete();
    await Directory(state.path).create();

    await expectLater(
      manager.refreshModFromGithub(),
      throwsA(isA<FileSystemException>()),
    );
    expect(manager.hasModPackage, isTrue);
    expect(manager.db.installedVersion, 'old');
    expect(
      await File(p.join(root.path, 'release', 'dlssg_for_sm86', defaultProxy))
          .readAsString(),
      'old-driver',
    );

    await Directory(state.path).delete();
    expect(await manager.refreshModFromGithub(), 'new');
    expect(requests, 1);
  });

  test('已记录的代理升级不重复备份驱动本身', () async {
    final manager = await openWithOldPackage(
      MockClient((_) async => Response('', 404)),
    );
    final exe = File(p.join(root.path, 'game', 'game.exe'));
    await exe.parent.create();
    await exe.writeAsString('exe');
    final target = File(p.join(exe.parent.path, defaultProxy));
    await target.writeAsString('original-game-dll');
    final game = await manager.addManualGame('Game', exe.path);
    await manager.installMod(game.id, confirmOverwrite: true);
    await File(p.join(root.path, 'release', 'dlssg_for_sm86', defaultProxy))
        .writeAsString('new-driver');

    await manager.installMod(game.id);
    expect(await target.readAsString(), 'new-driver');
    expect(game.backups, hasLength(1));
    await manager.uninstallMod(game.id);
    expect(await target.readAsString(), 'original-game-dll');
  });

  test('手动安装的未知版本 DLL 需确认并核对哈希后卸载', () async {
    final manager = await openWithOldPackage(
      MockClient((_) async => Response('', 404)),
    );
    final exe = File(p.join(root.path, 'game', 'game.exe'));
    await exe.parent.create();
    await exe.writeAsString('exe');
    final target = File(p.join(exe.parent.path, defaultProxy));
    await target.writeAsString('game-original');
    final ini = File(p.join(exe.parent.path, 'dlssg_sm86.ini'));
    await ini.writeAsString('[General]\nEnabled=1\n');
    final game = await manager.addManualGame('Game', exe.path);
    final status = (await manager.listGames()).single.mod;
    expect(status.kind, ModStateKind.applied);
    expect(status.version, '未知版本');
    expect(status.canUninstall, isTrue);
    await expectLater(manager.uninstallMod(game.id), throwsStateError);
    expect(await target.readAsString(), 'game-original');
    expect(await ini.exists(), isTrue);
    await manager.uninstallMod(
      game.id,
      proxy: defaultProxy,
      confirmUnrecognized: true,
      expectedSha256: status.unrecognizedProxyHashes[defaultProxy],
    );
    expect(await target.exists(), isFalse);
    expect(await ini.exists(), isFalse);
  });

  test('手动安装多个未知代理时只卸载明确选中的 DLL', () async {
    final manager = await openWithOldPackage(
      MockClient((_) async => Response('', 404)),
    );
    final exe = File(p.join(root.path, 'game', 'game.exe'));
    await exe.parent.create();
    await exe.writeAsString('exe');
    final gameDll = File(p.join(exe.parent.path, defaultProxy));
    final manualDll = File(p.join(exe.parent.path, 'winmm.dll'));
    await gameDll.writeAsString('game-original');
    await manualDll.writeAsString('manual-driver');
    final ini = File(p.join(exe.parent.path, 'dlssg_sm86.ini'));
    await ini.writeAsString('[General]\nEnabled=1\n');
    final game = await manager.addManualGame('Game', exe.path);
    final status = manager.view(game).mod;
    expect(
      status.unrecognizedProxyHashes.keys,
      containsAll([defaultProxy, 'winmm.dll']),
    );
    await expectLater(manager.installMod(game.id), throwsStateError);
    await expectLater(manager.uninstallMod(game.id), throwsStateError);
    await manager.uninstallMod(
      game.id,
      proxy: 'winmm.dll',
      confirmUnrecognized: true,
      expectedSha256: status.unrecognizedProxyHashes['winmm.dll'],
    );
    expect(await gameDll.readAsString(), 'game-original');
    expect(await manualDll.exists(), isFalse);
    expect(await ini.exists(), isFalse);
  });

  test('手动安装单个未知代理可直接更新对应文件', () async {
    final manager = await openWithOldPackage(
      MockClient((_) async => Response('', 404)),
    );
    final package = File(
      p.join(
        root.path,
        'release',
        'dlssg_for_sm86',
        'alternatives',
        'winmm.dll',
      ),
    );
    await package.parent.create(recursive: true);
    await package.writeAsString('new-winmm.dll');
    final exe = File(p.join(root.path, 'game', 'game.exe'));
    await exe.parent.create();
    await exe.writeAsString('exe');
    final manualDll = File(p.join(exe.parent.path, 'winmm.dll'));
    await manualDll.writeAsString('manual-driver');
    await File(p.join(exe.parent.path, 'dlssg_sm86.ini'))
        .writeAsString('[General]\nEnabled=1\n');
    final game = await manager.addManualGame('Game', exe.path);
    expect(manager.view(game).mod.proxy, 'winmm.dll');

    await manager.installMod(game.id);
    expect(await manualDll.readAsString(), 'new-winmm.dll');
    expect(await File(p.join(exe.parent.path, defaultProxy)).exists(), isFalse);
    expect(game.backups, isEmpty);
  });

  test('手动安装的 DLL 变更后拒绝按旧状态卸载', () async {
    final manager = await openWithOldPackage(
      MockClient((_) async => Response('', 404)),
    );
    final exe = File(p.join(root.path, 'game', 'game.exe'));
    await exe.parent.create();
    await exe.writeAsString('exe');
    final target = File(p.join(exe.parent.path, defaultProxy));
    await target.writeAsString('manual-driver');
    final ini = File(p.join(exe.parent.path, 'dlssg_sm86.ini'));
    await ini.writeAsString('[General]\nEnabled=1\n');
    final game = await manager.addManualGame('Game', exe.path);
    final oldHash = manager
        .view(game)
        .mod
        .unrecognizedProxyHashes[defaultProxy];
    await target.writeAsString('changed-driver');
    await expectLater(
      manager.uninstallMod(
        game.id,
        proxy: defaultProxy,
        confirmUnrecognized: true,
        expectedSha256: oldHash,
      ),
      throwsStateError,
    );
    expect(await target.readAsString(), 'changed-driver');
    expect(await ini.exists(), isTrue);
  });

  test('卸载重新验证文件，即使大小和时间不变也不会覆盖被替换的 DLL', () async {
    final manager = await openWithOldPackage(
      MockClient((_) async => Response('', 404)),
    );
    final exe = File(p.join(root.path, 'game', 'game.exe'));
    await exe.parent.create();
    await exe.writeAsString('exe');
    final target = File(p.join(exe.parent.path, defaultProxy));
    await target.writeAsString('original-game-dll');
    final game = await manager.addManualGame('Game', exe.path);
    await manager.installMod(game.id, confirmOverwrite: true);
    expect((await manager.listGames()).single.mod.kind, ModStateKind.applied);
    final modified = await target.lastModified();
    await target.writeAsString('other-data'); // same length as "old-driver"
    await target.setLastModified(modified);
    await expectLater(manager.uninstallMod(game.id), throwsStateError);
    expect(await target.readAsString(), 'other-data');
    expect(
      await File(p.join(exe.parent.path, 'dlssg_sm86.ini')).exists(),
      isTrue,
    );
    expect(game.install, isNotNull);
    expect(
      await File(game.backups.single.file).readAsString(),
      'original-game-dll',
    );
  });

  test('缺少 INI 的已知 DLL 重装时不把驱动自身备份为游戏原文件', () async {
    final manager = await openWithOldPackage(
      MockClient((_) async => Response('', 404)),
    );
    final exe = File(p.join(root.path, 'game', 'game.exe'));
    await exe.parent.create();
    await exe.writeAsString('exe');
    await File(p.join(exe.parent.path, defaultProxy))
        .writeAsString('old-driver');
    final game = await manager.addManualGame('Game', exe.path);
    expect(
      (await manager.listGames()).single.mod.kind,
      ModStateKind.notApplied,
    );
    await manager.installMod(game.id);
    expect(game.backups, isEmpty);
    expect((await manager.listGames()).single.mod.kind, ModStateKind.applied);
  });

  test('失效 Windows 路径不再当作网络地址，回退结果同步内存和磁盘', () async {
    final sourceFile = File(p.join(root.path, 'artwork.json'));
    await sourceFile.writeAsString(
      jsonEncode({'42': r'C:\missing\header.jpg'}),
    );
    final cache = SteamArtworkCache(sourceFile, findLocalPaths: (_) => []);
    final first = await cache.load(42);
    expect(first!.local, isFalse);
    expect(first.value, steamArtworkUrls(42).first);

    final next = await cache.nextNetworkSource(42, first.value);
    expect(next!.value, steamArtworkUrls(42)[1]);
    expect((await cache.load(42))!.value, next.value);
    final reopened = SteamArtworkCache(sourceFile, findLocalPaths: (_) => []);
    expect((await reopened.load(42))!.value, next.value);
  });

  test('所有封面源失败后可以重新加载', () async {
    final cache = SteamArtworkCache(
      File(p.join(root.path, 'artwork.json')),
      findLocalPaths: (_) => [],
    );
    var source = await cache.load(42);
    for (final url in steamArtworkUrls(42)) {
      expect(source!.value, url);
      source = await cache.nextNetworkSource(42, url);
    }
    expect(source, isNull);
    expect((await cache.load(42))!.value, steamArtworkUrls(42).first);
  });
}
