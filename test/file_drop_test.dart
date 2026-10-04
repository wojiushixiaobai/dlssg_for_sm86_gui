import 'dart:io';

import 'package:dlssg_for_sm86_manager/app.dart';
import 'package:dlssg_for_sm86_manager/hags.dart';
import 'package:dlssg_for_sm86_manager/manager.dart';
import 'package:dlssg_for_sm86_manager/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _channel = MethodChannel('dlssg/file-drop');
const _codec = StandardMethodCodec();

Future<void> _drop(WidgetTester tester, List<String> paths) async {
  await tester.runAsync(
    () => tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      _channel.name,
      _codec.encodeMethodCall(MethodCall('files', paths)),
      null,
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('文件选择添加游戏后打开新游戏设置，重复添加也选中已有游戏', (tester) async {
    _useDesktopSize(tester);
    final manager = _DropManager();
    await manager.addManualGame('已有游戏', r'C:\games\old.exe');
    const picked = r'C:\games\新游戏.exe';
    const pickerChannel = MethodChannel('plugins.flutter.io/file_selector');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      pickerChannel,
      (call) async => [picked],
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        pickerChannel,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Shell(
          manager,
          initialGames: List.of(manager.games),
          hagsStatusReader: () =>
              HardwareAcceleratedGpuSchedulingStatus.unavailable,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(DesktopNavigation),
        matching: find.text('游戏'),
      ),
    );
    await tester.pumpAndSettle();
    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.tap(find.widgetWithText(ListTile, '已有游戏'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('添加游戏'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<GameSettings>(find.byType(GameSettings))
            .view
            ?.game
            .exePath,
        picked,
      );
      expect(manager.games, hasLength(2));
      expect(find.text('程序设置'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('拖放 EXE 后自动添加并选中游戏', (tester) async {
    _useDesktopSize(tester);
    final directory = Directory.systemTemp.createTempSync('dlssg-drop-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final exe = File(p.join(directory.path, '测试游戏.exe'));
    exe.writeAsStringSync('test');
    final manager = _DropManager();
    await tester.pumpWidget(
      MaterialApp(
        home: Shell(
          manager,
          initialGames: const [],
          hagsStatusReader: () =>
              HardwareAcceleratedGpuSchedulingStatus.unavailable,
        ),
      ),
    );

    await _drop(tester, [exe.path]);

    expect(manager.added, [(name: '测试游戏', path: exe.path)]);
    expect(find.text('测试游戏'), findsWidgets);
    expect(find.text('程序设置'), findsOneWidget);
  });

  testWidgets('快捷方式使用其名称，并忽略无效目标', (tester) async {
    _useDesktopSize(tester);
    final directory = Directory.systemTemp.createTempSync('dlssg-drop-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final exe = File(p.join(directory.path, 'real.exe'));
    exe.writeAsStringSync('test');
    const shortcut = r'C:\Users\Test\Desktop\游戏快捷方式.lnk';
    const invalid = r'C:\Users\Test\Desktop\无效.lnk';
    final manager = _DropManager();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _channel,
      (call) async => call.arguments == shortcut ? exe.path : 'missing.exe',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Shell(
          manager,
          initialGames: const [],
          hagsStatusReader: () =>
              HardwareAcceleratedGpuSchedulingStatus.unavailable,
        ),
      ),
    );

    await _drop(tester, [shortcut, invalid]);

    expect(manager.added, [(name: '游戏快捷方式', path: exe.path)]);
    expect(find.textContaining('有 1 个文件未添加'), findsOneWidget);
    await _drop(tester, [shortcut]);
    expect(manager.games, hasLength(1));
  });
}

void _useDesktopSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _DropManager implements ModManager {
  final games = <GameView>[];
  final added = <({String name, String path})>[];

  @override
  Future<GameEntry> addManualGame(String name, String exePath) async {
    added.add((name: name, path: exePath));
    for (final view in games) {
      if (view.game.exePath == exePath) return view.game;
    }
    final game = GameEntry(
      id: 'game-${games.length}',
      name: name,
      source: const GameSource.manual(),
      exePath: exePath,
    );
    games.add(
      GameView(
        game,
        TargetState.ready,
        const ModStatus(ModStateKind.notApplied),
      ),
    );
    return game;
  }

  @override
  Future<List<GameView>> listGames() async => games;

  @override
  Future<String> latestDriverVersion() async => '1.0';

  @override
  ManagerInfo get info =>
      const ManagerInfo(installedVersion: null, modAvailable: false);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
