import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/audio_player_service.dart';
import '../../utils/battery_utils.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/queue_bottom_sheet.dart';
import '../widgets/sleep_timer_dialog.dart';

/// 전체화면 오디오 플레이어 모달 시트
/// 앨범 커버 아트 / 싱크 가사(.lrc) 전환, 구간 탐색(Seek), 셔플/반복,
/// 음장(EQ), 배속 조절, 취침 타이머 및 배터리 절전 예외 가이드를 제공합니다.
class FullPlayerSheet extends StatefulWidget {
  const FullPlayerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF0E121B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => const FractionallySizedBox(
        heightFactor: 0.96,
        child: FullPlayerSheet(),
      ),
    );
  }

  @override
  State<FullPlayerSheet> createState() => _FullPlayerSheetState();
}

class _FullPlayerSheetState extends State<FullPlayerSheet> {
  bool _showLyrics = false;
  double? _dragSeconds;
  bool _isIgnoringBatteryOpt = true;

  @override
  void initState() {
    super.initState();
    _checkBatteryOptimization();
  }

  Future<void> _checkBatteryOptimization() async {
    final ignoring = await BatteryUtils.isIgnoringBatteryOptimizations();
    if (mounted) {
      setState(() => _isIgnoringBatteryOpt = ignoring);
    }
  }

