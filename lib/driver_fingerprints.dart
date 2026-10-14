import 'dart:convert';

import 'package:flutter/services.dart';

/// Immutable indexes built from the shipped JSON catalog, shared with isolates.
class DriverFingerprintCatalog {
  DriverFingerprintCatalog._(
    this.proxyVersions,
    this.proxyVersionCandidates,
    this.runtimeFingerprints,
  );

  static const assetPath = 'driver-fingerprints.json';

  final Map<String, String> proxyVersions;
  final Map<String, List<String>> proxyVersionCandidates;
  final Map<String, Map<String, String>> runtimeFingerprints;

  /// Read once per manager startup. Do not cache asset text across reopenings.
  static Future<DriverFingerprintCatalog> load({AssetBundle? bundle}) async =>
      DriverFingerprintCatalog.fromJsonText(
        await (bundle ?? rootBundle).loadString(assetPath, cache: false),
      );

  factory DriverFingerprintCatalog.fromJsonText(String text) {
    final manifest = _object(jsonDecode(text));
    if (manifest['schema_version'] != 2 ||
        manifest['hash_algorithm'] != 'SHA-256') {
      throw const FormatException('Unsupported driver fingerprint catalog');
    }
    final candidates = <String, Set<String>>{};
    // Derive proxy indexes from source records, including archived releases.
    // Never choose one version arbitrarily when multiple tags reuse a proxy.
    for (final release in _list(manifest['tags'])) {
      for (final entry in _list(_object(release)['files'])) {
        final file = _object(entry);
        if (!file.containsKey('proxy_version')) continue;
        final version = _version(file['proxy_version']);
        final digest = _digest(file['sha256']);
        candidates.putIfAbsent(digest, () => {}).add(version);
      }
    }
    final runtimes = <String, Map<String, String>>{};
    for (final entry in _object(manifest['runtime_fingerprints']).entries) {
      final version = _version(entry.key);
      final files = <String, String>{};
      for (final file in _object(entry.value).entries) {
        final path = file.key;
        if (!path.startsWith('dlssg_sm86/') ||
            path.contains('\\') ||
            path.contains(':') ||
            path
                .split('/')
                .any((part) => part.isEmpty || part == '.' || part == '..')) {
          throw FormatException('Invalid runtime fingerprint path: $path');
        }
        files[path] = _digest(file.value);
      }
      if (runtimes.containsKey(version)) {
        throw FormatException(
          'Duplicate runtime fingerprint version: $version',
        );
      }
      runtimes[version] = Map.unmodifiable(files);
    }
    return DriverFingerprintCatalog._(
      Map.unmodifiable({
        for (final entry in candidates.entries)
          if (entry.value.length == 1) entry.key: entry.value.single,
      }),
      Map.unmodifiable({
        for (final entry in candidates.entries)
          entry.key: List<String>.unmodifiable(entry.value),
      }),
      Map.unmodifiable(runtimes),
    );
  }
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Expected a fingerprint catalog object');
  }
  return value;
}

List<dynamic> _list(Object? value) {
  if (value is! List) {
    throw const FormatException('Expected fingerprint catalog records');
  }
  return value;
}

String _digest(Object? value) {
  if (value is! String || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value)) {
    throw const FormatException('Invalid fingerprint SHA-256');
  }
  return value.toLowerCase();
}

String _version(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^[vV]?\d+\.\d+(?:\.\d+)?(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?(?:\+[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?$',
      ).hasMatch(value)) {
    throw const FormatException('Invalid fingerprint release version');
  }
  return value.replaceFirst(RegExp(r'^[vV]'), '');
}
