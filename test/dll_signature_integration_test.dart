import 'dart:io';
import 'dart:typed_data';

import 'package:dlssg_for_sm86_manager/dll_signature.dart';
import 'package:dlssg_for_sm86_manager/manager.dart';
import 'package:dlssg_for_sm86_manager/models.dart';
import 'package:dlssg_for_sm86_manager/steam.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _EmptyScanner extends SteamScanner {
  @override
  Future<List<GameEntry>> scan({required List<GameEntry> existing}) async =>
      existing;
  @override
  Future<Map<String, int>> manifestModificationTimes() async => {};
}

int _securityDirectory(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final optional = data.getUint32(0x3c, Endian.little) + 24;
  final directoryOffset = data.getUint16(optional, Endian.little) == 0x20b
      ? 112
      : 96;
  return optional + directoryOffset + 4 * 8;
}

void main() {
  final fixtureRoot = Platform.environment['DLSSG_SIGNATURE_FIXTURE_ROOT'];
  group(
    '实际上游 DLL 签名',
    () {
      late Directory root;
      setUp(() async {
        root = await Directory.systemTemp.createTemp('dlssg-signed-fixture-');
      });
      tearDown(() => root.delete(recursive: true));

      File fixture(String relative) => File(p.join(fixtureRoot!, relative));

      test('两代证书和各代理均能通过验证', () {
        for (final path in [
          'version.dll',
          '310.1/version.dll',
          'archive/0.2.4/version.dll',
          for (final proxy in proxies.where((value) => value != defaultProxy))
            'alternatives/$proxy',
        ]) {
          final signature = verifyDllSignature(fixture(path).path);
          expect(
            signature.isDlssg,
            isTrue,
            reason: '$path: ${signature.status.toRadixString(16)}',
          );
        }
        expect(
          verifyDllSignature(fixture('archive/0.1.0/version.dll').path).isDlssg,
          isFalse,
        );
      });

      test('篡改 PE 内容和签名数据均被拒绝', () async {
        final bytes = await fixture('version.dll').readAsBytes();
        final data = ByteData.sublistView(bytes);
        final pe = data.getUint32(0x3c, Endian.little);
        final firstSection = pe + 24 + data.getUint16(pe + 20, Endian.little);
        final content = data.getUint32(firstSection + 20, Endian.little);
        final tampered = Uint8List.fromList(bytes);
        tampered[content + 16] ^= 1;
        final target = File(p.join(root.path, 'tampered.dll'));
        await target.writeAsBytes(tampered);
        expect(verifyDllSignature(target.path).isDlssg, isFalse);

        final certificate = data.getUint32(
          _securityDirectory(bytes),
          Endian.little,
        );
        bytes[certificate + 8] ^=
            1; // corrupt the PKCS#7 ASN.1 tag, not excluded padding
        await target.writeAsBytes(bytes);
        expect(verifyDllSignature(target.path).isDlssg, isFalse);
      });

      test('将可信证书表移植到另一个 DLL 不能通过验证', () async {
        final signed = await fixture('version.dll').readAsBytes();
        final signedData = ByteData.sublistView(signed);
        final directory = _securityDirectory(signed);
        final offset = signedData.getUint32(directory, Endian.little);
        final length = signedData.getUint32(directory + 4, Endian.little);
        final unsigned = await fixture('archive/0.1.0/version.dll')
            .readAsBytes();
        final appendAt = (unsigned.length + 7) & ~7;
        final forged = Uint8List(appendAt + length)..setAll(0, unsigned);
        forged.setAll(appendAt, signed.sublist(offset, offset + length));
        final forgedData = ByteData.sublistView(forged);
        final forgedDirectory = _securityDirectory(forged);
        forgedData.setUint32(forgedDirectory, appendAt, Endian.little);
        forgedData.setUint32(forgedDirectory + 4, length, Endian.little);
        final target = File(p.join(root.path, 'forged.dll'));
        await target.writeAsBytes(forged);
        expect(verifyDllSignature(target.path).isDlssg, isFalse);
      });

      test('无记录的旧签名代理升级时不要求覆盖确认、不产生原始 DLL 备份', () async {
        final manager = await ModManager.open(
          dataDirectory: root,
          scanner: _EmptyScanner(),
        );
        addTearDown(manager.client.close);
        final package = Directory(
          p.join(root.path, 'release', 'dlssg_for_sm86'),
        );
        await package.create(recursive: true);
        await File(p.join(package.path, defaultProxy))
            .writeAsString('new-driver');
        await File(p.join(package.path, 'dlssg_sm86.ini'))
            .writeAsString('[General]\nEnabled=1\n');
        manager.db.installedVersion = 'new';
        final exe = File(p.join(root.path, 'game', 'game.exe'));
        await exe.parent.create();
        await exe.writeAsString('exe');
        await fixture('archive/0.2.4/version.dll')
            .copy(p.join(exe.parent.path, defaultProxy));
        final game = await manager.addManualGame('Game', exe.path);
        await manager.installMod(game.id);
        expect(game.backups, isEmpty);
        expect((await manager.listGames()).single.mod.version, 'new');
        await manager.uninstallMod(game.id);
        expect(
          await File(p.join(exe.parent.path, defaultProxy)).exists(),
          isFalse,
        );
      });

      for (final relative in [
        'archive/0.1.0/version.dll',
        'archive/0.2.4/version.dll',
        'alternatives/winmm.dll',
      ]) {
        test('无安装记录时识别并卸载 $relative，保留其他 DLL', () async {
          final manager = await ModManager.open(
            dataDirectory: root,
            scanner: _EmptyScanner(),
          );
          addTearDown(manager.client.close);
          final exe = File(p.join(root.path, 'game', 'game.exe'));
          await exe.parent.create();
          await exe.writeAsString('exe');
          final proxy = p.basename(relative);
          final target = await fixture(relative)
              .copy(p.join(exe.parent.path, proxy));
          final other = File(p.join(exe.parent.path, 'dbghelp.dll'));
          await other.writeAsString('game-original');
          final ini = File(p.join(exe.parent.path, 'dlssg_sm86.ini'));
          await ini.writeAsString('[General]\nEnabled=1\n');
          final game = await manager.addManualGame('Game', exe.path);
          final status = (await manager.listGames()).single.mod;
          expect(status.kind, ModStateKind.applied);
          expect(status.proxy, proxy);
          expect(status.version, relative.contains('0.1.0') ? '0.1.0' : '未知版本');
          await manager.uninstallMod(game.id);
          expect(await target.exists(), isFalse);
          expect(await ini.exists(), isFalse);
          expect(await other.readAsString(), 'game-original');
        });
      }
    },
    skip: !Platform.isWindows || fixtureRoot == null
        ? '设置 DLSSG_SIGNATURE_FIXTURE_ROOT 以运行真实 DLL 测试'
        : false,
  );
}