  String _formatDuration(Duration d) {
    if (d <= Duration.zero) return '00:00';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<AudioPlayerService>();
    final track = player.currentTrack;

    if (track == null) {
      return const Center(
        child: Text(
          '재생 중인 트랙이 없습니다.',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    final totalSec = player.duration.inSeconds > 0
        ? player.duration.inSeconds.toDouble()
        : 1.0;
    final currentSec = (_dragSeconds ?? player.position.inSeconds.toDouble())
        .clamp(0.0, totalSec);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1A2336), Color(0xFF0C0F17)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 4.5,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            // 상단 헤더 바
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 30,
                      color: Colors.white,
                    ),
                    tooltip: '닫기',
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          track.cloudBadgeLabel,
                          style: const TextStyle(
                            color: Colors.tealAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (track.folderName != null)
                          Text(
                            track.folderName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _showLyrics ? Icons.album_rounded : Icons.lyrics_rounded,
                      color:
                          _showLyrics ? Colors.tealAccent : Colors.white70,
                    ),
                    tooltip: _showLyrics ? '앨범 아트 보기' : '싱크 가사 보기',
                    onPressed: () => setState(() => _showLyrics = !_showLyrics),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.bedtime_rounded,
                      color: (player.remainingSleepTime != null ||
                              player.stopAfterCurrentTrack)
                          ? Colors.amberAccent
                          : Colors.white70,
                    ),
                    tooltip: '취침 예약 타이머',
                    onPressed: () => SleepTimerDialog.show(context),
                  ),
                ],
              ),
            ),

            // 화면 꺼짐 백그라운드 스트리밍을 위한 배터리 절전 예외 안내 배너
            if (!_isIgnoringBatteryOpt && Platform.isAndroid)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () async {
                    await BatteryUtils.requestIgnoreBatteryOptimizations();
                    await Future.delayed(const Duration(seconds: 2));
                    _checkBatteryOptimization();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.withAlpha(30),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amberAccent.withAlpha(80)),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.battery_saver_rounded,
                          color: Colors.amberAccent,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '화면 꺼짐 시 끊김 없는 재생을 위해 배터리 [제한 없음]을 켜주세요 (탭하여 설정)',
                            style: TextStyle(
                              color: Colors.amberAccent,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // 중앙: 앨범 커버 아트 또는 실시간 싱크 가사(.lrc)
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                child: _showLyrics
                    ? const LyricsView(key: ValueKey('lyrics'))
                    : _buildAlbumArtSection(player, track.item.audioFormatBadge),
              ),
            ),

            // 곡 정보 및 음장/배속 칩
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${track.artist} • ${track.item.formattedSize}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // 오디오 포맷 배지 + EQ 프리셋 + 배속 조절 버튼
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _buildChipBadge(
                        icon: Icons.high_quality_rounded,
                        label: track.item.audioFormatBadge,
                        active: true,
                        onTap: () => setState(() => _showLyrics = !_showLyrics),
                      ),
                      _buildChipBadge(
                        icon: Icons.equalizer_rounded,
                        label: player.eqPreset.label,
                        active: player.eqPreset != AudioEqPreset.flat,
                        onTap: () => _showEqSelector(context, player),
                      ),
                      _buildChipBadge(
                        icon: Icons.speed_rounded,
                        label: '${player.playbackSpeed.toStringAsFixed(2)}x',
                        active: player.playbackSpeed != 1.0,
                        onTap: () => _showSpeedSelector(context, player),
                      ),
                      if (player.lyrics.isNotEmpty)
                        _buildChipBadge(
                          icon: Icons.subtitles_rounded,
                          label: _showLyrics ? '가사 닫기' : 'LRC 가사 켜기',
                          active: _showLyrics,
                          onTap: () =>
                              setState(() => _showLyrics = !_showLyrics),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // 탐색 슬라이더(SeekBar)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 7,
                      ),
                      activeTrackColor: Colors.tealAccent,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.tealAccent,
                    ),
                    child: Slider(
                      value: currentSec,
                      min: 0.0,
                      max: totalSec,
                      onChanged: (val) => setState(() => _dragSeconds = val),
                      onChangeEnd: (val) {
                        player.seek(Duration(seconds: val.round()));
                        setState(() => _dragSeconds = null);
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(Duration(seconds: currentSec.round())),
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                        Text(
                          _formatDuration(player.duration),
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 메인 재생 컨트롤러 (셔플 / 이전 / 10초 뒤로 / 재생·일시정지 / 10초 앞으로 / 다음 / 반복)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 26),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.shuffle_rounded,
                      color:
                          player.isShuffle ? Colors.tealAccent : Colors.white54,
                    ),
                    tooltip: '셔플',
                    onPressed: player.toggleShuffle,
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.skip_previous_rounded,
                      size: 34,
                      color: Colors.white,
                    ),
                    tooltip: '이전 곡',
                    onPressed: player.skipToPrevious,
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.replay_10_rounded,
                      size: 28,
                      color: Colors.white70,
                    ),
                    tooltip: '10초 뒤로',
                    onPressed: () {
                      final target =
                          player.position - const Duration(seconds: 10);
                      player.seek(
                        target.isNegative ? Duration.zero : target,
                      );
                    },
                  ),
                  Container(
                    width: 68,
                    height: 68,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFF00F2FE), Color(0xFF4FACFE)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: player.isLoading
                        ? const Padding(
                            padding: EdgeInsets.all(18.0),
                            child: CircularProgressIndicator(
                              color: Colors.black,
                              strokeWidth: 3,
                            ),
                          )
                        : IconButton(
                            icon: Icon(
                              player.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              size: 40,
                              color: Colors.black,
                            ),
                            onPressed: player.togglePlayPause,
                          ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.forward_10_rounded,
                      size: 28,
                      color: Colors.white70,
                    ),
                    tooltip: '10초 앞으로',
                    onPressed: () {
                      final target =
                          player.position + const Duration(seconds: 10);
                      if (player.duration > Duration.zero &&
                          target < player.duration) {
                        player.seek(target);
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.skip_next_rounded,
                      size: 34,
                      color: Colors.white,
                    ),
                    tooltip: '다음 곡',
                    onPressed: player.skipToNext,
                  ),
                  IconButton(
                    icon: Icon(
                      player.repeatMode == AudioRepeatMode.one
                          ? Icons.repeat_one_rounded
                          : Icons.repeat_rounded,
                      color: player.repeatMode != AudioRepeatMode.off
                          ? Colors.tealAccent
                          : Colors.white54,
                    ),
                    tooltip: player.repeatMode.label,
                    onPressed: player.cycleRepeatMode,
                  ),
                ],
              ),
            ),

            // 하단 재생 대기열 열기 바
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextButton.icon(
                onPressed: () => QueueBottomSheet.show(context),
                icon: const Icon(
                  Icons.queue_music_rounded,
                  color: Colors.tealAccent,
                  size: 20,
                ),
                label: Text(
                  '재생 대기열 (${player.currentIndex + 1} / ${player.queue.length}곡)',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlbumArtSection(AudioPlayerService player, String badge) {
    final localPath = player.localCoverArtPath;
    final hasFile = localPath != null && File(localPath).existsSync();

    return Center(
      key: const ValueKey('artwork'),
      child: GestureDetector(
        onTap: () => setState(() => _showLyrics = true),
        child: Container(
          width: 260,
          height: 260,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.tealAccent.withAlpha(35),
                blurRadius: 36,
                spreadRadius: 4,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: hasFile
                ? Image.file(
                    File(localPath),
                    fit: BoxFit.cover,
                  )
                : Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF1D2B44), Color(0xFF121826)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          Icons.album_rounded,
                          size: 150,
                          color: Colors.tealAccent.withAlpha(60),
                        ),
                        const Icon(
                          Icons.music_note_rounded,
                          size: 56,
                          color: Colors.tealAccent,
                        ),
                        Positioned(
                          bottom: 16,
                          child: Text(
                            '탭하여 가사(.lrc) 보기',
                            style: TextStyle(
                              color: Colors.white.withAlpha(130),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildChipBadge({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? Colors.tealAccent.withAlpha(30)
              : Colors.white.withAlpha(15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active
                ? Colors.tealAccent.withAlpha(110)
                : Colors.white.withAlpha(30),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: active ? Colors.tealAccent : Colors.white70,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                color: active ? Colors.tealAccent : Colors.white70,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEqSelector(BuildContext context, AudioPlayerService player) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF171C28),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                '이퀄라이저 / 음장 프리셋',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            ...AudioEqPreset.values.map(
              (preset) => ListTile(
                leading: Icon(
                  Icons.equalizer_rounded,
                  color: player.eqPreset == preset
                      ? Colors.tealAccent
                      : Colors.white54,
                ),
                title: Text(preset.label),
                trailing: player.eqPreset == preset
                    ? const Icon(Icons.check, color: Colors.tealAccent)
                    : null,
                onTap: () {
                  player.setEqPreset(preset);
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSpeedSelector(BuildContext context, AudioPlayerService player) {
    const speeds = [0.75, 0.9, 1.0, 1.15, 1.25, 1.5, 1.75, 2.0];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF171C28),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                '재생 속도 설정',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            ...speeds.map(
              (s) => ListTile(
                leading: Icon(
                  Icons.speed_rounded,
                  color: (player.playbackSpeed - s).abs() < 0.01
                      ? Colors.tealAccent
                      : Colors.white54,
                ),
                title: Text('${s}x 배속'),
                trailing: (player.playbackSpeed - s).abs() < 0.01
                    ? const Icon(Icons.check, color: Colors.tealAccent)
                    : null,
                onTap: () {
                  player.setPlaybackSpeed(s);
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
