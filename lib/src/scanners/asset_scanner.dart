import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/trim_item.dart';
import 'project_context.dart';

/// Finds asset files that no Dart code (or tool configuration) refers to.
///
/// Candidates are:
/// * every file declared under `flutter: assets:` in `pubspec.yaml`
///   (directory entries are expanded the way Flutter does it, including
///   `2.0x/` / `3.0x/` resolution variants), and
/// * every file inside the configured asset directories (default `assets/`),
///   even when it is not declared.
///
/// An asset counts as used when its path, or its file name, appears in any
/// Dart source, in a non-asset value of `pubspec.yaml`, or in a root-level
/// YAML config such as `flutter_launcher_icons.yaml`. Projects that use
/// flutter_gen are matched by the generated getter name (`Assets.images.logo`).
class AssetScanner {
  /// Creates a scanner for [context].
  AssetScanner(this.context);

  /// The project being scanned.
  final ProjectContext context;

  static final RegExp _variantSegment = RegExp(r'/\d+(\.\d+)?x/');
  static final RegExp _variantDirectory = RegExp(r'^\d+(\.\d+)?x$');
  static const Set<String> _ignoredNames = {
    '.DS_Store',
    'Thumbs.db',
    'desktop.ini',
    '.gitkeep',
    '.keep',
  };

  /// Returns every unused asset, sorted by path.
  List<TrimItem> scan() {
    final declarations = _readDeclarations();

    final candidates = <String>{...declarations.files};
    for (final dir in {
      ...context.config.assetDirectories,
      ...declarations.directories,
    }) {
      candidates.addAll(_walk(dir));
    }
    candidates.removeAll(declarations.fonts);

    final corpus = _buildCorpus();
    final identifiers =
        context.usesFlutterGen ? _handWrittenIdentifiers() : const <String>{};

    final items = <TrimItem>[];
    for (final relative in candidates.toList()..sort()) {
      if (!context.filter.canReport(relative)) continue;
      final file = File(context.absolute(relative));
      if (!file.existsSync()) continue;
      if (_isReferenced(relative, corpus, identifiers)) continue;

      final declared = declarations.files.contains(relative);
      items.add(
        TrimItem(
          type: TrimItemType.asset,
          path: file.path,
          relativePath: relative,
          name: p.posix.basename(relative),
          sizeBytes: file.lengthSync(),
          reason: declared
              ? 'Declared in pubspec.yaml but never referenced'
              : 'Not declared in pubspec.yaml and never referenced',
        ),
      );
    }
    return items;
  }

  bool _isReferenced(String relative, String corpus, Set<String> identifiers) {
    // assets/images/2.0x/logo.png is a variant of assets/images/logo.png.
    final base = relative.replaceAll(_variantSegment, '/');
    if (corpus.contains(base) || corpus.contains(relative)) return true;

    // File name only: catches '$imagePath/logo.png' style concatenation.
    final fileName = p.posix.basename(base);
    final namePattern =
        RegExp('(^|[^A-Za-z0-9_\\-])${RegExp.escape(fileName)}');
    if (namePattern.hasMatch(corpus)) return true;

    if (identifiers.isNotEmpty) {
      if (identifiers.contains(flutterGenName(fileName))) return true;
    }
    return false;
  }

