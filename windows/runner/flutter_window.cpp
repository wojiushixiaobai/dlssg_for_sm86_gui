#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <shobjidl.h>

#include <cstring>
#include <optional>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

namespace {

using PrivateExtractIcons = UINT(WINAPI *)(LPCWSTR, int, int, int, HICON *,
                                           UINT *, UINT, UINT);

std::wstring Utf8ToWide(const std::string &value) {
  if (value.empty()) return {};
  const int length = MultiByteToWideChar(CP_UTF8, 0, value.data(),
                                         static_cast<int>(value.size()),
                                         nullptr, 0);
  if (length == 0) return {};
  std::wstring result(length, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
                      result.data(), length);
  return result;
}

std::string WideToUtf8(const std::wstring &value) {
  if (value.empty()) return {};
  const int length = WideCharToMultiByte(CP_UTF8, 0, value.data(),
                                         static_cast<int>(value.size()),
                                         nullptr, 0, nullptr, nullptr);
  if (length == 0) return {};
  std::string result(length, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.data(),
                      static_cast<int>(value.size()), result.data(), length,
                      nullptr, nullptr);
  return result;
}

std::wstring ResolveShortcut(const std::wstring &path) {
  IShellLinkW *link = nullptr;
  if (FAILED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                              IID_IShellLinkW,
                              reinterpret_cast<void **>(&link)))) {
    return {};
  }
  IPersistFile *persist = nullptr;
  std::wstring target;
  if (SUCCEEDED(link->QueryInterface(IID_IPersistFile,
                                     reinterpret_cast<void **>(&persist)))) {
    if (SUCCEEDED(persist->Load(path.c_str(), STGM_READ))) {
      std::vector<wchar_t> buffer(32768, L'\0');
      if (SUCCEEDED(link->GetPath(buffer.data(),
                                  static_cast<int>(buffer.size()), nullptr,
                                  0))) {
        target = buffer.data();
      }
    }
    persist->Release();
  }
  link->Release();
  return target;
}

