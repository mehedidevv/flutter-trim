import 'dart:collection';
import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import '../models/trim_item.dart';
import 'project_context.dart';

/// Finds `.dart` files in `lib/` that cannot be reached from any entry point
/// by following `import`, `export` and `part` directives (including
/// conditional imports).
///
/// Entry points are:
/// * every Dart file outside `lib/` (`test/`, `bin/`, `tool/`, ...),
/// * every file in `lib/` that declares a top-level `main` function
///   (`main.dart`, `main_dev.dart`, ...),
/// * for packages without a `main`, every public library directly under
///   `lib/` (outside `lib/src/`), because other packages may import them,
/// * files listed under `entry_points` in `flutter_trim.yaml`.
///
/// URIs are decoded before they are resolved (`common%20widget/` is the
/// folder `common widget/`), and a URI that differs from the file on disk
/// only by letter case still counts, because macOS and Windows compile such
/// imports.
///
/// Generated files (`*.g.dart`, `*.freezed.dart`, ...) and `part of` files are
/// never reported on their own; parts are deleted together with their library.
class FileScanner {
  /// Creates a scanner for [context].
  FileScanner(this.context);

  /// The project being scanned.
  final ProjectContext context;

  /// Returns every unreachable library in `lib/`, with its part files as
  /// companions.
  List<TrimItem> scan() {
    final reachable = reachableFiles();
    final items = <TrimItem>[];

    for (final file in context.dartFiles) {
      if (!file.relativePath.startsWith('lib/')) continue;
      if (reachable.contains(file.path)) continue;
      if (file.isPartOf || file.isIgnored) continue;
      if (!context.filter.canReport(file.relativePath)) continue;

      final companions = <String>{
        for (final uri in _partUris(file.unit))
          if (_resolveExisting(uri, file.path) case final part?) part,
      }.toList();
      var size = File(file.path).lengthSync();
      for (final companion in companions) {
        size += File(companion).lengthSync();
      }

      items.add(
        TrimItem(
          type: TrimItemType.file,
          path: file.path,
          relativePath: file.relativePath,
          name: p.posix.basename(file.relativePath),
          sizeBytes: size,
          reason: companions.isEmpty
              ? 'Not imported, exported or used as a part by any reachable '
                  'file'
              : 'Not reachable from any entry point '
                  '(also removes ${companions.length} part file(s))',
          companionPaths: companions,
        ),
      );
    }
    return items;
  }

  /// Absolute paths of every Dart file reachable from an entry point.
  Set<String> reachableFiles() {
    final entries = _entryPoints();
    final visited = <String>{...entries};
    final queue = Queue<String>.of(entries);

    while (queue.isNotEmpty) {
      final current = context.fileAt(queue.removeFirst());
      if (current == null) continue;
      for (final uri in _referencedUris(current.unit)) {
        final target = resolveUri(uri, current.path);
        if (target == null) continue;
        // Use the path of the file on disk, which may differ in letter case.
        final file = context.fileAt(target);
        if (file == null) continue;
        if (visited.add(file.path)) queue.add(file.path);
      }
    }
    return visited;
  }

  /// Resolves an `import` / `export` / `part` [uri] written in [fromFile] to
  /// an absolute path inside this package, or `null` for `dart:` URIs, other
  /// packages and malformed URIs.
  ///
  /// Percent-encoded characters are decoded, so
  /// `package:app/common%20widget/x.dart` is `lib/common widget/x.dart`.
  String? resolveUri(String uri, String fromFile) {
    final Uri parsed;
    try {
      parsed = Uri.parse(uri);
    } on FormatException {
      return null;
    }

    if (parsed.scheme == 'package') {
      final segments = parsed.pathSegments;
      if (segments.length < 2 || segments.first != context.packageName) {
        return null;
      }
      return context.absolute('lib/${segments.skip(1).join('/')}');
    }
    // dart:, other schemes and absolute URLs are outside the package.
    if (parsed.hasScheme || parsed.hasAuthority) return null;

    // `pathSegments` are already decoded (`%20` -> space).
    return p.normalize(
      p.joinAll([
        if (!parsed.path.startsWith('/')) p.dirname(fromFile),
        ...parsed.pathSegments,
      ]),
    );
  }

  /// [resolveUri], limited to files that exist (matching letter case
  /// leniently like [ProjectContext.fileAt]).
  String? _resolveExisting(String uri, String fromFile) {
    final target = resolveUri(uri, fromFile);
    if (target == null) return null;
    final parsed = context.fileAt(target);
    if (parsed != null) return parsed.path;
    return File(target).existsSync() ? target : null;
  }

  Set<String> _entryPoints() {
    final libFiles =
        context.dartFiles.where((f) => f.relativePath.startsWith('lib/'));
    final hasMain = libFiles.any(_declaresMain);

    final entries = <String>{};
    for (final file in context.dartFiles) {
      final inLib = file.relativePath.startsWith('lib/');
      if (!inLib ||
          _declaresMain(file) ||
          (!hasMain && !file.relativePath.startsWith('lib/src/'))) {
        entries.add(file.path);
      }
    }
    for (final relative in context.config.entryPoints) {
      final file = context.fileAt(context.absolute(relative));
      entries.add(file?.path ?? context.absolute(relative));
    }
    return entries;
  }

  static bool _declaresMain(ParsedDartFile file) => file.unit.declarations
      .whereType<FunctionDeclaration>()
      .any((function) => function.name.lexeme == 'main');

  static Iterable<String> _referencedUris(CompilationUnit unit) sync* {
    for (final directive in unit.directives) {
      if (directive is NamespaceDirective) {
        final uri = directive.uri.stringValue;
        if (uri != null) yield uri;
        for (final configuration in directive.configurations) {
          final conditional = configuration.uri.stringValue;
          if (conditional != null) yield conditional;
        }
      } else if (directive is PartDirective) {
        final uri = directive.uri.stringValue;
        if (uri != null) yield uri;
      }
    }
  }

  static Iterable<String> _partUris(CompilationUnit unit) sync* {
    for (final directive in unit.directives.whereType<PartDirective>()) {
      final uri = directive.uri.stringValue;
      if (uri != null) yield uri;
    }
  }
}
