part of '../../app.dart';

class _HagsWarning extends StatelessWidget {
  const _HagsWarning({required this.status});

  final HardwareAcceleratedGpuSchedulingStatus status;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.warning_amber_rounded, color: Colors.white54),
      const SizedBox(width: 10),
      Expanded(
        child: Text(switch (status) {
          HardwareAcceleratedGpuSchedulingStatus.disabled => '硬件加速 GPU 调度未开启',
          HardwareAcceleratedGpuSchedulingStatus.unavailable =>
            '无法读取硬件加速 GPU 调度状态',
          HardwareAcceleratedGpuSchedulingStatus.enabled => '',
        }),
      ),
      const SizedBox(width: 12),
      TextButton(
        style: _inlineActionButtonStyle,
        onPressed: _openWindowsGraphicsSettings,
        child: const Text('设置'),
      ),
    ],
  );
}
