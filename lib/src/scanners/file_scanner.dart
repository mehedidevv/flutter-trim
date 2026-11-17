import 'dart:collection';
import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import '../models/sweep_item.dart';
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
/// * files listed under `entry_points` in `flutter_sweeper.yaml`.
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
  List<SweepItem> scan() {
    final reachable = reachableFiles();
    final items = <SweepItem>[];

    for (final file in context.dartFiles) {
      if (!file.relativePath.startsWith('lib/')) continue;
      if (reachable.contains(file.path)) continue;
      if (file.isPartOf || file.isIgnored) continue;
      if (!context.filter.canReport(file.relativePath)) continue;

      final companions = [
        for (final uri in _partUris(file.unit))
          if (_resolve(uri, file.path) case final part?)
            if (File(part).existsSync()) part,
      ];
      var size = File(file.path).lengthSync();
      for (final companion in companions) {
        size += File(companion).lengthSync();
      }

      items.add(
        SweepItem(
          type: SweepItemType.file,
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
        final target = _resolve(uri, current.path);
        if (target == null || context.fileAt(target) == null) continue;
        if (visited.add(target)) queue.add(target);
      }
    }
    return visited;
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
      entries.add(context.absolute(relative));
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

  /// Resolves an import URI to an absolute path inside this package.
  String? _resolve(String uri, String fromFile) {
    if (uri.startsWith('package:')) {
      final rest = uri.substring('package:'.length);
      final slash = rest.indexOf('/');
      if (slash < 0 || rest.substring(0, slash) != context.packageName) {
        return null;
      }
      return context.absolute('lib/${rest.substring(slash + 1)}');
    }
    // dart:, other schemes and absolute URLs are outside the package.
    if (uri.contains(':')) return null;
    return p.normalize(
      p.join(p.dirname(fromFile), p.joinAll(p.url.split(uri))),
    );
  }
}
