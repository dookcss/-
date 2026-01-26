import 'dart:async';

import 'package:flutter/foundation.dart';
import '../models/dlna_device.dart';
import '../models/media_item.dart';
import '../models/didl_content.dart';
import '../services/ssdp_service.dart';
import '../services/dlna_service.dart';
import '../services/media_server.dart';
import '../services/content_directory_service.dart';

enum PlaybackState { idle, loading, playing, paused, stopped }

class CastProvider extends ChangeNotifier {
  final SSDPService _ssdpService = SSDPService();
  final DLNAService _dlnaService = DLNAService();
  final MediaServer _mediaServer = MediaServer();
  final ContentDirectoryService _contentDirectoryService = ContentDirectoryService();

  final List<DLNADevice> _devices = [];
  DLNADevice? _selectedRenderer;
  DLNADevice? _selectedServer;
  MediaItem? _currentMedia;
  PlaybackState _playbackState = PlaybackState.idle;
  bool _isScanning = false;
  String? _error;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  int _volume = 50;

  // Settings
  bool _autoSelectRenderer = true;

  // Content browsing state
  List<DIDLContent> _currentContents = [];
  final List<String> _navigationStack = ['0'];
  String _currentTitle = '根目录';
  bool _isBrowsing = false;

  // Manual discovery state
  bool _isManualDiscovering = false;

  StreamSubscription? _deviceSubscription;
  Timer? _positionTimer;

  // Device getters
  List<DLNADevice> get devices => List.unmodifiable(_devices);
  List<DLNADevice> get renderers =>
      _devices.where((d) => d.canPlayMedia).toList();
  List<DLNADevice> get servers =>
      _devices.where((d) => d.canBrowseMedia).toList();

  DLNADevice? get selectedRenderer => _selectedRenderer;
  DLNADevice? get selectedServer => _selectedServer;
  MediaItem? get currentMedia => _currentMedia;
  PlaybackState get playbackState => _playbackState;
  bool get isScanning => _isScanning;
  String? get error => _error;
  Duration get position => _position;
  Duration get duration => _duration;
  int get volume => _volume;
  bool get isPlaying => _playbackState == PlaybackState.playing;
  bool get autoSelectRenderer => _autoSelectRenderer;
  bool get isManualDiscovering => _isManualDiscovering;

  // Content browsing getters
  List<DIDLContent> get currentContents => List.unmodifiable(_currentContents);
  String get currentTitle => _currentTitle;
  bool get isBrowsing => _isBrowsing;
  bool get canGoBack => _navigationStack.length > 1;

  // SSDP log getters
  List<SSDPLogEntry> get ssdpLogs => _ssdpService.logs;
  Stream<SSDPLogEntry> get ssdpLogStream => _ssdpService.logStream;

  void clearSsdpLogs() {
    _ssdpService.clearLogs();
    notifyListeners();
  }

  void setAutoSelectRenderer(bool value) {
    _autoSelectRenderer = value;
    notifyListeners();
  }

  Future<void> startScan() async {
    if (_isScanning) return;

    _isScanning = true;
    _error = null;
    _devices.clear();
    notifyListeners();

    _deviceSubscription = _ssdpService.deviceStream.listen((device) {
      // Avoid duplicates by USN
      if (!_devices.any((d) => d.usn == device.usn)) {
        _devices.add(device);

        // Auto-select first renderer if enabled
        if (_autoSelectRenderer && _selectedRenderer == null && device.canPlayMedia) {
          _selectedRenderer = device;
        }

        notifyListeners();
      }
    });

    await _ssdpService.startDiscovery();

    Future.delayed(const Duration(seconds: 10), () {
      stopScan();
    });
  }

  void stopScan() {
    _isScanning = false;
    _deviceSubscription?.cancel();
    _ssdpService.stopDiscovery();
    notifyListeners();
  }

  /// Manual device discovery by IP address
  Future<bool> discoverDeviceByIP(String ip) async {
    if (_isManualDiscovering) return false;

    _isManualDiscovering = true;
    _error = null;
    notifyListeners();

    try {
      final devices = await _ssdpService.discoverDeviceByIP(ip);

      for (final device in devices) {
        if (!_devices.any((d) => d.usn == device.usn)) {
          _devices.add(device);

          // Auto-select first renderer if enabled
          if (_autoSelectRenderer && _selectedRenderer == null && device.canPlayMedia) {
            _selectedRenderer = device;
          }
        }
      }

      _isManualDiscovering = false;
      notifyListeners();
      return devices.isNotEmpty;
    } catch (e) {
      _error = '手动发现失败: $e';
      _isManualDiscovering = false;
      notifyListeners();
      return false;
    }
  }

