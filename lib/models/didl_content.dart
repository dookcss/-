enum ContentType { container, video, audio, image, unknown }

class DIDLContent {
  final String id;
  final String parentId;
  final String title;
  final ContentType type;
  final String? url;
  final String? mimeType;
  final String? albumArtUrl;
  final String? artist;
  final String? album;
  final int? duration;
  final int? size;
  final String? resolution;
  final int childCount;

  DIDLContent({
    required this.id,
    required this.parentId,
    required this.title,
    required this.type,
    this.url,
    this.mimeType,
    this.albumArtUrl,
    this.artist,
    this.album,
    this.duration,
    this.size,
    this.resolution,
    this.childCount = 0,
  });

  bool get isContainer => type == ContentType.container;
  bool get isPlayable => url != null && type != ContentType.container;

  String get typeIcon {
    switch (type) {
      case ContentType.container:
        return 'folder';
      case ContentType.video:
        return 'movie';
      case ContentType.audio:
        return 'music_note';
      case ContentType.image:
        return 'image';
      case ContentType.unknown:
        return 'insert_drive_file';
    }
  }

  String get durationDisplay {
    if (duration == null) return '';
    final d = Duration(seconds: duration!);
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    final seconds = d.inSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String get sizeDisplay {
    if (size == null) return '';
    if (size! < 1024) return '$size B';
    if (size! < 1024 * 1024) return '${(size! / 1024).toStringAsFixed(1)} KB';
    if (size! < 1024 * 1024 * 1024) {
      return '${(size! / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size! / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class BrowseResult {
  final List<DIDLContent> items;
  final int totalMatches;
  final int numberReturned;

  BrowseResult({
    required this.items,
    required this.totalMatches,
    required this.numberReturned,
  });

  bool get hasMore => numberReturned < totalMatches;
}
