import 'dart:async';
import 'dart:io';

import 'package:xml/xml.dart';
import 'package:http/http.dart' as http;
import '../models/dlna_device.dart';

class SSDPLogEntry {
  final DateTime timestamp;
  final String level; // INFO, WARN, ERROR, DEBUG
  final String message;

  SSDPLogEntry(this.level, this.message) : timestamp = DateTime.now();

  @override
  String toString() {
    final time = '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}';
    return '[$time] $level: $message';
  }
}

class SSDPService {
  static const String multicastAddress = '239.255.255.250';
  static const String broadcastAddress = '255.255.255.255';
  static const int ssdpPort = 1900;

  static const List<String> searchTargets = [
    'ssdp:all',
    'upnp:rootdevice',
    'urn:schemas-upnp-org:device:MediaRenderer:1',
    'urn:schemas-upnp-org:device:MediaServer:1',
    'urn:schemas-upnp-org:service:AVTransport:1',
    'urn:schemas-upnp-org:service:ContentDirectory:1',
  ];

  // Common DLNA ports for manual discovery
  static const List<int> commonDLNAPorts = [
    8008, 8080, 8443, 9000, 49152, 49153, 49154, 52235, 1400, 7000,
  ];

  RawDatagramSocket? _socket;
  final StreamController<DLNADevice> _deviceController =
      StreamController<DLNADevice>.broadcast();

  Stream<DLNADevice> get deviceStream => _deviceController.stream;

  final Set<String> _discoveredLocations = {};
  Timer? _searchTimer;
  String? _localIp;
  String? _subnetBroadcast;

  // Debug logging
  final List<SSDPLogEntry> _logs = [];
  final StreamController<SSDPLogEntry> _logController =
      StreamController<SSDPLogEntry>.broadcast();

  List<SSDPLogEntry> get logs => List.unmodifiable(_logs);
  Stream<SSDPLogEntry> get logStream => _logController.stream;

  void _log(String level, String message) {
    final entry = SSDPLogEntry(level, message);
    _logs.add(entry);
    if (_logs.length > 200) {
      _logs.removeAt(0); // Keep last 200 logs
    }
    _logController.add(entry);
    print('SSDP: $message');
  }

  void clearLogs() {
    _logs.clear();
  }

