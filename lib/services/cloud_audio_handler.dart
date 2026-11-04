import 'package:audio_service/audio_service.dart' as audio_svc;
import '../models/audio_queue_item.dart';
import 'audio_player_service.dart';

/// Android MediaSessionService / iOS RemoteCommandCenter와 연동되는
/// 백그라운드 오디오 핸들러입니다.
/// 화면이 꺼진 상태에서도 잠금화면 컨트롤러, 갤럭시 버즈(블루투스 이어폰),
/// 갤럭시 워치, 안드로이드 오토와 실시간으로 양방향 동기화됩니다.
class CloudAudioHandler extends audio_svc.BaseAudioHandler
    with audio_svc.QueueHandler, audio_svc.SeekHandler {
  AudioPlayerService? _playerService;

  CloudAudioHandler() {
    playbackState.add(
      audio_svc.PlaybackState(
        controls: [
          audio_svc.MediaControl.skipToPrevious,
          audio_svc.MediaControl.play,
          audio_svc.MediaControl.skipToNext,
        ],
        systemActions: const {
          audio_svc.MediaAction.seek,
          audio_svc.MediaAction.seekForward,
          audio_svc.MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: audio_svc.AudioProcessingState.idle,
        playing: false,
      ),
    );
  }

  void attachPlayerService(AudioPlayerService service) {
    _playerService = service;
  }

  /// 현재 곡 정보 및 재생 상태를 시스템 MediaSession 알림창과 잠금화면에 반영
  void broadcastState({
    required AudioQueueItem? currentTrack,
    required bool isPlaying,
    required bool isLoading,
    required Duration position,
    required Duration duration,
    required double speed,
    Uri? artUri,
  }) {
    if (currentTrack != null) {
      mediaItem.add(
        audio_svc.MediaItem(
          id: currentTrack.uniqueKey,
          title: currentTrack.title,
          artist: currentTrack.artist,
          album: currentTrack.cloudBadgeLabel,
          duration: duration > Duration.zero ? duration : null,
          artUri: artUri,
        ),
      );
    }

    playbackState.add(
      audio_svc.PlaybackState(
        controls: [
          audio_svc.MediaControl.skipToPrevious,
          isPlaying ? audio_svc.MediaControl.pause : audio_svc.MediaControl.play,
          audio_svc.MediaControl.skipToNext,
          audio_svc.MediaControl.stop,
        ],
        systemActions: const {
          audio_svc.MediaAction.seek,
          audio_svc.MediaAction.seekForward,
          audio_svc.MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: isLoading
            ? audio_svc.AudioProcessingState.loading
            : (currentTrack != null
                ? audio_svc.AudioProcessingState.ready
                : audio_svc.AudioProcessingState.idle),
        playing: isPlaying,
        updatePosition: position,
        speed: speed,
      ),
    );
  }

  @override
  Future<void> play() async {
    await _playerService?.play();
  }

  @override
  Future<void> pause() async {
    await _playerService?.pause();
  }

  @override
  Future<void> stop() async {
    await _playerService?.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await _playerService?.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    await _playerService?.skipToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    await _playerService?.skipToPrevious();
  }
}
