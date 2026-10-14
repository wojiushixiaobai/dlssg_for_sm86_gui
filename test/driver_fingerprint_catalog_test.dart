import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dlssg_for_sm86_manager/driver_fingerprints.dart';
import 'package:dlssg_for_sm86_manager/manager.dart';
import 'package:dlssg_for_sm86_manager/models.dart';
import 'package:dlssg_for_sm86_manager/steam.dart';
import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _EmptyScanner extends SteamScanner {
  @override
  Future<List<GameEntry>> scan({required List<GameEntry> existing}) async =>
      existing;
  @override
  Future<Map<String, int>> manifestModificationTimes() async => {};
}

String _hash(String text) => sha256.convert(utf8.encode(text)).toString();

Map<String, Object?> _manifest(
  List<(String, String)> proxies, {
  Map<String, Map<String, String>> runtimes = const {},
}) => {
  'schema_version': 2,
  'hash_algorithm': 'SHA-256',
  'tags': [
    for (final (version, hash) in proxies)
      {
        'files': [
          {'proxy_version': version, 'sha256': hash},
        ],
      },
  ],
  'runtime_fingerprints': runtimes,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('JSON 索引合并重复和大小写指纹，保留共享候选且不可修改', () {
    final hash = _hash('shared');
    final catalog = DriverFingerprintCatalog.fromJsonText(
      jsonEncode(
        _manifest(
          [('0.5.0', hash), ('0.5.0', hash.toUpperCase()), ('v0.6.0', hash)],
          runtimes: {
            '0.5.0': {
              'dlssg_sm86/backend/sm86_backend.dll': hash.toUpperCase(),
            },
          },
        ),
      ),
    );
    expect(catalog.proxyVersions, isEmpty);
    expect(catalog.proxyVersionCandidates[hash], ['0.5.0', '0.6.0']);
    expect(catalog.runtimeFingerprints['0.5.0']!.values.single, hash);
    expect(() => catalog.proxyVersions.clear(), throwsUnsupportedError);
    expect(
      () => catalog.proxyVersionCandidates.clear(),
      throwsUnsupportedError,
    );
    expect(
      () => catalog.proxyVersionCandidates[hash]!.clear(),
      throwsUnsupportedError,
    );
    expect(() => catalog.runtimeFingerprints.clear(), throwsUnsupportedError);
    expect(
      () => catalog.runtimeFingerprints['0.5.0']!.clear(),
      throwsUnsupportedError,
    );
  });

  test('拒绝不支持的格式、损坏指纹和运行目录之外的路径', () {
    final hash = _hash('proxy');
    final invalid = <Object?>[
      [],
      {..._manifest([]), 'schema_version': 3},
      {..._manifest([]), 'hash_algorithm': 'MD5'},
      {..._manifest([]), 'tags': null},
      _manifest([('invalid', hash)]),
      _manifest([('0.5.0', 'invalid')]),
      for (final path in [
        '../file.dll',
        'dlssg_sm86/../file.dll',
        r'dlssg_sm86/..\file.dll',
        'dlssg_sm86/file.dll:stream',
      ])
        _manifest(
          [],
          runtimes: {
            '0.5.0': {path: hash},
          },
        ),
    ];
    for (final value in invalid) {
      expect(
        () => DriverFingerprintCatalog.fromJsonText(jsonEncode(value)),
        throwsFormatException,
        reason: jsonEncode(value),
      );
    }
  });

  group('管理器从 JSON 资源加载目录', () {
    late Directory root;
    late File catalogFile;
    final managers = <ModManager>[];
    setUp(() async {
      root = await Directory.systemTemp.createTemp('dlssg-json-catalog-');
      catalogFile = File(p.join(root.path, 'driver-fingerprints.json'));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', (message) async {
            expect(
              utf8.decode(message!.buffer.asUint8List()),
              DriverFingerprintCatalog.assetPath,
            );
            if (!catalogFile.existsSync()) return null;
            return ByteData.sublistView(await catalogFile.readAsBytes());
          });
    });
    tearDown(() async {
      for (final manager in managers) {
        manager.client.close();
      }
      managers.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', null);
      await root.delete(recursive: true);
    });

    Future<ModManager> open() async {
      final manager = await ModManager.open(
        dataDirectory: Directory(p.join(root.path, 'data')),
        driversDirectory: Directory(p.join(root.path, 'no-drivers')),
        scanner: _EmptyScanner(),
      );
      managers.add(manager);
      return manager;
    }

    Future<GameEntry> game(ModManager manager, String proxy) async {
      final dir = await Directory(p.join(root.path, 'game')).create();
      await File(p.join(dir.path, 'version.dll')).writeAsString(proxy);
      await File(p.join(dir.path, 'dlssg_sm86.ini'))
          .writeAsString('[General]\nEnabled=1\n');
      final exe = await File(p.join(dir.path, 'game.exe')).writeAsString('exe');
      return manager.addManualGame('Game', exe.path);
    }

    test('只更新 JSON 后重新打开即可识别新版本，列表及卸载均使用加载的目录', () async {
      const proxy = 'MZ-new-legacy-proxy';
      await catalogFile.writeAsString(
        jsonEncode(_manifest([('0.3.6', _hash(proxy))])),
      );
      final first = await open();
      final entry = await game(first, proxy);
      expect((await first.view(entry)).mod.version, '0.3.6');
      await catalogFile.writeAsString(
        jsonEncode(_manifest([('0.3.7', _hash(proxy))])),
      );
      final second = await open();
      expect((await second.listGames()).single.mod.version, '0.3.7');
      // Each manager retains its own immutable startup snapshot across isolates.
      expect((await first.view(entry)).mod.version, '0.3.6');
      await second.uninstallMod(entry.id);
      expect(
        File(p.join(root.path, 'game', 'version.dll')).existsSync(),
        isFalse,
      );
      expect(
        File(p.join(root.path, 'game', 'dlssg_sm86.ini')).existsSync(),
        isFalse,
      );
    });

    test('JSON 中的伴随指纹区分共享代理，运行文件不匹配时保留未知版本', () async {
      const proxy = 'MZ-shared-modern-proxy';
      const runtimePath = 'dlssg_sm86/backend/sm86_backend.dll';
      await catalogFile.writeAsString(
        jsonEncode(
          _manifest(
            [('0.5.0', _hash(proxy)), ('0.6.0', _hash(proxy))],
            runtimes: {
              '0.5.0': {runtimePath: _hash('backend-five')},
              '0.6.0': {runtimePath: _hash('backend-six')},
            },
          ),
        ),
      );
      final manager = await open();
      final entry = await game(manager, proxy);
      final runtime = File(p.join(root.path, 'game', runtimePath));
      await runtime.parent.create(recursive: true);
      await runtime.writeAsString('backend-six');
      expect((await manager.view(entry)).mod.version, '0.6.0');
      await runtime.writeAsString('backend-five');
      expect((await manager.view(entry)).mod.version, '0.5.0');
      await runtime.writeAsString('unrecognized-backend');
      final view = await manager.view(entry);
      expect(view.mod.version, '未知版本');
      expect(view.mod.unrecognizedProxyHashes, isEmpty);
    });

    test('缺少或损坏的目录在启动时明确失败', () async {
      await expectLater(open(), throwsA(isA<FlutterError>()));
      await catalogFile.writeAsString('{broken');
      await expectLater(open(), throwsFormatException);
    });
  });
}
