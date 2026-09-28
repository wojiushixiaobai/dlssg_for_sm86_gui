import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;
import 'dart:ui' as ui show Image, PixelFormat, decodeImageFromPixels;

import 'package:ffi/ffi.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:win32/win32.dart';

import 'driver_settings.dart';
import 'hags.dart';
import 'manager.dart';
import 'models.dart';
import 'steam.dart';

// UI sections share private styling and helpers within this library.
part 'src/shared/theme.dart';
part 'src/platform/windows_links.dart';
part 'src/app/shell.dart';
part 'src/app/navigation.dart';
part 'src/home/home.dart';
part 'src/drivers/drivers.dart';
part 'src/settings/settings.dart';
part 'src/games/game_list.dart';
part 'src/games/game_settings.dart';
part 'src/settings/driver_config.dart';
part 'src/settings/hags_warning.dart';
part 'src/games/artwork.dart';
part 'src/shared/common.dart';
part 'src/settings/global_settings.dart';

class InitializationApp extends StatelessWidget {
  const InitializationApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'DLSSG for SM86 Manager',
    theme: ThemeData.dark(),
    home: Scaffold(
      backgroundColor: _nvidiaAppBackground,
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: _nvidiaGreen),
            SizedBox(height: 20),
            Text('正在检查游戏状态…'),
          ],
        ),
      ),
    ),
  );
}

class DlssgApp extends StatelessWidget {
  DlssgApp(this.manager, {this.initialGames, super.key})
    : artworkCache = SteamArtworkCache(manager.artworkSourcesFile);
  final ModManager manager;
  final List<GameView>? initialGames;
  final SteamArtworkCache artworkCache;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'DLSSG for SM86 Manager',
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: _uiFontFamily,
      fontFamilyFallback: _uiFontFallback,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _nvidiaGreen,
        brightness: Brightness.dark,
        surface: _nvidiaAppBackground,
      ),
      scaffoldBackgroundColor: _nvidiaAppBackground,
      dividerColor: const Color(0xff303030),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: _nvidiaText),
        titleMedium: TextStyle(color: _nvidiaText),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          mouseCursor: _buttonMouseCursor,
          shape: const WidgetStatePropertyAll(_controlButtonShape),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          mouseCursor: _buttonMouseCursor,
          shape: const WidgetStatePropertyAll(_controlButtonShape),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          mouseCursor: _buttonMouseCursor,
          shape: const WidgetStatePropertyAll(_controlButtonShape),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          mouseCursor: _buttonMouseCursor,
          shape: const WidgetStatePropertyAll(_controlButtonShape),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(mouseCursor: _buttonMouseCursor),
      ),
    ),
    home: ArtworkCacheScope(
      cache: artworkCache,
      child: Shell(manager, initialGames: initialGames),
    ),
  );
}
