part of '../../app.dart';

const _installationGuideUrl = 'https://github.com/sdli1995/dlssg_for_sm86';
const _repositoryUrl = 'https://github.com/wojiushixiaobai/dlssg_for_sm86_gui';

void _openInstallationGuide() =>
    _openBrowserUrl(_installationGuideUrl, '无法使用默认浏览器打开安装说明。');

void _openRepository() =>
    _openBrowserUrl(_repositoryUrl, '无法使用默认浏览器打开 GitHub 仓库。');

void _openBrowserUrl(String address, String errorMessage) {
  if (!Platform.isWindows) return;
  final operation = 'open'.toNativeUtf16();
  final url = address.toNativeUtf16();
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
      throw StateError(errorMessage);
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
