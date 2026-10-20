import 'package:flame_audio/flame_audio.dart';

import 'audio_service.dart';

/// [AudioService] backed by flame_audio. Every error is swallowed: sound is
/// never allowed to break the game (for example when a browser blocks
/// autoplay).
class FlameAudioService implements AudioService {
  static const _files = {
    Sfx.move: 'move.wav',
    Sfx.plate: 'plate.wav',
    Sfx.door: 'door.wav',
    Sfx.runEnd: 'run_end.wav',
    Sfx.win: 'win.wav',
  };

  bool _preloaded = false;

  Future<void> _preload() async {
    if (_preloaded) return;
    _preloaded = true;
    try {
      await FlameAudio.audioCache.loadAll([..._files.values, 'ambient.wav']);
    } catch (_) {}
  }

  @override
  Future<void> playSfx(Sfx s) async {
    try {
      await _preload();
      await FlameAudio.play(_files[s]!);
    } catch (_) {}
  }

  @override
  Future<void> startMusic() async {
    try {
      await _preload();
      if (FlameAudio.bgm.isPlaying) return;
      await FlameAudio.bgm.play('ambient.wav', volume: 0.5);
    } catch (_) {}
  }

  @override
  Future<void> stopMusic() async {
    try {
      await FlameAudio.bgm.stop();
    } catch (_) {}
  }
}
