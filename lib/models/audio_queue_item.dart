import 'cloud_account.dart';
import 'media_item.dart';

/// 오디오 플레이어 재생 큐(Queue)에 담기는 개별 트랙 모델
/// 서로 다른 클라우드 계정(Google Drive, Mega, Naver, WebDAV 등)의 곡들을
/// 하나의 통합 플레이리스트로 묶어 연속 재생할 수 있도록 계정 메타데이터를 함께 보관합니다.
class AudioQueueItem {
  final String accountId;
  final String accountName;
  final CloudType cloudType;
  final MediaItem item;
  final String? folderName;
  final MediaItem? coverArtItem;
  final MediaItem? lyricsItem;

  const AudioQueueItem({
    required this.accountId,
    required this.accountName,
    required this.cloudType,
    required this.item,
    this.folderName,
    this.coverArtItem,
    this.lyricsItem,
  });

  String get uniqueKey => '${accountId}_${item.id}';

  String get title => item.cleanTrackTitle;

  String get artist {
    final inferred = item.displayArtist;
    if (inferred != '클라우드 오디오') return inferred;
    if (folderName != null && folderName!.trim().isNotEmpty) {
      return folderName!;
    }
    return accountName;
  }

  String get cloudBadgeLabel {
    switch (cloudType) {
      case CloudType.googleDrive:
        return 'Google Drive';
      case CloudType.oneDrive:
        return 'OneDrive';
      case CloudType.webDav:
        return 'WebDAV';
      case CloudType.box:
        return 'Box';
      case CloudType.dropbox:
        return 'Dropbox';
      case CloudType.local:
        return '내 기기';
      case CloudType.terabox:
        return 'TeraBox';
      case CloudType.baidu:
        return 'Baidu';
      case CloudType.naver:
        return 'Naver MYBOX';
      case CloudType.mega:
        return 'MEGA';
    }
  }

  Map<String, dynamic> toJson() => {
        'accountId': accountId,
        'accountName': accountName,
        'cloudType': cloudType.name,
        'item': item.toJson(),
        'folderName': folderName,
        'coverArtItem': coverArtItem?.toJson(),
        'lyricsItem': lyricsItem?.toJson(),
      };

  factory AudioQueueItem.fromJson(Map<String, dynamic> json) {
    final cTypeStr = json['cloudType'] as String? ?? 'googleDrive';
    final cType = CloudType.values.firstWhere(
      (e) => e.name == cTypeStr,
      orElse: () => CloudType.googleDrive,
    );
    return AudioQueueItem(
      accountId: json['accountId'] as String? ?? '',
      accountName: json['accountName'] as String? ?? '',
      cloudType: cType,
      item: MediaItem.fromJson(json['item'] as Map<String, dynamic>),
      folderName: json['folderName'] as String?,
      coverArtItem: json['coverArtItem'] != null
          ? MediaItem.fromJson(json['coverArtItem'] as Map<String, dynamic>)
          : null,
      lyricsItem: json['lyricsItem'] != null
          ? MediaItem.fromJson(json['lyricsItem'] as Map<String, dynamic>)
          : null,
    );
  }
}
