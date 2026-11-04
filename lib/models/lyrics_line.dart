/// 실시간 싱크 가사(.lrc / .srt / .smi)의 개별 타임스탬프 라인 모델
class LyricsLine {
  final Duration timestamp;
  final String text;

  const LyricsLine({
    required this.timestamp,
    required this.text,
  });

  String get formattedTime {
    final m = timestamp.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = timestamp.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
