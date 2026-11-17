import 'package:mason_logger/mason_logger.dart';

import '../models/trim_item.dart';
import '../version.dart';
import 'ui.dart';

/// Counters collected during an interactive session.
class TrimStats {
  /// Items that were removed.
  int deleted = 0;

  /// Items the user chose to keep.
  int kept = 0;

  /// Items left unreviewed after "Quit".
  int skipped = 0;

  /// Items whose removal failed.
  int failed = 0;

  /// Total bytes reclaimed.
  int bytesFreed = 0;

  /// Whether any Dart file or declaration was removed.
  bool touchedDartCode = false;

  /// `location: error` for every failed removal.
  final List<String> failures = [];

  /// Number of items that have been decided so far.
  int get reviewed => deleted + kept + failed;
}

/// Formatted terminal output: banner, summary, detail tables and the final
/// session summary.
class TrimReporter {
  /// Creates a reporter that writes to [logger], laid out by [ui].
  TrimReporter(this.logger, {Ui? ui}) : ui = ui ?? Ui();

  /// Destination of all output.
  final Logger logger;

  /// Box and table renderer.
  final Ui ui;

  void _lines(Iterable<String> lines) => lines.forEach(logger.info);

  /// Prints the banner and the run settings.
  void printHeader({
    required String root,
    required bool dryRun,
    required List<String> scope,
  }) {
    logger.info('');
    _lines(
      ui.box(
        [
          [
            '${paint(styleBold, 'flutter_trim')}  '
                '${paint(darkGray, 'v$packageVersion')}',
            paint(
              darkGray,
              'Find and remove unused code and assets in Flutter projects',
            ),
          ],
        ],
      ),
    );
    final mode = dryRun
        ? paint(lightYellow, 'Dry run · nothing will be deleted')
        : 'Interactive review';
    logger
      ..info(_field('Project', paint(lightCyan, root)))
      ..info(_field('Mode', mode))
      ..info(_field('Scope', scope.join(paint(darkGray, ' · '))))
      ..info('');
  }

  static String _field(String label, String value) =>
      '${Ui.indent}  ${paint(darkGray, label.padRight(8))} $value';

  /// Prints the summary dashboard followed by one detail table per category.
  void printReport(List<TrimItem> items) {
    final groups = <TrimItemType, List<TrimItem>>{};
    for (final item in items) {
      groups.putIfAbsent(item.type, () => []).add(item);
    }
    int sizeOf(Iterable<TrimItem> list) =>
        list.fold<int>(0, (sum, item) => sum + item.sizeBytes);

    logger
      ..info('')
      ..info('${Ui.indent}${paint(styleBold, 'Summary')}');
    _lines(
      ui.table(
        const ['Category', 'Items', 'Size'],
        [
          for (final type in TrimItemType.values)
            if (groups[type] case final group?)
              [
                title(type),
                '${group.length}',
                formatBytes(sizeOf(group)),
              ],
        ],
        footer: [
          ['Total', '${items.length}', formatBytes(sizeOf(items))],
        ],
        alignRight: const {1, 2},
      ),
    );

    var index = 1;
    for (final type in TrimItemType.values) {
      final group = groups[type];
      if (group == null) continue;
      logger
        ..info('')
        ..info(
          '${Ui.indent}${paint(styleBold, title(type))} '
          '${paint(darkGray, '(${group.length})')}',
        );
      _lines(
        ui.table(
          [
            '#',
            'Type',
            'Name',
            type == TrimItemType.declaration ? 'Location' : 'Folder',
            'Size',
          ],
          [
            for (final item in group)
              [
                '${index++}',
                item.typeLabel,
                fitEnd(item.displayName, 36),
                _location(item),
                formatBytes(item.sizeBytes),
              ],
          ],
          alignRight: const {0, 4},
          shrink: 3,
        ),
      );
    }
    logger.info('');
  }

  /// Prints the "nothing to do" message.
  void printClean() {
    logger.info('');
    _lines(
      ui.box(
        [
          [
            '${paint(lightGreen, '✔')} '
                '${paint(styleBold, 'Nothing to trim.')} '
                'Your project has no unused assets or code.',
          ],
        ],
        title: 'All clean',
        titleColor: lightGreen,
      ),
    );
    logger.info('');
  }

  /// Prints the closing line of a dry run.
  void printDryRunDone(int count) {
    logger
      ..info(
        '${Ui.indent}${paint(lightYellow, '●')} Dry run complete. '
        'Nothing was deleted.',
      )
      ..info(
        '${Ui.indent}  Run ${paint(lightCyan, 'ftrim')} without '
        '${paint(lightCyan, '--dry-run')} to review the $count item(s) '
        'one by one.',
      )
      ..info('');
  }

  /// Prints the result of an interactive session and suggested next steps.
  void printSummary(TrimStats stats) {
    String row(String label, AnsiCode color, int value, [String extra = '']) =>
        '${paint(color, label.padRight(9))}'
        '${paint(styleBold, '$value'.padLeft(4))}'
        '${extra.isEmpty ? '' : '   ${paint(darkGray, extra)}'}';

    logger.info('');
    _lines(
      ui.box(
        [
          [
            row(
              'Deleted',
              lightRed,
              stats.deleted,
              '${formatBytes(stats.bytesFreed)} freed',
            ),
            row('Kept', lightGreen, stats.kept),
            row('Skipped', darkGray, stats.skipped),
            if (stats.failed > 0) row('Failed', lightYellow, stats.failed),
          ],
          if (stats.failures.isNotEmpty)
            [
              for (final failure in stats.failures)
                paint(lightYellow, '⚠ $failure'),
            ],
        ],
        title: 'Session summary',
      ),
    );

    if (stats.touchedDartCode) {
      String step(int n, String command, String why) =>
          '${Ui.indent}  ${paint(darkGray, '$n.')} '
          '${paint(lightCyan, command.padRight(18))} ${paint(darkGray, why)}';
      logger
        ..info('')
        ..info('${Ui.indent}${paint(styleBold, 'Next steps')}')
        ..info(step(1, 'dart fix --apply', 'remove imports that became unused'))
        ..info(step(2, 'flutter analyze', 'make sure everything compiles'))
        ..info(step(3, 'git diff', 'review the changes before committing'));
    }
    logger.info('');
  }

  /// Files and assets already show their file name, so the location column
  /// shows the folder; declarations show `path:line`.
  static String _location(TrimItem item) {
    if (item.isDeclaration) return item.location;
    final slash = item.relativePath.lastIndexOf('/');
    return slash < 0 ? './' : item.relativePath.substring(0, slash + 1);
  }

  /// Heading for a category of findings.
  static String title(TrimItemType type) => switch (type) {
        TrimItemType.asset => 'Unused assets',
        TrimItemType.file => 'Unreferenced Dart files',
        TrimItemType.declaration => 'Unused classes, functions & methods',
      };
}
