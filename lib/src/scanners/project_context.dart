import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../models/sweep_item.dart';
import '../utils/config_loader.dart';

/// Marker comment that protects a declaration from being reported.
const String keepMarker = 'flutter_sweeper:keep';

/// Marker comment that excludes a whole file from every scanner's findings.
const String ignoreFileMarker = 'flutter_sweeper:ignore_file';

/// A Dart file parsed once and shared by every scanner.
class ParsedDartFile {
  ParsedDartFile._({
    required this.path,
    required this.relativePath,
    required this.content,
    required this.unit,
    required this.lineInfo,
  });

  /// Parses [content] without resolving it (no SDK or packages needed).
  factory ParsedDartFile.parse({
    required String path,
    required String relativePath,
    required String content,
  }) {
    final result = parseString(
      content: content,
      path: path,
      throwIfDiagnostics: false,
    );
    return ParsedDartFile._(
      path: path,
      relativePath: relativePath,
      content: content,
      unit: result.unit,
      lineInfo: result.lineInfo,
    );
  }

  /// Absolute path of the file.
  final String path;

  /// Project-relative path with `/` separators.
  final String relativePath;

  /// Source text.
  final String content;

  /// Unresolved AST of [content].
  final CompilationUnit unit;

  /// Maps offsets to line numbers.
  final LineInfo lineInfo;

  /// Every identifier token in the file (comments are not part of the token
  /// stream, so `/// [Foo]` doc references are deliberately not counted).
  late final List<Token> identifiers = _collectIdentifiers();

  /// Whether the file contains `// flutter_sweeper:ignore_file`.
  late final bool isIgnored = content.contains(ignoreFileMarker);

  /// Whether the file is a `part of` another library.
  late final bool isPartOf =
      unit.directives.any((directive) => directive is PartOfDirective);

  /// 1-based line number of [offset].
  int lineOf(int offset) => lineInfo.getLocation(offset).lineNumber;

  List<Token> _collectIdentifiers() {
    final tokens = <Token>[];
    var token = unit.beginToken;
    while (!token.isEof) {
      if (token.isIdentifier) tokens.add(token);
      final next = token.next;
      if (next == null || identical(next, token)) break;
      token = next;
    }
    return tokens;
  }
}

/// Everything the scanners need to know about the project under analysis.
class ProjectContext {
  ProjectContext._({
    required this.root,
    required this.packageName,
    required this.pubspec,
    required this.config,
    required this.filter,
    required this.dartFiles,
    required this.skippedFiles,
  });

  /// Folders whose Dart files count as references.
  static const List<String> dartSourceDirectories = [
    'lib',
    'bin',
    'test',
    'integration_test',
    'test_driver',
    'tool',
  ];

  /// Reads `pubspec.yaml` and parses every Dart file under [rootPath].
  ///
  /// Throws a [SweeperException] when the pubspec is missing or invalid.
  factory ProjectContext.load(
    String rootPath, {
    SweeperConfig config = const SweeperConfig(),
  }) {
    final root = p.normalize(p.absolute(rootPath));
    final pubspecFile = File(p.join(root, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      throw SweeperException(
        'No pubspec.yaml found in $root.',
        exitCode: ExitCodes.noInput,
      );
    }

    final Object? pubspec;
    try {
      pubspec = loadYaml(pubspecFile.readAsStringSync());
    } on YamlException catch (e) {
      throw SweeperException('Invalid pubspec.yaml: ${e.message}');
    }
    if (pubspec is! Map || pubspec['name'] is! String) {
      throw const SweeperException('pubspec.yaml has no package "name".');
    }

    final dartFiles = <ParsedDartFile>[];
    final skipped = <String, String>{};
    for (final dirName in dartSourceDirectories) {
      final dir = Directory(p.join(root, dirName));
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final absolute = p.normalize(entity.path);
        final relative = _toRelative(root, absolute);
        if (relative.split('/').any((segment) => segment.startsWith('.'))) {
          continue;
        }
        try {
          dartFiles.add(
            ParsedDartFile.parse(
              path: absolute,
              relativePath: relative,
              content: entity.readAsStringSync(),
            ),
          );
        } on Object catch (e) {
          skipped[relative] = '$e';
        }
      }
    }
    dartFiles.sort((a, b) => a.relativePath.compareTo(b.relativePath));

    return ProjectContext._(
      root: root,
      packageName: pubspec['name'] as String,
      pubspec: pubspec,
      config: config,
      filter: PathFilter(config.exclude),
      dartFiles: List.unmodifiable(dartFiles),
      skippedFiles: Map.unmodifiable(skipped),
    );
  }

  /// Absolute, normalized project root.
  final String root;

  /// `name` from `pubspec.yaml`.
  final String packageName;

  /// Parsed `pubspec.yaml`.
  final Map<dynamic, dynamic> pubspec;

  /// Effective configuration.
  final SweeperConfig config;

  /// Decides which paths may be reported.
  final PathFilter filter;

  /// Every parsed Dart file, sorted by relative path.
  final List<ParsedDartFile> dartFiles;

  /// Files that could not be read, keyed by relative path.
  final Map<String, String> skippedFiles;

  late final Map<String, ParsedDartFile> _byPath = {
    for (final file in dartFiles) file.path: file,
  };

  /// The parsed file at [absolutePath], or `null` if it is not a project
  /// source.
  ParsedDartFile? fileAt(String absolutePath) =>
      _byPath[p.normalize(absolutePath)];

  /// Project-relative path with `/` separators.
  String relative(String absolutePath) => _toRelative(root, absolutePath);

  /// Absolute path for a project-relative `/` separated path.
  String absolute(String relativePosixPath) =>
      p.normalize(p.joinAll([root, ...p.posix.split(relativePosixPath)]));

  /// Whether the project uses flutter_gen (`Assets.images.logo`).
  late final bool usesFlutterGen = _hasDependency('flutter_gen_runner') ||
      _hasDependency('flutter_gen') ||
      dartFiles.any((f) => f.relativePath.endsWith('assets.gen.dart'));

  bool _hasDependency(String name) {
    for (final key in const ['dependencies', 'dev_dependencies']) {
      final deps = pubspec[key];
      if (deps is Map && deps.containsKey(name)) return true;
    }
    return false;
  }

  static String _toRelative(String root, String absolutePath) =>
      p.split(p.relative(absolutePath, from: root)).join('/');
}
