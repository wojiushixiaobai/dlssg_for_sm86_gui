part of '../../app.dart';

const _installationGuideUrl = 'https://github.com/sdli1995/dlssg_for_sm86';

void _openInstallationGuide() {
  if (!Platform.isWindows) return;
  final operation = 'open'.toNativeUtf16();
  final url = _installationGuideUrl.toNativeUtf16();
  try {
    final result = ShellExecute(
      0,
      operation,
      url,
      nullptr,
      nullptr,
      SW_SHOWNORMAL,
    );
    if (result <= 32) {
      throw StateError('无法使用默认浏览器打开安装说明。');
    }
  } finally {
    calloc.free(operation);
    calloc.free(url);
  }
}

void _openWindowsGraphicsSettings() {
  if (!Platform.isWindows) return;
  final operation = 'open'.toNativeUtf16();
  final target = 'ms-settings:display-advancedgraphics'.toNativeUtf16();
  try {
    final result = ShellExecute(
      0,
      operation,
      target,
      nullptr,
      nullptr,
      SW_SHOWNORMAL,
    );
    if (result <= 32) {
      throw StateError('无法打开 Windows 图形设置。');
    }
  } finally {
    calloc.free(operation);
    calloc.free(target);
  }
}
