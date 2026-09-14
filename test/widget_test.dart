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
            knownHashes: 0,
            globalProfile: null,
            modAvailable: false,
          ),
          false,
          _ignore,
        ),
      ),
    );
    expect(find.text('下载 Mod 后开始配置'), findsOneWidget);
    expect(find.text('配置功能已禁用'), findsOneWidget);
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
      const ConfigStatus(ConfigStateKind.defaultConfig),
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
  const ConfigStatus(ConfigStateKind.defaultConfig),
);
