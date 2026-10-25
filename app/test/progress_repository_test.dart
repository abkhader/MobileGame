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

  test('completion survives reopen and unlocks next', () async {
    var repo = await ProgressRepository.open();
    await repo.recordCompletion('1-01', 2);
    repo = await ProgressRepository.open();
    expect(repo.progressOf('1-01').completed, isTrue);
    expect(repo.progressOf('1-01').stars, 2);
    expect(repo.isUnlocked('1-02', ids), isTrue);
  });

  test('keeps max stars and clamps', () async {
    final repo = await ProgressRepository.open();
    await repo.recordCompletion('1-01', 3);
    await repo.recordCompletion('1-01', 1);
    expect(repo.progressOf('1-01').stars, 3);
    await repo.recordCompletion('1-02', 9);
    expect(repo.progressOf('1-02').stars, 3);
    await repo.recordCompletion('1-03', -4);
    expect(repo.progressOf('1-03').stars, 0);
  });

  test(
    'skip completes with 0 stars, unlocks next, later completion sets stars',
    () async {
      final repo = await ProgressRepository.open();
      await repo.recordSkip('1-02');
      expect(repo.progressOf('1-02').completed, isTrue);
      expect(repo.progressOf('1-02').stars, 0);
      expect(repo.isUnlocked('1-03', ids), isTrue);
      await repo.recordCompletion('1-02', 2);
      expect(repo.progressOf('1-02').stars, 2);
      await repo.recordSkip('1-02');
      expect(repo.progressOf('1-02').stars, 2);
    },
  );

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
      await repo.recordCompletion('1-01', 1);
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
    expect(repo.progressOf('1-01').stars, 2);
    expect(repo.musicOn, isFalse);
    expect(repo.seenChapterIntro(1), isFalse);
    expect(repo.endingSeen, isFalse);
  });

  test('story flags survive later progress saves', () async {
    var repo = await ProgressRepository.open();
    await repo.markChapterIntroSeen(1);
    await repo.markEndingSeen();
    await repo.recordCompletion('1-01', 3);
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
    expect(repo.progressOf('1-01').stars, 2);
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
    expect(repo.progressOf('1-01').stars, 2);
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
      expect(repo.progressOf('1-01').stars, 2);
      SharedPreferences.setMockInitialValues({
        key: '{"reduceEffects":"yes","vibration":1}',
      });
      repo = await ProgressRepository.open();
      expect(repo.reduceEffects, isFalse);
      expect(repo.vibration, isTrue);
    },
  );
}
