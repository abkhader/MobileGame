import 'dart:convert';
import 'dart:io';

import 'package:echo_core/echo_core.dart';

import 'replay.dart';
import 'solver.dart';

const _usage =
    'usage: echo_solver <levels-dir> (--check | --write) [--max-nodes N]';

/// Runs the solver CLI and returns the process exit code.
///
/// `--check` verifies every `*.json` level in the directory; `--write` fills
/// in `bestScore` and `solution` from the solver. Output goes to [out]
/// (default [stdout]).
Future<int> runCli(List<String> args, {StringSink? out}) async {
  final sink = out ?? stdout;
  final options = _parseArgs(args);
  if (options == null) {
    sink.writeln(_usage);
    return 64;
  }

  final files =
      options.dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => _baseName(a).compareTo(_baseName(b)));

  var failed = false;
  for (final file in files) {
    final name = _baseName(file);
    final result = _process(file, options);
    if (result.startsWith('OK')) {
      sink.writeln('$name: $result');
    } else {
      failed = true;
      sink.writeln('$name: FAIL $result');
    }
  }
  return failed ? 1 : 0;
}

class _Options {
  _Options(this.dir, {required this.write, required this.maxNodes});

  final Directory dir;
  final bool write;
  final int? maxNodes;
}

_Options? _parseArgs(List<String> args) {
  String? dir;
  bool? write;
  int? maxNodes;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    switch (arg) {
      case '--check' || '--write':
        if (write != null) return null;
        write = arg == '--write';
      case '--max-nodes':
        if (maxNodes != null || i + 1 >= args.length) return null;
        final n = int.tryParse(args[++i]);
        if (n == null || n < 1) return null;
        maxNodes = n;
      default:
        if (arg.startsWith('--') || dir != null) return null;
        dir = arg;
    }
  }
  if (dir == null || write == null) return null;
  final directory = Directory(dir);
  if (!directory.existsSync()) return null;
  return _Options(directory, write: write, maxNodes: maxNodes);
}

String _baseName(File file) => file.uri.pathSegments.last;

/// Returns `OK (best N)` or the failure reason.
String _process(File file, _Options options) {
  final String text;
  try {
    text = file.readAsStringSync();
  } on FileSystemException {
    return 'cannot read file';
  }
  final Level level;
  try {
    level = LevelLoader.parse(text);
  } on LevelFormatException catch (e) {
    return e.message;
  }

  final name = _baseName(file);
  if ('${level.id}.json' != name) {
    return "id '${level.id}' does not match file name";
  }

  final result = options.maxNodes == null
      ? solve(level)
      : solve(level, maxNodes: options.maxNodes!);
  switch (result) {
    case Unsolvable():
      return 'unsolvable';
    case BudgetExceeded():
      return 'budget exceeded';
    case Solved(:final bestScore, :final solution):
      if (options.write) {
        final map = jsonDecode(text) as Map<String, dynamic>;
        map['bestScore'] = bestScore;
        map['solution'] = [
          for (final run in solution) [for (final m in run) m.code],
        ];
        file.writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(map)}\n',
        );
        return 'OK (best $bestScore)';
      }
      final stored = level.bestScore;
      if (stored == null) return 'missing bestScore';
      if (stored != bestScore) {
        return 'stored $stored, computed $bestScore';
      }
      final stack = level.solution;
      if (stack == null) return 'missing solution';
      final score = replayScore(level, stack);
      if (score != bestScore) {
        return 'solution scores ${score ?? 'none'}, expected $bestScore';
      }
      return 'OK (best $bestScore)';
  }
}
