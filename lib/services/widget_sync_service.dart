import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/audio_queue_item.dart';
import 'audio_player_service.dart';

/// 갤럭시 S26+ (One UI 7/8) 홈 화면 위젯 및 위젯 스택(Widget Stack: 4x1 & 4x2)과
/// Flutter 백그라운드 오디오 서비스를 양방향으로 동기화하는 브릿지 서비스입니다.
class WidgetSyncService {
  static final WidgetSyncService instance = WidgetSyncService._();
  WidgetSyncService._();

  static const MethodChannel _widgetChannel =
      MethodChannel('com.example.cloud_audio_player/widget');

  bool _initialized = false;

  /// 네이티브 Android AppWidgetProvider로부터 전달되는 버튼 클릭(재생/일시정지/다음/이전/셔플/반복) 수신 초기화
  void initialize(AudioPlayerService playerService) {
    if (_initialized) return;
    _initialized = true;

    if (!Platform.isAndroid) return;

    _widgetChannel.setMethodCallHandler((call) async {
      debugPrint('[WidgetSyncService] 네이티브 위젯 명령 수신: ${call.method}');
      switch (call.method) {
        case 'onWidgetAction':
          final action = call.arguments as String? ?? '';
          await _handleWidgetAction(playerService, action);
          break;
      }
      return true;
    });
  }

  Future<void> _handleWidgetAction(
    AudioPlayerService playerService,
    String action,
  ) async {
    switch (action) {
      case 'ACTION_PLAY_PAUSE':
        await playerService.togglePlayPause();
        break;
      case 'ACTION_NEXT':
        await playerService.skipToNext();
        break;
      case 'ACTION_PREV':
        await playerService.skipToPrevious();
        break;
      case 'ACTION_SHUFFLE':
        playerService.toggleShuffle();
        break;
      case 'ACTION_REPEAT':
        playerService.cycleRepeatMode();
        break;
    }
  }

  /// 현재 재생 상태를 갤럭시 S26+ 위젯(4x1 슬림 & 4x2 스택형)으로 즉시 브로드캐스트합니다.
  Future<void> updateWidgetState({
    required AudioQueueItem? currentTrack,
    required bool isPlaying,
    required Duration position,
    required Duration duration,
    required bool isShuffle,
    required AudioRepeatMode repeatMode,
    String? localCoverPath,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      final int progressPercent = (duration.inMilliseconds > 0)
          ? ((position.inMilliseconds / duration.inMilliseconds) * 100)
              .round()
              .clamp(0, 100)
          : 0;

      await _widgetChannel.invokeMethod('updateAudioWidget', {
        'title': currentTrack?.title ?? '재생 중인 곡 없음',
        'artist': currentTrack?.artist ?? '폴더를 선택해 음악을 재생하세요',
        'cloudBadge': currentTrack != null
            ? '${currentTrack.cloudBadgeLabel} • ${currentTrack.item.audioFormatBadge}'
            : 'Cloud Audio Player',
        'isPlaying': isPlaying,
        'progress': progressPercent,
        'positionText': _formatDuration(position),
        'durationText': _formatDuration(duration),
        'isShuffle': isShuffle,
        'repeatMode': repeatMode.name,
        'coverPath': localCoverPath ?? '',
      });
    } catch (e) {
      debugPrint('[WidgetSyncService] 위젯 업데이트 실패: $e');
    }
  }

  String _formatDuration(Duration d) {
    if (d <= Duration.zero) return '00:00';
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}
