import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Folder (relative to the project root) that holds deletion backups.
///
/// It starts with a dot, so the scanners never look inside it.
const String backupDirName = '.flutter_trim';

/// One undoable change: the original copies of every file it touched.
class BackupEntry {
  /// Creates an entry.
  const BackupEntry({
    required this.id,
    required this.label,
    required this.files,
    this.restored = false,
  });

  /// Reads an entry from the session manifest.
  factory BackupEntry.fromJson(Map<String, Object?> json) => BackupEntry(
        id: json['id'] as int,
        label: json['label'] as String,
        files: [
          for (final file in json['files'] as List<Object?>)
            (file as Map<String, Object?>)['path'] as String,
        ],
        restored: json['restored'] as bool? ?? false,
      );

  /// Position of the change inside its session (1, 2, …).
  final int id;

  /// What was removed, e.g. `UnusedWidget`.
  final String label;

  /// Project-relative (posix) paths of the files saved for this change.
  final List<String> files;

  /// Whether the change has already been undone.
  final bool restored;

  /// JSON form stored in `manifest.json`.
  Map<String, Object?> toJson() => {
        'id': id,
        'label': label,
        'files': [
          for (final file in files) {'path': file},
        ],
        'restored': restored,
      };

  /// A copy with [restored] set.
  BackupEntry markRestored() =>
      BackupEntry(id: id, label: label, files: files, restored: true);
}

/// Keeps a copy of every file before `ftrim` deletes or edits it, so each
/// change can be undone during the review or later with `ftrim --restore`.
///
/// Layout: `<root>/.flutter_trim/backups/<session>/<entry id>/<relative path>`
/// plus a `manifest.json` per session.
class BackupStore {
  BackupStore._(this.root, this.sessionDir);

  /// Starts a new backup session for the project at [root].
  factory BackupStore.start(String root) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final name = '${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    var dir = p.join(backupsDir(root), name);
    for (var i = 2; Directory(dir).existsSync(); i++) {
      dir = p.join(backupsDir(root), '$name-$i');
    }
    return BackupStore._(root, dir);
  }

  /// Opens the most recent session of [root] that still has changes to
  /// undo, or returns `null` when there is none.
  static BackupStore? latest(String root) {
    final dir = Directory(backupsDir(root));
    if (!dir.existsSync()) return null;
    final sessions = dir.listSync().whereType<Directory>().toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final session in sessions) {
      final store = BackupStore._(root, session.path);
      if (store.pending.isNotEmpty) return store;
    }
    return null;
  }

  /// Folder that holds every backup session of [root].
  static String backupsDir(String root) =>
      p.join(root, backupDirName, 'backups');

  /// Project root the relative paths are resolved against.
  final String root;

  /// Folder of this session.
  final String sessionDir;

  /// Session name (its folder name), e.g. `20261118-153012`.
  String get name => p.basename(sessionDir);

  File get _manifest => File(p.join(sessionDir, 'manifest.json'));

  /// Every change recorded in this session, oldest first.
  List<BackupEntry> get entries {
    if (!_manifest.existsSync()) return [];
    final json = jsonDecode(_manifest.readAsStringSync());
    if (json is! Map<String, Object?>) return [];
    return [
      for (final entry in json['entries'] as List<Object?>? ?? const [])
        BackupEntry.fromJson(entry as Map<String, Object?>),
    ];
  }

  /// Changes that have not been undone yet, oldest first.
  List<BackupEntry> get pending =>
      entries.where((entry) => !entry.restored).toList();

  /// Copies the existing files among [paths] (absolute) into a new entry and
  /// returns its id. Throws a [FileSystemException] if a copy fails, so the
  /// caller can refuse to delete anything without a backup.
  int save(String label, Iterable<String> paths) {
    final all = entries;
    final id = all.isEmpty ? 1 : all.last.id + 1;
    final saved = <String>[];
    for (final path in paths) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final relative = p.relative(path, from: root);
      final target = File(p.join(sessionDir, '$id', relative));
      target.parent.createSync(recursive: true);
      file.copySync(target.path);
      saved.add(p.posix.joinAll(p.split(relative)));
    }
    _write([...all, BackupEntry(id: id, label: label, files: saved)]);
    return id;
  }

  /// Puts back the files of entry [id] and marks it as restored.
  /// Returns the number of files written.
  int restore(int id) {
    final all = entries;
    final index = all.indexWhere((entry) => entry.id == id);
    if (index < 0) {
      throw FileSystemException('No backup with id $id', sessionDir);
    }
    final entry = all[index];
    for (final relative in entry.files) {
      final source =
          File(p.joinAll([sessionDir, '$id', ...relative.split('/')]));
      final target = File(p.joinAll([root, ...relative.split('/')]));
      target.parent.createSync(recursive: true);
      source.copySync(target.path);
    }
    all[index] = entry.markRestored();
    _write(all);
    return entry.files.length;
  }

  /// Undoes every pending change, newest first, and returns them.
  List<BackupEntry> restoreAll() {
    final undone = pending.reversed.toList();
    for (final entry in undone) {
      restore(entry.id);
    }
    return undone;
  }

  void _write(List<BackupEntry> all) {
    _manifest.parent.createSync(recursive: true);
    _manifest.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'session': name,
        'entries': [for (final entry in all) entry.toJson()],
      }),
    );
  }
}
