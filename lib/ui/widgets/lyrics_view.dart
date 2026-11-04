import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/audio_player_service.dart';

/// 실시간 타임스탬프 싱크 가사(.lrc / .srt / .smi) 뷰어 위젯
/// 현재 재생 중인 구간의 가사를 하이라이트하고 자동으로 중앙 스크롤하며,
/// 가사 라인을 탭하면 해당 시간으로 즉시 탐색(Seek)합니다.
class LyricsView extends StatefulWidget {
  const LyricsView({super.key});

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  final ScrollController _scrollController = ScrollController();
  int _lastScrolledIndex = -1;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToActiveLine(int activeIdx, int totalCount) {
    if (activeIdx < 0 || activeIdx == _lastScrolledIndex) return;
    _lastScrolledIndex = activeIdx;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      const double estimatedItemHeight = 52.0;
      final viewportHeight = _scrollController.position.viewportDimension;
      final targetOffset =
          (activeIdx * estimatedItemHeight) - (viewportHeight / 2) + 26;
      final clamped = targetOffset.clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.animateTo(
        clamped,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<AudioPlayerService>();
    final lyrics = player.lyrics;

    if (player.isLoadingLyrics) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.tealAccent),
            SizedBox(height: 12),
            Text(
              '클라우드에서 싱크 가사(.lrc)를 불러오는 중...',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (lyrics.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lyrics_outlined,
                size: 54,
                color: Colors.white.withAlpha(70),
              ),
              const SizedBox(height: 12),
              const Text(
                '표시할 싱크 가사가 없습니다',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '같은 클라우드 폴더에 오디오 파일과 동일한 이름의\n.lrc, .srt, .smi 파일을 넣어두면 자동으로 연동됩니다.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withAlpha(120),
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final activeIdx = player.currentLyricsIndex;
    _scrollToActiveLine(activeIdx, lyrics.length);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 20),
      itemCount: lyrics.length,
      itemBuilder: (context, index) {
        final line = lyrics[index];
        final isActive = index == activeIdx;

        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => player.seek(line.timestamp),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              color: isActive
                  ? Colors.tealAccent.withAlpha(22)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.formattedTime,
                  style: TextStyle(
                    fontSize: 11,
                    color: isActive
                        ? Colors.tealAccent
                        : Colors.white.withAlpha(80),
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    line.text,
                    style: TextStyle(
                      fontSize: isActive ? 16.5 : 14.5,
                      fontWeight:
                          isActive ? FontWeight.bold : FontWeight.normal,
                      color: isActive
                          ? Colors.tealAccent
                          : Colors.white.withAlpha(150),
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
