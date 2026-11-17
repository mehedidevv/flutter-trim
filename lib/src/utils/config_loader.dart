import 'dart:io';

import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../models/sweep_item.dart';

/// Settings read from an optional `flutter_sweeper.yaml` and merged with CLI
/// flags.
///
/// ```yaml
/// exclude:
///   - lib/generated/**
///   - assets/legal/**
/// entry_points:
///   - lib/main_staging.dart
/// keep:
///   - LegacyApiClient
/// asset_directories:
///   - assets
///   - res
/// scan:
///   assets: true
///   files: true
///   code: true
///   methods: true
/// ```
class SweeperConfig {
  /// Creates a configuration. The defaults scan everything.
  const SweeperConfig({
    this.exclude = const [],
    this.entryPoints = const [],
    this.keep = const {},
    this.assetDirectories = defaultAssetDirectories,
    this.scanAssets = true,
    this.scanFiles = true,
    this.scanCode = true,
    this.scanMethods = true,
  });

  /// Builds a configuration from a parsed YAML map. Unknown keys are
  /// ignored, and a single string is accepted where a list is expected.
  factory SweeperConfig.fromMap(Map<dynamic, dynamic> map) {
    final scan = map['scan'];
    bool flag(String key) {
      if (scan is Map) {
        final value = scan[key];
        if (value is bool) return value;
      }
      return true;
    }

    return SweeperConfig(
      exclude: _stringList(map['exclude']),
      entryPoints: _stringList(map['entry_points']),
      keep: _stringList(map['keep']).toSet(),
      assetDirectories: map.containsKey('asset_directories')
          ? _stringList(map['asset_directories'])
          : defaultAssetDirectories,
      scanAssets: flag('assets'),
      scanFiles: flag('files'),
      scanCode: flag('code'),
      scanMethods: flag('methods'),
    );
  }

  /// Folders searched for assets when `asset_directories` is not set.
  static const List<String> defaultAssetDirectories = ['assets'];

  /// Glob patterns (project-relative, `/` separated) that are never reported.
  final List<String> exclude;

  /// Extra Dart files treated as program entry points.
  final List<String> entryPoints;

  /// Declaration names that are never reported.
  final Set<String> keep;

  /// Folders that are searched for assets, declared or not.
  final List<String> assetDirectories;

  /// Whether unused assets are reported (`scan.assets`).
  final bool scanAssets;

  /// Whether unreferenced Dart files are reported (`scan.files`).
  final bool scanFiles;

  /// Whether unused declarations are reported (`scan.code`).
  final bool scanCode;

  /// Whether unused methods inside used classes are reported
  /// (`scan.methods`).
  final bool scanMethods;

  /// Returns a copy with the given fields replaced.
  SweeperConfig copyWith({
    List<String>? exclude,
    List<String>? entryPoints,
    Set<String>? keep,
    List<String>? assetDirectories,
    bool? scanAssets,
    bool? scanFiles,
    bool? scanCode,
    bool? scanMethods,
  }) {
    return SweeperConfig(
      exclude: exclude ?? this.exclude,
      entryPoints: entryPoints ?? this.entryPoints,
      keep: keep ?? this.keep,
      assetDirectories: assetDirectories ?? this.assetDirectories,
      scanAssets: scanAssets ?? this.scanAssets,
      scanFiles: scanFiles ?? this.scanFiles,
      scanCode: scanCode ?? this.scanCode,
      scanMethods: scanMethods ?? this.scanMethods,
    );
  }

  static List<String> _stringList(Object? value) {
    if (value is String) return [value];
    if (value is List) return value.whereType<String>().toList();
    return const [];
  }
}

/// Loads `flutter_sweeper.yaml` from a project root.
abstract final class ConfigLoader {
  /// Name of the optional configuration file.
  static const String fileName = 'flutter_sweeper.yaml';

  /// Reads [fileName] from [projectRoot], or returns the defaults when the
  /// file does not exist. Throws a [SweeperException] for invalid YAML.
  static SweeperConfig load(String projectRoot) {
    final file = File(p.join(projectRoot, fileName));
    if (!file.existsSync()) return const SweeperConfig();

    final doc = _parse(file);
    if (doc == null) return const SweeperConfig();
    if (doc is! Map) {
      throw const SweeperException(
        '$fileName must contain a YAML map at the top level.',
        exitCode: ExitCodes.config,
      );
    }
    // Allow the settings to be nested under a `flutter_sweeper:` key too.
    final nested = doc['flutter_sweeper'];
    return SweeperConfig.fromMap(nested is Map ? nested : doc);
  }

  static Object? _parse(File file) {
    try {
      return loadYaml(file.readAsStringSync());
    } on YamlException catch (e) {
      throw SweeperException(
        'Invalid $fileName: ${e.message}',
        exitCode: ExitCodes.config,
      );
    }
  }
}

/// Decides which project-relative paths may be reported.
class PathFilter {
  /// Creates a filter for the exclude glob [patterns].
  PathFilter(Iterable<String> patterns)
      : _globs = [
          for (final pattern in patterns) Glob(pattern, context: p.posix),
        ];

  final List<Glob> _globs;

  /// File suffixes produced by common code generators.
  static const List<String> generatedSuffixes = [
    '.g.dart',
    '.freezed.dart',
    '.gr.dart',
    '.config.dart',
    '.mocks.dart',
    '.gen.dart',
    '.pb.dart',
    '.pbenum.dart',
    '.pbjson.dart',
    '.pbserver.dart',
  ];

  /// Whether [relativePath] looks like code generated by a builder.
  bool isGenerated(String relativePath) {
    final base = p.posix.basename(relativePath);
    return generatedSuffixes.any(relativePath.endsWith) ||
        base == 'generated_plugin_registrant.dart' ||
        base.startsWith('app_localizations') ||
        relativePath.startsWith('lib/generated/');
  }

  /// Whether [relativePath] matches a user `--exclude` / config glob.
  bool isExcluded(String relativePath) =>
      _globs.any((glob) => glob.matches(relativePath));

  /// Whether a finding at [relativePath] may be shown to the user.
  bool canReport(String relativePath) =>
      !isGenerated(relativePath) && !isExcluded(relativePath);
}
