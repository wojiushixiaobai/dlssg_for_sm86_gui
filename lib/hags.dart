import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// The effective state of Windows Hardware-accelerated GPU scheduling.
enum HardwareAcceleratedGpuSchedulingStatus { enabled, disabled, unavailable }

/// Converts Windows' `HwSchMode` registry value to a user-facing state.
///
/// Windows writes `2` after the user enables Hardware-accelerated GPU
/// scheduling. Other present values mean it is not enabled; a missing or
/// unreadable value is deliberately reported as unavailable instead of being
/// mistaken for an explicit user choice.
HardwareAcceleratedGpuSchedulingStatus hagsStatusFromHwSchMode(int? value) =>
    switch (value) {
      2 => HardwareAcceleratedGpuSchedulingStatus.enabled,
      null => HardwareAcceleratedGpuSchedulingStatus.unavailable,
      _ => HardwareAcceleratedGpuSchedulingStatus.disabled,
    };

/// Reads the HAGS state selected in Windows Settings.
///
/// This is read-only and does not attempt to change a system-level setting.
HardwareAcceleratedGpuSchedulingStatus readHagsStatus() {
  if (!Platform.isWindows) {
    return HardwareAcceleratedGpuSchedulingStatus.unavailable;
  }

  final subKey = r'SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
      .toNativeUtf16();
  final valueName = 'HwSchMode'.toNativeUtf16();
  final type = calloc<Uint32>();
  final data = calloc<Uint32>();
  final size = calloc<Uint32>()..value = sizeOf<Uint32>();
  try {
    final result = RegGetValue(
      HKEY_LOCAL_MACHINE,
      subKey,
      valueName,
      RRF_RT_REG_DWORD,
      type,
      data.cast(),
      size,
    );
    if (result != 0 ||
        type.value != REG_DWORD ||
        size.value != sizeOf<Uint32>()) {
      return HardwareAcceleratedGpuSchedulingStatus.unavailable;
    }
    return hagsStatusFromHwSchMode(data.value);
  } finally {
    calloc.free(subKey);
    calloc.free(valueName);
    calloc.free(type);
    calloc.free(data);
    calloc.free(size);
  }
}
