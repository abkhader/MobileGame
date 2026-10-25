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
    put('1-01.json', level('1-01', ['#######', '#S...E#', '#######'], 1));
    put(
      '1-02.json',
      level('1-02', ['#######', '#S...E#', '#######'], 1, {'bestScore': 4}),
    );
    final (code, out) = await run(['--check']);
    expect(code, 1);
    expect(out, contains('1-01.json: FAIL missing bestScore'));
    expect(out, contains('1-02.json: FAIL missing solution'));
  });

  test('--check reports a solution with the wrong score', () async {
    put(
      '1-01.json',
      level(
        '1-01',
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
    expect(out, contains('1-01.json: FAIL solution scores 5, expected 4'));
  });

  test('--check reports an id that does not match the file name', () async {
    put('1-01.json', level('1-02', ['#######', '#S...E#', '#######'], 1));
    final (code, out) = await run(['--check']);
    expect(code, 1);
    expect(out, '1-01.json: FAIL id \'1-02\' does not match file name\n');
  });

  test('--check reports format errors', () async {
    put('1-01.json', level('1-01', ['#######', '#.....#', '#######'], 1));
    final (code, out) = await run(['--check']);
    expect(code, 1);
    expect(out, '1-01.json: FAIL grid must contain exactly one S\n');
  });

  test('--check reports an unsolvable level', () async {
    put('1-01.json', level('1-01', ['S#E'], 1));
    final (code, out) = await run(['--check']);
    expect(code, 1);
    expect(out, '1-01.json: FAIL unsolvable\n');
  });

  test('an unreadable file fails and processing continues', () async {
    File('${dir.path}/bad.json').writeAsBytesSync([0xff, 0xfe, 0xfd]);
    put('1-01.json', level('1-01', ['#######', '#S...E#', '#######'], 1));
    final (code, out) = await run(['--write']);
    expect(code, 1);
    expect(out, '1-01.json: OK (best 4)\nbad.json: FAIL cannot read file\n');
  });

  test('--write does not modify a file that fails', () async {
    put('1-01.json', level('1-02', ['#######', '#S...E#', '#######'], 1));
    final before = File('${dir.path}/1-01.json').readAsStringSync();
    final (code, _) = await run(['--write']);
    expect(code, 1);
    expect(File('${dir.path}/1-01.json').readAsStringSync(), before);
  });

  test('--max-nodes 10 reports budget exceeded', () async {
    put('1-03.json', level('1-03', ['#######', '#Sa.AE#', '#######'], 2));
    final (code, out) = await run(['--check', '--max-nodes', '10']);
    expect(code, 1);
    expect(out, '1-03.json: FAIL budget exceeded\n');
  });

  test('files are processed in name order', () async {
    put('1-02.json', level('1-02', ['#######', '#S...E#', '#######'], 1));
    put('1-01.json', level('1-01', ['#######', '#S...E#', '#######'], 1));
    final (_, out) = await run(['--write']);
    expect(out, '1-01.json: OK (best 4)\n1-02.json: OK (best 4)\n');
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

    test('ids outside C-NN with chapter 1-3 and level 01-10 fail', () async {
      const grid = ['#######', '#S...E#', '#######'];
      for (final id in ['a', '4-01', '0-01', '1-00', '1-11', '1-1', '01-01']) {
        put('$id.json', level(id, grid, 1));
      }
      final (code, out) = await run(['--write']);
      expect(code, 1);
      final lines = out.trimRight().split('\n');
      expect(lines, hasLength(7));
      for (final line in lines) {
        expect(
          line,
          matches(
            RegExp(
              r"^(\S+)\.json: FAIL id '\1' is not C-NN with chapter 1-3 and level 01-10$",
            ),
          ),
        );
      }
    });

    test('a tip on a level other than 1-01 to 1-03 and 1-07 fails', () async {
      for (final id in ['1-04', '1-05', '1-06', '1-08']) {
        put(
          '$id.json',
          level(id, ['#######', '#S...E#', '#######'], 1, {'tip': 'Hi.'}),
        );
        final (code, out) = await run(['--write']);
        expect(code, 1);
        expect(
          out,
          '$id.json: FAIL tip only allowed on levels 1-01 to 1-03 and 1-07\n',
        );
        File('${dir.path}/$id.json').deleteSync();
      }
    });

    test('a tip on 1-07 passes', () async {
      put(
        '1-07.json',
        level('1-07', ['#######', '#S...E#', '#######'], 1, {'tip': 'Hi.'}),
      );
      final (code, out) = await run(['--write']);
      expect(code, 0);
      expect(out, '1-07.json: OK (best 4)\n');
    });

    test('a tip on 1-01 to 1-03 passes', () async {
      put(
        '1-01.json',
        level('1-01', ['#######', '#S...E#', '#######'], 1, {'tip': 'Hi.'}),
      );
      final (code, out) = await run(['--write']);
      expect(code, 0);
      expect(out, '1-01.json: OK (best 4)\n');
    });

    test('a reduced solve that exceeds the budget fails', () async {
      put('1-03.json', level('1-03', echoGrid, 2));
      // The main solve searches every smaller run count first, so a shared
      // --max-nodes cannot overflow only the proof: shrink its budget alone.
      final buffer = StringBuffer();
      final code = await runCli(
        [dir.path, '--write'],
        out: buffer,
        reducedMaxNodes: 1,
      );
      final out = buffer.toString();
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
