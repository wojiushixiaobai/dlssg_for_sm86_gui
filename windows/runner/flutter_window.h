#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <commctrl.h>
#include <shellapi.h>

#include <memory>
#include <map>
#include <cstdint>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  static LRESULT CALLBACK DropSubclassProc(HWND window, UINT message,
                                           WPARAM wparam, LPARAM lparam,
                                           UINT_PTR id, DWORD_PTR data);
  void HandleFileDrop(HDROP drop);
  void CompleteIconRequests();
  struct IconWorker;
  std::shared_ptr<IconWorker> icon_worker_;
  uint64_t next_icon_request_ = 0;
  std::map<uint64_t,
           std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>>
      icon_results_;

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Serves high-resolution application icons embedded in game executables.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      executable_icon_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      file_drop_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      app_info_channel_;
  HWND flutter_view_window_ = nullptr;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
