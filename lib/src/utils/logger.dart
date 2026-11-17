import 'package:mason_logger/mason_logger.dart';

import '../models/sweep_item.dart';
import '../version.dart';

/// Applies [code] to [text]; falls back to plain text when colors are off.
String paint(AnsiCode code, String text) => code.wrap(text) ?? text;

/// Human readable byte count (`512 B`, `1.4 KB`, `23 MB`).
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var size = bytes / 1024;
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return '${size.toStringAsFixed(size >= 10 ? 0 : 1)} ${units[unit]}';
}

/// Counters collected during an interactive session.
class SweepStats {
  /// Items that were removed.
  int deleted = 0;

  /// Items the user chose to keep.
  int kept = 0;

  /// Items left unreviewed after "Skip all / Quit".
  int skipped = 0;

  /// Items whose removal failed.
  int failed = 0;

  /// Total bytes reclaimed.
  int bytesFreed = 0;

  /// Whether any Dart file or declaration was removed.
  bool touchedDartCode = false;

  /// `location: error` for every failed removal.
  final List<String> failures = [];
}

/// Formatted terminal output: header, report tables and summary.
class SweepReporter {
  /// Creates a reporter that writes to [logger].
  SweepReporter(this.logger);

  /// Destination of all output.
  final Logger logger;

  /// Prints the banner with the version and project path.
  void printHeader({required String root, required bool dryRun}) {
    logger
      ..info('')
      ..info(
        '${paint(styleBold, paint(lightCyan, '🧹 flutter_sweeper'))} '
        '${paint(darkGray, 'v$packageVersion')}',
      )
      ..info('${paint(darkGray, 'Project:')} $root');
    if (dryRun) {
      logger.info(paint(lightYellow, 'Dry run: nothing will be deleted.'));
    }
    logger.info('');
  }

  /// Prints all findings as tables grouped by type.
  void printReport(List<SweepItem> items) {
    final groups = <SweepItemType, List<SweepItem>>{};
    for (final item in items) {
      groups.putIfAbsent(item.type, () => []).add(item);
    }

    var index = 1;
    for (final type in SweepItemType.values) {
      final group = groups[type];
      if (group == null) continue;
      final groupSize = group.fold<int>(0, (sum, i) => sum + i.sizeBytes);
      logger
        ..info('')
        ..info(
          paint(
            styleBold,
            '${_title(type)} (${group.length}, ${formatBytes(groupSize)})',
          ),
        );
      _table(
        const ['#', 'Type', 'Name', 'Location', 'Size'],
        [
          for (final item in group)
            [
              '${index++}',
              item.typeLabel,
              item.displayName,
              item.location,
              formatBytes(item.sizeBytes),
            ],
        ],
        maxWidths: const [4, 12, 40, 60, 10],
      );
    }

    final total = items.fold<int>(0, (sum, i) => sum + i.sizeBytes);
    logger
      ..info('')
      ..info(
        'Found ${paint(styleBold, '${items.length}')} unused item(s), '
        '${paint(styleBold, formatBytes(total))} in total.',
      );
  }

  /// Prints the result of an interactive session.
  void printSummary(SweepStats stats) {
    logger
      ..info('')
      ..info(paint(styleBold, 'Sweep summary'))
      ..info(
        '  ${paint(lightRed, 'Deleted')} : ${stats.deleted} '
        '(${formatBytes(stats.bytesFreed)} freed)',
      )
      ..info('  ${paint(lightGreen, 'Kept')}    : ${stats.kept}')
      ..info('  ${paint(darkGray, 'Skipped')} : ${stats.skipped}');
    if (stats.failed > 0) {
      logger.info('  ${paint(lightYellow, 'Failed')}  : ${stats.failed}');
      for (final failure in stats.failures) {
        logger.info(paint(darkGray, '    - $failure'));
      }
    }
    if (stats.touchedDartCode) {
      logger
        ..info('')
        ..info(
          'Next: run ${paint(lightCyan, 'dart fix --apply')} to drop '
          'imports that became unused, then '
          '${paint(lightCyan, 'flutter analyze')}.',
        );
    }
  }

  static String _title(SweepItemType type) => switch (type) {
        SweepItemType.asset => 'Unused assets',
        SweepItemType.file => 'Unreferenced Dart files',
        SweepItemType.declaration => 'Unused classes, functions & methods',
      };

  void _table(
    List<String> headers,
    List<List<String>> rows, {
    required List<int> maxWidths,
  }) {
    final widths = <int>[
      for (var c = 0; c < headers.length; c++)
        _min(
          [headers[c].length, for (final row in rows) row[c].length]
              .reduce((a, b) => a > b ? a : b),
          maxWidths[c],
        ),
    ];

    String line(String left, String mid, String right) =>
        left + [for (final w in widths) '─' * (w + 2)].join(mid) + right;

    String cells(List<String> values) => '│${[
          for (var c = 0; c < values.length; c++)
            ' ${_fit(values[c], widths[c]).padRight(widths[c])} ',
        ].join('│')}│';

    logger
      ..info(paint(darkGray, line('┌', '┬', '┐')))
      ..info(paint(styleBold, cells(headers)))
      ..info(paint(darkGray, line('├', '┼', '┤')));
    for (final row in rows) {
      logger.info(cells(row));
    }
    logger.info(paint(darkGray, line('└', '┴', '┘')));
  }

  static int _min(int a, int b) => a < b ? a : b;

  /// Truncates from the left so that file names stay visible.
  static String _fit(String value, int width) {
    if (value.length <= width) return value;
    if (width <= 1) return value.substring(0, width);
    return '…${value.substring(value.length - width + 1)}';
  }
}
