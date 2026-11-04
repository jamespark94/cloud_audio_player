import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/audio_queue_item.dart';
import '../models/cloud_account.dart';
import '../models/lyrics_line.dart';
import '../models/media_item.dart';
import '../utils/battery_utils.dart';
import '../utils/lrc_parser_utils.dart';
import 'account_manager.dart';
import 'cloud_audio_handler.dart';
import 'cloud_playback_sync_service.dart';
import 'cloud_service_interface.dart';
import 'local_stream_proxy.dart';
import 'playback_history_service.dart';
import 'widget_sync_service.dart';

enum AudioRepeatMode {
  off('반복 끔'),
  all('전체 반복'),
  one('한 곡 반복');

  final String label;
  const AudioRepeatMode(this.label);
}

enum AudioEqPreset {
  flat('기본 (Flat)', ''),
  bassBoost('베이스 부스트', 'superequalizer=1b=4:2b=3.5:3b=2.5:4b=1.2'),
  vocalBoost('보컬/팟캐스트 강조', 'superequalizer=8b=2.5:9b=3:10b=3:11b=2.5:12b=1.5'),
  trebleBoost('고음 선명화', 'superequalizer=13b=2:14b=2.5:15b=3:16b=3.5:17b=3.5'),
  loudness('음량 평준화 (Normalizer)', 'dynaudnorm=f=150:g=15');

  final String label;
  final String mpvFilter;
  const AudioEqPreset(this.label, this.mpvFilter);
}

/// 화면이 꺼진 백그라운드/Doze 상태에서도 클라우드 오디오 스트리밍,
/// 큐(Queue) 자동 전환, 다음 곡 선행 프리페치(Prefetch), 싱크 가사(.lrc),
/// 갤럭시 S26+ 위젯 스택 동기화를 총괄하는 전역 싱글톤 서비스입니다.
class AudioPlayerService extends ChangeNotifier {
  static final AudioPlayerService instance = AudioPlayerService._internal();
  AudioPlayerService._internal();

  static const String _savedQueueKey = 'cloud_audio_saved_queue_v1';
  static const String _savedIndexKey = 'cloud_audio_saved_index_v1';
  static const String _savedShuffleKey = 'cloud_audio_saved_shuffle_v1';
  static const String _savedRepeatKey = 'cloud_audio_saved_repeat_v1';

  Player? _player;
  AccountManager? _accountManager;
  CloudAudioHandler? _audioHandler;
  AudioSession? _audioSession;

  List<AudioQueueItem> _originalQueue = [];
  List<AudioQueueItem> _activeQueue = [];
  int _currentIndex = -1;

  bool _isPlaying = false;
  bool _isLoading = false;
  String? _errorMessage;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _playbackSpeed = 1.0;
  bool _isShuffle = false;
  AudioRepeatMode _repeatMode = AudioRepeatMode.all;
  AudioEqPreset _eqPreset = AudioEqPreset.flat;

  // 현재 곡의 싱크 가사 및 로컬 캐시된 커버 이미지 경로
  List<LyricsLine> _lyrics = [];
  bool _isLoadingLyrics = false;
  String? _localCoverArtPath;

  // 다음 곡 무중단 전환을 위한 Prefetch 상태
  String? _activeProxyUrl;
  String? _prefetchedNextProxyUrl;
  String? _prefetchedNextUniqueKey;
  bool _isPrefetchingNext = false;

  // 취침 예약 타이머 (Sleep Timer)
  Timer? _sleepTimer;
  DateTime? _sleepTimerTarget;
  bool _stopAfterCurrentTrack = false;

  // 스트림 구독
  StreamSubscription? _playingSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _completedSub;
  StreamSubscription? _errorSub;
  Timer? _historySaveTimer;
  int _lastWidgetUpdateSec = -1;
  int _playSessionToken = 0;