std::vector<uint8_t> ExtractExecutableIcon(const std::wstring &path,
                                           const int size) {
  // PrivateExtractIconsW is exported by User32, not Shell32. Looking it up
  // from Shell32 silently failed and made every game fall back to Steam art.
  const auto user32 = GetModuleHandleW(L"user32.dll");
  if (user32 == nullptr) return {};
  const auto extract_icons = reinterpret_cast<PrivateExtractIcons>(
      GetProcAddress(user32, "PrivateExtractIconsW"));
  if (extract_icons == nullptr) return {};

  HICON icon = nullptr;
  UINT icon_id = 0;
  if (extract_icons(path.c_str(), 0, size, size, &icon, &icon_id, 1, 0) == 0 ||
      icon == nullptr) {
    return {};
  }

  const HDC screen_dc = GetDC(nullptr);
  const HDC memory_dc = CreateCompatibleDC(screen_dc);
  BITMAPINFO bitmap_info = {};
  bitmap_info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bitmap_info.bmiHeader.biWidth = size;
  bitmap_info.bmiHeader.biHeight = -size;  // A top-down BGRA buffer.
  bitmap_info.bmiHeader.biPlanes = 1;
  bitmap_info.bmiHeader.biBitCount = 32;
  bitmap_info.bmiHeader.biCompression = BI_RGB;
  void *bits = nullptr;
  const HBITMAP bitmap =
      CreateDIBSection(screen_dc, &bitmap_info, DIB_RGB_COLORS, &bits, nullptr, 0);

  std::vector<uint8_t> pixels;
  if (memory_dc != nullptr && bitmap != nullptr && bits != nullptr) {
    const auto previous = SelectObject(memory_dc, bitmap);
    const size_t byte_count = static_cast<size_t>(size) * size * 4;
    std::memset(bits, 0, byte_count);
    if (DrawIconEx(memory_dc, 0, 0, icon, size, size, 0, nullptr, DI_NORMAL)) {
      pixels.assign(static_cast<uint8_t *>(bits),
                    static_cast<uint8_t *>(bits) + byte_count);
    }
    SelectObject(memory_dc, previous);
  }

  if (bitmap != nullptr) DeleteObject(bitmap);
  if (memory_dc != nullptr) DeleteDC(memory_dc);
  if (screen_dc != nullptr) ReleaseDC(nullptr, screen_dc);
  DestroyIcon(icon);
  return pixels;
}

}  // namespace

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  executable_icon_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "dlssg/executable-icon",
          &flutter::StandardMethodCodec::GetInstance());
  executable_icon_channel_->SetMethodCallHandler(
      [](const auto &call, auto result) {
        if (call.method_name() != "extract") {
          result->NotImplemented();
          return;
        }
        const auto *arguments = std::get_if<flutter::EncodableMap>(call.arguments());
        if (arguments == nullptr) {
          result->Error("invalid-arguments");
          return;
        }
        const auto path = arguments->find(flutter::EncodableValue("path"));
        if (path == arguments->end() || !std::holds_alternative<std::string>(path->second)) {
          result->Error("invalid-arguments");
          return;
        }
        const auto wide_path = Utf8ToWide(std::get<std::string>(path->second));
        const auto pixels = ExtractExecutableIcon(wide_path, 128);
        if (pixels.empty()) {
          result->Success();
          return;
        }
        flutter::EncodableMap icon;
        icon[flutter::EncodableValue("size")] = flutter::EncodableValue(128);
        icon[flutter::EncodableValue("pixels")] = flutter::EncodableValue(pixels);
        result->Success(flutter::EncodableValue(icon));
      });
  file_drop_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "dlssg/file-drop",
          &flutter::StandardMethodCodec::GetInstance());
  file_drop_channel_->SetMethodCallHandler(
      [](const auto &call, auto result) {
        if (call.method_name() != "resolveShortcut") {
          result->NotImplemented();
          return;
        }
        const auto *path = std::get_if<std::string>(call.arguments());
        if (path == nullptr) {
          result->Error("invalid-arguments");
          return;
        }
        const auto target = ResolveShortcut(Utf8ToWide(*path));
        if (target.empty()) {
          result->Error("invalid-shortcut", "Shortcut target is unavailable");
          return;
        }
        result->Success(flutter::EncodableValue(WideToUtf8(target)));
      });
  flutter_view_window_ = flutter_controller_->view()->GetNativeWindow();
  SetChildContent(flutter_view_window_);
  DragAcceptFiles(GetHandle(), TRUE);
  if (SetWindowSubclass(flutter_view_window_, DropSubclassProc, 1,
                        reinterpret_cast<DWORD_PTR>(this))) {
    DragAcceptFiles(flutter_view_window_, TRUE);
  }

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_view_window_ != nullptr && IsWindow(flutter_view_window_)) {
    DragAcceptFiles(flutter_view_window_, FALSE);
    RemoveWindowSubclass(flutter_view_window_, DropSubclassProc, 1);
  }
  flutter_view_window_ = nullptr;
  if (GetHandle() != nullptr) DragAcceptFiles(GetHandle(), FALSE);
  file_drop_channel_ = nullptr;
  executable_icon_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT CALLBACK FlutterWindow::DropSubclassProc(
    HWND window, UINT message, WPARAM wparam, LPARAM lparam, UINT_PTR id,
    DWORD_PTR data) {
  if (message == WM_DROPFILES) {
    reinterpret_cast<FlutterWindow *>(data)->HandleFileDrop(
        reinterpret_cast<HDROP>(wparam));
    return 0;
  }
  return DefSubclassProc(window, message, wparam, lparam);
}

void FlutterWindow::HandleFileDrop(HDROP drop) {
  const UINT count = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
  flutter::EncodableList paths;
  for (UINT i = 0; i < count; ++i) {
    const UINT length = DragQueryFileW(drop, i, nullptr, 0);
    std::wstring path(length + 1, L'\0');
    DragQueryFileW(drop, i, path.data(), length + 1);
    path.resize(length);
    paths.emplace_back(WideToUtf8(path));
  }
  DragFinish(drop);
  if (file_drop_channel_ && !paths.empty()) {
    file_drop_channel_->InvokeMethod(
        "files", std::make_unique<flutter::EncodableValue>(paths));
  }
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_DROPFILES:
      HandleFileDrop(reinterpret_cast<HDROP>(wparam));
      return 0;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
