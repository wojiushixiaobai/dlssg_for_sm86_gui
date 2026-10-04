part of '../../app.dart';

class SteamArtwork extends StatefulWidget {
  const SteamArtwork({
    required this.appId,
    required this.cache,
    required this.fallback,
    super.key,
  });

  final int appId;
  final SteamArtworkCache cache;
  final Widget fallback;

  @override
  State<SteamArtwork> createState() => _SteamArtworkState();
}

class _SteamArtworkState extends State<SteamArtwork> {
  late Future<SteamArtworkSource?> _artwork;
  var _retryingNetworkSource = false;

  @override
  void initState() {
    super.initState();
    _artwork = widget.cache.load(widget.appId);
  }

  @override
  void didUpdateWidget(covariant SteamArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appId != widget.appId || oldWidget.cache != widget.cache) {
      _artwork = widget.cache.load(widget.appId);
      _retryingNetworkSource = false;
    }
  }

  void _tryNextNetworkSource(String failedUrl) {
    if (_retryingNetworkSource) return;
    _retryingNetworkSource = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final next = await widget.cache.nextNetworkSource(
        widget.appId,
        failedUrl,
      );
      if (mounted && next != null) {
        setState(() {
          _artwork = Future.value(next);
          _retryingNetworkSource = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<SteamArtworkSource?>(
    future: _artwork,
    builder: (_, snapshot) {
      final source = snapshot.data;
      if (source == null) return widget.fallback;
      return source.local
          ? Image.file(
              File(source.value),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => widget.fallback,
            )
          : Image.network(
              source.value,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) {
                _tryNextNetworkSource(source.value);
                return widget.fallback;
              },
            );
    },
  );
}

class GameIcon extends StatelessWidget {
  const GameIcon(this.game, {this.size = 40, super.key});
  final GameEntry game;
  final double size;

  @override
  Widget build(BuildContext c) {
    final appId = game.source.appId;
    const placeholder = DecoratedBox(
      decoration: BoxDecoration(color: _raisedSurface),
      child: Icon(Icons.sports_esports_outlined, color: _secondaryText),
    );
    final fallback = appId == null
        ? placeholder
        : SteamArtwork(
            appId: appId,
            cache: ArtworkCacheScope.of(c),
            fallback: placeholder,
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * .22),
      child: SizedBox(
        width: size,
        height: size,
        child: ExecutableIcon(executablePath: game.exePath, fallback: fallback),
      ),
    );
  }
}

class ExecutableIcon extends StatefulWidget {
  const ExecutableIcon({
    required this.executablePath,
    required this.fallback,
    super.key,
  });

  final String? executablePath;
  final Widget fallback;

  @override
  State<ExecutableIcon> createState() => _ExecutableIconState();
}

class _ExecutableIconState extends State<ExecutableIcon> {
  static const _channel = MethodChannel('dlssg/executable-icon');
  // Cache raw pixels, not ui.Image handles: each widget owns and disposes its
  // decoded image. Futures also coalesce simultaneous requests for one EXE.
  static final _pixels = <String, Future<Map<String, dynamic>?>>{};
  Future<ui.Image?>? _icon;
  ui.Image? _displayedImage;
  final _deferredDisposals = <ui.Image>[];

  @override
  void initState() {
    super.initState();
    _replaceIcon();
  }

  @override
  void didUpdateWidget(covariant ExecutableIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.executablePath != widget.executablePath) _replaceIcon();
  }

  void _replaceIcon() {
    final icon = _load();
    _icon = icon;
    unawaited(
      icon.then<void>((image) {
        if (!mounted || !identical(_icon, icon)) {
          image?.dispose();
          return;
        }
        final previous = _displayedImage;
        _displayedImage = image;
        if (previous != null && !identical(previous, image)) {
          // FutureBuilder still renders the previous image until it rebuilds
          // with this future's result, so release it after that frame.
          _deferredDisposals.add(previous);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_deferredDisposals.remove(previous)) previous.dispose();
          });
        }
      }, onError: (_, _) {}),
    );
  }

  @override
  void dispose() {
    _displayedImage?.dispose();
    for (final image in _deferredDisposals) {
      image.dispose();
    }
    _deferredDisposals.clear();
    super.dispose();
  }

  Future<ui.Image?> _load() async {
    final path = widget.executablePath;
    if (path == null) return null;
    try {
      final stat = await File(path).stat();
      if (stat.type != FileSystemEntityType.file) return null;
      final key =
          '${p.normalize(path).toLowerCase()}:${stat.size}:'
          '${stat.modified.microsecondsSinceEpoch}';
      final request =
          _pixels.remove(key) ??
          _channel.invokeMapMethod<String, dynamic>('extract', {'path': path});
      _pixels[key] = request;
      // 256 icons at 128x128 BGRA use at most 16 MiB of cached pixel data.
      while (_pixels.length > 256) {
        _pixels.remove(_pixels.keys.first);
      }
      final icon = await request;
      final bytes = icon?['pixels'];
      final size = icon?['size'];
      if (bytes is! Uint8List ||
          size is! int ||
          bytes.length != size * size * 4) {
        return null;
      }
      return await _decodeBgraIcon(bytes, size);
    } on FileSystemException {
      return null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<ui.Image> _decodeBgraIcon(Uint8List bytes, int size) {
    final result = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      bytes,
      size,
      size,
      ui.PixelFormat.bgra8888,
      result.complete,
      rowBytes: size * 4,
    );
    return result.future;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ui.Image?>(
    future: _icon,
    builder: (_, snapshot) => snapshot.data == null
        ? widget.fallback
        : RawImage(
            image: snapshot.data,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
  );
}
