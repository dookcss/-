import 'dart:async';

import 'package:flutter/foundation.dart';
import '../models/dlna_device.dart';
import '../models/media_item.dart';
import '../services/ssdp_service.dart';
import '../services/dlna_service.dart';
import '../services/media_server.dart';

enum PlaybackState { idle, loading, playing, paused, stopped }

class CastProvider extends ChangeNotifier {
  final SSDPService _ssdpService = SSDPService();
  final DLNAService _dlnaService = DLNAService();
  final MediaServer _mediaServer = MediaServer();

  final List<DLNADevice> _devices = [];
  DLNADevice? _selectedDevice;
  MediaItem? _currentMedia;
  PlaybackState _playbackState = PlaybackState.idle;
  bool _isScanning = false;
  String? _error;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  int _volume = 50;

  StreamSubscription? _deviceSubscription;
  Timer? _positionTimer;

  List<DLNADevice> get devices => List.unmodifiable(_devices);
  DLNADevice? get selectedDevice => _selectedDevice;
  MediaItem? get currentMedia => _currentMedia;
  PlaybackState get playbackState => _playbackState;
  bool get isScanning => _isScanning;
  String? get error => _error;
  Duration get position => _position;
  Duration get duration => _duration;
  int get volume => _volume;
  bool get isPlaying => _playbackState == PlaybackState.playing;

  Future<void> startScan() async {
    if (_isScanning) return;

    _isScanning = true;
    _error = null;
    _devices.clear();
    notifyListeners();

    _deviceSubscription = _ssdpService.deviceStream.listen((device) {
      if (!_devices.contains(device)) {
        _devices.add(device);
        notifyListeners();
      }
    });

    await _ssdpService.startDiscovery();

    // Stop scanning after 10 seconds
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

  void selectDevice(DLNADevice? device) {
    _selectedDevice = device;
    notifyListeners();
  }

  Future<bool> castMedia(String filePath, String fileName) async {
    if (_selectedDevice == null) {
      _error = 'No device selected';
      notifyListeners();
      return false;
    }

    _playbackState = PlaybackState.loading;
    _error = null;
    notifyListeners();

    try {
      // Start local media server
      final mediaUrl = await _mediaServer.startServer(filePath);
      if (mediaUrl == null) {
        _error = 'Failed to start media server';
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

      // Set media URL on device
      final success = await _dlnaService.setMediaUrl(
        _selectedDevice!,
        mediaUrl,
        fileName,
        mimeType: mimeType,
      );

      if (!success) {
        _error = 'Failed to set media URL';
        _playbackState = PlaybackState.idle;
        notifyListeners();
        return false;
      }

      // Start playback
      final playSuccess = await _dlnaService.play(_selectedDevice!);
      if (playSuccess) {
        _playbackState = PlaybackState.playing;
        _startPositionPolling();
      } else {
        _error = 'Failed to start playback';
        _playbackState = PlaybackState.idle;
      }

      notifyListeners();
      return playSuccess;
    } catch (e) {
      _error = 'Cast error: $e';
      _playbackState = PlaybackState.idle;
      notifyListeners();
      return false;
    }
  }

  Future<void> play() async {
    if (_selectedDevice == null) return;

    final success = await _dlnaService.play(_selectedDevice!);
    if (success) {
      _playbackState = PlaybackState.playing;
      _startPositionPolling();
      notifyListeners();
    }
  }

  Future<void> pause() async {
    if (_selectedDevice == null) return;

    final success = await _dlnaService.pause(_selectedDevice!);
    if (success) {
      _playbackState = PlaybackState.paused;
      _stopPositionPolling();
      notifyListeners();
    }
  }

  Future<void> stop() async {
    if (_selectedDevice == null) return;

    await _dlnaService.stop(_selectedDevice!);
    await _mediaServer.stopServer();

    _playbackState = PlaybackState.stopped;
    _position = Duration.zero;
    _duration = Duration.zero;
    _currentMedia = null;
    _stopPositionPolling();
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    if (_selectedDevice == null) return;

    await _dlnaService.seek(_selectedDevice!, position);
    _position = position;
    notifyListeners();
  }

  Future<void> setVolume(int volume) async {
    if (_selectedDevice == null) return;

    final success = await _dlnaService.setVolume(_selectedDevice!, volume);
    if (success) {
      _volume = volume;
      notifyListeners();
    }
  }

  void _startPositionPolling() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_selectedDevice == null) return;

      final info = await _dlnaService.getPositionInfo(_selectedDevice!);
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
