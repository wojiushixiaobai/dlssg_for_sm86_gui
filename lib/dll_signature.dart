import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

// SHA-256 of the complete DER signing certificate, not its display name.
// See docs/dll-identification.md for provenance and the update procedure.
const trustedDlssgCertificates = {
  '080e89dcd7f0c8c67b32639938f9212e8636970eb9365247f457797422a1f47f',
  '03055e992aca440499639451bbd2021276a6d324ea9a650240a382b8b547f959',
};

const _untrustedRoot = 0x800b0109;

class DllSignature {
  const DllSignature(
    this.status, {
    this.certificateSha256,
    this.chainErrors,
    this.stepErrors = const [],
  });

  final int status;
  final String? certificateSha256;
  final int? chainErrors;
  final List<int> stepErrors;

  bool get isDlssg =>
      trustedDlssgCertificates.contains(certificateSha256) &&
      (status == 0 || status == _untrustedRoot) &&
      (chainErrors == 0 ||
          chainErrors == 0x20) && // CERT_TRUST_IS_UNTRUSTED_ROOT only
      stepErrors.every((error) => error == 0 || error == _untrustedRoot);
}

/// Verifies embedded Authenticode signatures without loading/executing the DLL,
/// showing UI, fetching certificates online, or changing Windows trust stores.
/// Only the pinned self-signed root exception is accepted; digest, signature,
/// expiry, usage, and all other verification failures remain unknown files.
DllSignature verifyDllSignature(String path) {
  if (!Platform.isWindows) return const DllSignature(0x800b0100);
  final nativePath = File(path).absolute.path.toNativeUtf16();
  final file = calloc<_WintrustFileInfo>();
  final data = calloc<_WintrustData>();
  final action = GUIDFromString('{00AAC56B-CD44-11d0-8CC2-00C04FC295EE}');
  try {
    file.ref
      ..cbStruct = sizeOf<_WintrustFileInfo>()
      ..filePath = nativePath;
    data.ref
      ..cbStruct = sizeOf<_WintrustData>()
      ..uiChoice =
          2 // WTD_UI_NONE
      ..unionChoice =
          1 // WTD_CHOICE_FILE: verify the outer DLL, not its payload.
      ..file = file
      ..stateAction =
          1 // WTD_STATEACTION_VERIFY
      ..providerFlags =
          0x1000 | 0x10 | 0x2000; // cache-only, no revocation, no MD2/4
    final status = _winVerifyTrust(-1, action, data) & 0xffffffff;
    if (status != 0 && status != _untrustedRoot) return DllSignature(status);
    final provider = _providerFromState(data.ref.stateData);
    if (provider == nullptr) return DllSignature(status);
    final errors = provider.ref.stepErrors;
    final count = provider.ref.stepErrorCount;
    if (errors == nullptr || count == 0 || count > 128) {
      return DllSignature(status);
    }
    final stepErrors = [provider.ref.error, ...errors.asTypedList(count)];
    final signer = _signerFromChain(provider, 0, 0, 0);
    if (signer == nullptr) return DllSignature(status);
    if (signer.ref.chain == nullptr) return DllSignature(status);
    stepErrors.add(signer.ref.error);
    final certificate = _certificateFromChain(signer, 0);
    if (certificate == nullptr || certificate.ref.context == nullptr) {
      return DllSignature(status);
    }
    final context = certificate.ref.context.ref;
    if (context.pbCertEncoded == nullptr || context.cbCertEncoded == 0) {
      return DllSignature(status);
    }
    return DllSignature(
      status,
      chainErrors: signer.ref.chain.ref.errorStatus,
      certificateSha256: sha256
          .convert(context.pbCertEncoded.asTypedList(context.cbCertEncoded))
          .toString(),
      stepErrors: stepErrors,
    );
  } finally {
    data.ref.stateAction = 2; // Every VERIFY must be paired with CLOSE.
    _winVerifyTrust(-1, action, data);
    calloc.free(action);
    calloc.free(data);
    calloc.free(file);
    calloc.free(nativePath);
  }
}

