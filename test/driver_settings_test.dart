import 'package:dlssg_for_sm86_manager/driver_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('公开配置键拥有默认值和说明', () {
    final setting = driverSettingDefinition('FRAMEGENERATION', 'optimized');

    expect(setting?.defaultValue, '1');
    expect(setting?.description, isNotEmpty);
    expect(setting?.choices, contains('0'));
  });

  test('未在上游公开配置中定义的键保持通用编辑模式', () {
    expect(driverSettingDefinition('Advanced', 'ExperimentalKey'), isNull);
  });
}
