enum MediaType { video, audio, image }

class MediaItem {
  final String path;
  final String name;
  final MediaType type;
  final int? size;
  final String? mimeType;

  MediaItem({
    required this.path,
    required this.name,
    required this.type,
    this.size,
    this.mimeType,
  });

  String get extension => path.split('.').last.toLowerCase();

  static MediaType getTypeFromExtension(String ext) {
    const videoExtensions = ['mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm'];
    const audioExtensions = ['mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a'];
    const imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'];

    final lowerExt = ext.toLowerCase();
    if (videoExtensions.contains(lowerExt)) return MediaType.video;
    if (audioExtensions.contains(lowerExt)) return MediaType.audio;
    if (imageExtensions.contains(lowerExt)) return MediaType.image;
    return MediaType.video;
  }

  static String getMimeType(String ext, MediaType type) {
    final lowerExt = ext.toLowerCase();
    switch (type) {
      case MediaType.video:
        return 'video/$lowerExt';
      case MediaType.audio:
        return 'audio/$lowerExt';
      case MediaType.image:
        return 'image/$lowerExt';
    }
  }
}
