import 'package:echo_app/data/progress_repository.dart';
import 'package:echo_app/game/game_clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const ids = ['1-01', '1-02', '1-03'];
const key = 'echo.progress.v1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('fresh install: only first level unlocked', () async {
    final repo = await ProgressRepository.open();
    expect(repo.isUnlocked('1-01', ids), isTrue);
    expect(repo.isUnlocked('1-02', ids), isFalse);
    expect(repo.isUnlocked('9-99', ids), isFalse);
    expect(repo.progressOf('1-01').completed, isFalse);
  });

  test('a win survives reopen and unlocks next', () async {
    var repo = await ProgressRepository.open();
    await repo.recordWin('1-01', score: 5, best: 4, sparkMask: 0);
    repo = await ProgressRepository.open();
    final p = repo.progressOf('1-01');
    expect(p.completed, isTrue);
    expect(p.finished, isTrue);
    expect(p.stars, 1);
    expect(repo.isUnlocked('1-02', ids), isTrue);
  });

  test('stars: finished + all three sparks + moves', () async {
    final repo = await ProgressRepository.open();
    await repo.recordWin('1-01', score: 4, best: 4, sparkMask: 0);
    expect(repo.progressOf('1-01').stars, 2);
    await repo.recordWin('1-02', score: 9, best: 4, sparkMask: 0x7);
    expect(repo.progressOf('1-02').stars, 2);
    await repo.recordWin('1-03', score: 3, best: 4, sparkMask: 0x7);
    final p = repo.progressOf('1-03');
    expect(p.stars, 3);
    expect(p.goals, (finished: true, allSparks: true, moves: true));
  });

  test('sparks OR across wins; moves star is kept', () async {
    var repo = await ProgressRepository.open();
    await repo.recordWin('1-01', score: 4, best: 4, sparkMask: 0x1);
    await repo.recordWin('1-01', score: 9, best: 4, sparkMask: 0x4);
    var p = repo.progressOf('1-01');
    expect(p.sparkMask, 0x5);
    expect(p.movesStar, isTrue);
    expect(p.stars, 2);
    expect(p.goals, (finished: true, allSparks: false, moves: true));
    await repo.recordWin('1-01', score: 9, best: 4, sparkMask: 0x2);
    repo = await ProgressRepository.open();
    p = repo.progressOf('1-01');
    expect(p.sparkMask, 0x7);
    expect(p.stars, 3);
  });

  test('a spark mask is limited to three bits', () async {
    final repo = await ProgressRepository.open();
    await repo.recordWin('1-01', score: 9, best: 4, sparkMask: 0xFA);
    expect(repo.progressOf('1-01').sparkMask, 0x2);
  });

  test('totalSparks counts every saved spark', () async {
    var repo = await ProgressRepository.open();
    expect(repo.totalSparks, 0);
    await repo.recordWin('1-01', score: 9, best: 4, sparkMask: 0x5);
    await repo.recordWin('1-02', score: 9, best: 4, sparkMask: 0x7);
    await repo.recordWin('1-02', score: 9, best: 4, sparkMask: 0x1);
    repo = await ProgressRepository.open();
    expect(repo.totalSparks, 5);
  });

  test('recordWin notifies listeners', () async {
    final repo = await ProgressRepository.open();
    var calls = 0;
    repo.addListener(() => calls++);
    await repo.recordWin('1-01', score: 4, best: 4, sparkMask: 1);
    expect(calls, 1);
  });

  test(
    'skip completes with 0 stars, unlocks next, a later win sets stars',
    () async {
      final repo = await ProgressRepository.open();
      await repo.recordSkip('1-02');
      expect(repo.progressOf('1-02').completed, isTrue);
      expect(repo.progressOf('1-02').finished, isFalse);
      expect(repo.progressOf('1-02').stars, 0);
      expect(repo.isUnlocked('1-03', ids), isTrue);
      await repo.recordWin('1-02', score: 4, best: 4, sparkMask: 0);
      expect(repo.progressOf('1-02').stars, 2);
      await repo.recordSkip('1-02');
      expect(repo.progressOf('1-02').stars, 2);
      expect(repo.progressOf('1-02').finished, isTrue);
    },
  );

  test(
    'old saves migrate: 3 stars keeps the moves star, sparks start at 0',
    () async {
      SharedPreferences.setMockInitialValues({
        key:
            '{"levels":{"1-01":{"stars":3},"1-02":{"stars":2},'
            '"1-03":{"stars":1},"2-01":{"stars":0}}}',
      });
      var repo = await ProgressRepository.open();
      final three = repo.progressOf('1-01');
      expect(three.completed, isTrue);
      expect(three.finished, isTrue);
      expect(three.movesStar, isTrue);
      expect(three.sparkMask, 0);
      expect(three.stars, 2);
      expect(repo.progressOf('1-02').stars, 1);
      expect(repo.progressOf('1-02').movesStar, isFalse);
      expect(repo.progressOf('1-03').stars, 1);
      // An old skip (0 stars) stays a skip.
      expect(repo.progressOf('2-01').completed, isTrue);
      expect(repo.progressOf('2-01').stars, 0);
      expect(repo.totalSparks, 0);
      // The migrated data is saved in the new shape on the next save.
      await repo.setMusicOn(false);
      repo = await ProgressRepository.open();
      expect(repo.progressOf('1-01').stars, 2);
      expect(repo.progressOf('2-01').stars, 0);
      expect(repo.progressOf('2-01').completed, isTrue);
    },
  );

  test('garbled level values load as defaults', () async {
    SharedPreferences.setMockInitialValues({
      key:
          '{"levels":{"1-01":{"completed":true,"finished":"y","sparks":"x",'
          '"moves":1},"1-02":{"completed":true,"finished":true,"sparks":-1,'
          '"moves":true},"1-03":{"stars":"x"},"2-01":7}}',
    });
    final repo = await ProgressRepository.open();
    final a = repo.progressOf('1-01');
    expect(a.completed, isTrue);
    expect(a.finished, isFalse);
    expect(a.sparkMask, 0);
    expect(a.movesStar, isFalse);
    final b = repo.progressOf('1-02');
    expect(b.sparkMask, 0);
    expect(b.stars, 2);
    expect(repo.progressOf('1-03').completed, isTrue);
    expect(repo.progressOf('1-03').stars, 0);
    expect(repo.progressOf('2-01').completed, isFalse);
  });

  for (final bad in [
    '{oops',
    '{"levels":5}',
    '[]',
    '{"levels":{"1-01":5,"1-02":{"stars":"x"}},"musicOn":1,"sfxOn":"no"}',
  ]) {
    test('corrupt value $bad opens as defaults and is replaced', () async {
      SharedPreferences.setMockInitialValues({key: bad});
      final repo = await ProgressRepository.open();
      expect(repo.progressOf('1-01').completed, isFalse);
      expect(repo.musicOn, isTrue);
      expect(repo.sfxOn, isTrue);
      await repo.recordWin('1-01', score: 9, best: 4, sparkMask: 0);
      final again = await ProgressRepository.open();
      expect(again.progressOf('1-01').stars, 1);
      expect(again.isUnlocked('1-02', ids), isTrue);
    });
  }

  test('settings default on and persist', () async {
    var repo = await ProgressRepository.open();
    expect(repo.musicOn, isTrue);
    expect(repo.sfxOn, isTrue);
    await repo.setMusicOn(false);
    await repo.setSfxOn(false);
    repo = await ProgressRepository.open();
    expect(repo.musicOn, isFalse);
    expect(repo.sfxOn, isFalse);
  });

  test('story flags default to false', () async {
    final repo = await ProgressRepository.open();
    expect(repo.seenChapterIntro(2), isFalse);
    expect(repo.endingSeen, isFalse);
  });

  test('story flags persist per chapter', () async {
    var repo = await ProgressRepository.open();
    await repo.markChapterIntroSeen(2);
    await repo.markEndingSeen();
    repo = await ProgressRepository.open();
    expect(repo.seenChapterIntro(2), isTrue);
    expect(repo.seenChapterIntro(1), isFalse);
    expect(repo.endingSeen, isTrue);
  });

  test('old saved data without story keys still opens', () async {
    SharedPreferences.setMockInitialValues({
      key: '{"levels":{"1-01":{"stars":2}},"musicOn":false,"sfxOn":true}',
    });
    final repo = await ProgressRepository.open();
    expect(repo.progressOf('1-01').stars, 1);
    expect(repo.musicOn, isFalse);
    expect(repo.seenChapterIntro(1), isFalse);
    expect(repo.endingSeen, isFalse);
  });

  test('story flags survive later progress saves', () async {
    var repo = await ProgressRepository.open();
    await repo.markChapterIntroSeen(1);
    await repo.markEndingSeen();
    await repo.recordWin('1-01', score: 4, best: 4, sparkMask: 0);
    repo = await ProgressRepository.open();
    expect(repo.seenChapterIntro(1), isTrue);
    expect(repo.endingSeen, isTrue);
  });

  test('rewind tip count starts at 0 and survives reopen', () async {
    var repo = await ProgressRepository.open();
    expect(repo.rewindTipsShown, 0);
    await repo.markRewindTipShown();
    await repo.markRewindTipShown();
    repo = await ProgressRepository.open();
    expect(repo.rewindTipsShown, 2);
  });

  test('old prefs without the rewind key load with count 0', () async {
    SharedPreferences.setMockInitialValues({
      key: '{"levels":{"1-01":{"stars":2}},"musicOn":false}',
    });
    final repo = await ProgressRepository.open();
    expect(repo.rewindTipsShown, 0);
    expect(repo.progressOf('1-01').stars, 1);
    expect(repo.musicOn, isFalse);
  });

  test('moveSpeed defaults to normal, persists, old data loads', () async {
    var repo = await ProgressRepository.open();
    expect(repo.moveSpeed, MoveSpeed.normal);
    await repo.setMoveSpeed(MoveSpeed.fast);
    repo = await ProgressRepository.open();
    expect(repo.moveSpeed, MoveSpeed.fast);
    SharedPreferences.setMockInitialValues({
      key: '{"levels":{"1-01":{"stars":2}},"musicOn":false}',
    });
    repo = await ProgressRepository.open();
    expect(repo.moveSpeed, MoveSpeed.normal);
    expect(repo.progressOf('1-01').stars, 1);
    SharedPreferences.setMockInitialValues({key: '{"moveSpeed":"warp"}'});
    repo = await ProgressRepository.open();
    expect(repo.moveSpeed, MoveSpeed.normal);
  });

  test(
    'reduceEffects and vibration default, persist, old data loads',
    () async {
      var repo = await ProgressRepository.open();
      expect(repo.reduceEffects, isFalse);
      expect(repo.vibration, isTrue);
      await repo.setReduceEffects(true);
      await repo.setVibration(false);
      repo = await ProgressRepository.open();
      expect(repo.reduceEffects, isTrue);
      expect(repo.vibration, isFalse);
      SharedPreferences.setMockInitialValues({
        key: '{"levels":{"1-01":{"stars":2}},"musicOn":false}',
      });
      repo = await ProgressRepository.open();
      expect(repo.reduceEffects, isFalse);
      expect(repo.vibration, isTrue);
      expect(repo.progressOf('1-01').stars, 1);
      SharedPreferences.setMockInitialValues({
        key: '{"reduceEffects":"yes","vibration":1}',
      });
      repo = await ProgressRepository.open();
      expect(repo.reduceEffects, isFalse);
      expect(repo.vibration, isTrue);
    },
  );
}
