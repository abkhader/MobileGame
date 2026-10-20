/// The short sound effects the game can play.
enum Sfx { move, plate, door, runEnd, win }

/// Plays the game's sound effects and background music.
abstract interface class AudioService {
  Future<void> playSfx(Sfx s);
  Future<void> startMusic();
  Future<void> stopMusic();
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
}
