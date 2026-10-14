import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dlssg_for_sm86_manager/driver_fingerprints.dart';
import 'package:dlssg_for_sm86_manager/manager.dart';
import 'package:dlssg_for_sm86_manager/models.dart';
import 'package:dlssg_for_sm86_manager/steam.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _EmptyScanner extends SteamScanner {
  @override
  Future<List<GameEntry>> scan({required List<GameEntry> existing}) async =>
      existing;
  @override
  Future<Map<String, int>> manifestModificationTimes() async => {};
}

Future<void> _copyGitBlob(String repository, String blob, File target) async {
  await target.parent.create(recursive: true);
  final process = await Process.start('git', [
    '-C',
    repository,
    'cat-file',
    'blob',
    blob,
  ]);
  final errors = process.stderr.transform(utf8.decoder).join();
  final sink = target.openWrite();
  try {
    await sink.addStream(process.stdout);
  } finally {
    await sink.close();
  }
  expect(await process.exitCode, 0, reason: await errors);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DriverFingerprintCatalog catalog;
  setUpAll(() async {
    catalog = await DriverFingerprintCatalog.load();
  });
  final manifest = jsonDecode(
    File('driver-fingerprints.json').readAsStringSync(),
  ) as Map;
  final tags = (manifest['tags'] as List).cast<Map>();

  test('所有 tag 的代理指纹与审计记录一致，历史存档归属正确且无版本冲突', () {
    final fingerprints = <String, Set<String>>{};
    var fileCount = 0;
    final versions = <String>{};
    for (final tag in tags) {
      expect(tag['commit'], matches(r'^[0-9a-f]{40}$'));
      for (final file in (tag['files'] as List).cast<Map>()) {
        fileCount++;
        expect(file['sha256'], matches(r'^[0-9a-f]{64}$'));
        expect(file['git_blob'], matches(r'^[0-9a-f]{40}$'));
        expect(file['size'], greaterThanOrEqualTo(0));
        final version = file['proxy_version'] as String?;
        if (version == null) continue;
        final path = file['path'] as String;
        final expected = path.startsWith('archive/')
            ? path.split('/')[1]
            : tag['tag'];
        expect(
          compareDriverVersions(version, expected as String),
          0,
          reason: '${tag['tag']}:$path',
        );
        versions.add(version);
        fingerprints
            .putIfAbsent(file['sha256'] as String, () => {})
            .add(version);
      }
    }
    expect(manifest['tag_count'], tags.length);
    expect(manifest['file_count'], fileCount);
    final candidates = {
      for (final entry in fingerprints.entries)
        entry.key: entry.value.toList()
          ..sort((a, b) => compareDriverVersions(a, b)!),
    };
    expect(manifest['ambiguous_proxy_fingerprints'], {
      for (final entry in candidates.entries)
        if (entry.value.length > 1) entry.key: entry.value,
    });
    expect(catalog.proxyVersionCandidates, candidates);
    expect(catalog.proxyVersions, {
      for (final entry in fingerprints.entries)
        if (entry.value.length == 1) entry.key: entry.value.single,
    });
    expect(catalog.runtimeFingerprints, manifest['runtime_fingerprints']);
    expect(
      versions,
      containsAll([
        '0.1.0',
        '0.2.4',
        '0.3.0',
        '0.3.1',
        '0.3.2',
        '0.3.3',
        '0.3.4',
        '0.3.5',
        '0.4.0',
      ]),
    );
  });

  final repository = Platform.environment['DLSSG_UPSTREAM_REPO'];
  test(
    '所有 tag 的真实代理 DLL：无安装记录时识别版本，补全旧记录并安全卸载',
    () async {
      final root = await Directory.systemTemp.createTemp('dlssg-historical-');
      addTearDown(() => root.delete(recursive: true));
      final tagResult = await Process.run('git', [
        '-C',
        repository!,
        'tag',
        '--list',
      ]);
      expect(tagResult.exitCode, 0, reason: tagResult.stderr.toString());
      expect(
        (tagResult.stdout as String).trim().split(RegExp(r'\r?\n')),
        unorderedEquals(tags.map((tag) => tag['tag'])),
      );
      final manager = await ModManager.open(
        dataDirectory: Directory(p.join(root.path, 'data')),
        driversDirectory: Directory(p.join(root.path, 'no-drivers')),
        scanner: _EmptyScanner(),
      );
      addTearDown(manager.client.close);
      final fixtures = <String, Map>{};
      for (final tag in tags) {
        for (final file in (tag['files'] as List).cast<Map>()) {
          if (file['proxy_version'] == null ||
              !proxies.contains(p.posix.basename(file['path'] as String))) {
            continue;
          }
          fixtures['${file['proxy_version']}/${file['sha256']}/${p.posix.basename(file['path'] as String)}'] =
              file;
        }
      }
      final expected = <String, Map>{};
      final blobs = {
        for (final tag in tags)
          for (final file in (tag['files'] as List).cast<Map>())
            file['sha256'] as String: file['git_blob'] as String,
      };
      for (final entry in fixtures.entries) {
        final file = entry.value;
        final proxy = p.posix.basename(file['path'] as String);
        final dir = await Directory(
          p.join(root.path, 'games', entry.key.replaceAll('/', '-')),
        ).create(recursive: true);
        final target = File(p.join(dir.path, proxy));
        await _copyGitBlob(repository, file['git_blob'] as String, target);
        for (final runtime
            in (catalog.runtimeFingerprints[file['proxy_version']] ??
                    const <String, String>{})
                .entries) {
          await _copyGitBlob(
            repository,
            blobs[runtime.value]!,
            File(p.join(dir.path, runtime.key)),
          );
        }
        expect(await sha256File(target), file['sha256']);
        await File(p.join(dir.path, 'game.exe')).writeAsString('exe');
        await File(p.join(dir.path, 'dlssg_sm86.ini'))
            .writeAsString('[General]\nEnabled=1\n');
        final game = GameEntry(
          id: entry.key,
          name: entry.key,
          source: const GameSource.manual(),
          exePath: p.join(dir.path, 'game.exe'),
          selectedProxy: proxy,
        );
        manager.db.games.add(game);
        expected[game.id] = file;
      }
      final views = await manager.listGames();
      expect(views.length, fixtures.length);
      for (final view in views) {
        final file = expected[view.game.id]!;
        expect(view.mod.kind, ModStateKind.applied);
        expect(
          view.mod.version,
          file['proxy_version'],
          reason: file['path'] as String,
        );
        expect(view.mod.canUninstall, isTrue);
        expect(view.mod.unrecognizedProxyHashes, isEmpty);
        expect(
          requiresCleanInstall(view.mod.version, '0.4.0'),
          requiresCleanInstall(file['proxy_version'] as String, '0.4.0'),
        );
      }

      final legacy = views
          .firstWhere(
            (view) =>
                view.mod.version == '0.3.5' && view.mod.proxy == defaultProxy,
          )
          .game;
      for (final oldLabel in ['未知版本', '本地包']) {
        legacy.install = ManagedInstall(
          proxy: defaultProxy,
          dllSha256: expected[legacy.id]!['sha256'] as String,
          version: oldLabel,
        );
        expect((await manager.view(legacy)).mod.version, '0.3.5');
      }
      legacy.install = null;

      final package = await Directory(
        p.join(manager.releaseRoot.path, 'dlssg_for_sm86'),
      ).create();
      for (final name in [defaultProxy, ...runtimeDriverFiles]) {
        final file = File(p.join(package.path, name));
        await file.parent.create(recursive: true);
        await file.writeAsString('new driver');
      }
      await File(p.join(package.path, 'dlssg_sm86.ini'))
          .writeAsString('[DLSSG]\nOptimized=2\n');
      manager.db.installedVersion = '0.4.0';
      await expectLater(
        manager.installMod(legacy.id),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('请先卸载旧版本'),
          ),
        ),
      );
      expect(
        await sha256File(
          File(p.join(File(legacy.exePath!).parent.path, defaultProxy)),
        ),
        expected[legacy.id]!['sha256'],
      );

      final modern = views
          .firstWhere(
            (view) =>
                view.mod.version == '0.4.0' && view.mod.proxy == defaultProxy,
          )
          .game;
      final modernDll = File(
        p.join(File(modern.exePath!).parent.path, defaultProxy),
      );
      final modernDir = modernDll.parent;
      final historicalRuntime = <String, String>{};
      for (final file
          in (tags.firstWhere((tag) => tag['tag'] == '0.4.0')['files'] as List)
              .cast<Map>()) {
        final name = file['path'] as String;
        if (!name.startsWith('dlssg_sm86/')) continue;
        await _copyGitBlob(
          repository,
          file['git_blob'] as String,
          File(p.join(modernDir.path, name)),
        );
        historicalRuntime[name] = file['sha256'] as String;
      }
      modern.install = ManagedInstall(
        proxy: defaultProxy,
        dllSha256: expected[modern.id]!['sha256'] as String,
        version: '0.4.0',
        runtimeFiles: historicalRuntime,
      );
      await _copyGitBlob(
        repository,
        expected[modern.id]!['git_blob'] as String,
        File(p.join(package.path, defaultProxy)),
      );
      manager.db.installedVersion = '0.5.0';
      for (final name in runtimeDriverFiles) {
        final file = File(p.join(package.path, name));
        await file.parent.create(recursive: true);
        await file.writeAsString('newer runtime $name');
      }
      expect((await manager.view(modern)).mod.version, '0.4.0');
      for (final name in runtimeDriverFiles) {
        await copyAtomic(
          File(p.join(package.path, name)),
          File(p.join(modernDir.path, name)),
        );
      }
      expect((await manager.view(modern)).mod.version, '0.5.0');
      final bytes = await modernDll.readAsBytes();
      final pe = ByteData.sublistView(bytes);
      final header = pe.getUint32(0x3c, Endian.little);
      final section = header + 24 + pe.getUint16(header + 20, Endian.little);
      bytes[pe.getUint32(section + 20, Endian.little) + 16] ^= 1;
      await modernDll.writeAsBytes(bytes);
      expect((await manager.view(modern)).mod.version, '未知版本');
      await expectLater(manager.uninstallMod(modern.id), throwsStateError);
      expect(await modernDll.exists(), isTrue);
      await _copyGitBlob(
        repository,
        expected[modern.id]!['git_blob'] as String,
        modernDll,
      );

      for (final view in views) {
        await manager.uninstallMod(view.game.id);
        final dir = File(view.game.exePath!).parent;
        expect(await File(p.join(dir.path, view.mod.proxy!)).exists(), isFalse);
        expect(
          await File(p.join(dir.path, 'dlssg_sm86.ini')).exists(),
          isFalse,
        );
      }
    },
    skip: repository == null
        ? '设置 DLSSG_UPSTREAM_REPO 可验证全部 tag 的真实 DLL'
        : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
