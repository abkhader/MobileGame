/// The short sound effects the game can play.
enum Sfx { move, plate, door, runEnd, win, bump, spark }

/// Plays the game's sound effects and background music.
abstract interface class AudioService {
  Future<void> playSfx(Sfx s);
  Future<void> startMusic();
  Future<void> stopMusic();

  /// Time is frozen (no input held): duck the music. False restores it.
  Future<void> setFrozen(bool frozen);

  /// Rewind is held: loop the rewind sweep until false.
  Future<void> setRewinding(bool rewinding);
}

/// Plays nothing. Used where no audio backend is wanted.
class SilentAudioService implements AudioService {
  const SilentAudioService();

  @override
  Future<void> playSfx(Sfx s) async {}

  @override
  Future<void> startMusic() async {}

  @override
  Future<void> stopMusic() async {}

  @override
  Future<void> setFrozen(bool frozen) async {}

  @override
  Future<void> setRewinding(bool rewinding) async {}
}
