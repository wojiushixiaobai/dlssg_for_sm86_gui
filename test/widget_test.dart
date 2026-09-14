import 'package:flutter/gestures.dart';
import 'package:dlssg_for_sm86_manager/main.dart';
import 'package:dlssg_for_sm86_manager/manager.dart';
import 'package:dlssg_for_sm86_manager/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('主页无游戏时不显示游戏库栏目', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Home([], _ignoreGame)));
    expect(find.text('Steam 库'), findsNothing);
    expect(find.text('其他游戏库'), findsNothing);
    expect(find.byType(GameCard), findsNothing);
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

  testWidgets('游戏库切换时仅显示可用方向的居中箭头', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CardRow(List.generate(6, _gameView), _ignoreGame)),
      ),
    );

    expect(find.byIcon(Icons.chevron_left), findsNothing);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.chevron_left), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.chevron_right), findsNothing);
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

  testWidgets('未配置驱动的游戏禁用启动按钮', (tester) async {
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
    expect(launchButton.onPressed, isNull);
    await tester.tap(find.text('启动'));
    expect(launched, 0);
  });

  testWidgets('已启动的游戏显示运行中并禁用启动按钮', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameCard(_gameView(1), () {}, launch: _ignore, running: true),
        ),
      ),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(GameCard)));
    await tester.pump();

    final launchButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '运行中'),
    );
    expect(launchButton.onPressed, isNull);
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
