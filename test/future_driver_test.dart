import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dlssg_for_sm86_manager/app.dart';
import 'package:dlssg_for_sm86_manager/manager.dart';
import 'package:dlssg_for_sm86_manager/models.dart';
import 'package:dlssg_for_sm86_manager/steam.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

const _ini =
    '[FrameGeneration]\nEngine=DLSS\n[DLSSG]\nPreset=Auto\nOptimized=2\n[SuperResolution]\nMode=Off\n';

Map<String, String> _files(
  String version, {
  List<String> runtime = runtimeDriverFiles,
  String ini = _ini,
}) => {
  for (final proxy in proxies)
    proxy == defaultProxy ? proxy : 'alternatives/$proxy': 'shared-$proxy',
  for (final name in runtime) name: '$version-$name',
  'dlssg_sm86.ini': ini,
};

List<int> _zip(
  String version, {
  List<String> runtime = runtimeDriverFiles,
  String ini = _ini,
  String? missing,
  bool wrongHash = false,
  String? manifestVersion,
  String? runtimeContentVersion,
}) {
  final files = _files(
    runtimeContentVersion ?? version,
    runtime: runtime,
    ini: ini,
  );
  final manifest = {
    'bundle': {
      'version': manifestVersion ?? version,
      'backend_path': runtime[0],
      'kernel_pack_path': runtime[1],
      'runtime_path': runtime[2],
    },
    'files': [
      for (final entry in files.entries)
        {
          'path': entry.key,
          'size': utf8.encode(entry.value).length,
          'sha256': wrongHash && entry.key == runtime[0]
              ? '0' * 64
              : sha256.convert(utf8.encode(entry.value)).toString(),
        },
    ],
  };
  files['manifest.json'] = jsonEncode(manifest);
  final archive = Archive();
  for (final entry in files.entries) {
    if (entry.key == missing) continue;
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

class _ConfigManager implements ModManager {
  _ConfigManager(this.profile);
  ConfigProfile profile;
  @override
  Future<ConfigProfile> loadGlobalConfig() async => profile;
  @override
  Future<void> saveGlobalConfig(ConfigProfile config) async {
    profile = config;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root, drivers;
  final clients = <Client>[];
  setUp(() async {
    root = await Directory.systemTemp.createTemp('dlssg-future-');
    drivers = await Directory(p.join(root.path, 'drivers')).create();
  });
  tearDown(() async {
    for (final client in clients) {
      client.close();
    }
    clients.clear();
    await root.delete(recursive: true);
  });
  Future<void> bundle(String version, {List<int>? bytes}) async {
    await File(p.join(drivers.path, 'dlssg-release-$version-x64.zip'))
        .writeAsBytes(bytes ?? _zip(version));
  }

  Future<ModManager> open({Client? client}) async {
    client ??= MockClient(
      (request) async => throw StateError('离线读取请求了网络：${request.url}'),
    );
    clients.add(client);
    return ModManager.open(
      dataDirectory: Directory(p.join(root.path, 'data')),
      driversDirectory: drivers,
      scanner: _EmptyScanner(),
      client: client,
    );
  }

  Future<GameEntry> game(ModManager manager, String name) async {
    final exe = File(p.join(root.path, name, 'game.exe'));
    await exe.parent.create(recursive: true);
    await exe.writeAsString('exe');
    return manager.addManualGame(name, exe.path);
  }

  test('版本按数值和预发布标识比较，不将较旧包或不同 v 前缀当作更新', () {
    for (final (a, b, expected) in <(String, String, int)>[
      ('0.4.0', '0.4.1', -1),
      ('0.9.0', '0.10.0', -1),
      ('0.10.0', '1.0.0', -1),
      ('v0.5', '0.5.0', 0),
      ('0.5.0+build.1', '0.5.0+build.2', 0),
      ('0.5.0-rc.2', '0.5.0-rc.10', -1),
      ('0.5.0-rc.10', '0.5.0', -1),
      ('0.5.0-alpha', '0.5.0-beta', -1),
      ('1.0.0', '0.10.0', 1),
    ]) {
      expect(compareDriverVersions(a, b)?.sign, expected, reason: '$a → $b');
    }
    expect(isDriverUpdateAvailable('1.0.0', '0.10.0'), isFalse);
    expect(isDriverUpdateAvailable('v0.5.0', '0.5.0'), isFalse);
    expect(isDriverUpdateAvailable('未知版本', '0.5.0'), isTrue);
    expect(compareDriverVersions('invalid', '0.5.0'), isNull);
    expect(requiresCleanInstall('0.3.99', '1.0.0'), isTrue);
    expect(requiresCleanInstall('0.4.0-beta.1', '0.5.0'), isFalse);
  });

  test('离线目录选择最高版本，升级旧缓存并保留游戏配置，已有更新在线缓存不降级', () async {
    await bundle('0.4.0');
    var manager = await open();
    final g = await game(manager, 'old-game');
    await manager.installMod(g.id);
    final ini = File(p.join(File(g.exePath!).parent.path, 'dlssg_sm86.ini'));
    final before = await ini.readAsBytes();
    await bundle(
      '0.5.0',
      bytes: _zip('0.5.0', ini: '$_ini\n[Future]\nNewKey=42\n'),
    );
    manager = await open();
    expect(manager.info.installedVersion, '0.5.0');
    expect((await manager.loadGlobalConfig()).value('Future', 'NewKey'), '42');
    expect(await ini.readAsBytes(), before);
    await bundle('0.9.0');
    await bundle('0.10.0');
    manager = await open();
    expect(manager.info.installedVersion, '0.10.0');
    final latestClient = MockClient(
      (request) async => request.url.toString() == latestReleaseUrl
          ? Response(
              jsonEncode({
                'tag_name': '1.0.0',
                'assets': [
                  {
                    'name': 'dlssg-release-1.0.0-x64.zip',
                    'browser_download_url':
                        'https://example.invalid/latest.zip',
                  },
                ],
              }),
              200,
            )
          : Response.bytes(_zip('1.0.0'), 200),
    );
    manager = await open(client: latestClient);
    await manager.refreshModFromGithub();
    expect((await open()).info.installedVersion, '1.0.0');
    expect(await ini.readAsBytes(), before);
  });

  test('新版清单可增删运行模块，更新只补充新参数并保留用户值，卸载保留被用户修改的废弃文件', () async {
    var latest = '0.5.0';
    const nextRuntime = [
      'dlssg_sm86/backend/new_backend.dll',
      'dlssg_sm86/models/new_kernels.bin',
      'dlssg_sm86/runtime/new_runtime.dll',
    ];
    final newIni = '$_ini\n[Future]\nNewParameter=17\n';
    await bundle('0.5.0');
    final manager = await open(
      client: MockClient(
        (request) async => request.url.toString() == latestReleaseUrl
            ? Response(
                jsonEncode({
                  'tag_name': latest,
                  'assets': [
                    {
                      'name': 'dlssg-release-$latest-x64.zip',
                      'browser_download_url':
                          'https://example.invalid/latest.zip',
                    },
                  ],
                }),
                200,
              )
            : Response.bytes(
                _zip(latest, runtime: nextRuntime, ini: newIni),
                200,
              ),
      ),
    );
    final g = await game(manager, 'game');
    await manager.installMod(g.id);
    final dir = File(g.exePath!).parent;
    await manager.saveGameConfig(
      g.id,
      (await manager.loadGameConfig(g.id)).withValue('DLSSG', 'Preset', 'C'),
    );
    final global = (await manager.loadGlobalConfig()).withValue(
      'DLSSG',
      'Optimized',
      '1',
    );
    await manager.saveGlobalConfig(global);
    final modified = await File(p.join(dir.path, runtimeDriverFiles.last))
        .writeAsString('user customized old module');
    latest = '0.6.0';
    await manager.refreshModFromGithub();
    expect((await manager.loadGlobalConfig()).value('DLSSG', 'Optimized'), '1');
    expect(
      (await manager.loadGlobalConfig()).value('Future', 'NewParameter'),
      '17',
    );
    expect(
      (await manager.loadGameConfig(g.id)).value('Future', 'NewParameter'),
      isNull,
    );
    await manager.installMod(g.id);
    expect((await manager.view(g)).mod.version, '0.6.0');
    final config = await manager.loadGameConfig(g.id);
    expect(config.value('DLSSG', 'Preset'), 'C');
    expect(config.value('DLSSG', 'Optimized'), '2');
    expect(config.value('Future', 'NewParameter'), '17');
    for (final name in nextRuntime) {
      expect(await File(p.join(dir.path, name)).exists(), isTrue);
    }
    expect(
      await File(p.join(dir.path, runtimeDriverFiles.first)).exists(),
      isFalse,
    );
    expect(await modified.readAsString(), 'user customized old module');
    expect(
      g.install!.runtimeFiles.keys,
      isNot(contains(runtimeDriverFiles.last)),
    );
    await manager.uninstallMod(g.id);
    for (final name in nextRuntime) {
      expect(await File(p.join(dir.path, name)).exists(), isFalse);
    }
    expect(await modified.readAsString(), 'user customized old module');
  });

  for (final invalid in ['missing', 'hash', 'version']) {
    test('后续版本的清单损坏时不激活包：$invalid', () async {
      await bundle(
        '0.8.0',
        bytes: _zip(
          '0.8.0',
          missing: invalid == 'missing' ? runtimeDriverFiles.first : null,
          wrongHash: invalid == 'hash',
          manifestVersion: invalid == 'version' ? '0.7.0' : null,
        ),
      );
      await expectLater(open(), throwsStateError);
    });
  }

  test('新版仅新增模块且旧 DLL 字节不变时，完整运行文件优先于过时安装记录', () async {
    const extra = 'dlssg_sm86/extra/new_model.bin';
    await bundle('0.4.0');
    final manager = await open(
      client: MockClient(
        (request) async => request.url.toString() == latestReleaseUrl
            ? Response(
                jsonEncode({
                  'tag_name': '0.5.0',
                  'assets': [
                    {
                      'name': 'dlssg-release-0.5.0-x64.zip',
                      'browser_download_url':
                          'https://example.invalid/latest.zip',
                    },
                  ],
                }),
                200,
              )
            : Response.bytes(
                _zip(
                  '0.5.0',
                  runtime: [...runtimeDriverFiles, extra],
                  runtimeContentVersion: '0.4.0',
                  ini: '$_ini\n[Future]\nNewKey=17\n',
                ),
                200,
              ),
      ),
    );
    final g = await game(manager, 'game');
    await manager.installMod(g.id);
    await manager.refreshModFromGithub();
    expect((await manager.view(g)).mod.version, '0.4.0');
    final target = File(p.join(File(g.exePath!).parent.path, extra));
    await copyAtomic(
      File(p.join(manager.releaseRoot.path, 'dlssg_for_sm86', extra)),
      target,
    );
    expect((await manager.view(g)).mod.version, '0.5.0');
    expect(
      (await manager.loadGameConfig(g.id)).value('Future', 'NewKey'),
      '17',
    );
    await manager.uninstallMod(g.id);
    expect(await target.exists(), isFalse);
  });

  test('v 前缀 tag 可使用不带 v 的完整包名称，所有新增资源都复制', () async {
    final manager = await open(
      client: MockClient(
        (request) async => request.url.toString() == latestReleaseUrl
            ? Response(
                jsonEncode({
                  'tag_name': 'v0.7.0',
                  'assets': [
                    {
                      'name': 'dlssg-release-0.7.0-x64.zip',
                      'browser_download_url':
                          'https://example.invalid/latest.zip',
                    },
                  ],
                }),
                200,
              )
            : Response.bytes(
                _zip(
                  '0.7.0',
                  runtime: [
                    ...runtimeDriverFiles,
                    'dlssg_sm86/extra/new_feature.bin',
                  ],
                ),
                200,
              ),
      ),
    );
    expect(await manager.refreshModFromGithub(), 'v0.7.0');
    final g = await game(manager, 'game');
    await manager.installMod(g.id);
    expect(
      await File(
        p.join(
          File(g.exePath!).parent.path,
          'dlssg_sm86/extra/new_feature.bin',
        ),
      ).exists(),
      isTrue,
    );
  });

  testWidgets('配置使用新版默认值和新增候选值，新引擎不显示 DLSS/XeSS 专用选项', (tester) async {
    final defaults = ModManager.parseProfile(
      '[FrameGeneration]\nEngine=NewEngine\n[DLSSG]\nPreset=D\n[XeSSFG]\nUseHudless=1\n[Future]\nNewKey=17\n',
    );
    final manager = _ConfigManager(
      ModManager.parseProfile(
        '[FrameGeneration]\nEngine=DLSS\n[DLSSG]\nPreset=Auto\n',
      ).withDefaults(defaults),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GlobalSettings(true, manager, (job) => job())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('[DLSSG]'), findsOneWidget);
    expect(find.text('[XeSSFG]'), findsNothing);
    await tester.tap(find.text('Auto'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(PopupMenuItem<String>, 'D'), findsOneWidget);
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'D'));
    await tester.pumpAndSettle();
    expect(manager.profile.value('DLSSG', 'Preset'), 'D');
    await tester.tap(find.text('DLSS'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'NewEngine'));
    await tester.pumpAndSettle();
    expect(find.text('[DLSSG]'), findsNothing);
    expect(find.text('[XeSSFG]'), findsNothing);
    expect(find.text('[Future]'), findsOneWidget);
    expect(manager.profile.value('DLSSG', 'Preset'), 'D');
    expect(tester.takeException(), isNull);
  });

  test('带 build metadata 的后续 Release 可下载、缓存并安装', () async {
    const tag = '0.5.0+build.17';
    final manager = await open(
      client: MockClient(
        (request) async => request.url.toString() == latestReleaseUrl
            ? Response(
                jsonEncode({
                  'tag_name': tag,
                  'assets': [
                    {
                      'name': 'dlssg-release-$tag-x64.zip',
                      'browser_download_url':
                          'https://example.invalid/latest.zip',
                    },
                  ],
                }),
                200,
              )
            : Response.bytes(_zip(tag), 200),
      ),
    );
    expect(await manager.refreshModFromGithub(), tag);
    expect(manager.hasModPackage, isTrue);
    final g = await game(manager, 'game');
    await manager.installMod(g.id);
    expect((await manager.view(g)).mod.version, tag);
  });
}
