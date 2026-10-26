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
/// (default [stdout]). Both modes also run the spark checks
/// ([sparkFailure]).
/// [reducedMaxNodes] and [sparkMaxNodes] are test-only: they override the
/// node budget of the "needs every run" proof and of each spark proof.
Future<int> runCli(
  List<String> args, {
  StringSink? out,
  int? reducedMaxNodes,
  int? sparkMaxNodes,
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
    final result = _process(file, options, reducedMaxNodes, sparkMaxNodes);
    watch.stop();
    if (result.failure == null) {
      sink.writeln('$name: OK (best ${result.best})');
      if (options.report) {
        sink.writeln(
          '  runs ${result.runs}, best ${result.best}, nodes ${result.nodes}, '
          '${watch.elapsedMilliseconds} ms',
        );
        sink.writeln('  sparks: ${result.sparks}');
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
  _Outcome.fail(this.failure) : best = 0, runs = 0, nodes = 0, sparks = '';
  _Outcome.ok({
    required this.best,
    required this.runs,
    required this.nodes,
    required this.sparks,
  }) : failure = null;

  final String? failure;
  final int best;
  final int runs;
  final int nodes;

  /// The `--report` spark list.
  final String sparks;
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

_Outcome _process(
  File file,
  _Options options,
  int? reducedMaxNodes,
  int? sparkMaxNodes,
) {
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
      final labels = <String>[];
      final failure = sparkFailure(
        level,
        maxNodes: sparkMaxNodes ?? options.maxNodes,
        labels: labels,
      );
      if (failure != null) return _Outcome.fail(failure);
      return _Outcome.ok(
        best: bestScore,
        runs: level.runLimit,
        nodes: nodes,
        sparks: labels.join(', '),
      );
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

/// The spark checks: exactly 3 sparks, each on a floor tile and collectible
/// in a winning play, and in chapters 2-3 at least one that needs an echo
/// (no winning play collects it in run 1). Returns the first failure, or
/// null after adding `(x,y) echo` or `(x,y) run1` per spark to [labels].
/// [maxNodes] is the node budget of each spark proof (default
/// [sparkProofMaxNodes]).
String? sparkFailure(Level level, {int? maxNodes, List<String>? labels}) {
  final sparks = level.sparks;
  if (sparks.length != 3) return 'level has ${sparks.length} sparks (need 3)';
  String at(Position p) => '(${p.x},${p.y})';
  for (final p in sparks) {
    if (!level.inBounds(p) || level.tileAt(p).kind != TileKind.floor) {
      return 'spark at ${at(p)} is not on floor';
    }
  }
  final found = <String>[];
  var echo = false;
  for (final p in sparks) {
    final proof = maxNodes == null
        ? sparkProof(level, p)
        : sparkProof(level, p, maxNodes: maxNodes);
    if (proof.budgetExceeded) {
      return 'cannot prove spark at ${at(p)} is collectible (budget exceeded)';
    }
    if (!proof.collectible) {
      return 'spark at ${at(p)} cannot be collected in a winning play';
    }
    echo |= proof.echoNeeded;
    found.add('${at(p)} ${proof.echoNeeded ? 'echo' : 'run1'}');
  }
  if (!echo && level.id.startsWith(RegExp('[23]-'))) {
    return 'no spark needs an echo';
  }
  labels?.addAll(found);
  return null;
}