  Future<void> startDiscovery() async {
    await stopDiscovery();
    _discoveredLocations.clear();
    _log('INFO', '开始设备发现...');

    try {
      // Get network info first
      await _getNetworkInfo();
      _log('INFO', '本地IP: $_localIp, 子网广播: $_subnetBroadcast');

      // Create socket - try different binding strategies for iOS
      _socket = await _createSocket();
      if (_socket == null) {
        _log('ERROR', '创建Socket失败');
        return;
      }

      _socket!.listen(
        (event) {
          if (event == RawSocketEvent.read) {
            final datagram = _socket!.receive();
            if (datagram != null) {
              final response = String.fromCharCodes(datagram.data);
              _log('DEBUG', '收到响应 from ${datagram.address.address}:${datagram.port}');
              _handleResponse(response);
            }
          }
        },
        onError: (error) => _log('ERROR', 'Socket错误: $error'),
        onDone: () => _log('INFO', 'Socket关闭'),
      );

      // Send initial search
      await _sendAllSearchRequests();

      // Schedule retries - more aggressive for iOS
      int retryCount = 0;
      _searchTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
        retryCount++;
        if (retryCount <= 5) {
          _log('INFO', '重试搜索 $retryCount/5');
          await _sendAllSearchRequests();
        } else {
          timer.cancel();
          _log('INFO', '搜索完成，共发现 ${_discoveredLocations.length} 个位置');
        }
      });

    } catch (e) {
      _log('ERROR', '发现过程错误: $e');
    }
  }

  Future<void> _getNetworkInfo() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      for (final interface in interfaces) {
        final name = interface.name.toLowerCase();
        // Prefer WiFi interfaces (en0 on iOS, wlan on Android)
        if (name.contains('en0') || name.contains('en1') ||
            name.contains('wlan') || name.contains('wifi')) {
          for (final addr in interface.addresses) {
            if (!addr.isLoopback) {
              _localIp = addr.address;
              // Calculate subnet broadcast (assume /24)
              final parts = _localIp!.split('.');
              if (parts.length == 4) {
                _subnetBroadcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
              }
              _log('INFO', '使用接口 ${interface.name}: $_localIp');
              return;
            }
          }
        }
      }

      // Fallback to any interface
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback) {
            _localIp = addr.address;
            final parts = _localIp!.split('.');
            if (parts.length == 4) {
              _subnetBroadcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
            }
            _log('INFO', '使用备用接口 ${interface.name}: $_localIp');
            return;
          }
        }
      }
    } catch (e) {
      _log('ERROR', '获取网络信息失败: $e');
    }
  }

  Future<RawDatagramSocket?> _createSocket() async {
    // Strategy 1: Bind to local IP (best for iOS)
    if (_localIp != null) {
      try {
        final socket = await RawDatagramSocket.bind(
          InternetAddress(_localIp!),
          0,
          reuseAddress: true,
          reusePort: true,
        );
        socket.broadcastEnabled = true;
        socket.readEventsEnabled = true;
        _log('INFO', 'Socket绑定到 $_localIp:${socket.port}');

        // Try to join multicast (may fail on iOS, that's OK)
        _tryJoinMulticast(socket);
        return socket;
      } catch (e) {
        _log('WARN', '绑定到本地IP失败: $e');
      }
    }

    // Strategy 2: Bind to any IPv4
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
        reusePort: true,
      );
      socket.broadcastEnabled = true;
      socket.readEventsEnabled = true;
      _log('INFO', 'Socket绑定到 anyIPv4:${socket.port}');
      _tryJoinMulticast(socket);
      return socket;
    } catch (e) {
      _log('WARN', '绑定到anyIPv4失败: $e');
    }

    // Strategy 3: Bind to specific port (for receiving responses)
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        ssdpPort,
        reuseAddress: true,
        reusePort: true,
      );
      socket.broadcastEnabled = true;
      socket.readEventsEnabled = true;
      _log('INFO', 'Socket绑定到 SSDP端口 $ssdpPort');
      _tryJoinMulticast(socket);
      return socket;
    } catch (e) {
      _log('ERROR', '绑定到SSDP端口失败: $e');
    }

    return null;
  }

  void _tryJoinMulticast(RawDatagramSocket socket) {
    try {
      socket.joinMulticast(InternetAddress(multicastAddress));
      _log('INFO', '加入组播组 $multicastAddress');
    } catch (e) {
      _log('WARN', '无法加入组播(iOS正常): $e');
    }
  }

  Future<void> _sendAllSearchRequests() async {
    if (_socket == null) return;

    final targets = [
      InternetAddress(multicastAddress),
      InternetAddress(broadcastAddress),
      if (_subnetBroadcast != null) InternetAddress(_subnetBroadcast!),
    ];

    int sentCount = 0;
    for (final target in searchTargets) {
      final message = _buildSearchMessage(target);
      final data = message.codeUnits;

      for (final address in targets) {
        for (var i = 0; i < 2; i++) {
          try {
            _socket!.send(data, address, ssdpPort);
            sentCount++;
          } catch (e) {
            // Ignore send errors
          }
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }
    }
    _log('INFO', '发送搜索请求到 ${targets.length} 个地址, 共 $sentCount 个包');
  }

  String _buildSearchMessage(String target) {
    return 'M-SEARCH * HTTP/1.1\r\n'
        'HOST: $multicastAddress:$ssdpPort\r\n'
        'MAN: "ssdp:discover"\r\n'
        'MX: 5\r\n'
        'ST: $target\r\n'
        'USER-AGENT: iOS UPnP/1.0 DLNADOC/1.50\r\n'
        '\r\n';
  }

  void _handleResponse(String response) async {
    if (!response.contains('HTTP/1.1 200') &&
        !response.toUpperCase().contains('NOTIFY')) {
      return;
    }

    final headers = _parseHeaders(response);
    final location = headers['location'];

    if (location == null || location.isEmpty) return;
    if (_discoveredLocations.contains(location)) return;

    _discoveredLocations.add(location);
    _log('INFO', '发现设备: $location');

    try {
      final devices = await _fetchDeviceDescription(location);
      for (final device in devices) {
        if (device.canPlayMedia || device.canBrowseMedia) {
          _log('INFO', '添加设备: ${device.friendlyName} (${device.typeLabel})');
          _deviceController.add(device);
        }
      }
    } catch (e) {
      _log('ERROR', '获取设备描述失败: $e');
    }
  }

  Map<String, String> _parseHeaders(String response) {
    final headers = <String, String>{};
    final lines = response.split(RegExp(r'\r?\n'));

    for (final line in lines) {
      final colonIndex = line.indexOf(':');
      if (colonIndex > 0) {
        final key = line.substring(0, colonIndex).toLowerCase().trim();
        final value = line.substring(colonIndex + 1).trim();
        headers[key] = value;
      }
    }
    return headers;
  }

  Future<List<DLNADevice>> _fetchDeviceDescription(String location) async {
    final devices = <DLNADevice>[];

    try {
      final response = await http.get(
        Uri.parse(location),
        headers: {'User-Agent': 'iOS UPnP/1.0 DLNADOC/1.50'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return devices;

      final document = XmlDocument.parse(response.body);
      final deviceElements = document.findAllElements('device');
      if (deviceElements.isEmpty) return devices;

      final rootDevice = deviceElements.first;
      final baseUrl = _getBaseUrl(location);

      final allDevices = [rootDevice, ...rootDevice.findAllElements('device')];

      for (final device in allDevices) {
        final parsed = _parseDevice(device, location, baseUrl);
        if (parsed != null) {
          devices.add(parsed);
        }
      }
    } catch (e) {
      _log('ERROR', '解析设备描述失败: $e');
    }

    return devices;
  }

  /// Manual device discovery by IP address
  /// Tries common DLNA ports to find device description
  Future<List<DLNADevice>> discoverDeviceByIP(String ip) async {
    _log('INFO', '手动发现设备: $ip');
    final devices = <DLNADevice>[];

    // Try common description paths
    final paths = [
      '/description.xml',
      '/rootDesc.xml',
      '/DeviceDescription.xml',
      '/upnp/desc.xml',
      '/dmr.xml',
      '/dms.xml',
      '/',
    ];

    for (final port in commonDLNAPorts) {
      for (final path in paths) {
        final location = 'http://$ip:$port$path';
        try {
          _log('DEBUG', '尝试: $location');
          final foundDevices = await _fetchDeviceDescription(location);
          if (foundDevices.isNotEmpty) {
            _log('INFO', '手动发现成功: $location');
            for (final device in foundDevices) {
              if (device.canPlayMedia || device.canBrowseMedia) {
                if (!_discoveredLocations.contains(location)) {
                  _discoveredLocations.add(location);
                  devices.add(device);
                  _deviceController.add(device);
                }
              }
            }
            if (devices.isNotEmpty) {
              return devices;
            }
          }
        } catch (e) {
          // Continue trying other ports/paths
        }
      }
    }

    // Try direct port 80
    for (final path in paths) {
      final location = 'http://$ip$path';
      try {
        _log('DEBUG', '尝试: $location');
        final foundDevices = await _fetchDeviceDescription(location);
        if (foundDevices.isNotEmpty) {
          _log('INFO', '手动发现成功: $location');
          for (final device in foundDevices) {
            if (device.canPlayMedia || device.canBrowseMedia) {
              if (!_discoveredLocations.contains(location)) {
                _discoveredLocations.add(location);
                devices.add(device);
                _deviceController.add(device);
              }
            }
          }
          if (devices.isNotEmpty) {
            return devices;
          }
        }
      } catch (e) {
        // Continue trying
      }
    }

    _log('WARN', '手动发现失败: 在 $ip 未找到DLNA设备');
    return devices;
  }

  DLNADevice? _parseDevice(XmlElement device, String location, String baseUrl) {
    final deviceType = device.findElements('deviceType').firstOrNull?.innerText ?? '';

    if (!deviceType.contains('MediaRenderer') &&
        !deviceType.contains('MediaServer')) {
      return null;
    }

    String? avTransportUrl;
    String? renderingControlUrl;
    String? contentDirectoryUrl;

    final serviceList = device.findElements('serviceList').firstOrNull;
    if (serviceList != null) {
      for (final service in serviceList.findElements('service')) {
        final serviceType = service.findElements('serviceType').firstOrNull?.innerText ?? '';
        final controlUrl = service.findElements('controlURL').firstOrNull?.innerText ?? '';

        if (serviceType.contains('AVTransport')) {
          avTransportUrl = _resolveUrl(baseUrl, controlUrl);
        } else if (serviceType.contains('RenderingControl')) {
          renderingControlUrl = _resolveUrl(baseUrl, controlUrl);
        } else if (serviceType.contains('ContentDirectory')) {
          contentDirectoryUrl = _resolveUrl(baseUrl, controlUrl);
        }
      }
    }

    if (avTransportUrl == null && contentDirectoryUrl == null) {
      return null;
    }

    final friendlyName = device.findElements('friendlyName').firstOrNull?.innerText ?? 'Unknown';
    final manufacturer = device.findElements('manufacturer').firstOrNull?.innerText;
    final modelName = device.findElements('modelName').firstOrNull?.innerText;
    final udn = device.findElements('UDN').firstOrNull?.innerText ?? location;

    String? dlnaVersion;
    final dlnaDocElements = device.findAllElements('X_DLNADOC');
    if (dlnaDocElements.isNotEmpty) {
      dlnaVersion = dlnaDocElements.first.innerText;
    }

    String? dlnaCapabilities;
    final dlnaCapElements = device.findAllElements('X_DLNACAP');
    if (dlnaCapElements.isNotEmpty) {
      dlnaCapabilities = dlnaCapElements.first.innerText;
    }

    return DLNADevice(
      usn: udn,
      friendlyName: friendlyName,
      location: location,
      deviceType: deviceType,
      manufacturer: manufacturer,
      modelName: modelName,
      dlnaVersion: dlnaVersion,
      dlnaCapabilities: dlnaCapabilities,
      avTransportUrl: avTransportUrl,
      renderingControlUrl: renderingControlUrl,
      contentDirectoryUrl: contentDirectoryUrl,
    );
  }

  String _getBaseUrl(String location) {
    final uri = Uri.parse(location);
    return '${uri.scheme}://${uri.host}:${uri.port}';
  }

  String _resolveUrl(String baseUrl, String path) {
    if (path.startsWith('http')) return path;
    if (path.startsWith('/')) return '$baseUrl$path';
    return '$baseUrl/$path';
  }

  Future<void> stopDiscovery() async {
    _searchTimer?.cancel();
    _searchTimer = null;
    _socket?.close();
    _socket = null;
  }

  void dispose() {
    stopDiscovery();
    _deviceController.close();
    _logController.close();
  }
}
