import '../utils/subtitle_utils.dart';
import '../models/lyrics_line.dart';

/// LRC(.lrc), SRT(.srt), SAMI(.smi) 및 일반 텍스트 가사를
/// 타임스탬프 기반 [LyricsLine] 리스트로 변환하는 유틸리티
class LrcParserUtils {
  /// 바이트 배열을 자동 인코딩 감지(UTF-8, CP949, EUC-KR, GBK)로 디코딩한 뒤 가사 라인으로 파싱합니다.
  static Future<List<LyricsLine>> parseLyricsBytes(
    List<int> rawBytes, {
    required String fileName,
  }) async {
    final text = await SubtitleUtils.decodeSubtitleToUtf8String(rawBytes);
    return parseLyricsString(text, fileName: fileName);
  }

  /// 가사 문자열을 확장자 및 포맷에 맞춰 파싱합니다.
  static List<LyricsLine> parseLyricsString(
    String content, {
    String fileName = '',
  }) {
    final lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.smi') || content.toLowerCase().contains('<sami>')) {
      final srt = SubtitleUtils.smiToSrt(content);
      return _parseSrt(srt);
    }
    if (lowerName.endsWith('.srt') || RegExp(r'\d{2}:\d{2}:\d{2},\d{3}\s*-->').hasMatch(content)) {
      return _parseSrt(content);
    }
    return _parseLrcOrPlainText(content);
  }

  /// 표준 .lrc 포맷 (`[mm:ss.xx]가사` 또는 다중 타임태그 `[00:12.00][01:24.50]가사`) 파싱
  static List<LyricsLine> _parseLrcOrPlainText(String content) {
    final lines = content.replaceAll('\r\n', '\n').split('\n');
    final result = <LyricsLine>[];
    // [mm:ss.xx], [mm:ss:xx], [mm:ss] 매칭
    final timeTagRegex = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
    // [offset:+500] 메타 태그 감지
    int offsetMs = 0;
    final offsetRegex = RegExp(r'\[offset:\s*([+-]?\d+)\s*\]', caseSensitive: false);

    for (final rawLine in lines) {
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty) continue;

      final offsetMatch = offsetRegex.firstMatch(trimmed);
      if (offsetMatch != null) {
        offsetMs = int.tryParse(offsetMatch.group(1)!) ?? 0;
        continue;
      }

      // ID 태그 ([ar:...], [ti:...], [al:...], [by:...]) 스킵
      if (RegExp(r'^\[(ar|ti|al|by|re|ve|length):', caseSensitive: false).hasMatch(trimmed)) {
        continue;
      }

      final matches = timeTagRegex.allMatches(trimmed).toList();
      if (matches.isEmpty) continue;

      final lyricText = trimmed.replaceAll(timeTagRegex, '').trim();
      for (final match in matches) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final fracStr = match.group(3) ?? '0';
        int millis = 0;
        if (fracStr.length == 1) {
          millis = int.parse(fracStr) * 100;
        } else if (fracStr.length == 2) {
          millis = int.parse(fracStr) * 10;
        } else if (fracStr.length >= 3) {
          millis = int.parse(fracStr.substring(0, 3));
        }

        final totalMs = (minutes * 60 * 1000) + (seconds * 1000) + millis - offsetMs;
        result.add(
          LyricsLine(
            timestamp: Duration(milliseconds: totalMs < 0 ? 0 : totalMs),
            text: lyricText.isEmpty ? '♪' : lyricText,
          ),
        );
      }
    }

    if (result.isNotEmpty) {
      result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return result;
    }

    // 타임태그가 전혀 없는 일반 텍스트 가사(.txt)인 경우 0초 간격 라인으로 반환
    final plainLines = <LyricsLine>[];
    var idx = 0;
    for (final rawLine in lines) {
      final t = rawLine.trim();
      if (t.isNotEmpty) {
        plainLines.add(
          LyricsLine(
            timestamp: Duration(seconds: idx * 4),
            text: t,
          ),
        );
        idx++;
      }
    }
    return plainLines;
  }

  static List<LyricsLine> _parseSrt(String srt) {
    final result = <LyricsLine>[];
    final blocks = srt.replaceAll('\r\n', '\n').split(RegExp(r'\n\s*\n'));
    final timeRegex = RegExp(r'(\d{2}):(\d{2}):(\d{2})[,.](\d{3})\s*-->');

    for (final block in blocks) {
      final lines = block.trim().split('\n');
      if (lines.length < 2) continue;

      RegExpMatch? match;
      int timeLineIdx = -1;
      for (var i = 0; i < lines.length; i++) {
        match = timeRegex.firstMatch(lines[i]);
        if (match != null) {
          timeLineIdx = i;
          break;
        }
      }
      if (match == null || timeLineIdx < 0) continue;

      final h = int.parse(match.group(1)!);
      final m = int.parse(match.group(2)!);
      final s = int.parse(match.group(3)!);
      final ms = int.parse(match.group(4)!);

      final textLines = lines
          .sublist(timeLineIdx + 1)
          .map((l) => l.replaceAll(RegExp(r'<[^>]*>'), '').trim())
          .where((l) => l.isNotEmpty)
          .join('\n');

      if (textLines.isNotEmpty) {
        result.add(
          LyricsLine(
            timestamp: Duration(hours: h, minutes: m, seconds: s, milliseconds: ms),
            text: textLines,
          ),
        );
      }
    }

    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result;
  }

  /// 오디오 파일명과 가사 파일명이 매칭되는지 확인
  static bool isLyricsForAudio(String lyricsFileName, String audioFileName) {
    return SubtitleUtils.isSubtitleForVideo(lyricsFileName, audioFileName);
  }
}
