import 'package:echo_app/audio/audio_service.dart';

/// Records every call; set [throws] to make each call fail.
class FakeAudioService implements AudioService {
  FakeAudioService({this.throws = false});

  final bool throws;
  final List<Sfx> played = [];
  int startMusicCalls = 0;
  int stopMusicCalls = 0;

  @override
  Future<void> playSfx(Sfx s) async {
    if (throws) throw StateError('playSfx failed');
    played.add(s);
  }

  @override
  Future<void> startMusic() async {
    startMusicCalls++;
    if (throws) throw StateError('startMusic failed');
  }

  @override
  Future<void> stopMusic() async {
    stopMusicCalls++;
    if (throws) throw StateError('stopMusic failed');
  }
}
