import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/audio_player_service.dart';
import '../screens/full_player_sheet.dart';
import 'queue_bottom_sheet.dart';

/// 홈 화면 및 폴더 탐색기 하단에 상시 고정되는 미니 오디오 플레이어 바
/// 탭하거나 위로 스와이프하면 전체 오디오 플레이어 시트([FullPlayerSheet])가 열립니다.
class MiniPlayerBar extends StatelessWidget {
  const MiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<AudioPlayerService>();
    final track = player.currentTrack;
    if (track == null) return const SizedBox.shrink();

    final progress = (player.duration.inMilliseconds > 0)
        ? (player.position.inMilliseconds / player.duration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;

    return GestureDetector(
      onTap: () => FullPlayerSheet.show(context),
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) < -200) {
          FullPlayerSheet.show(context);
        }
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1E2638), Color(0xFF171C29)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.tealAccent.withAlpha(65),
            width: 0.9,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(140),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Row(
                  children: [
                    // 앨범 아트 썸네일
                    _buildCoverArt(player),
                    const SizedBox(width: 12),
                    // 곡 제목 & 아티스트 / 클라우드 배지
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.tealAccent.withAlpha(35),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${track.cloudBadgeLabel} • ${track.item.audioFormatBadge}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.tealAccent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (player.remainingSleepTime != null ||
                                  player.stopAfterCurrentTrack) ...[
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.bedtime_rounded,
                                  size: 13,
                                  color: Colors.amberAccent,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withAlpha(170),
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 이전 곡 / 재생·일시정지 / 다음 곡 / 재생큐 버튼
                    IconButton(
                      icon: const Icon(Icons.skip_previous_rounded, size: 24),
                      color: Colors.white70,
                      tooltip: '이전 곡',
                      onPressed: player.skipToPrevious,
                    ),
                    player.isLoading
                        ? const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.tealAccent,
                              ),
                            ),
                          )
                        : IconButton(
                            icon: Icon(
                              player.isPlaying
                                  ? Icons.pause_circle_filled_rounded
                                  : Icons.play_circle_filled_rounded,
                              size: 36,
                              color: Colors.tealAccent,
                            ),
                            tooltip: player.isPlaying ? '일시정지' : '재생',
                            onPressed: player.togglePlayPause,
                          ),
                    IconButton(
                      icon: const Icon(Icons.skip_next_rounded, size: 24),
                      color: Colors.white70,
                      tooltip: '다음 곡',
                      onPressed: player.skipToNext,
                    ),
                    IconButton(
                      icon: const Icon(Icons.queue_music_rounded, size: 22),
                      color: Colors.white70,
                      tooltip: '재생 큐',
                      onPressed: () => QueueBottomSheet.show(context),
                    ),
                  ],
                ),
              ),
              // 하단 슬림 프로그레스 바
              LinearProgressIndicator(
                value: progress,
                minHeight: 2.5,
                backgroundColor: Colors.white.withAlpha(25),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Colors.tealAccent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCoverArt(AudioPlayerService player) {
    final localPath = player.localCoverArtPath;
    if (localPath != null && File(localPath).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(
          File(localPath),
          width: 46,
          height: 46,
          fit: BoxFit.cover,
        ),
      );
    }

    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00B4DB), Color(0xFF0083B0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(
        Icons.album_rounded,
        color: Colors.white,
        size: 26,
      ),
    );
  }
}
