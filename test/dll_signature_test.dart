import 'dart:io';

import 'package:dlssg_for_sm86_manager/dll_signature.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final pinned = trustedDlssgCertificates.first;
  test('固定证书允许有效签名和仅不信任根的自签名', () {
    for (final certificate in trustedDlssgCertificates) {
      expect(
        DllSignature(0, certificateSha256: certificate, chainErrors: 0).isDlssg,
        isTrue,
      );
      expect(
        DllSignature(
          0x800b0109,
          certificateSha256: certificate,
          chainErrors: 0x20,
        ).isDlssg,
        isTrue,
      );
    }
  });
  test('证书缺失或不在固定列表中时即使系统信任也不识别', () {
    expect(const DllSignature(0, chainErrors: 0).isDlssg, isFalse);
    expect(
      const DllSignature(
        0,
        certificateSha256: 'unknown',
        chainErrors: 0,
      ).isDlssg,
      isFalse,
    );
  });
  test('固定证书不能掩盖摘要、签名、过期、用途或链验证错误', () {
    for (final status in [
      0x80096010,
      0x800b0101,
      0x800b0110,
      0x800b0100,
      0x800b0004,
    ]) {
      expect(
        DllSignature(
          status,
          certificateSha256: pinned,
          chainErrors: 0x20,
        ).isDlssg,
        isFalse,
      );
    }
    for (final chainError in [0x21, 0x28, 0x30, 0x40]) {
      expect(
        DllSignature(
          0x800b0109,
          certificateSha256: pinned,
          chainErrors: chainError,
        ).isDlssg,
        isFalse,
      );
    }
    expect(
      DllSignature(
        0x800b0109,
        certificateSha256: pinned,
        chainErrors: 0x20,
        stepErrors: [0x80096010],
      ).isDlssg,
      isFalse,
    );
    expect(
      DllSignature(0x800b0109, certificateSha256: pinned).isDlssg,
      isFalse,
    );
  });
  test('不存在的文件和普通文本 DLL 不通过原生验证', () async {
    final root = await Directory.systemTemp.createTemp('dlssg-signature-');
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/unknown.dll');
    expect(verifyDllSignature(file.path).isDlssg, isFalse);
    await file.writeAsString('CN=DLSSG for SM86 (self-signed)');
    expect(verifyDllSignature(file.path).isDlssg, isFalse);
  });
  test('Microsoft 的系统 DLL 不属于 DLSSG', () {
    expect(
      verifyDllSignature(
        '${Platform.environment['WINDIR']}\\System32\\version.dll',
      ).isDlssg,
      isFalse,
    );
  }, skip: !Platform.isWindows);
}