  /// The getter name flutter_gen generates for [fileName]
  /// (`ic_home-active.png` -> `icHomeActive`).
  static String flutterGenName(String fileName) {
    final stem = p.posix.basenameWithoutExtension(fileName);
    final parts = stem
        .split(RegExp('[^A-Za-z0-9]+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return stem;
    final buffer = StringBuffer()
      ..write(parts.first[0].toLowerCase())
      ..write(parts.first.substring(1));
    for (final part in parts.skip(1)) {
      buffer
        ..write(part[0].toUpperCase())
        ..write(part.substring(1));
    }
    return buffer.toString();
  }

  _AssetDeclarations _readDeclarations() {
    final files = <String>{};
    final directories = <String>{};
    final fonts = <String>{};

    final flutter = context.pubspec['flutter'];
    if (flutter is! Map) return _AssetDeclarations(files, directories, fonts);

    final assets = flutter['assets'];
    if (assets is List) {
      for (final entry in assets) {
        String? raw;
        if (entry is String) {
          raw = entry;
        } else if (entry is Map && entry['path'] is String) {
          raw = entry['path'] as String; // Flutter 3.19+ flavored assets.
        }
        if (raw == null || raw.startsWith('packages/')) continue;

        final normalized = p.posix.normalize(raw);
        final isDirectory = raw.endsWith('/') ||
            Directory(context.absolute(normalized)).existsSync();
        if (isDirectory) {
          directories.add(normalized);
          files.addAll(_listDeclaredDirectory(normalized));
        } else {
          files.add(normalized);
        }
      }
    }

    final families = flutter['fonts'];
    if (families is List) {
      for (final family in families) {
        if (family is! Map || family['fonts'] is! List) continue;
        for (final font in family['fonts'] as List) {
          if (font is Map && font['asset'] is String) {
            fonts.add(p.posix.normalize(font['asset'] as String));
          }
        }
      }
    }
    return _AssetDeclarations(files, directories, fonts);
  }

  /// Flutter includes the files directly inside a declared directory plus
  /// their resolution-aware variants (`2.0x/`, `3.0x/`), but not other
  /// sub-directories.
  Set<String> _listDeclaredDirectory(String relativeDir) {
    final result = <String>{};
    final dir = Directory(context.absolute(relativeDir));
    if (!dir.existsSync()) return result;
    for (final entity in dir.listSync(followLinks: false)) {
      final name = p.basename(entity.path);
      if (entity is File && _isAssetFile(name)) {
        result.add(context.relative(entity.path));
      } else if (entity is Directory && _variantDirectory.hasMatch(name)) {
        for (final variant in entity.listSync(followLinks: false)) {
          if (variant is File && _isAssetFile(p.basename(variant.path))) {
            result.add(context.relative(variant.path));
          }
        }
      }
    }
    return result;
  }

  Set<String> _walk(String relativeDir) {
    final result = <String>{};
    final dir = Directory(context.absolute(relativeDir));
    if (!dir.existsSync()) return result;
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = context.relative(entity.path);
      if (relative.split('/').any((s) => s.startsWith('.'))) continue;
      if (_isAssetFile(p.basename(entity.path))) result.add(relative);
    }
    return result;
  }

  bool _isAssetFile(String name) =>
      !_ignoredNames.contains(name) &&
      !name.startsWith('.') &&
      !name.endsWith('.dart');

  /// All text that may mention an asset path.
  String _buildCorpus() {
    final buffer = StringBuffer();
    for (final file in context.dartFiles) {
      // flutter_gen output lists every asset path, which would mark
      // everything as used; usage is detected through getters instead.
      if (file.relativePath.endsWith('.gen.dart')) continue;
      buffer.writeln(file.content);
    }

    _collectStrings(context.pubspec, buffer, const []);

    final rootDir = Directory(context.root);
    for (final entity in rootDir.listSync(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      const skip = {'pubspec.yaml', 'pubspec.lock', 'flutter_trim.yaml'};
      if ((name.endsWith('.yaml') || name.endsWith('.yml')) &&
          !skip.contains(name)) {
        try {
          buffer.writeln(entity.readAsStringSync());
        } on FileSystemException {
          // Unreadable config files are simply ignored.
        }
      }
    }
    return buffer.toString();
  }

  /// Writes every scalar in the pubspec except the asset/font declarations
  /// themselves (so `flutter_launcher_icons: image_path: ...` counts).
  void _collectStrings(Object? node, StringBuffer out, List<String> path) {
    if (node is Map) {
      node.forEach((key, value) {
        final isDeclarationList = path.length == 1 &&
            path.first == 'flutter' &&
            (key == 'assets' || key == 'fonts');
        if (!isDeclarationList) {
          _collectStrings(value, out, [...path, '$key']);
        }
      });
    } else if (node is List) {
      for (final value in node) {
        _collectStrings(value, out, path);
      }
    } else if (node is String) {
      out.writeln(node);
    }
  }

  Set<String> _handWrittenIdentifiers() => {
        for (final file in context.dartFiles)
          if (!context.filter.isGenerated(file.relativePath))
            for (final token in file.identifiers) token.lexeme,
      };
}

class _AssetDeclarations {
  _AssetDeclarations(this.files, this.directories, this.fonts);

  final Set<String> files;
  final Set<String> directories;
  final Set<String> fonts;
}
