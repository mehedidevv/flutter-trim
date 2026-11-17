import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';

import '../models/trim_item.dart';
import '../scanners/declaration_utils.dart';

/// Outcome of removing one [TrimItem].
class CleanResult {
  /// The item was removed and [bytesFreed] bytes were reclaimed.
  const CleanResult.success(this.bytesFreed, {this.message})
      : success = true,
        error = null;

  /// The item could not be removed because of [error].
  const CleanResult.failure(this.error)
      : success = false,
        bytesFreed = 0,
        message = null;

  /// Whether the removal succeeded.
  final bool success;

  /// Bytes reclaimed by the removal (0 on failure).
  final int bytesFreed;

  /// Optional extra detail on success, such as `Removed 2 files`.
  final String? message;

  /// Why the removal failed, or `null` on success.
  final String? error;
}

/// Deletes asset/Dart files and surgically removes Dart declarations.
///
/// Declarations are located again from a fresh parse at deletion time, so
/// earlier edits to the same file never leave stale offsets behind. If the
/// edit would introduce new syntax errors the file is left untouched.
class FileCleaner {
  /// Creates a cleaner. With [dryRun] nothing is written to disk.
  const FileCleaner({this.dryRun = false});

  /// When true nothing is written; results report what *would* happen.
  final bool dryRun;

  /// Deletes the file(s) of an asset or Dart file item, or removes a
  /// declaration from its file. Never throws for file-system problems;
  /// they are returned as [CleanResult.failure].
  CleanResult clean(TrimItem item) {
    try {
      return switch (item.type) {
        TrimItemType.asset || TrimItemType.file => _deleteFiles(item),
        TrimItemType.declaration => _removeDeclaration(item),
      };
    } on FileSystemException catch (e) {
      return CleanResult.failure('${e.message}: ${e.path ?? item.path}');
    }
  }

  CleanResult _deleteFiles(TrimItem item) {
    var freed = 0;
    var removed = 0;
    for (final path in [item.path, ...item.companionPaths]) {
      final file = File(path);
      if (!file.existsSync()) continue;
      freed += file.lengthSync();
      if (!dryRun) file.deleteSync();
      removed++;
    }
    if (removed == 0) {
      return const CleanResult.failure('File no longer exists');
    }
    return CleanResult.success(
      freed,
      message: removed > 1 ? 'Removed $removed files' : null,
    );
  }

  CleanResult _removeDeclaration(TrimItem item) {
    final file = File(item.path);
    if (!file.existsSync()) {
      return const CleanResult.failure('File no longer exists');
    }
    final content = file.readAsStringSync();
    final parsed = parseString(
      content: content,
      path: item.path,
      throwIfDiagnostics: false,
    );

    final node = DeclarationUtils.locate(parsed.unit, item);
    if (node == null) {
      return CleanResult.failure(
        '${item.displayName} was not found (already removed or renamed?)',
      );
    }

    final updated = removeRange(content, node.offset, node.end);
    final errorsBefore = parsed.errors.length;
    final errorsAfter = parseString(
      content: updated,
      path: item.path,
      throwIfDiagnostics: false,
    ).errors.length;
    if (errorsAfter > errorsBefore) {
      return const CleanResult.failure(
        'Removal would introduce syntax errors; file left unchanged',
      );
    }

    if (!dryRun) file.writeAsStringSync(updated);
    return CleanResult.success(
      utf8.encode(content).length - utf8.encode(updated).length,
    );
  }

  /// Removes `[start, end)` from [content] together with the indentation in
  /// front of it, the line break after it and one surplus blank line.
  static String removeRange(String content, int start, int end) {
    bool isBlank(String char) => char == ' ' || char == '\t';

    var from = start;
    while (from > 0 && isBlank(content[from - 1])) {
      from--;
    }
    if (from != 0 && content[from - 1] != '\n') from = start;

    var to = end;
    while (to < content.length && isBlank(content[to])) {
      to++;
    }
    if (to < content.length && content[to] == '\r') to++;
    if (to < content.length && content[to] == '\n') {
      to++;
    } else {
      to = end;
    }

    final before = content.substring(0, from);
    var after = content.substring(to);
    final blankBefore = before.isEmpty ||
        before.endsWith('\n\n') ||
        before.endsWith('\n\r\n') ||
        before.trimRight().endsWith('{');
    if (blankBefore) {
      after = after.replaceFirst(RegExp(r'^[ \t]*\r?\n'), '');
    }
    return before + after;
  }
}
