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
            color: _nvidiaGreen,
            backgroundColor: const Color(0xff3b3b3b),
          ),
          const SizedBox(height: 6),
          Text(detail, style: const TextStyle(color: _nvidiaMutedText)),
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
        : '正在读取上游 latest Release。';
    final pageStatus = updateCheckFailed
        ? '更新检查失败'
        : updateAvailable
        ? '有可用更新'
        : upToDate
        ? '驱动程序已是最新版本'
        : '检查更新中';
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
          style: const TextStyle(fontSize: 21, fontWeight: _uiEmphasisWeight),
        ),
        const SizedBox(height: 3),
        Text(updateDetail, style: const TextStyle(color: _nvidiaMutedText)),
        const SizedBox(height: 4),
        Row(
          children: [
            const Text('已安装版本', style: TextStyle(color: _nvidiaMutedText)),
            const SizedBox(width: 8),
            Text(installedVersion ?? '尚未安装'),
          ],
        ),
      ],
    );
    final downloadControl = busy
        ? _DriverDownloadProgress(progress)
        : Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: download,
              style: FilledButton.styleFrom(
                backgroundColor: _nvidiaGreen,
                foregroundColor: Colors.black,
                minimumSize: const Size(80, 44),
              ),
              child: Text(downloadLabel),
            ),
          );
    return ListView(
      padding: const EdgeInsets.fromLTRB(30, 18, 30, 30),
      children: [
        Row(
          children: [
            Text(
              pageStatus,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: _uiEmphasisWeight,
              ),
            ),
            const Spacer(),
            const Text(
              'DLSSG for SM86 驱动程序',
              style: TextStyle(color: _nvidiaMutedText, fontSize: 16),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.expand_more, color: _nvidiaMutedText),
          ],
        ),
        const Divider(height: 26),
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth < 920
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
                    SizedBox(width: 520, child: downloadControl),
                  ],
                ),
        ),
        const SizedBox(height: 18),
        _DriverUpdateHero(
          title: updateTitle,
          detail: updateCheckFailed
              ? '暂时无法获取上游版本信息。恢复网络后可再次下载并校验驱动程序。'
              : '下载经过校验的最新版驱动程序包，为支持的游戏启用 DLSSG for SM86。',
        ),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: _nvidiaGreen, width: 5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '最新版本会从 sdli1995/dlssg_for_sm86 的 GitHub latest Release 获取。下载完成后会校验所需 DLL 并缓存安装包；不会改动已安装游戏的 INI。',
                style: TextStyle(color: _nvidiaMutedText, height: 1.55),
              ),
              const SizedBox(height: 5),
              TextButton(
                onPressed: _openInstallationGuide,
                style: TextButton.styleFrom(
                  foregroundColor: _nvidiaText,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                ),
                child: const Text(
                  '了解安装方式',
                  style: TextStyle(fontWeight: _uiEmphasisWeight),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const Divider(height: 1),
        const SizedBox(height: 15),
        Text(
          ready ? '已安装 - DLSSG for SM86 驱动程序' : '尚未安装 - DLSSG for SM86 驱动程序',
          style: const TextStyle(fontSize: 19, fontWeight: _uiEmphasisWeight),
        ),
        const SizedBox(height: 3),
        Text(
          installedVersion == null ? '版本：尚未安装' : '版本：$installedVersion',
          style: const TextStyle(color: _nvidiaMutedText),
        ),
      ],
    );
  }
}

class _DriverUpdateHero extends StatelessWidget {
  const _DriverUpdateHero({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 224),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: const Color(0xff080a0b),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: const Color(0xff242424)),
    ),
    child: Stack(
      children: [
        Positioned(
          right: -70,
          top: -120,
          child: Container(
            width: 440,
            height: 440,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  _nvidiaGreen.withValues(alpha: 0.22),
                  const Color(0xff101a0c).withValues(alpha: 0.1),
                  Colors.transparent,
                ],
                stops: const [0, .45, 1],
              ),
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(100, 32, 28, 28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DLSSG for SM86\n驱动程序更新',
                      style: const TextStyle(
                        fontSize: 27,
                        fontWeight: _uiEmphasisWeight,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      title,
                      style: const TextStyle(
                        color: _nvidiaGreen,
                        fontWeight: _uiEmphasisWeight,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      detail,
                      style: const TextStyle(
                        color: _nvidiaMutedText,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 5,
              child: Center(
                child: Icon(
                  title.contains('失败') ? Icons.error_outline : Icons.memory,
                  size: 96,
                  color: _nvidiaGreen.withValues(alpha: 0.75),
                ),
              ),
            ),
          ],
        ),
        const Positioned(
          left: 42,
          top: 0,
          bottom: 0,
          child: VerticalDivider(width: 1, thickness: 3, color: _nvidiaGreen),
        ),
      ],
    ),
  );
}
