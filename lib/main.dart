import 'package:flutter/material.dart';

import 'app.dart';
import 'manager.dart';

export 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var firstLaunch = false;
  final manager = await ModManager.open(
    onFirstLaunch: () async {
      firstLaunch = true;
      runApp(const InitializationApp());
      await WidgetsBinding.instance.endOfFrame;
    },
  );
  final initialGames = firstLaunch ? await manager.listGames() : null;
  runApp(DlssgApp(manager, initialGames: initialGames));
}
