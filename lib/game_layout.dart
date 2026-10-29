import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Publisher-specific deployment locations, independent of launcher location.
class GameLayout {
  const GameLayout(this.executables, {this.settings});

  final List<String> executables;
  final File? settings;

  void requireDx12() {
    final file = settings;
    if (file == null) return;
    try {
      if (_settings(file)['dx12']?.toLowerCase() == 'true') return;
      final bytes = file.readAsBytesSync();
      final hasBom =
          bytes.length >= 3 &&
          bytes[0] == 0xef &&
          bytes[1] == 0xbb &&
          bytes[2] == 0xbf;
      final original = '${hasBom ? '\uFEFF' : ''}${utf8.decode(bytes)}';
      final header = RegExp(
        r'^\uFEFF?[ \t]*\[General\][ \t]*(?=\r?$)',
        multiLine: true,
        caseSensitive: false,
      ).firstMatch(original);
      if (header == null) throw StateError('未找到 [General] 配置节');
      final rest = original.substring(header.end);
      final nextSection = RegExp(
        r'^[ \t]*\[',
        multiLine: true,
      ).firstMatch(rest);
      final end = header.end + (nextSection?.start ?? rest.length);
      final section = original.substring(header.end, end);
      final key = RegExp(
        r'^([ \t]*DX12[ \t]*=[ \t]*)[^\r\n]*',
        multiLine: true,
        caseSensitive: false,
      );
      final newline = original.contains('\r\n') ? '\r\n' : '\n';
      final updated = key.hasMatch(section)
          ? section.replaceAllMapped(key, (match) => '${match[1]}true')
          : '${newline}DX12=true$section';
      file.writeAsStringSync(
        original.substring(0, header.end) + updated + original.substring(end),
        flush: true,
      );
      if (_settings(file)['dx12']?.toLowerCase() != 'true') {
        throw StateError('写入后校验未通过');
      }
    } on Object catch (error) {
      throw StateError(
        '请在启动器设置中手动开启 DX12'
        '（${file.path}）。原因：$error',
      );
    }
  }

  static GameLayout resolve(String executable) {
    var directory = File(executable).absolute.parent;
    while (true) {
      final settings = File(
        p.join(directory.path, 'Win32', 'deploy', 'setting.ini'),
      );
      if (settings.existsSync()) {
        final values = _settings(settings);
        final install = values['installpath'];
        if (install == null || install.isEmpty) {
          throw StateError('燕云十六声 setting.ini 缺少 InstallPath。');
        }
        final path = p.normalize(
          p.isAbsolute(install) ? install : p.join(directory.path, install),
        );
        return GameLayout([
          for (final variant in ['Win64r', 'Win64rh'])
            p.join(path, 'Engine', 'Binaries', variant, 'yysls.exe'),
        ], settings: settings);
      }
      // PBZ ships an Unreal layout too, but loads its proxy in platform/steam.
      if (p.basename(directory.path).toLowerCase() == 'pbz' ||
          File(p.join(directory.path, 'platform', 'steam', 'PBZ.exe'))
              .existsSync()) {
        final target = p.join(directory.path, 'platform', 'steam', 'PBZ.exe');
        if (File(target).existsSync()) return GameLayout([target]);
      }
      final parent = directory.parent;
      if (parent.path == directory.path) break;
      directory = parent;
    }
    return GameLayout([executable]);
  }

  static Map<String, String> _settings(File file) {
    final result = <String, String>{};
    var general = false;
    for (var line in file.readAsLinesSync()) {
      line = line.replaceFirst('\uFEFF', '').trim();
      if (line.startsWith(';') || line.startsWith('#')) continue;
      if (line.startsWith('[')) {
        general = line.toLowerCase() == '[general]';
        continue;
      }
      final equals = line.indexOf('=');
      if (!general || equals < 0) continue;
      result[line.substring(0, equals).trim().toLowerCase()] = line
          .substring(equals + 1)
          .trim()
          .replaceAll(RegExp(r'^"|"$'), '');
    }
    return result;
  }
}