final _wintrust = DynamicLibrary.open('wintrust.dll');
final _winVerifyTrust = _wintrust
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<GUID>, Pointer<_WintrustData>),
      int Function(int, Pointer<GUID>, Pointer<_WintrustData>)
    >('WinVerifyTrust');
final _providerFromState = _wintrust
    .lookupFunction<
      Pointer<_ProviderDataPrefix> Function(Pointer<Void>),
      Pointer<_ProviderDataPrefix> Function(Pointer<Void>)
    >('WTHelperProvDataFromStateData');
final _signerFromChain = _wintrust
    .lookupFunction<
      Pointer<_ProviderSigner> Function(
        Pointer<_ProviderDataPrefix>,
        Uint32,
        Int32,
        Uint32,
      ),
      Pointer<_ProviderSigner> Function(
        Pointer<_ProviderDataPrefix>,
        int,
        int,
        int,
      )
    >('WTHelperGetProvSignerFromChain');
final _certificateFromChain = _wintrust
    .lookupFunction<
      Pointer<_ProviderCertificatePrefix> Function(
        Pointer<_ProviderSigner>,
        Uint32,
      ),
      Pointer<_ProviderCertificatePrefix> Function(
        Pointer<_ProviderSigner>,
        int,
      )
    >('WTHelperGetProvCertFromChain');

final class _WintrustFileInfo extends Struct {
  @Uint32()
  external int cbStruct;
  external Pointer<Utf16> filePath;
  external Pointer<Void> fileHandle;
  external Pointer<GUID> knownSubject;
}

final class _WintrustData extends Struct {
  @Uint32()
  external int cbStruct;
  external Pointer<Void> policyCallbackData;
  external Pointer<Void> sipClientData;
  @Uint32()
  external int uiChoice;
  @Uint32()
  external int revocationChecks;
  @Uint32()
  external int unionChoice;
  external Pointer<_WintrustFileInfo> file;
  @Uint32()
  external int stateAction;
  external Pointer<Void> stateData;
  external Pointer<Utf16> urlReference;
  @Uint32()
  external int providerFlags;
  @Uint32()
  external int uiContext;
  external Pointer<Void> signatureSettings;
}

// Read-only prefixes of provider-owned structures. These are never allocated
// or passed to APIs expecting caller-supplied buffers; WinVerifyTrust owns them
// until STATEACTION_CLOSE. Field layout follows the Windows SDK wintrust.h.
final class _ProviderDataPrefix extends Struct {
  @Uint32()
  external int cbStruct;
  external Pointer<_WintrustData> wintrustData;
  @Int32()
  external int openedFile;
  external Pointer<Void> parentWindow;
  external Pointer<GUID> actionId;
  @UintPtr()
  external int cryptoProvider;
  @Uint32()
  external int error;
  @Uint32()
  external int securitySettings;
  @Uint32()
  external int policySettings;
  external Pointer<Void> functions;
  @Uint32()
  external int stepErrorCount;
  external Pointer<Uint32> stepErrors;
}

final class _ProviderCertificatePrefix extends Struct {
  @Uint32()
  external int cbStruct;
  external Pointer<CERT_CONTEXT> context;
}

final class _ProviderSigner extends Struct {
  @Uint32()
  external int cbStruct;
  external FILETIME verifiedAt;
  @Uint32()
  external int certificateCount;
  external Pointer<Void> certificates;
  @Uint32()
  external int signerType;
  external Pointer<Void> signerInfo;
  @Uint32()
  external int error;
  @Uint32()
  external int counterSignerCount;
  external Pointer<Void> counterSigners;
  external Pointer<_ChainContextPrefix> chain;
}

final class _ChainContextPrefix extends Struct {
  @Uint32()
  external int cbStruct;
  @Uint32()
  external int errorStatus;
  @Uint32()
  external int infoStatus;
}
