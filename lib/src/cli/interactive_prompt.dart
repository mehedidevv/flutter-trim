import 'dart:io';

import 'package:mason_logger/mason_logger.dart';

import '../cleaners/file_cleaner.dart';
import '../models/trim_item.dart';
import 'reporter.dart';
import 'ui.dart';

/// Choices offered for every item.
enum PromptDecision {
  /// Leave the item and move on.
  keep('Keep'),

  /// Delete the item now.
  delete('Delete'),

  /// Delete this and every remaining item (after a confirmation).
  deleteAll('Delete all remaining'),

  /// Stop and leave everything that is left.
  quit('Quit and keep the rest');

  const PromptDecision(this.label);

  /// Text shown in the menu.
  final String label;
}

/// Walks the user through findings one by one with an arrow-key menu.
class InteractivePrompt {
  /// Creates a prompt that talks through [logger] and deletes with [cleaner].
  InteractivePrompt({required this.logger, required this.cleaner, Ui? ui})
      : ui = ui ?? Ui();

  /// Terminal used for output, menus and confirmations.
  final Logger logger;

  /// Performs the actual deletions.
  final FileCleaner cleaner;

  /// Box renderer for the item cards.
  final Ui ui;

  static const int _previewLines = 6;

  /// Asks about each of [items] in order and returns what happened.
  TrimStats run(List<TrimItem> items) {
    final stats = TrimStats();
    var deleteAll = false;

    for (var i = 0; i < items.length; i++) {
      final item = items[i];

      if (!deleteAll) {
        _describe(item, i + 1, items.length, stats);
        final decision = logger.chooseOne<PromptDecision>(
          'What do you want to do?',
          choices: PromptDecision.values,
          defaultValue: PromptDecision.keep,
          display: (choice) => choice.label,
        );

        if (decision == PromptDecision.keep) {
          stats.kept++;
          logger.info('${Ui.indent}${paint(lightGreen, '●')} Kept');
          continue;
        }
        if (decision == PromptDecision.quit) {
          stats.skipped += items.length - i;
          return stats;
        }
        if (decision == PromptDecision.deleteAll) {
          final others = items.length - i - 1;
          final confirmed = logger.confirm(
            'Delete this item and the $others remaining item(s) '
            'without asking?',
            defaultValue: false,
          );
          if (!confirmed) {
            i--; // Ask again about the same item.
            continue;
          }
          deleteAll = true;
        }
      }

      _delete(item, stats);
    }
    return stats;
  }

  void _describe(TrimItem item, int position, int total, TrimStats stats) {
    final details = <String>[
      paint(styleBold, item.displayName),
      '${paint(lightCyan, item.location)}'
          '${paint(darkGray, '  ·  ${formatBytes(item.sizeBytes)}')}',
      paint(darkGray, item.reason),
      for (final companion in item.companionPaths)
        paint(darkGray, '+ also deletes $companion'),
    ];
    final preview = item.isDeclaration ? _preview(item) : const <String>[];

    logger.info('');
    ui.box(
      [details, if (preview.isNotEmpty) preview],
      title: item.typeLabel,
      titleColor: _colorFor(item),
      trailing: '$position / $total',
    ).forEach(logger.info);
    logger.info(
      '${Ui.indent}${Ui.progressBar(position - 1, total)} '
      '${paint(darkGray, '${stats.deleted} deleted · ${stats.kept} kept')}',
    );
  }

  static AnsiCode _colorFor(TrimItem item) => switch (item.type) {
        TrimItemType.asset => lightMagenta,
        TrimItemType.file => lightYellow,
        TrimItemType.declaration => lightCyan,
      };

  List<String> _preview(TrimItem item) {
    final line = item.lineNumber;
    if (line == null) return const [];
    try {
      final lines = File(item.path).readAsLinesSync();
      final start = line - 1;
      final end = (start + _previewLines).clamp(0, lines.length);
      return [
        for (var i = start; i < end; i++)
          '${paint(darkGray, '${i + 1}'.padLeft(5))} '
              '${paint(darkGray, '│')} '
              '${lines[i].replaceAll('\t', '  ')}',
      ];
    } on FileSystemException {
      return const []; // The preview is best effort only.
    }
  }

  void _delete(TrimItem item, TrimStats stats) {
    final result = cleaner.clean(item);
    if (result.success) {
      stats.deleted++;
      stats.bytesFreed += result.bytesFreed;
      if (item.type != TrimItemType.asset) stats.touchedDartCode = true;
      final extra = result.message == null ? '' : ', ${result.message}';
      logger.info(
        '${Ui.indent}${paint(lightRed, '✗')} Deleted '
        '${paint(styleBold, item.displayName)} '
        '${paint(darkGray, '(${formatBytes(result.bytesFreed)} freed$extra)')}',
      );
    } else {
      stats.failed++;
      stats.failures.add('${item.location}: ${result.error}');
      logger.warn('Could not delete ${item.displayName}: ${result.error}');
    }
  }
}
