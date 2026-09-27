import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:dlssg_for_sm86_manager/main.dart';
import 'package:dlssg_for_sm86_manager/manager.dart';
import 'package:dlssg_for_sm86_manager/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('首次启动只显示游戏状态检查提示', (tester) async {
    await tester.pumpWidget(const InitializationApp());
    expect(find.text('正在检查游戏状态…'), findsOneWidget);
    expect(find.byType(Shell), findsNothing);
  });

  testWidgets('首次检查完成后直接展示预加载游戏', (tester) async {
    final game = _gameView(1);
    final manager = _FakeManager(games: [game]);
    await tester.pumpWidget(
      MaterialApp(home: Shell(manager, initialGames: [game])),
    );

    expect(find.text('游戏 1'), findsOneWidget);
    expect(manager.listCalls, 0);
  });

  testWidgets('连续两次管理员权限启动失败都显示相同类型的提示', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final game = GameView(
      GameEntry(
        id: 'uac-game',
        name: '需要授权的游戏',
        source: const GameSource.manual(),
      ),
      TargetState.ready,
      const ModStatus(ModStateKind.notApplied),
      const ConfigStatus(ConfigStateKind.global),
    );
    final manager = _FakeManager(games: [game]);
    await tester.pumpWidget(MaterialApp(home: Shell(manager)));
    await tester.pump();
    await tester.tap(find.text('游戏设置').first);
    await tester.pump();

    for (var attempt = 1; attempt <= 2; attempt++) {
      await tester.tap(find.widgetWithText(TextButton, '启动游戏'));
      await tester.pump();
      expect(manager.launchCalls, attempt);
      expect(
        find.textContaining('操作失败：ProcessException: 无法以管理员权限启动游戏'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
      expect(
        find.textContaining('操作失败：ProcessException: 无法以管理员权限启动游戏'),
        findsNothing,
      );
    }
  });

  testWidgets('驱动下载失败后再次点击仍显示提示', (tester) async {
    final manager = _FakeManager();
    await tester.pumpWidget(MaterialApp(home: Shell(manager)));
    await tester.tap(find.text('驱动程序').first);
    await tester.pump();

    for (var attempt = 1; attempt <= 2; attempt++) {
      await tester.tap(find.widgetWithText(FilledButton, '下载'));
      await tester.pump();
      expect(manager.refreshCalls, attempt);
      expect(find.textContaining('下载失败'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(find.textContaining('下载失败'), findsNothing);
    }
  });

  testWidgets('重复操作错误会重新显示提示并重置关闭时间', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Shell(_FakeManager())));
    final shell = tester.state(find.byType(Shell)) as dynamic;

    Future<void> fail() => shell.act(() async {
      throw StateError('重复错误');
    });

    await fail();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('重复错误'), findsOneWidget);
    expect(find.byKey(const ValueKey('toast-1')), findsOneWidget);

    await fail();
    await tester.pump();
    expect(find.textContaining('重复错误'), findsOneWidget);
    expect(find.byKey(const ValueKey('toast-1')), findsNothing);
    expect(find.byKey(const ValueKey('toast-2')), findsOneWidget);
    final replayOpacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byKey(const ValueKey('toast-2')),
        matching: find.byType(Opacity),
      ),
    );
    expect(replayOpacity.opacity, 0);

    await tester.pump(const Duration(seconds: 4));
    expect(find.textContaining('重复错误'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('重复错误'), findsNothing);

    await fail();
    await tester.pump();
    expect(find.textContaining('重复错误'), findsOneWidget);
    expect(find.byKey(const ValueKey('toast-3')), findsOneWidget);
  });

  testWidgets('主页无游戏时不显示游戏库栏目', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Home([], _ignoreGame)));
    expect(find.text('Steam 库'), findsNothing);
    expect(find.text('其他游戏库'), findsNothing);
    expect(find.byType(GameCard), findsNothing);
  });

  testWidgets('手动添加的游戏也优先使用 EXE 内嵌图标', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GameIcon(
          GameEntry(
            id: 'manual-game',
            name: '手动游戏',
            source: const GameSource.manual(),
            exePath: r'D:\Games\手动游戏\game.exe',
          ),
        ),
      ),
    );

    final icon = tester.widget<ExecutableIcon>(find.byType(ExecutableIcon));
    expect(icon.executablePath, r'D:\Games\手动游戏\game.exe');
  });

  testWidgets('主页按游玩时间显示最近运行游戏', (tester) async {
    final older = _gameView(1).game..lastPlayedAt = DateTime.utc(2026, 1, 1);
    final newer = _gameView(2).game..lastPlayedAt = DateTime.utc(2026, 1, 2);
    await tester.pumpWidget(
      MaterialApp(
        home: Home([
          GameView(
            older,
            TargetState.ready,
            const ModStatus(ModStateKind.applied),
            const ConfigStatus(ConfigStateKind.global),
          ),
          GameView(
            newer,
            TargetState.ready,
            const ModStatus(ModStateKind.applied),
            const ConfigStatus(ConfigStateKind.global),
          ),
        ], _ignoreGame),
      ),
    );

    expect(find.text('最近运行'), findsOneWidget);
    final cards = tester.widgetList<GameCard>(find.byType(GameCard)).toList();
    expect(cards.first.game.game.id, newer.id);
  });

  testWidgets('游戏库支持鼠标横向拖动', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CardRow(List.generate(6, _gameView), _ignoreGame)),
      ),
    );

    expect(find.byIcon(Icons.chevron_left), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);

    final firstCard = find.byKey(const ValueKey('home-game-game-1'));
    final initialPosition = tester.getTopLeft(firstCard);
    final mouse = await tester.startGesture(
      tester.getCenter(firstCard),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(-20, 0));
    await tester.pump();
    await mouse.moveBy(const Offset(-140, 0));
    await tester.pump();
    await mouse.up();

    expect(tester.getTopLeft(firstCard).dx, lessThan(initialPosition.dx));
  });

  testWidgets('横向拖动后会打开鼠标所在的游戏卡片', (tester) async {
    GameView? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CardRow(List.generate(6, _gameView), (game) => opened = game),
        ),
      ),
    );

    final firstCard = find.byKey(const ValueKey('home-game-game-1'));
    final secondCard = find.byKey(const ValueKey('home-game-game-2'));
    final mouse = await tester.startGesture(
      tester.getCenter(firstCard),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(-20, 0));
    await tester.pump();
    await mouse.moveBy(const Offset(-140, 0));
    await tester.pump();
    await mouse.up();

    final click = await tester.startGesture(
      tester.getCenter(secondCard),
      kind: PointerDeviceKind.mouse,
    );
    await click.up();
    expect(opened?.game.id, 'game-2');
  });

  testWidgets('横向拖动后新出现的游戏卡片可悬停', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CardRow(List.generate(6, _gameView), _ignoreGame)),
      ),
    );

    final firstCard = find.byKey(const ValueKey('home-game-game-1'));
    final fifthCard = find.byKey(const ValueKey('home-game-game-5'));
    final drag = await tester.startGesture(
      tester.getCenter(firstCard),
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveBy(const Offset(-20, 0));
    await tester.pump();
    await drag.moveBy(const Offset(-1200, 0));
    await tester.pump();
    await drag.up();
    await drag.removePointer();

    final hover = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await hover.addPointer(location: const Offset(1, 1));
    await hover.moveTo(tester.getCenter(fifthCard));
    await tester.pump();

    final card = tester.widget<GameCard>(
      find.descendant(of: fifthCard, matching: find.byType(GameCard)),
    );
    expect(card.selected, isTrue);
  });

  testWidgets('驱动程序页显示未下载锁定状态', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Drivers(
          ManagerInfo(
            dataDirectory: 'data',
            installedVersion: null,
            modAvailable: false,
          ),
          null,
          false,
          false,
          _ignore,
        ),
      ),
    );
    expect(find.text('正在检查驱动程序更新'), findsOneWidget);
    expect(find.text('已安装版本'), findsOneWidget);
  });

  testWidgets('驱动程序页顶部显示更新，底部显示已安装版本', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Drivers(
          ManagerInfo(
            dataDirectory: 'data',
            installedVersion: '0.2.0',
            modAvailable: true,
          ),
          '0.3.0',
          false,
          false,
          _ignore,
        ),
      ),
    );

    expect(find.text('有可用的驱动程序更新'), findsOneWidget);
    expect(find.text('最新版本：0.3.0'), findsOneWidget);
    expect(find.text('已安装版本'), findsOneWidget);
    expect(find.text('0.2.0'), findsOneWidget);
  });

  testWidgets('驱动程序页显示下载百分比和已下载大小', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Drivers(
          ManagerInfo(
            dataDirectory: 'data',
            installedVersion: null,
            modAvailable: false,
          ),
          '0.3.0',
          false,
          true,
          _ignore,
          progress: DownloadProgress(
            phase: DownloadPhase.downloading,
            downloadedBytes: 512 * 1024,
            totalBytes: 1024 * 1024,
          ),
        ),
      ),
    );

    expect(find.text('已下载 512 KB / 1.0 MB (50%)'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('悬停游戏卡片时显示设置和启动操作', (tester) async {
    var settingsOpened = 0;
    var launched = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameCard(
            _gameView(1),
            () => settingsOpened++,
            launch: () => launched++,
          ),
        ),
      ),
    );
    expect(find.text('设置'), findsNothing);
    expect(find.text('启动'), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(GameCard)));
    await tester.pump();

    expect(find.text('设置'), findsOneWidget);
    expect(find.text('启动'), findsOneWidget);
    await tester.tap(find.text('设置'));
    await tester.tap(find.text('启动'));
    expect(settingsOpened, 1);
    expect(launched, 1);
  });

  testWidgets('未配置驱动的游戏仍可启动', (tester) async {
    var launched = 0;
    final game = GameView(
      GameEntry(
        id: 'unconfigured',
        name: '未配置游戏',
        source: const GameSource.manual(),
      ),
      TargetState.ready,
      const ModStatus(ModStateKind.notApplied),
      const ConfigStatus(ConfigStateKind.global),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GameCard(game, () {}, launch: () => launched++)),
      ),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(GameCard)));
    await tester.pump();

    final launchButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '启动'),
    );
    expect(launchButton.onPressed, isNotNull);
    await tester.tap(find.text('启动'));
    expect(launched, 1);
  });

  testWidgets('游戏卡片始终显示启动操作', (tester) async {
    var launched = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameCard(_gameView(1), () {}, launch: () => launched++),
        ),
      ),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(GameCard)));
    await tester.pump();

    final launchButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '启动'),
    );
    expect(launchButton.onPressed, isNotNull);
    await tester.tap(find.text('启动'));
    expect(launched, 1);
  });

  testWidgets('长按游戏列表条目会移除游戏', (tester) async {
    GameView? removed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameList(
            [_gameView(1)],
            null,
            (_) {},
            _ignore,
            (game) => removed = game,
          ),
        ),
      ),
    );

    await tester.longPress(find.text('游戏 1'));
    expect(removed?.game.id, 'game-1');
  });
}

class _FakeManager implements ModManager {
  _FakeManager({this.games = const []});

  final List<GameView> games;
  int listCalls = 0;
  int refreshCalls = 0;
  int launchCalls = 0;

  @override
  Future<List<GameView>> listGames() async {
    listCalls++;
    return games;
  }

  @override
  Future<void> launchGame(String id) async {
    launchCalls++;
    throw ProcessException(
      'game.exe',
      const [],
      '无法以管理员权限启动游戏 (Win32: 1223)',
      1223,
    );
  }

  @override
  Future<String> refreshModFromGithub({
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    refreshCalls++;
    throw StateError('下载失败');
  }

  @override
  Future<String> latestDriverVersion() async => '1.0';

  @override
  ManagerInfo get info => const ManagerInfo(
    dataDirectory: 'test',
    installedVersion: null,
    modAvailable: false,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _ignore() {}
void _ignoreGame(GameView _) {}

GameView _gameView(int index) => GameView(
  GameEntry(
    id: 'game-$index',
    name: '游戏 $index',
    source: const GameSource.manual(),
  ),
  TargetState.ready,
  const ModStatus(ModStateKind.applied),
  const ConfigStatus(ConfigStateKind.global),
);