  void selectRenderer(DLNADevice? device) {
    _selectedRenderer = device;
    notifyListeners();
  }

  void selectServer(DLNADevice? device) {
    _selectedServer = device;
    if (device != null && device.canBrowseMedia) {
      browseRoot();
    } else {
      _currentContents.clear();
      _navigationStack.clear();
      _navigationStack.add('0');
      _currentTitle = '根目录';
    }
    notifyListeners();
  }

  // Content browsing methods
  Future<void> browseRoot() async {
    _navigationStack.clear();
    _navigationStack.add('0');
    _currentTitle = '根目录';
    await _browseContainer('0');
  }

  Future<void> browseContainer(DIDLContent container) async {
    if (!container.isContainer) return;
    _navigationStack.add(container.id);
    _currentTitle = container.title;
    await _browseContainer(container.id);
  }

  Future<void> goBack() async {
    if (_navigationStack.length <= 1) return;
    _navigationStack.removeLast();
    final parentId = _navigationStack.last;

    if (parentId == '0') {
      _currentTitle = '根目录';
    }

    await _browseContainer(parentId);
  }

  Future<void> _browseContainer(String containerId) async {
    if (_selectedServer == null || !_selectedServer!.canBrowseMedia) return;

    _isBrowsing = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _contentDirectoryService.browse(
        _selectedServer!,
        objectId: containerId,
      );

      if (result != null) {
        _currentContents = result.items;
      } else {
        _error = '浏览内容失败';
        _currentContents = [];
      }
    } catch (e) {
      _error = '浏览错误: $e';
      _currentContents = [];
    }

