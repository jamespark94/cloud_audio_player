class MediaItem {
  final String id;
  final String name;
  final String? parentId;
  final bool isFolder;
  final int? size;
  final String? mimeType;
  final String? thumbnailUrl;
  final String? directStreamUrl;
  final DateTime? modifiedTime;
  final Duration? duration;

  // 오디오 특화 메타데이터 (선택적)
  final String? artist;
  final String? album;
  final int? trackNumber;

  MediaItem({
    required this.id,
    required this.name,
    this.parentId,
    required this.isFolder,
    this.size,
    this.mimeType,
    this.thumbnailUrl,
    this.directStreamUrl,
    this.modifiedTime,
    this.duration,
    this.artist,
    this.album,
    this.trackNumber,
  });

  /// 오디오 파일 여부 판별 (고음질 무손실 및 일반 오디오 포맷 전체 지원)
  bool get isAudio {
    if (isFolder) return false;
    final lowerName = name.toLowerCase();
    const audioExtensions = [
      '.mp3',
      '.flac',
      '.wav',
      '.m4a',
      '.aac',
      '.ogg',
      '.opus',
      '.wma',
      '.alac',
      '.ape',
      '.dsf',
      '.dff',
      '.mka',
      '.aiff',
      '.aif',
      '.wv',
      '.tta',
      '.mp2',
      '.amr',
      '.mid',
      '.midi',
    ];
    if (audioExtensions.any((ext) => lowerName.endsWith(ext))) return true;
    if (mimeType != null && mimeType!.startsWith('audio/')) return true;
    return false;
  }

  /// 비디오 파일 여부 판별 (기존 호환성 유지 및 뮤직비디오/오디오 추출 재생 지원)
  bool get isVideo {
    if (isFolder) return false;
    final lowerName = name.toLowerCase();
    final videoExtensions = [
      '.mp4',
      '.mkv',
      '.avi',
      '.mov',
      '.wmv',
      '.flv',
      '.webm',
      '.m4v',
      '.ts',
      '.tp',
      '.m2ts',
      '.mts',
      '.3gp',
      '.asf',
      '.vob',
      '.mpg',
      '.mpeg',
      '.m2v',
      '.ogv',
      '.divx',
      '.rm',
      '.rmvb',
      '.f4v',
    ];
    if (videoExtensions.any((ext) => lowerName.endsWith(ext))) return true;
    if (mimeType != null && mimeType!.startsWith('video/')) return true;
    return false;
  }

  /// 싱크 가사(.lrc) 및 자막 파일 판별
  bool get isLyrics {
    if (isFolder) return false;
    final lowerName = name.toLowerCase();
    return lowerName.endsWith('.lrc') ||
        lowerName.endsWith('.srt') ||
        lowerName.endsWith('.smi') ||
        lowerName.endsWith('.vtt') ||
        lowerName.endsWith('.txt');
  }

  bool get isSubtitle => isLyrics;

  /// 폴더 내 앨범 커버 이미지 판별 (cover.jpg, folder.png 등 또는 일반 이미지)
  bool get isImage {
    if (isFolder) return false;
    final lowerName = name.toLowerCase();
    return lowerName.endsWith('.jpg') ||
        lowerName.endsWith('.jpeg') ||
        lowerName.endsWith('.png') ||
        lowerName.endsWith('.webp') ||
        lowerName.endsWith('.gif') ||
        lowerName.endsWith('.avif') ||
        lowerName.endsWith('.bmp');
  }

  bool get isCoverArtCandidate {
    if (!isImage) return false;
    final lowerName = name.toLowerCase();
    return lowerName.startsWith('cover.') ||
        lowerName.startsWith('folder.') ||
        lowerName.startsWith('front.') ||
        lowerName.startsWith('album.') ||
        lowerName.startsWith('art.') ||
        lowerName.contains('cover');
  }

  /// 만화책 뷰어 재사용 호환 게터
  bool get isComicArchive {
    if (isFolder) return false;
    final lowerName = name.toLowerCase();
    return lowerName.endsWith('.zip') ||
        lowerName.endsWith('.cbz') ||
        lowerName.endsWith('.rar') ||
        lowerName.endsWith('.cbr') ||
        lowerName.endsWith('.7z') ||
        lowerName.endsWith('.tar') ||
        lowerName.endsWith('.pdf');
  }

  /// 파일명에서 확장자를 제거한 깔끔한 곡 제목 추출
  String get displayTitle {
    final lastDot = name.lastIndexOf('.');
    if (lastDot > 0) {
      return name.substring(0, lastDot);
    }
    return name;
  }

  /// 파일명 패턴("Artist - Title.mp3")에서 아티스트 추론
  String get displayArtist {
    if (artist != null && artist!.trim().isNotEmpty) return artist!;
    final base = displayTitle;
    final dashIdx = base.indexOf(' - ');
    if (dashIdx > 0) {
      final candidate = base.substring(0, dashIdx).trim();
      // 트랙 번호("01 - Title")만 있는 경우는 제외
      if (RegExp(r'^\d+$').hasMatch(candidate)) {
        return '클라우드 오디오';
      }
      return candidate;
    }
    return '클라우드 오디오';
  }

  /// 파일명에서 아티스트 접두어와 트랙 번호를 정제한 순수 곡 제목
  String get cleanTrackTitle {
    final base = displayTitle;
    final dashIdx = base.indexOf(' - ');
    if (dashIdx > 0 && dashIdx + 3 < base.length) {
      return base.substring(dashIdx + 3).trim();
    }
    return base;
  }

  /// 오디오 포맷 배지 텍스트 (예: FLAC, MP3, M4A, DSD)
  String get audioFormatBadge {
    final lastDot = name.lastIndexOf('.');
    if (lastDot >= 0 && lastDot + 1 < name.length) {
      return name.substring(lastDot + 1).toUpperCase();
    }
    return 'AUDIO';
  }

  String get formattedSize {
    if (size == null || size == 0) return '';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double dSize = size!.toDouble();
    while (dSize >= 1024 && i < suffixes.length - 1) {
      dSize /= 1024;
      i++;
    }
    return '${dSize.toStringAsFixed(1)} ${suffixes[i]}';
  }

  String get formattedDuration {
    if (duration == null || duration == Duration.zero) return '';
    final hours = duration!.inHours;
    final minutes = duration!.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration!.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'parentId': parentId,
        'isFolder': isFolder,
        'size': size,
        'mimeType': mimeType,
        'thumbnailUrl': thumbnailUrl,
        'directStreamUrl': directStreamUrl,
        'modifiedTime': modifiedTime?.toIso8601String(),
        'durationMs': duration?.inMilliseconds,
        'artist': artist,
        'album': album,
        'trackNumber': trackNumber,
      };

  factory MediaItem.fromJson(Map<String, dynamic> json) => MediaItem(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        parentId: json['parentId'] as String?,
        isFolder: json['isFolder'] as bool? ?? false,
        size: (json['size'] as num?)?.toInt(),
        mimeType: json['mimeType'] as String?,
        thumbnailUrl: json['thumbnailUrl'] as String?,
        directStreamUrl: json['directStreamUrl'] as String?,
        modifiedTime: json['modifiedTime'] != null
            ? DateTime.tryParse(json['modifiedTime'] as String)
            : null,
        duration: json['durationMs'] != null
            ? Duration(milliseconds: (json['durationMs'] as num).toInt())
            : null,
        artist: json['artist'] as String?,
        album: json['album'] as String?,
        trackNumber: (json['trackNumber'] as num?)?.toInt(),
      );
}
