import 'dart:convert';
import 'dart:io';

import 'package:echo_solver/src/cli.dart';
import 'package:test/test.dart';

const _usage =
    'usage: echo_solver <levels-dir> (--check | --write) [--max-nodes N] '
    '[--report]';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('echo_cli_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  void put(String file, Map<String, Object?> level) =>
      File('${dir.path}/$file').writeAsStringSync(jsonEncode(level));

  Map<String, Object?> level(
    String id,
    List<String> grid,
    int runs, [
    Map<String, Object?> extra = const {},
  ]) => {'id': id, 'name': 'T', 'runLimit': runs, 'grid': grid, ...extra};

  Future<(int, String)> run(List<String> args) async {
    final out = StringBuffer();
    final code = await runCli([dir.path, ...args], out: out);
    return (code, out.toString());
  }

  test('--write adds bestScore and solution, then --check passes', () async {
    put('1-01.json', level('1-01', ['#######', '#S...E#', '#######'], 1));
    final (wCode, wOut) = await run(['--write']);
    expect(wCode, 0);
    expect(wOut, '1-01.json: OK (best 4)\n');
    final written =
        jsonDecode(File('${dir.path}/1-01.json').readAsStringSync()) as Map;
    expect(written['bestScore'], 4);
    expect(written['solution'], [
      ['R', 'R', 'R', 'R'],
    ]);
    expect(written.keys.toList(), [
      'id',
      'name',
      'runLimit',
      'grid',
      'bestScore',
      'solution',
    ]);
    expect(File('${dir.path}/1-01.json').readAsStringSync(), endsWith('}\n'));
    final (cCode, cOut) = await run(['--check']);
    expect(cCode, 0);
    expect(cOut, '1-01.json: OK (best 4)\n');
  });

  test('--check reports a wrong stored bestScore', () async {
    put(
      '1-03.json',
      level(
        '1-03',
        ['#######', '#Sa.AE#', '#######'],
        2,
        {
          'bestScore': 9,
          'solution': [
            ['R', 'W'],
            ['R', 'R', 'R'],
          ],
        },
      ),
    );
    final (code, out) = await run(['--check']);
    expect(code, 1);
    expect(out, contains('stored 9, computed 5'));
  });

  test('--check reports a missing bestScore and a missing solution', () async {
    put('a.json', level('a', ['#######', '#S...E#', '#######'], 1));
    put(
      'b.json',
      level('b', ['#######', '#S...E#', '#######'], 1, {'bestScore': 4}),
    );
    final (code, out) = await run(['--check']);
    expect(code, 1);
    expect(out, contains('a.json: FAIL missing bestScore'));
    expect(out, contains('b.json: FAIL missing solution'));
  });

  test('--check reports a solution with the wrong score', () async {
    put(
      'a.json',
      level(
        'a',
        ['#######', '#S...E#', '#######'],
        1,
        {
          'bestScore': 4,
          'solution': [
            ['R', 'R', 'R', 'W', 'R'],
          ],
        },
      ),
    );
    final (code, out) = await run(['--check']);
    expect(code, 1);
    expect(out, contains('a.json: FAIL solution scores 5, expected 4'));
  });

  test('--check reports an id that does not match the file name', () async {
    put('x.json', level('y', ['#######', '#S...E#', '#######'], 1));
    final (code, out) = await run(['--check']);
    expect(code, 1);
    expect(out, 'x.json: FAIL id \'y\' does not match file name\n');
  });

  test('--check reports format errors', () async {
    put('a.json', level('a', ['#######', '#.....#', '#######'], 1));
    final (code, out) = await run(['--check']);
    expect(code, 1);
    expect(out, 'a.json: FAIL grid must contain exactly one S\n');
  });

  test('--check reports an unsolvable level', () async {
    put('a.json', level('a', ['S#E'], 1));
    final (code, out) = await run(['--check']);
    expect(code, 1);
    expect(out, 'a.json: FAIL unsolvable\n');
  });

  test('an unreadable file fails and processing continues', () async {
    File('${dir.path}/bad.json').writeAsBytesSync([0xff, 0xfe, 0xfd]);
    put('ok.json', level('ok', ['#######', '#S...E#', '#######'], 1));
    final (code, out) = await run(['--write']);
    expect(code, 1);
    expect(out, 'bad.json: FAIL cannot read file\nok.json: OK (best 4)\n');
  });

  test('--write does not modify a file that fails', () async {
    put('x.json', level('y', ['#######', '#S...E#', '#######'], 1));
    final before = File('${dir.path}/x.json').readAsStringSync();
    final (code, _) = await run(['--write']);
    expect(code, 1);
    expect(File('${dir.path}/x.json').readAsStringSync(), before);
  });

  test('--max-nodes 10 reports budget exceeded', () async {
    put('a.json', level('a', ['#######', '#Sa.AE#', '#######'], 2));
    final (code, out) = await run(['--check', '--max-nodes', '10']);
    expect(code, 1);
    expect(out, 'a.json: FAIL budget exceeded\n');
  });

  test('files are processed in name order', () async {
    put('b.json', level('b', ['#######', '#S...E#', '#######'], 1));
    put('a.json', level('a', ['#######', '#S...E#', '#######'], 1));
    final (_, out) = await run(['--write']);
    expect(out, 'a.json: OK (best 4)\nb.json: OK (best 4)\n');
  });

  test('an empty directory exits 0 with no output', () async {
    final (code, out) = await run(['--check']);
    expect(code, 0);
    expect(out, isEmpty);
  });

  group('level quality checks', () {
    const echoGrid = ['#######', '#Sa.AE#', '#######'];

    test('1-03 with 2 runs passes and needs both runs', () async {
      put('1-03.json', level('1-03', echoGrid, 2));
      final (wCode, wOut) = await run(['--write']);
      expect(wCode, 0);
      expect(wOut, '1-03.json: OK (best 5)\n');
      final (cCode, cOut) = await run(['--check']);
      expect(cCode, 0);
      expect(cOut, '1-03.json: OK (best 5)\n');
    });

    test('a level solvable with one run fewer fails', () async {
      put('2-09.json', level('2-09', echoGrid, 3));
      final (wCode, wOut) = await run(['--write']);
      expect(wCode, 1);
      expect(wOut, '2-09.json: FAIL solvable with 2 runs (best 5)\n');
      final written =
          jsonDecode(File('${dir.path}/2-09.json').readAsStringSync()) as Map;
      expect(written['bestScore'], 5);
      final (cCode, cOut) = await run(['--check']);
      expect(cCode, 1);
      expect(cOut, '2-09.json: FAIL solvable with 2 runs (best 5)\n');
    });

    test('runLimit outside the chapter range fails', () async {
      put('2-01.json', level('2-01', ['#######', '#S...E#', '#######'], 1));
      final (code, out) = await run(['--write']);
      expect(code, 1);
      expect(
        out,
        '2-01.json: FAIL runLimit 1 outside chapter 2 range 2\u20133\n',
      );
    });

    test('ids without a known chapter skip the range check', () async {
      put('a.json', level('a', ['#######', '#S...E#', '#######'], 1));
      final (code, _) = await run(['--write']);
      expect(code, 0);
    });

    test('a reduced solve that exceeds the budget fails', () async {
      put('1-03.json', level('1-03', echoGrid, 2));
      final (code, out) = await run(['--write', '--max-nodes', '50']);
      expect(code, 1);
      expect(
        out,
        '1-03.json: FAIL cannot prove 2 runs are needed (budget exceeded)\n',
      );
    });

    test('--report prints difficulty after the OK line', () async {
      put('1-01.json', level('1-01', ['#######', '#S...E#', '#######'], 1));
      await run(['--write']);
      final (code, out) = await run(['--check', '--report']);
      expect(code, 0);
      final lines = out.trimRight().split('\n');
      expect(lines, hasLength(2));
      expect(lines[0], '1-01.json: OK (best 4)');
      expect(
        lines[1],
        matches(RegExp(r'^  runs 1, best 4, nodes \d+, \d+ ms$')),
      );
    });
  });

  group('bad arguments exit 64 with the usage line', () {
    Future<void> expectUsage(List<String> args) async {
      final out = StringBuffer();
      expect(await runCli(args, out: out), 64);
      expect(out.toString(), '$_usage\n');
    }

    test('no mode flag', () => expectUsage([dir.path]));
    test(
      'both mode flags',
      () => expectUsage([dir.path, '--check', '--write']),
    );
    test('no arguments', () => expectUsage([]));
    test(
      'missing directory',
      () => expectUsage(['${dir.path}/nope', '--check']),
    );
    test(
      'non-numeric max-nodes',
      () => expectUsage([dir.path, '--check', '--max-nodes', 'x']),
    );
    test(
      'zero max-nodes',
      () => expectUsage([dir.path, '--check', '--max-nodes', '0']),
    );
    test(
      'max-nodes without value',
      () => expectUsage([dir.path, '--check', '--max-nodes']),
    );
    test('--report without a mode', () => expectUsage([dir.path, '--report']));
    test(
      'repeated --report',
      () => expectUsage([dir.path, '--check', '--report', '--report']),
    );
    test('unknown flag', () => expectUsage([dir.path, '--check', '--nope']));
  });
}
