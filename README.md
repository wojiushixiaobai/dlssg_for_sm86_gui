# DLSSG for SM86 便携版管理器

Flutter + Dart Windows x64 桌面程序。全部状态、配置档和备份写入
`%LOCALAPPDATA%\dlssg_for_sm86_gui\data`；每个 Mod 版本的压缩包与解压文件写入
`%LOCALAPPDATA%\dlssg_for_sm86_gui\release\<tag>`。

## 运行与开发

需要 Flutter stable，以及 Visual Studio 的 **Desktop development with C++** 工作负载（MSVC、CMake tools、Windows SDK）。Windows Flutter 插件还需要启用 Developer Mode，或者预建 `windows/flutter/ephemeral/.plugin_symlinks/file_selector_windows` 的目录联接。

```powershell
flutter pub get
flutter test
flutter run -d windows
```

## 便携版发布

```powershell
.\tool\package_windows.ps1
```

脚本生成 `release/dlssg-for-sm86-manager-portable.zip`。解压后直接运行
`dlssg-for-sm86-manager.exe`；首次运行会在 `%LOCALAPPDATA%` 创建配置目录。启动自动扫描 Steam 游戏。

Mod 更新来源为 `wojiushixiaobai/dlssg_for_sm86_gui` 的 GitHub Releases。每日工作流读取
`sdli1995/dlssg_for_sm86` 的 `main` 提交，以其短 SHA 创建同名 Release，并仅上传
`dlssg_for_sm86.tar.gz`。管理器从仓库根目录的 `mod-hash-catalog.json` 取得完整提交 SHA；
只有 `%LOCALAPPDATA%\dlssg_for_sm86_gui\release\<短SHA>\dlssg_for_sm86.tar.gz`
不存在时才下载对应 Release 资产。压缩包和解压的运行文件都保存在该 `<短SHA>` 目录内。

## 上游 DLL 哈希目录

`Build upstream DLL hash catalog` 工作流每日或手动运行时，都会使用
`git clone --mirror` 完整镜像 `sdli1995/dlssg_for_sm86` 的全部分支和标签历史，
生成仓库根目录的 [mod-hash-catalog.json](mod-hash-catalog.json)，并提交到 `main`，
供管理器读取；该文件不会作为 Release 附件发布。

JSON 的 `latest.files` 只包含当前运行包的 `version.dll` 和
`altnative/*.dll`；`historical.files` 包含其余历史 DLL（包括保留在 `archive/`
目录内的旧包）。每个条目记录 `path`、`file_name`、`sha256` 与出现过的提交。
管理器会将命中 `latest` 的游戏 DLL 显示为最新，将仅命中 `historical` 的 DLL
显示为“需要更新”。
