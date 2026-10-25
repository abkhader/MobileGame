import 'dart:convert';
import 'dart:io';

import 'package:echo_core/echo_core.dart';

import 'replay.dart';
import 'solver.dart';

const _usage =
    'usage: echo_solver <levels-dir> (--check | --write) [--max-nodes N] '
    '[--report]';

/// Allowed `runLimit` range (inclusive) per chapter.
final _levelId = RegExp(r'^[1-3]-(0[1-9]|10)$');
const _tipIds = {'1-01', '1-02', '1-03', '1-07'};
const _chapterRanges = {'1': (1, 2), '2': (2, 3), '3': (3, 4)};

/// Runs the solver CLI and returns the process exit code.
///
/// `--check` verifies every `*.json` level in the directory; `--write` fills
/// in `bestScore` and `solution` from the solver. Output goes to [out]
/// (default [stdout]). [reducedMaxNodes] is test-only: it overrides the node
/// budget of the "needs every run" proof.
Future<int> runCli(
  List<String> args, {
  StringSink? out,
  int? reducedMaxNodes,
}) async {
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
    final watch = Stopwatch()..start();
    final result = _process(file, options, reducedMaxNodes);
    watch.stop();
    if (result.failure == null) {
      sink.writeln('$name: OK (best ${result.best})');
      if (options.report) {
        sink.writeln(
          '  runs ${result.runs}, best ${result.best}, nodes ${result.nodes}, '
          '${watch.elapsedMilliseconds} ms',
        );
      }
    } else {
      failed = true;
      sink.writeln('$name: FAIL ${result.failure}');
    }
  }
  return failed ? 1 : 0;
}

class _Options {
  _Options(
    this.dir, {
    required this.write,
    required this.maxNodes,
    required this.report,
  });

  final Directory dir;
  final bool write;
  final int? maxNodes;
  final bool report;
}

/// Outcome of processing one file: [failure] is null when every check passed.
class _Outcome {
  _Outcome.fail(this.failure) : best = 0, runs = 0, nodes = 0;
  _Outcome.ok({required this.best, required this.runs, required this.nodes})
    : failure = null;

  final String? failure;
  final int best;
  final int runs;
  final int nodes;
}

_Options? _parseArgs(List<String> args) {
  String? dir;
  bool? write;
  int? maxNodes;
  var report = false;
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
      case '--report':
        if (report) return null;
        report = true;
      default:
        if (arg.startsWith('--') || dir != null) return null;
        dir = arg;
    }
  }
  if (dir == null || write == null) return null;
  final directory = Directory(dir);
  if (!directory.existsSync()) return null;
  return _Options(directory, write: write, maxNodes: maxNodes, report: report);
}

String _baseName(File file) => file.uri.pathSegments.last;

_Outcome _process(File file, _Options options, int? reducedMaxNodes) {
  final String text;
  try {
    text = file.readAsStringSync();
  } on FileSystemException {
    return _Outcome.fail('cannot read file');
  }
  final Level level;
  try {
    level = LevelLoader.parse(text);
  } on LevelFormatException catch (e) {
    return _Outcome.fail(e.message);
  }

  final name = _baseName(file);
  if ('${level.id}.json' != name) {
    return _Outcome.fail("id '${level.id}' does not match file name");
  }

  final result = options.maxNodes == null
      ? solve(level)
      : solve(level, maxNodes: options.maxNodes!);
  switch (result) {
    case Unsolvable():
      return _Outcome.fail('unsolvable');
    case BudgetExceeded():
      return _Outcome.fail('budget exceeded');
    case Solved(:final bestScore, :final solution, :final nodes):
      if (options.write) {
        final map = jsonDecode(text) as Map<String, dynamic>;
        map['bestScore'] = bestScore;
        map['solution'] = [
          for (final run in solution) [for (final m in run) m.code],
        ];
        file.writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(map)}\n',
        );
      } else {
        final stored = level.bestScore;
        if (stored == null) return _Outcome.fail('missing bestScore');
        if (stored != bestScore) {
          return _Outcome.fail('stored $stored, computed $bestScore');
        }
        final stack = level.solution;
        if (stack == null) return _Outcome.fail('missing solution');
        final score = replayScore(level, stack);
        if (score != bestScore) {
          return _Outcome.fail(
            'solution scores ${score ?? 'none'}, expected $bestScore',
          );
        }
      }
      final quality = _qualityFailure(
        level,
        jsonDecode(text) as Map<String, dynamic>,
        options.maxNodes,
        reducedMaxNodes,
      );
      if (quality != null) return _Outcome.fail(quality);
      return _Outcome.ok(best: bestScore, runs: level.runLimit, nodes: nodes);
  }
}

/// Id format, chapter run range, tip rule, then the proof that `runLimit - 1` runs do not suffice.
String? _qualityFailure(
  Level level,
  Map<String, dynamic> map,
  int? maxNodes,
  int? reducedMaxNodes,
) {
  final runs = level.runLimit;
  if (!_levelId.hasMatch(level.id)) {
    return "id '${level.id}' is not C-NN with chapter 1-3 and level 01-10";
  }
  final chapter = level.id.substring(0, 1);
  final (lo, hi) = _chapterRanges[chapter]!;
  if (runs < lo || runs > hi) {
    return 'runLimit $runs outside chapter $chapter range $lo\u2013$hi';
  }
  if (level.tip != null && !_tipIds.contains(level.id)) {
    return 'tip only allowed on levels 1-01 to 1-03 and 1-07';
  }
  if (runs > 1) {
    final reduced = LevelLoader.fromMap(
      {...map, 'runLimit': runs - 1}
        ..remove('bestScore')
        ..remove('solution'),
    );
    final budget = reducedMaxNodes ?? maxNodes;
    switch (budget == null
        ? solve(reduced)
        : solve(reduced, maxNodes: budget)) {
      case Solved(:final bestScore):
        return 'solvable with ${runs - 1} runs (best $bestScore)';
      case BudgetExceeded():
        return 'cannot prove $runs runs are needed (budget exceeded)';
      case Unsolvable():
        break;
    }
  }
  return null;
}
