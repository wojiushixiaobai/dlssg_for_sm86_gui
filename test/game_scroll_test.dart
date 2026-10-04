import 'dart:async';
import 'dart:io';

import 'package:dlssg_for_sm86_manager/app.dart';
import 'package:dlssg_for_sm86_manager/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('300 个游戏跳到列表底部只读取可见区域的图标', (tester) async {
    tester.view.physicalSize = const Size(800, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var fileReads = 0;
    final callerZone = Zone.current;
    await IOOverrides.runZoned(
      () async {
        final games = List.generate(
          300,
          (index) => GameView(
            GameEntry(
              id: '$index',
              name: 'Game ${index.toString().padLeft(3, '0')}',
              source: const GameSource.manual(),
              exePath: 'scroll-test-$index.exe',
            ),
            TargetState.ready,
            const ModStatus(ModStateKind.notApplied),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: GameList(games, null, (_) {}, () {}, (_) {})),
          ),
        );
        final scrollable = tester.state<ScrollableState>(
          find.descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          ),
        );
        fileReads = 0;
        scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
        await tester.pump();
        expect(find.text('Game 299'), findsOneWidget);
        expect(fileReads, lessThan(30), reason: '跳转不能逐个构建并读取中间的游戏');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
      createFile: (path) {
        if (path.startsWith('scroll-test-')) fileReads++;
        return callerZone.run(() => File(path));
      },
    );
  });

  testWidgets('图标请求复用缓存，移除与重建组件不会重复提取或释放其他组件的图像', (tester) async {
    final directory = Directory.systemTemp.createTempSync('dlssg-icon-cache-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final exe = File('${directory.path}/game.exe')..writeAsStringSync('exe');
    const channel = MethodChannel('dlssg/executable-icon');
    var requests = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      requests++;
      return {
        'size': 1,
        'pixels': Uint8List.fromList([0, 0, 255, 255]),
      };
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    Widget icons(int count) => MaterialApp(
      home: Row(
        children: [
          for (var index = 0; index < count; index++)
            ExecutableIcon(
              key: ValueKey(index),
              executablePath: exe.path,
              fallback: const SizedBox(width: 10, height: 10),
            ),
        ],
      ),
    );
    Future<void> loadIcons(int count) async {
      await tester.pumpWidget(icons(count));
      await tester.runAsync(() async {
        // Let async file metadata and image decoding finish on the real loop.
        for (var attempt = 0; attempt < 100; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
          if (find.byType(RawImage).evaluate().length == count) return;
        }
        fail('图标未完成加载');
      });
    }

    await loadIcons(2);
    expect(requests, 1);
    await loadIcons(1);
    await tester.pumpWidget(const SizedBox());
    await loadIcons(2);
    expect(requests, 1);
    await tester.pumpWidget(const SizedBox());
    exe.writeAsStringSync('changed executable');
    await loadIcons(1);
    expect(requests, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
