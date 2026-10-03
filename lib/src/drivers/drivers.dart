part of '../../app.dart';

String _formatBytes(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _DriverDownloadProgress extends StatelessWidget {
  const _DriverDownloadProgress(this.progress);

  final DownloadProgress? progress;

  @override
  Widget build(BuildContext context) {
    final current = progress;
    final fraction = current?.fraction;
    final verifying = current?.phase == DownloadPhase.verifying;
    final detail = current == null
        ? '正在准备下载…'
        : verifying
        ? '下载完成，正在校验驱动程序包…'
        : fraction == null
        ? '已下载 ${_formatBytes(current.downloadedBytes)}'
        : '已下载 ${_formatBytes(current.downloadedBytes)} / '
              '${_formatBytes(current.totalBytes!)} '
              '(${(fraction * 100).toStringAsFixed(0)}%)';
    final title = verifying ? '正在校验…' : '正在下载……';
    final percent = fraction == null ? null : '${(fraction * 100).round()}%';
    return Semantics(
      label: detail,
      value: percent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: _uiEmphasisWeight,
                ),
              ),
              const Spacer(),
              if (percent != null)
                Text(
                  percent,
                  style: const TextStyle(fontWeight: _uiEmphasisWeight),
                ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: verifying ? 1 : fraction,
            minHeight: 4,
            color: _accent,
            backgroundColor: _raisedSurface,
          ),
          const SizedBox(height: 6),
          Text(detail, style: const TextStyle(color: _secondaryText)),
        ],
      ),
    );
  }
}

class Drivers extends StatelessWidget {
  const Drivers(
    this.info,
    this.latestVersion,
    this.updateCheckFailed,
    this.busy,
    this.download, {
    this.progress,
    super.key,
  });
  final ManagerInfo? info;
  final String? latestVersion;
  final bool updateCheckFailed;
  final bool busy;
  final VoidCallback download;
  final DownloadProgress? progress;
  @override
  Widget build(BuildContext c) {
    final ready = info?.modAvailable == true;
    final installedVersion = info?.installedVersion;
    final updateAvailable =
        latestVersion != null && latestVersion != installedVersion;
    final upToDate = ready && latestVersion == installedVersion;
    final updateTitle = updateCheckFailed
        ? '暂时无法检查更新'
        : updateAvailable
        ? ready
              ? '有可用的驱动程序更新'
              : '有可用的驱动程序'
        : upToDate
        ? '驱动程序已是最新版本'
        : '正在检查驱动程序更新';
    final updateDetail = updateCheckFailed
        ? '请检查网络连接后重试。'
        : latestVersion != null
        ? '最新版本：$latestVersion'
        : '正在获取最新版本信息…';
    final downloadLabel = updateAvailable
        ? '下载'
        : ready
        ? '重新下载'
        : '下载';
    final updateInfo = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          updateAvailable ? '新 - DLSSG for SM86 驱动程序' : 'DLSSG for SM86 驱动程序',
          style: const TextStyle(fontSize: 16, fontWeight: _uiEmphasisWeight),
        ),
        const SizedBox(height: 3),
        Text(updateDetail, style: const TextStyle(color: _secondaryText)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            const Text('已安装版本', style: TextStyle(color: _secondaryText)),
            Text(installedVersion ?? '尚未安装'),
          ],
        ),
      ],
    );
    final downloadControl = busy
        ? _DriverDownloadProgress(progress)
        : Align(
            alignment: Alignment.centerRight,
            child: DesktopButton(onPressed: download, label: downloadLabel),
          );
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 30),
      children: [
        Row(
          children: [
            Icon(
              updateCheckFailed
                  ? Icons.cloud_off_rounded
                  : upToDate
                  ? Icons.check_circle_outline_rounded
                  : Icons.system_update_alt_rounded,
              size: 18,
              color: upToDate ? _success : _accent,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                updateTitle,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: _uiEmphasisWeight,
                ),
              ),
            ),
          ],
        ),
        const Divider(height: 26),
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth < 680
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    updateInfo,
                    const SizedBox(height: 16),
                    SizedBox(width: double.infinity, child: downloadControl),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: updateInfo),
                    const SizedBox(width: 34),
                    SizedBox(width: 250, child: downloadControl),
                  ],
                ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _surfaceBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '最新版本会从 sdli1995/dlssg_for_sm86 的 GitHub latest Release 获取。下载完成后会校验所需 DLL 并缓存安装包；不会改动已安装游戏的 INI。',
                style: TextStyle(color: _secondaryText, height: 1.55),
              ),
              const SizedBox(height: 5),
              DesktopButton(onPressed: _openInstallationGuide, label: '了解安装方式'),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const Divider(height: 1),
        const SizedBox(height: 15),
        Text(
          ready ? '已安装 - DLSSG for SM86 驱动程序' : '尚未安装 - DLSSG for SM86 驱动程序',
          style: const TextStyle(fontSize: 16, fontWeight: _uiEmphasisWeight),
        ),
        const SizedBox(height: 3),
        Text(
          installedVersion == null ? '版本：尚未安装' : '版本：$installedVersion',
          style: const TextStyle(color: _secondaryText),
        ),
      ],
    );
  }
}
