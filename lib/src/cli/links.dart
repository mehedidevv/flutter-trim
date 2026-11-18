import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/trim_item.dart';

/// Turns finding locations into clickable terminal links that open the
/// code in an editor.
///
/// The visible text is always `path:line` relative to the current folder,
/// which the VS Code, Cursor and Android Studio / IntelliJ terminals already
/// make clickable (with the line). Other terminals (iTerm2, WezTerm, kitty,
/// Ghostty, Windows Terminal, …) get an OSC 8 hyperlink around that text.
class Linker {
  /// Creates a linker.
  ///
  /// [editor] is one of `auto`, `vscode`, `cursor`, `idea`, `file`, `none`.
  /// [environment], [workingDirectory] and [terminal] are injectable for
  /// tests.
  Linker({
    this.editor = 'auto',
    bool enabled = true,
    Map<String, String>? environment,
    String? workingDirectory,
    bool? terminal,
  })  : _environment = environment ?? Platform.environment,
        workingDirectory = workingDirectory ?? Directory.current.path,
        _enabled = enabled &&
            editor != 'none' &&
            (terminal ?? (stdout.hasTerminal && stdout.supportsAnsiEscapes));

  /// A linker that never adds hyperlinks.
  Linker.plain({String? workingDirectory})
      : this(editor: 'none', workingDirectory: workingDirectory);

  /// Requested editor (see the constructor).
  final String editor;

  /// Folder that visible paths are relative to.
  final String workingDirectory;

  final Map<String, String> _environment;
  final bool _enabled;

  /// Whether the terminal turns plain `path:line` text into links itself.
  bool get _ideTerminal =>
      _environment['TERM_PROGRAM'] == 'vscode' ||
      _environment['TERMINAL_EMULATOR'] == 'JetBrains-JediTerm';

  /// `path` relative to the working folder, or absolute when it lies outside.
  String displayPath(String path) {
    final relative = p.relative(path, from: workingDirectory);
    return relative.startsWith('..') ? path : relative;
  }

  /// `path:line` (declarations) or `path` (files), clickable when possible.
  String location(TrimItem item) {
    final line = item.lineNumber;
    final text = line == null
        ? displayPath(item.path)
        : '${displayPath(item.path)}:$line';
    return wrap(text, item.path, line);
  }

  /// Wraps [text] in a hyperlink to [path] (at [line]) when links are on.
  String wrap(String text, String path, [int? line]) {
    final uri = uriFor(path, line);
    if (uri == null) return text;
    return '\x1B]8;;$uri\x1B\\$text\x1B]8;;\x1B\\';
  }

  /// The URI a click should open, or `null` when no hyperlink is needed.
  String? uriFor(String path, [int? line]) {
    if (!_enabled) return null;
    final filePath = Uri.file(p.absolute(path)).path;
    final suffix = line == null ? '' : ':$line';
    return switch (editor) {
      'vscode' => 'vscode://file$filePath$suffix',
      'cursor' => 'cursor://file$filePath$suffix',
      'idea' => 'idea://open?file=${Uri.encodeQueryComponent(p.absolute(path))}'
          '${line == null ? '' : '&line=$line'}',
      'file' => Uri.file(p.absolute(path)).toString(),
      // auto: IDE terminals link plain `path:line` text (keeping the line),
      // which an OSC 8 file link would override.
      _ => _ideTerminal ? null : Uri.file(p.absolute(path)).toString(),
    };
  }
}
