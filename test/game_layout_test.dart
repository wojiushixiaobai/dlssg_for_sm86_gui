import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dlssg_for_sm86_manager/game_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _UnwritableSettings implements File {
  _UnwritableSettings(this.file, {this.ignoreWrite = false});
  final File file;
  final bool ignoreWrite;
  @override
  String get path => file.path;
  @override
  Uint8List readAsBytesSync() => file.readAsBytesSync();
  @override
  List<String> readAsLinesSync({Encoding encoding = utf8}) =>
      file.readAsLinesSync(encoding: encoding);
  @override
  String readAsStringSync({Encoding encoding = utf8}) =>
      file.readAsStringSync(encoding: encoding);
  @override
  void writeAsStringSync(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) {
    if (!ignoreWrite) throw FileSystemException('Access denied', path);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory root;
  late File settings;
  late String installPath;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('dlssg-dx12-');
    settings = File(p.join(root.path, 'setting.ini'));
    installPath = p.join(root.path, 'custom-install').replaceAll('\\', '/');
  });
  tearDown(() => root.delete(recursive: true));

  test('自动开启仅修改 General 的 DX12，保留 BOM、CRLF 和其他配置', () {
    final before =
        '\uFEFF[General]\r\nInstallPath=$installPath\r\nDX12=false\r\n; comment\r\n[Other]\r\nDX12=false\r\n';
    settings.writeAsStringSync(before);
    GameLayout([], settings: settings).requireDx12();
    expect(
      settings.readAsBytesSync(),
      utf8.encode(before.replaceFirst('DX12=false', 'DX12=true')),
    );
  });

  test('缺少 DX12 时在 General 内新增且保留换行', () {
    settings.writeAsStringSync(
      '[General]\r\nInstallPath=$installPath\r\n[Other]\r\nValue=1\r\n',
    );
    GameLayout([], settings: settings).requireDx12();
    expect(
      settings.readAsStringSync(),
      '[General]\r\nDX12=true\r\nInstallPath=$installPath\r\n[Other]\r\nValue=1\r\n',
    );
  });

  test('已经开启时不尝试写入', () {
    settings.writeAsStringSync('[General]\nDX12=TRUE\n');
    GameLayout([], settings: _UnwritableSettings(settings)).requireDx12();
  });

  for (final ignoreWrite in [false, true]) {
    test(ignoreWrite ? '写入后校验失败提示手动开启' : '写入失败提示手动开启', () {
      const original = '[General]\nDX12=false\n';
      settings.writeAsStringSync(original);
      final layout = GameLayout(
        [],
        settings: _UnwritableSettings(settings, ignoreWrite: ignoreWrite),
      );
      expect(
        layout.requireDx12,
        throwsA(
          isA<StateError>()
              .having((e) => e.message, 'message', contains('手动开启'))
              .having((e) => e.message, 'path', contains(settings.path)),
        ),
      );
      expect(settings.readAsStringSync(), original);
    });
  }
}
