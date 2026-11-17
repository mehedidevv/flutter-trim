// Programmatic use of flutter_sweeper.
//
// Most people run the CLI instead:
//
//   dart pub global activate flutter_sweeper
//   fsweep --dry-run
//
// This example runs the scanners as a library and prints a report without
// deleting anything:
//
//   dart run example/example.dart path/to/flutter_app

import 'dart:io';

import 'package:flutter_sweeper/flutter_sweeper.dart';

void main(List<String> args) {
  final root = args.isEmpty ? '.' : args.first;

  // Optional: honour the project's flutter_sweeper.yaml.
  final config = ConfigLoader.load(root);
  final context = ProjectContext.load(root, config: config);

  final unusedAssets = AssetScanner(context).scan();
  final unusedFiles = FileScanner(context).scan();
  final unusedCode = CodeScanner(
    context,
    includeMethods: config.scanMethods,
    // Declarations inside files that are already unused are not repeated.
    skipFiles: {for (final item in unusedFiles) item.path},
  ).scan();

  final items = [...unusedAssets, ...unusedFiles, ...unusedCode];
  if (items.isEmpty) {
    stdout.writeln('Nothing to sweep in ${context.root}.');
    return;
  }

  for (final item in items) {
    stdout.writeln(
      '${item.typeLabel.padRight(11)} '
      '${item.displayName.padRight(32)} '
      '${item.location}  (${formatBytes(item.sizeBytes)})',
    );
  }
  final total = items.fold<int>(0, (sum, item) => sum + item.sizeBytes);
  stdout.writeln('\n${items.length} unused item(s), ${formatBytes(total)}.');

  // To delete an item programmatically:
  // const FileCleaner().clean(items.first);
}