  // Getters
  List<AudioQueueItem> get queue => List.unmodifiable(_activeQueue);
  int get currentIndex => _currentIndex;
  AudioQueueItem? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _activeQueue.length)
          ? _activeQueue[_currentIndex]
          : null;
  bool get hasTrack => currentTrack != null;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  Duration get position => _position;
  Duration get duration => _duration;
  double get playbackSpeed => _playbackSpeed;
  bool get isShuffle => _isShuffle;
  AudioRepeatMode get repeatMode => _repeatMode;
  AudioEqPreset get eqPreset => _eqPreset;
  List<LyricsLine> get lyrics => List.unmodifiable(_lyrics);
  bool get isLoadingLyrics => _isLoadingLyrics;
  String? get localCoverArtPath => _localCoverArtPath;
  bool get stopAfterCurrentTrack => _stopAfterCurrentTrack;

  Duration? get remainingSleepTime {
    if (_sleepTimerTarget == null) return null;
    final diff = _sleepTimerTarget!.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  /// 현재 재생 위치에 해당하는 활성 가사 인덱스 반환
  int get currentLyricsIndex {
    if (_lyrics.isEmpty) return -1;
    for (int i = _lyrics.length - 1; i >= 0; i--) {
      if (_position >= _lyrics[i].timestamp) {
        return i;
      }
    }
    return 0;
  }

  Future<void> initialize({
    required AccountManager accountManager,
    CloudAudioHandler? audioHandler,
  }) async {
    _accountManager = accountManager;
    _audioHandler = audioHandler;
    _audioHandler?.attachPlayerService(this);
    WidgetSyncService.instance.initialize(this);

    if (_player != null) return;

    // 오디오 전용 Player 초기화 (VideoController를 생성하지 않아 화면 꺼짐 시 GPU/메모리 사용 최소화)
    _player = Player(
      configuration: const PlayerConfiguration(
        title: 'Cloud Audio Player',
        bufferSize: 32 * 1024 * 1024, // 32MB 넉넉한 오디오 스트림 버퍼링
      ),
    );

    await _configureMpvForBackgroundAudio();
    await _initAudioSession();
    _bindPlayerStreams();
    await _restoreSavedQueue();
  }

  Future<void> _configureMpvForBackgroundAudio() async {
    try {
      final platform = _player?.platform as dynamic;
      // 비디오 트랙 디코딩을 완전히 비활성화하여 오디오 스트리밍 성능 극대화
      await platform.setProperty('vid', 'no');
      await platform.setProperty('cache', 'yes');
      await platform.setProperty('demuxer-max-bytes', '${32 * 1024 * 1024}');
      await platform.setProperty('demuxer-readahead-secs', '60');
      await platform.setProperty('network-timeout', '20');
    } catch (e) {
      debugPrint('[AudioPlayerService] mpv 오디오 속성 설정 실패: $e');
    }
  }

  Future<void> _initAudioSession() async {
    try {
      _audioSession = await AudioSession.instance;
      await _audioSession!.configure(const AudioSessionConfiguration.music());

      _audioSession!.becomingNoisyEventStream.listen((_) {
        // 이어폰/블루투스 연결 해제 시 자동 일시정지
        if (_isPlaying) {
          pause();
        }
      });

      _audioSession!.interruptionEventStream.listen((event) {
        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
              _player?.setVolume(30.0);
              break;
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              if (_isPlaying) pause();
              break;
          }
        } else {
          switch (event.type) {
            case AudioInterruptionType.duck:
              _player?.setVolume(100.0);
              break;
            case AudioInterruptionType.pause:
              play();
              break;
            case AudioInterruptionType.unknown:
              break;
          }
        }
      });
    } catch (e) {
      debugPrint('[AudioPlayerService] AudioSession 초기화 오류: $e');
    }
  }

  void _bindPlayerStreams() {
    final p = _player!;

    _playingSub = p.stream.playing.listen((playing) {
      _isPlaying = playing;
      // 재생 중에는 CPU WakeLock + High-Perf WifiLock 유지
      BatteryUtils.setBackgroundStreamingLock(playing);
      _syncExternalControllers(forceWidgetUpdate: true);
      notifyListeners();
    });

    _positionSub = p.stream.position.listen((pos) {
      _position = pos;

      // 종료 20초 전 또는 80% 경과 시 다음 곡 스트림 URL 백그라운드 선행 준비(Prefetch)
      if (_duration.inSeconds > 15 &&
          (_duration - pos).inSeconds <= 20 &&
          !_isPrefetchingNext) {
        _prefetchNextTrackIfNeeded();
      }

      // 위젯 업데이트는 매 3초마다 혹은 상태 변경 시에만 호출하여 S26+ 배터리 보호
      if ((pos.inSeconds - _lastWidgetUpdateSec).abs() >= 3) {
        _lastWidgetUpdateSec = pos.inSeconds;
        _syncExternalControllers(forceWidgetUpdate: false);
      }
      notifyListeners();
    });

    _durationSub = p.stream.duration.listen((dur) {
      if (dur > Duration.zero) {
        _duration = dur;
        _syncExternalControllers(forceWidgetUpdate: true);
        notifyListeners();
      }
    });

    _completedSub = p.stream.completed.listen((completed) {
      if (completed && !_isLoading) {
        _onTrackCompleted();
      }
    });

    _errorSub = p.stream.error.listen((err) {
      if (err.isNotEmpty) {
        debugPrint('[AudioPlayerService] 재생 엔진 경고/오류: $err');
      }
    });

    // 10초마다 현재 곡 재생 진도 자동 저장
    _historySaveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_isPlaying && currentTrack != null && _duration > Duration.zero) {
        _saveCurrentProgress();
      }
    });
  }

  /// 폴더 내 오디오 파일 목록을 기반으로 재생 큐를 구성하고 즉시 스트리밍을 시작합니다.
  Future<void> playFolderQueue({
    required CloudAccount account,
    required List<MediaItem> allFolderItems,
    required MediaItem startItem,
    String? folderName,
    bool shuffle = false,
  }) async {
    final audioItems = allFolderItems.where((i) => i.isAudio).toList();
    if (audioItems.isEmpty) {
      audioItems.add(startItem);
    }

    // 폴더 내 대표 커버 이미지(cover.jpg, folder.jpg 등 또는 첫 번째 이미지) 탐색
    MediaItem? folderCover = allFolderItems.cast<MediaItem?>().firstWhere(
          (i) => i != null && i.isCoverArtCandidate,
          orElse: () => null,
        );
    folderCover ??= allFolderItems.cast<MediaItem?>().firstWhere(
          (i) => i != null && i.isImage,
          orElse: () => null,
        );

    // 각 오디오 파일에 매칭되는 동명 .lrc / .srt 가사 파일 자동 매핑
    final lyricsCandidates = allFolderItems.where((i) => i.isLyrics).toList();

    final builtQueue = audioItems.map((audio) {
      MediaItem? matchedLyrics;
      for (final lrc in lyricsCandidates) {
        if (LrcParserUtils.isLyricsForAudio(lrc.name, audio.name)) {
          matchedLyrics = lrc;
          break;
        }
      }
      // 동명 이미지 파일(Song.jpg)이 있으면 우선 사용, 없으면 폴더 대표 커버 사용
      MediaItem? specificCover;
      final audioBase = audio.displayTitle.toLowerCase();
      for (final img in allFolderItems.where((i) => i.isImage)) {
        if (img.displayTitle.toLowerCase() == audioBase) {
          specificCover = img;
          break;
        }
      }

      return AudioQueueItem(
        accountId: account.id,
        accountName: account.name,
        cloudType: account.type,
        item: audio,
        folderName: folderName,
        coverArtItem: specificCover ?? folderCover,
        lyricsItem: matchedLyrics,
      );
    }).toList();

    _originalQueue = List.from(builtQueue);
    _isShuffle = shuffle;

    if (shuffle) {
      _activeQueue = List.from(_originalQueue)..shuffle(math.Random());
      // 선택한 시작 곡이 있으면 맨 앞으로 배치
      final idx = _activeQueue.indexWhere((q) => q.item.id == startItem.id);
      if (idx > 0) {
        final chosen = _activeQueue.removeAt(idx);
        _activeQueue.insert(0, chosen);
      }
      _currentIndex = 0;
    } else {
      _activeQueue = List.from(_originalQueue);
      final idx = _activeQueue.indexWhere((q) => q.item.id == startItem.id);
      _currentIndex = idx >= 0 ? idx : 0;
    }

    await _persistQueueState();
    await _loadAndPlayCurrentIndex();
  }

  /// 단일 기록 또는 바로가기에서 재생 시작
  Future<void> playSingleOrResume({
    required CloudAccount account,
    required MediaItem item,
    Duration? resumePosition,
  }) async {
    final queueItem = AudioQueueItem(
      accountId: account.id,
      accountName: account.name,
      cloudType: account.type,
      item: item,
    );

    _originalQueue = [queueItem];
    _activeQueue = [queueItem];
    _currentIndex = 0;
    await _persistQueueState();
    await _loadAndPlayCurrentIndex(initialSeek: resumePosition);
  }

  /// 현재 큐에 트랙 추가 (다음에 재생 / 맨 끝에 추가)
  Future<void> addTrackToQueue(AudioQueueItem track, {bool playNext = false}) async {
    _originalQueue.add(track);
    if (_activeQueue.isEmpty) {
      _activeQueue.add(track);
      _currentIndex = 0;
      await _persistQueueState();
      await _loadAndPlayCurrentIndex();
      return;
    }

    if (playNext && _currentIndex >= 0 && _currentIndex < _activeQueue.length) {
      _activeQueue.insert(_currentIndex + 1, track);
    } else {
      _activeQueue.add(track);
    }
    await _persistQueueState();
    notifyListeners();
  }

  /// 큐 내 특정 인덱스의 곡 즉시 재생
  Future<void> skipToQueueIndex(int index) async {
    if (index < 0 || index >= _activeQueue.length) return;
    _currentIndex = index;
    await _persistQueueState();
    await _loadAndPlayCurrentIndex();
  }

  /// 큐에서 특정 곡 제거
  Future<void> removeQueueItemAt(int index) async {
    if (index < 0 || index >= _activeQueue.length) return;
    final removed = _activeQueue.removeAt(index);
    _originalQueue.removeWhere((e) => e.uniqueKey == removed.uniqueKey);

    if (_activeQueue.isEmpty) {
      await stop();
      return;
    }

    if (index < _currentIndex) {
      _currentIndex--;
    } else if (index == _currentIndex) {
      if (_currentIndex >= _activeQueue.length) {
        _currentIndex = 0;
      }
      await _loadAndPlayCurrentIndex();
    }
    await _persistQueueState();
    notifyListeners();
  }

  /// 큐 순서 변경 (드래그 앤 드롭)
  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final currentKey = currentTrack?.uniqueKey;
    final item = _activeQueue.removeAt(oldIndex);
    _activeQueue.insert(newIndex, item);

    if (currentKey != null) {
      _currentIndex = _activeQueue.indexWhere((e) => e.uniqueKey == currentKey);
    }
    await _persistQueueState();
    notifyListeners();
  }

  /// 핵심 트랙 로드 및 스트리밍 시작 로직
  Future<void> _loadAndPlayCurrentIndex({Duration? initialSeek}) async {
    final track = currentTrack;
    if (track == null || _accountManager == null) return;

    final int token = ++_playSessionToken;
    _isLoading = true;
    _errorMessage = null;
    _position = Duration.zero;
    _duration = track.item.duration ?? Duration.zero;
    _lyrics = [];
    _localCoverArtPath = null;
    notifyListeners();
    _syncExternalControllers(forceWidgetUpdate: true);

    try {
      await _audioSession?.setActive(true);
      await BatteryUtils.setBackgroundStreamingLock(true);

      final account = _accountManager!.findMatchingAccount(
        accountId: track.accountId,
        cloudType: track.cloudType,
      );
      final service = _accountManager!.getService(account);

      // 1. 스트림 URL 준비 (이미 Prefetch된 URL이 있으면 즉시 사용하여 화면 꺼짐 시 딜레이 제로화)
      String playUrl;
      Map<String, String> headers = {};

      if (account.type == CloudType.local) {
        playUrl = await service.getStreamUrl(track.item);
      } else if (_prefetchedNextUniqueKey == track.uniqueKey &&
          _prefetchedNextProxyUrl != null) {
        LocalStreamProxy.instance.unregisterStream(_activeProxyUrl);
        _activeProxyUrl = _prefetchedNextProxyUrl;
        _prefetchedNextProxyUrl = null;
        _prefetchedNextUniqueKey = null;
        playUrl = _activeProxyUrl!;
        debugPrint('[AudioPlayerService] Prefetch된 프록시 스트림 즉시 사용: ${track.title}');
      } else {
        await LocalStreamProxy.instance.start();
        await service.refreshTokensIfNeeded().timeout(const Duration(seconds: 10));
        LocalStreamProxy.instance.unregisterStream(_activeProxyUrl);

        String? directUrl;
        if (account.type != CloudType.mega) {
          directUrl = await service.getStreamUrl(track.item).timeout(const Duration(seconds: 15));
        }
        _activeProxyUrl = LocalStreamProxy.instance.registerStream(
          service,
          track.item,
          initialUrl: directUrl,
        );
        playUrl = _activeProxyUrl!;
      }

      if (token != _playSessionToken) return;

      // 2. 백그라운드에서 가사(.lrc) 및 앨범 커버 이미지 비동기 로드
      unawaited(_loadLyricsInBackground(service, track, token));
      unawaited(_loadCoverArtInBackground(service, track, token));

      // 3. media_kit 오디오 재생 시작
      await _player!.open(
        Media(playUrl, httpHeaders: headers),
        play: true,
      );

      if (_playbackSpeed != 1.0) {
        await _player!.setRate(_playbackSpeed);
      }

      // 4. 이어듣기 위치(initialSeek 또는 15분 이상 긴 오디오북/믹스셋 기록) 복원
      Duration? targetSeek = initialSeek;
      if (targetSeek == null) {
        final savedPos = await PlaybackHistoryService.instance.getSavedPosition(
          accountId: track.accountId,
          item: track.item,
        );
        // 10분 이상 길이의 오디오북/강의/믹스셋은 자동 이어듣기
        if (savedPos != null &&
            (_duration.inMinutes >= 10 || (track.item.size ?? 0) > 30 * 1024 * 1024)) {
          targetSeek = savedPos;
        }
      }

      if (targetSeek != null && targetSeek > Duration.zero) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (token == _playSessionToken) {
            seek(targetSeek!);
          }
        });
      }

      _isLoading = false;
      _isPlaying = true;
      _syncExternalControllers(forceWidgetUpdate: true);
      notifyListeners();
    } catch (e) {
      if (token != _playSessionToken) return;
      debugPrint('[AudioPlayerService] 트랙 재생 실패 (${track.title}): $e');
      _isLoading = false;
      _errorMessage = '스트리밍 연결 실패: $e';
      notifyListeners();
    }
  }

  /// 다음 트랙 스트림 URL을 백그라운드에서 미리 준비(Prefetch)
  Future<void> _prefetchNextTrackIfNeeded() async {
    if (_isPrefetchingNext || _accountManager == null) return;
    final nextIdx = _peekNextIndex();
    if (nextIdx == null || nextIdx < 0 || nextIdx >= _activeQueue.length) return;

    final nextTrack = _activeQueue[nextIdx];
    if (_prefetchedNextUniqueKey == nextTrack.uniqueKey) return;
    if (nextTrack.cloudType == CloudType.local) return;

    _isPrefetchingNext = true;
    try {
      final account = _accountManager!.findMatchingAccount(
        accountId: nextTrack.accountId,
        cloudType: nextTrack.cloudType,
      );
      final service = _accountManager!.getService(account);
      LocalStreamProxy.instance.unregisterStream(_prefetchedNextProxyUrl);
      final proxyUrl = await LocalStreamProxy.instance.prefetchAudioStream(
        service,
        nextTrack.item,
      );
      if (proxyUrl != null) {
        _prefetchedNextProxyUrl = proxyUrl;
        _prefetchedNextUniqueKey = nextTrack.uniqueKey;
      }
    } finally {
      _isPrefetchingNext = false;
    }
  }

  Future<void> _loadLyricsInBackground(
    CloudService service,
    AudioQueueItem track,
    int token,
  ) async {
    if (track.lyricsItem == null) return;
    _isLoadingLyrics = true;
    notifyListeners();

    try {
      final bytes = await service.downloadBytes(track.lyricsItem!);
      if (token != _playSessionToken) return;
      final parsed = await LrcParserUtils.parseLyricsBytes(
        bytes,
        fileName: track.lyricsItem!.name,
      );
      if (token != _playSessionToken) return;
      _lyrics = parsed;
    } catch (e) {
      debugPrint('[AudioPlayerService] 가사 파일 로드 실패: $e');
    } finally {
      if (token == _playSessionToken) {
        _isLoadingLyrics = false;
        notifyListeners();
      }
    }
  }

  Future<void> _loadCoverArtInBackground(
    CloudService service,
    AudioQueueItem track,
    int token,
  ) async {
    try {
      Uint8List? imageBytes;
      if (track.coverArtItem != null) {
        imageBytes = await service.downloadBytes(track.coverArtItem!);
      }
      if (token != _playSessionToken || imageBytes == null || imageBytes.isEmpty) {
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final coverFile = File(
        '${tempDir.path}/s26_widget_cover_${track.uniqueKey.hashCode.abs()}.jpg',
      );
      await coverFile.writeAsBytes(imageBytes, flush: true);

      if (token != _playSessionToken) return;
      _localCoverArtPath = coverFile.path;
      _syncExternalControllers(forceWidgetUpdate: true);
      notifyListeners();
    } catch (e) {
      debugPrint('[AudioPlayerService] 커버 아트 캐싱 실패: $e');
    }
  }

  void _onTrackCompleted() {
    _saveCurrentProgress(completed: true);

    if (_stopAfterCurrentTrack) {
      _stopAfterCurrentTrack = false;
      pause();
      notifyListeners();
      return;
    }

    if (_repeatMode == AudioRepeatMode.one) {
      seek(Duration.zero);
      play();
      return;
    }

    final nextIdx = _peekNextIndex();
    if (nextIdx != null) {
      _currentIndex = nextIdx;
      _persistQueueState();
      _loadAndPlayCurrentIndex();
    } else {
      _isPlaying = false;
      BatteryUtils.setBackgroundStreamingLock(false);
      _syncExternalControllers(forceWidgetUpdate: true);
      notifyListeners();
    }
  }

  int? _peekNextIndex() {
    if (_activeQueue.isEmpty) return null;
    if (_currentIndex + 1 < _activeQueue.length) {
      return _currentIndex + 1;
    }
    if (_repeatMode == AudioRepeatMode.all) {
      return 0;
    }
    return null;
  }

  // 기본 컨트롤 메서드
  Future<void> togglePlayPause() async {
    if (_player == null) return;
    if (currentTrack == null && _activeQueue.isNotEmpty) {
      _currentIndex = 0;
      await _loadAndPlayCurrentIndex();
      return;
    }
    if (_isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> play() async {
    if (_player == null) return;
    if (currentTrack != null && _activeProxyUrl == null && !_isLoading) {
      await _loadAndPlayCurrentIndex();
      return;
    }
    await _audioSession?.setActive(true);
    await BatteryUtils.setBackgroundStreamingLock(true);
    await _player!.play();
  }

  Future<void> pause() async {
    if (_player == null) return;
    await _player!.pause();
    await BatteryUtils.setBackgroundStreamingLock(false);
    await _saveCurrentProgress();
  }

  Future<void> stop() async {
    await _saveCurrentProgress();
    await _player?.stop();
    await BatteryUtils.setBackgroundStreamingLock(false);
    _isPlaying = false;
    _position = Duration.zero;
    _syncExternalControllers(forceWidgetUpdate: true);
    notifyListeners();
  }

  Future<void> seek(Duration target) async {
    if (_player == null) return;
    _position = target;
    await _player!.seek(target);
    _syncExternalControllers(forceWidgetUpdate: true);
    notifyListeners();
  }

  Future<void> skipToNext() async {
    if (_activeQueue.isEmpty) return;
    if (_currentIndex + 1 < _activeQueue.length) {
      _currentIndex++;
    } else {
      _currentIndex = 0;
    }
    await _persistQueueState();
    await _loadAndPlayCurrentIndex();
  }

  Future<void> skipToPrevious() async {
    if (_activeQueue.isEmpty) return;
    // 4초 이상 재생된 상태에서는 현재 곡 처음으로 이동
    if (_position.inSeconds > 4) {
      await seek(Duration.zero);
      return;
    }
    if (_currentIndex > 0) {
      _currentIndex--;
    } else {
      _currentIndex = _activeQueue.length - 1;
    }
    await _persistQueueState();
    await _loadAndPlayCurrentIndex();
  }

  void toggleShuffle() {
    _isShuffle = !_isShuffle;
    final current = currentTrack;
    if (_isShuffle) {
      _activeQueue = List.from(_originalQueue)..shuffle(math.Random());
      if (current != null) {
        final idx = _activeQueue.indexWhere((e) => e.uniqueKey == current.uniqueKey);
        if (idx > 0) {
          final item = _activeQueue.removeAt(idx);
          _activeQueue.insert(0, item);
        }
        _currentIndex = 0;
      }
    } else {
      _activeQueue = List.from(_originalQueue);
      if (current != null) {
        _currentIndex = _activeQueue.indexWhere((e) => e.uniqueKey == current.uniqueKey);
        if (_currentIndex < 0) _currentIndex = 0;
      }
    }
    _persistQueueState();
    _syncExternalControllers(forceWidgetUpdate: true);
    notifyListeners();
  }

  void cycleRepeatMode() {
    switch (_repeatMode) {
      case AudioRepeatMode.off:
        _repeatMode = AudioRepeatMode.all;
        break;
      case AudioRepeatMode.all:
        _repeatMode = AudioRepeatMode.one;
        break;
      case AudioRepeatMode.one:
        _repeatMode = AudioRepeatMode.off;
        break;
    }
    _persistQueueState();
    _syncExternalControllers(forceWidgetUpdate: true);
    notifyListeners();
  }

  Future<void> setPlaybackSpeed(double speed) async {
    _playbackSpeed = speed.clamp(0.5, 2.0);
    await _player?.setRate(_playbackSpeed);
    _syncExternalControllers(forceWidgetUpdate: false);
    notifyListeners();
  }

  Future<void> setEqPreset(AudioEqPreset preset) async {
    _eqPreset = preset;
    try {
      final platform = _player?.platform as dynamic;
      await platform.setProperty('af', preset.mpvFilter);
    } catch (e) {
      debugPrint('[AudioPlayerService] EQ 필터 적용 실패: $e');
    }
    notifyListeners();
  }

  /// 취침 예약 타이머 설정 (예: 15분, 30분, 60분 뒤 자동 일시정지 또는 현재 곡 종료 후 정지)
  void setSleepTimer({Duration? duration, bool stopAfterCurrent = false}) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerTarget = null;
    _stopAfterCurrentTrack = stopAfterCurrent;

    if (duration != null && duration > Duration.zero) {
      _sleepTimerTarget = DateTime.now().add(duration);
      _sleepTimer = Timer(duration, () {
        _sleepTimerTarget = null;
        pause();
        notifyListeners();
      });
    }
    notifyListeners();
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerTarget = null;
    _stopAfterCurrentTrack = false;
    notifyListeners();
  }

  void _syncExternalControllers({required bool forceWidgetUpdate}) {
    final track = currentTrack;
    final artUri = _localCoverArtPath != null ? Uri.file(_localCoverArtPath!) : null;

    _audioHandler?.broadcastState(
      currentTrack: track,
      isPlaying: _isPlaying,
      isLoading: _isLoading,
      position: _position,
      duration: _duration,
      speed: _playbackSpeed,
      artUri: artUri,
    );

    if (forceWidgetUpdate || _isPlaying) {
      WidgetSyncService.instance.updateWidgetState(
        currentTrack: track,
        isPlaying: _isPlaying,
        position: _position,
        duration: _duration,
        isShuffle: _isShuffle,
        repeatMode: _repeatMode,
        localCoverPath: _localCoverArtPath,
      );
    }
  }

  Future<void> _saveCurrentProgress({bool completed = false}) async {
    final track = currentTrack;
    if (track == null) return;
    final posToSave = completed ? _duration : _position;
    await PlaybackHistoryService.instance.savePosition(
      accountId: track.accountId,
      item: track.item,
      position: posToSave,
      totalDuration: _duration,
      localThumbnailPath: _localCoverArtPath,
    );
    if (_accountManager != null) {
      CloudPlaybackSyncService.instance.scheduleAutoPush(_accountManager!);
    }
  }

  Future<void> _persistQueueState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 최대 200곡까지 큐 상태 보존
      final queueToSave = _activeQueue.take(200).map((e) => e.toJson()).toList();
      await prefs.setString(_savedQueueKey, jsonEncode(queueToSave));
      await prefs.setInt(_savedIndexKey, _currentIndex);
      await prefs.setBool(_savedShuffleKey, _isShuffle);
      await prefs.setString(_savedRepeatKey, _repeatMode.name);
    } catch (e) {
      debugPrint('[AudioPlayerService] 큐 상태 저장 실패: $e');
    }
  }

  Future<void> _restoreSavedQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawQueue = prefs.getString(_savedQueueKey);
      if (rawQueue != null && rawQueue.isNotEmpty) {
        final list = jsonDecode(rawQueue) as List<dynamic>;
        _activeQueue = list
            .map((e) => AudioQueueItem.fromJson(e as Map<String, dynamic>))
            .toList();
        _originalQueue = List.from(_activeQueue);
        _currentIndex = (prefs.getInt(_savedIndexKey) ?? 0)
            .clamp(0, math.max(0, _activeQueue.length - 1));
      }
      _isShuffle = prefs.getBool(_savedShuffleKey) ?? false;
      final repStr = prefs.getString(_savedRepeatKey);
      if (repStr != null) {
        _repeatMode = AudioRepeatMode.values.firstWhere(
          (e) => e.name == repStr,
          orElse: () => AudioRepeatMode.all,
        );
      }
      _syncExternalControllers(forceWidgetUpdate: true);
      notifyListeners();
    } catch (e) {
      debugPrint('[AudioPlayerService] 저장된 큐 복원 실패: $e');
    }
  }

  @override
  void dispose() {
    _playingSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _completedSub?.cancel();
    _errorSub?.cancel();
    _historySaveTimer?.cancel();
    _sleepTimer?.cancel();
    _player?.dispose();
    super.dispose();
  }
}