    _isBrowsing = false;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (_navigationStack.isNotEmpty) {
      await _browseContainer(_navigationStack.last);
    }
  }

  // Cast methods
  Future<bool> castMedia(String filePath, String fileName) async {
    if (_selectedRenderer == null) {
      _error = '未选择播放设备';
      notifyListeners();
      return false;
    }

    _playbackState = PlaybackState.loading;
    _error = null;
    notifyListeners();

    try {
      final mediaUrl = await _mediaServer.startServer(filePath);
      if (mediaUrl == null) {
        _error = '启动媒体服务器失败';
        _playbackState = PlaybackState.idle;
        notifyListeners();
        return false;
      }

      final ext = filePath.split('.').last;
      final mediaType = MediaItem.getTypeFromExtension(ext);
      final mimeType = MediaItem.getMimeType(ext, mediaType);

      _currentMedia = MediaItem(
        path: filePath,
        name: fileName,
        type: mediaType,
        mimeType: mimeType,
      );

      final success = await _dlnaService.setMediaUrl(
        _selectedRenderer!,
        mediaUrl,
        fileName,
        mimeType: mimeType,
      );

      if (!success) {
        _error = '设置媒体URL失败';
        _playbackState = PlaybackState.idle;
        notifyListeners();
        return false;
      }

      final playSuccess = await _dlnaService.play(_selectedRenderer!);
      if (playSuccess) {
        _playbackState = PlaybackState.playing;
        _startPositionPolling();
      } else {
        _error = '开始播放失败';
        _playbackState = PlaybackState.idle;
      }

      notifyListeners();
      return playSuccess;
    } catch (e) {
      _error = '投屏错误: $e';
      _playbackState = PlaybackState.idle;
      notifyListeners();
      return false;
    }
  }

  Future<bool> castUrl(String url, String title, String mimeType) async {
    if (_selectedRenderer == null) {
      _error = '未选择播放设备';
      notifyListeners();
      return false;
    }

    _playbackState = PlaybackState.loading;
    _error = null;
    notifyListeners();

    try {
      _currentMedia = MediaItem(
        path: url,
        name: title,
        type: _getMediaTypeFromMime(mimeType),
        mimeType: mimeType,
      );

      final success = await _dlnaService.setMediaUrl(
        _selectedRenderer!,
        url,
        title,
        mimeType: mimeType,
      );

      if (!success) {
        _error = '设置媒体URL失败';
        _playbackState = PlaybackState.idle;
        notifyListeners();
        return false;
      }

      final playSuccess = await _dlnaService.play(_selectedRenderer!);
      if (playSuccess) {
        _playbackState = PlaybackState.playing;
        _startPositionPolling();
      } else {
        _error = '开始播放失败';
        _playbackState = PlaybackState.idle;
      }

      notifyListeners();
      return playSuccess;
    } catch (e) {
      _error = '投屏错误: $e';
      _playbackState = PlaybackState.idle;
      notifyListeners();
      return false;
    }
  }

  MediaType _getMediaTypeFromMime(String mimeType) {
    if (mimeType.startsWith('video/')) return MediaType.video;
    if (mimeType.startsWith('audio/')) return MediaType.audio;
    if (mimeType.startsWith('image/')) return MediaType.image;
    return MediaType.video;
  }

  Future<bool> castContent(DIDLContent content) async {
    if (_selectedRenderer == null) {
      _error = '未选择播放设备';
      notifyListeners();
      return false;
    }

    if (content.url == null) {
      _error = '内容没有可播放的URL';
      notifyListeners();
      return false;
    }

    _playbackState = PlaybackState.loading;
    _error = null;
    notifyListeners();

    try {
      final mimeType = content.mimeType ?? _getMimeTypeFromContentType(content.type);

      _currentMedia = MediaItem(
        path: content.url!,
        name: content.title,
        type: _convertContentType(content.type),
        mimeType: mimeType,
      );

      final success = await _dlnaService.setMediaUrl(
        _selectedRenderer!,
        content.url!,
        content.title,
        mimeType: mimeType,
      );

      if (!success) {
        _error = '设置媒体URL失败';
        _playbackState = PlaybackState.idle;
        notifyListeners();
        return false;
      }

      final playSuccess = await _dlnaService.play(_selectedRenderer!);
      if (playSuccess) {
        _playbackState = PlaybackState.playing;
        _startPositionPolling();
      } else {
        _error = '开始播放失败';
        _playbackState = PlaybackState.idle;
      }

      notifyListeners();
      return playSuccess;
    } catch (e) {
      _error = '投屏错误: $e';
      _playbackState = PlaybackState.idle;
      notifyListeners();
      return false;
    }
  }

  MediaType _convertContentType(ContentType type) {
    switch (type) {
      case ContentType.video:
        return MediaType.video;
      case ContentType.audio:
        return MediaType.audio;
      case ContentType.image:
        return MediaType.image;
      default:
        return MediaType.video;
    }
  }

  String _getMimeTypeFromContentType(ContentType type) {
    switch (type) {
      case ContentType.video:
        return 'video/mp4';
      case ContentType.audio:
        return 'audio/mp3';
      case ContentType.image:
        return 'image/jpeg';
      default:
        return 'video/mp4';
    }
  }

  Future<void> play() async {
    if (_selectedRenderer == null) return;

    final success = await _dlnaService.play(_selectedRenderer!);
    if (success) {
      _playbackState = PlaybackState.playing;
      _startPositionPolling();
      notifyListeners();
    }
  }

  Future<void> pause() async {
    if (_selectedRenderer == null) return;

    final success = await _dlnaService.pause(_selectedRenderer!);
    if (success) {
      _playbackState = PlaybackState.paused;
      _stopPositionPolling();
      notifyListeners();
    }
  }

  Future<void> stop() async {
    if (_selectedRenderer == null) return;

    await _dlnaService.stop(_selectedRenderer!);
    await _mediaServer.stopServer();

    _playbackState = PlaybackState.stopped;
    _position = Duration.zero;
    _duration = Duration.zero;
    _currentMedia = null;
    _stopPositionPolling();
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    if (_selectedRenderer == null) return;

    await _dlnaService.seek(_selectedRenderer!, position);
    _position = position;
    notifyListeners();
  }

  Future<void> setVolume(int volume) async {
    if (_selectedRenderer == null) return;

    final success = await _dlnaService.setVolume(_selectedRenderer!, volume);
    if (success) {
      _volume = volume;
      notifyListeners();
    }
  }

  void _startPositionPolling() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_selectedRenderer == null) return;

      final info = await _dlnaService.getPositionInfo(_selectedRenderer!);
      if (info != null) {
        _position = info['position'] as Duration;
        _duration = info['duration'] as Duration;
        notifyListeners();
      }
    });
  }

  void _stopPositionPolling() {
    _positionTimer?.cancel();
    _positionTimer = null;
  }

  @override
  void dispose() {
    _deviceSubscription?.cancel();
    _positionTimer?.cancel();
    _ssdpService.dispose();
    _mediaServer.dispose();
    super.dispose();
  }
}
