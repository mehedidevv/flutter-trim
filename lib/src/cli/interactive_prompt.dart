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

  /// Bring back the most recently deleted item (only offered when the
  /// cleaner keeps backups and something was deleted).
  undo('Undo last delete'),

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

  /// Deletions that can still be undone in this session, newest last.
  final List<_Deletion> _undoable = [];

  /// Asks about each of [items] in order and returns what happened.
  TrimStats run(List<TrimItem> items) {
    final stats = TrimStats()..backedUp = cleaner.backup != null;
    var deleteAll = false;

    for (var i = 0; i < items.length; i++) {
      final item = items[i];

      if (!deleteAll) {
        _describe(item, i + 1, items.length, stats);
        final decision = logger.chooseOne<PromptDecision>(
          'What do you want to do?',
          choices: [
            for (final choice in PromptDecision.values)
              if (choice != PromptDecision.undo || _undoable.isNotEmpty) choice,
          ],
          defaultValue: PromptDecision.keep,
          display: (choice) => choice == PromptDecision.undo
              ? '${choice.label} (${_undoable.last.item.displayName})'
              : choice.label,
        );

        if (decision == PromptDecision.undo) {
          _undo(stats);
          i--; // Ask again about the current item.
          continue;
        }
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

  void _undo(TrimStats stats) {
    final last = _undoable.removeLast();
    try {
      cleaner.backup!.restore(last.backupId);
    } on FileSystemException catch (e) {
      logger.warn('Could not undo ${last.item.displayName}: ${e.message}');
      return;
    }
    stats
      ..deleted -= 1
      ..bytesFreed -= last.bytesFreed
      ..kept += 1
      ..restored += 1;
    logger.info(
      '${Ui.indent}${paint(lightCyan, '↺')} Restored '
      '${paint(styleBold, last.item.displayName)} (now kept)',
    );
  }

  void _delete(TrimItem item, TrimStats stats) {
    final result = cleaner.clean(item);
    if (result.success) {
      if (result.backupId case final id?) {
        _undoable.add(_Deletion(item, id, result.bytesFreed));
      }
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

/// A deletion that can be undone from its backup.
class _Deletion {
  const _Deletion(this.item, this.backupId, this.bytesFreed);

  final TrimItem item;
  final int backupId;
  final int bytesFreed;
}
