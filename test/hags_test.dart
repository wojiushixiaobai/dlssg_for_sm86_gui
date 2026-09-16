import 'package:dlssg_for_sm86_manager/hags.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HAGS 状态', () {
    test('HwSchMode=2 表示已启用', () {
      expect(
        hagsStatusFromHwSchMode(2),
        HardwareAcceleratedGpuSchedulingStatus.enabled,
      );
    });

    test('其他已读取的值表示未启用，缺失值表示无法读取', () {
      expect(
        hagsStatusFromHwSchMode(1),
        HardwareAcceleratedGpuSchedulingStatus.disabled,
      );
      expect(
        hagsStatusFromHwSchMode(null),
        HardwareAcceleratedGpuSchedulingStatus.unavailable,
      );
    });
  });
}
