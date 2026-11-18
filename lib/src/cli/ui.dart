import 'dart:io';
import 'dart:math' as math;

import 'package:mason_logger/mason_logger.dart';

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

/// Color codes and OSC 8 hyperlink markers; neither takes up columns.
final RegExp _ansi = RegExp('\x1B(\\[[0-9;]*m|\\]8;;[^\x1B]*\x1B\\\\)');

/// Number of terminal columns [text] occupies (ANSI color codes and
/// hyperlink markers excluded).
int visibleLength(String text) => text.replaceAll(_ansi, '').length;

/// Pads [text] with spaces to [width] visible columns.
String padVisible(String text, int width, {bool alignRight = false}) {
  final gap = width - visibleLength(text);
  if (gap <= 0) return text;
  return alignRight ? '${' ' * gap}$text' : '$text${' ' * gap}';
}

/// Shortens plain [text] to [width] columns, keeping the *end* visible.
/// Used for paths, where the file name matters most.
String fitStart(String text, int width) {
  if (text.length <= width) return text;
  if (width <= 1) return text.substring(text.length - width);
  return '…${text.substring(text.length - width + 1)}';
}

/// Shortens plain [text] to [width] columns, keeping the *start* visible.
String fitEnd(String text, int width) {
  if (text.length <= width) return text;
  if (width <= 1) return text.substring(0, width);
  return '${text.substring(0, width - 1)}…';
}

/// Width available for boxes and tables: the terminal width when known,
/// clamped to a readable range.
int contentWidth() {
  var columns = 100;
  try {
    if (stdout.hasTerminal) columns = stdout.terminalColumns;
  } on StdoutException {
    // Not a terminal; keep the default.
  }
  return math.max(60, math.min(columns - 4, 110));
}

/// Draws rounded boxes, tables and progress bars with consistent styling.
class Ui {
  /// Creates a renderer that lays content out in [width] columns.
  Ui({int? width}) : width = width ?? contentWidth();

  /// Total width of boxes and tables, borders included.
  final int width;

  /// Left margin used for every block.
  static const String indent = '  ';

  String _border(String text) => paint(darkGray, text);

  /// A rounded box with an optional [title] on the top border and [trailing]
  /// text on the right of it. Each entry in [sections] is a group of lines;
  /// groups are separated by a horizontal rule.
  List<String> box(
    List<List<String>> sections, {
    String? title,
    String? trailing,
    AnsiCode titleColor = lightCyan,
  }) {
    final inner = width - 4; // `│ ` + content + ` │`
    final out = <String>[];

    final head = title == null ? '' : ' ${paint(titleColor, title)} ';
    final tail = trailing == null ? '' : ' ${paint(darkGray, trailing)} ';
    final fill = width - 2 - 1 - visibleLength(head) - visibleLength(tail) - 1;
    out.add(
      '$indent${_border('╭─')}$head'
      '${_border('─' * math.max(1, fill))}$tail${_border('─╮')}',
    );

    for (var s = 0; s < sections.length; s++) {
      if (s > 0) out.add('$indent${_border('├${'─' * (width - 2)}┤')}');
      for (final line in sections[s]) {
        final fitted =
            visibleLength(line) > inner ? fitEnd(_strip(line), inner) : line;
        out.add(
          '$indent${_border('│')} ${padVisible(fitted, inner)} ${_border('│')}',
        );
      }
    }
    out.add('$indent${_border('╰${'─' * (width - 2)}╯')}');
    return out;
  }

  /// A bordered table. [align] marks right-aligned columns; [shrink] is the
  /// index of the column that gives up space when the table is too wide.
  /// Cells of the shrinking column are shortened from the start, so paths
  /// keep their file names.
  List<String> table(
    List<String> headers,
    List<List<String>> rows, {
    Set<int> alignRight = const {},
    int shrink = -1,
    List<List<String>> footer = const [],
  }) {
    final all = [headers, ...rows, ...footer];
    final widths = [
      for (var c = 0; c < headers.length; c++)
        all.map((row) => visibleLength(row[c])).reduce(math.max),
    ];
    // Borders and padding take 3 columns per cell plus 1.
    final total = widths.fold<int>(1, (sum, w) => sum + w + 3);
    if (total > width && shrink >= 0) {
      widths[shrink] = math.max(8, widths[shrink] - (total - width));
    }

    String rule(String left, String mid, String right) => _border(
          left + [for (final w in widths) '─' * (w + 2)].join(mid) + right,
        );

    String cells(List<String> values, {bool bold = false}) {
      final parts = <String>[];
      for (var c = 0; c < values.length; c++) {
        var value = values[c];
        if (visibleLength(value) > widths[c]) {
          value = c == shrink
              ? fitStart(_strip(value), widths[c])
              : fitEnd(_strip(value), widths[c]);
        }
        value =
            padVisible(value, widths[c], alignRight: alignRight.contains(c));
        parts.add(' ${bold ? paint(styleBold, value) : value} ');
      }
      return '${_border('│')}${parts.join(_border('│'))}${_border('│')}';
    }

    return [
      '$indent${rule('┌', '┬', '┐')}',
      '$indent${cells(headers, bold: true)}',
      '$indent${rule('├', '┼', '┤')}',
      for (final row in rows) '$indent${cells(row)}',
      if (footer.isNotEmpty) ...[
        '$indent${rule('├', '┼', '┤')}',
        for (final row in footer) '$indent${cells(row, bold: true)}',
      ],
      '$indent${rule('└', '┴', '┘')}',
    ];
  }

  /// A fixed-width progress bar such as `▰▰▰▱▱▱▱▱▱▱`.
  static String progressBar(int done, int total, {int length = 20}) {
    final filled = total == 0 ? length : (done * length / total).round();
    return paint(lightCyan, '▰' * filled) +
        paint(darkGray, '▱' * (length - filled));
  }

  static String _strip(String text) => text.replaceAll(_ansi, '');
}
