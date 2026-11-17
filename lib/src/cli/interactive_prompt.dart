import 'dart:io';

import 'package:mason_logger/mason_logger.dart';

import '../cleaners/file_cleaner.dart';
import '../models/sweep_item.dart';
import '../utils/logger.dart';

/// Choices offered for every item.
enum PromptDecision {
  /// Leave the item and move on.
  keep('Keep'),

  /// Delete the item now.
  delete('Delete'),

  /// Delete this and every remaining item (after a confirmation).
  deleteAll('Delete all remaining'),

  /// Stop and leave everything that is left.
  quit('Skip all / Quit');

  const PromptDecision(this.label);

  /// Text shown in the menu.
  final String label;
}

/// Walks the user through findings one by one with an arrow-key menu.
class InteractivePrompt {
  /// Creates a prompt that talks through [logger] and deletes with [cleaner].
  InteractivePrompt({required this.logger, required this.cleaner});

  /// Terminal used for output, menus and confirmations.
  final Logger logger;

  /// Performs the actual deletions.
  final FileCleaner cleaner;

  static const int _previewLines = 4;

  /// Asks about each of [items] in order and returns what happened.
  SweepStats run(List<SweepItem> items) {
    final stats = SweepStats();
    var deleteAll = false;

    for (var i = 0; i < items.length; i++) {
      final item = items[i];

      if (!deleteAll) {
        _describe(item, i + 1, items.length);
        final decision = logger.chooseOne<PromptDecision>(
          'What should flutter_sweeper do?',
          choices: PromptDecision.values,
          defaultValue: PromptDecision.keep,
          display: (choice) => choice.label,
        );

        if (decision == PromptDecision.keep) {
          stats.kept++;
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

  void _describe(SweepItem item, int position, int total) {
    final header = ' ${item.typeLabel} · $position/$total ';
    final ruleLength = header.length >= 46 ? 4 : 50 - header.length;
    logger
      ..info('')
      ..info(paint(darkGray, '──$header${'─' * ruleLength}'))
      ..info(_row('Name', paint(styleBold, item.displayName)))
      ..info(_row('Location', paint(lightCyan, item.location)))
      ..info(_row('Size', formatBytes(item.sizeBytes)))
      ..info(_row('Reason', item.reason));
    for (final companion in item.companionPaths) {
      logger.info(_row('Also', companion));
    }
    if (item.isDeclaration && item.lineNumber != null) _preview(item);
  }

  static String _row(String label, String value) =>
      '  ${paint(darkGray, label.padRight(8))} $value';

  void _preview(SweepItem item) {
    try {
      final lines = File(item.path).readAsLinesSync();
      final start = item.lineNumber! - 1;
      final end = start + _previewLines < lines.length
          ? start + _previewLines
          : lines.length;
      for (var i = start; i < end; i++) {
        final number = '${i + 1}'.padLeft(5);
        logger.info(paint(darkGray, '  $number │ ${lines[i]}'));
      }
    } on FileSystemException {
      // The preview is best effort only.
    }
  }

  void _delete(SweepItem item, SweepStats stats) {
    final result = cleaner.clean(item);
    if (result.success) {
      stats.deleted++;
      stats.bytesFreed += result.bytesFreed;
      if (item.type != SweepItemType.asset) stats.touchedDartCode = true;
      final extra = result.message == null ? '' : ' (${result.message})';
      logger.info(
        '  ${paint(lightRed, '✗ Deleted')} ${item.displayName}$extra',
      );
    } else {
      stats.failed++;
      stats.failures.add('${item.location}: ${result.error}');
      logger.warn('Could not delete ${item.displayName}: ${result.error}');
    }
  }
}
