# DLSSG for SM86 Manager

`%LOCALAPPDATA%\dlssg_for_sm86_gui` 配置文件路径。

## 开发

需要 Flutter stable，以及 Visual Studio 的 **Desktop development with C++** 工作负载（MSVC、CMake tools、Windows SDK）。

```powershell
flutter pub get
flutter test
```

## 发布

```powershell
.\tool\package_windows.ps1
```

脚本生成 `release/dlssg-for-sm86-manager-portable.zip`。解压后直接运行。

## 配置

仅保留两层配置：`data\global.ini` 是全局默认配置，安装驱动程序时会写入游戏目录；
用户在某游戏的设置页面修改参数后，会将该游戏标记为自定义配置。修改全局配置会同步
到所有仍使用全局配置的已安装游戏；游戏自定义配置不会被覆盖，且可随时恢复为全局配置。
