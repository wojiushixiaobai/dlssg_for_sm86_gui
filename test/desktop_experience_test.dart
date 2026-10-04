import 'dart:io';

import 'package:dlssg_for_sm86_manager/app.dart';
import 'package:dlssg_for_sm86_manager/manager.dart';
import 'package:dlssg_for_sm86_manager/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('dlssg/app-info'), (
          call,
        ) async {
          expect(call.method, 'version');
          return '1.1.1';
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('dlssg/app-info'), null);
  });
  for (final size in [const Size(1280, 800), const Size(800, 700)]) {
    testWidgets('桌面主题在 ${size.width.toInt()} 宽度下可导航、搜索和切换设置', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(DlssgApp(_TestManager(), initialGames: _games));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('添加游戏'), findsNothing);
      expect(find.text('v1.1.1'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(DesktopNavigation),
          matching: find.text('驱动'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('最新版本：0.3.0'), findsOneWidget);
      final actionHeight = tester
          .getSize(find.widgetWithText(DesktopButton, '重新下载'))
          .height;
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.descendant(
          of: find.byType(DesktopNavigation),
          matching: find.text('游戏'),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('添加游戏'), findsOneWidget);
      final installedTile = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Cyberpunk 2077'),
      );
      expect(installedTile.trailing, isNull);
      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Cyberpunk 2077'),
          matching: find.byIcon(Icons.check_circle),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Alan Wake 2'),
          matching: find.byIcon(Icons.check_circle),
        ),
        findsNothing,
      );
      expect(
        tester.getSize(find.widgetWithText(DesktopButton, '启动游戏')).height,
        actionHeight,
      );
      final search = find.widgetWithText(TextField, '搜索游戏');
      await tester.enterText(search, 'Alan Wake 2');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Alan Wake 2'));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.widgetWithText(DesktopButton, '安装')).height,
        actionHeight,
      );
      await tester.enterText(search, 'horizon');
      await tester.pumpAndSettle();
      final list = find.byType(GameList);
      expect(
        find.descendant(
          of: list,
          matching: find.text('Horizon Forbidden West'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: list, matching: find.text('Cyberpunk 2077')),
        findsNothing,
      );
      await tester.tap(find.text('Horizon Forbidden West'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<GameSettings>(find.byType(GameSettings)).view?.game.id,
        'game-1',
      );
      await tester.tap(find.byTooltip('清除搜索'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: list, matching: find.text('Cyberpunk 2077')),
        findsOneWidget,
      );
      await tester.tap(find.text('全局设置'));
      await tester.pumpAndSettle();
      expect(find.text('全局配置'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('分段设置可用键盘激活，减少动画时卡片不缩放', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(DlssgApp(_TestManager(), initialGames: _games));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(DesktopNavigation),
        matching: find.text('游戏'),
      ),
    );
    await tester.pumpAndSettle();
    Focus.of(tester.element(find.text('全局设置'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(GlobalSettings), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: SizedBox(
              width: 265,
              height: 215,
              child: GameCard(_games.first, () {}, selected: true),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).duration,
      Duration.zero,
    );
    expect(tester.takeException(), isNull);
  });
}

final _games = [
  for (var index = 0; index < 4; index++)
    GameView(
      GameEntry(
        id: 'game-$index',
        name: [
          'Cyberpunk 2077',
          'Horizon Forbidden West',
          '黑神话：悟空',
          'Alan Wake 2',
        ][index],
        source: const GameSource.manual(),
      ),
      TargetState.ready,
      ModStatus(
        index == 3 ? ModStateKind.notApplied : ModStateKind.applied,
        version: '0.3.0',
      ),
    ),
];

class _TestManager implements ModManager {
  @override
  List<String> get availableProxies => proxies;

  @override
  File get artworkSourcesFile =>
      File('${Directory.systemTemp.path}/dlssg-ui-test-artwork.json');
  @override
  ManagerInfo get info =>
      const ManagerInfo(installedVersion: '0.3.0', modAvailable: true);
  @override
  Future<String> latestDriverVersion() async => '0.3.0';
  @override
  Future<List<GameView>> listGames() async => _games;
  @override
  Future<ConfigProfile> loadGameConfig(String id) async => _profile;
  @override
  Future<ConfigProfile> loadGlobalConfig() async => _profile;
  ConfigProfile get _profile =>
      ModManager.parseProfile('[General]\nEnabled=1\n[DLSSG]\nEnable=1\n');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
