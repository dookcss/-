import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';
import '../models/dlna_device.dart';
import 'ios_native_network.dart';

// iOS网络诊断工具

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

  // UPnP/DLNA search targets
  static const List<String> searchTargets = [
    'ssdp:all',
    'upnp:rootdevice',
    'urn:schemas-upnp-org:device:MediaRenderer:1',
    'urn:schemas-upnp-org:device:MediaServer:1',
    'urn:schemas-upnp-org:service:AVTransport:1',
    'urn:schemas-upnp-org:service:RenderingControl:1',
    'urn:schemas-upnp-org:service:ContentDirectory:1',
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
    if (_logs.length > 2000) {
      _logs.removeAt(0);
    }
    _logController.add(entry);
    print('SSDP: $message');
  }

  void clearLogs() {
    _logs.clear();
  }

  /// Start SSDP device discovery
  /// This sends M-SEARCH requests and listens for device responses
  /// The LOCATION header in responses contains the device description URL
  Future<void> startDiscovery() async {
    await stopDiscovery();
    _discoveredLocations.clear();
    _probedIPs.clear();
    _log('INFO', '开始SSDP设备发现...');

    try {
      await _getNetworkInfo();
      _log('INFO', '本地IP: $_localIp, 子网广播: $_subnetBroadcast');

      _socket = await _createSocket();
      if (_socket == null) {
        _log('ERROR', '创建UDP Socket失败');
        return;
      }

      _socket!.listen(
        (event) {
          if (event == RawSocketEvent.read) {
            final datagram = _socket!.receive();
            if (datagram != null) {
              final response = String.fromCharCodes(datagram.data);
              final sourceIp = datagram.address.address;
              _log('DEBUG', '收到UDP响应 from $sourceIp:${datagram.port}');
              _handleSSDPResponse(response, sourceIp);
            }
          }
        },
        onError: (error) => _log('ERROR', 'Socket错误: $error'),
        onDone: () => _log('INFO', 'Socket关闭'),
      );

      // Send initial search
      await _sendSearchRequests();

      // Retry periodically
      int retryCount = 0;
      _searchTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
        retryCount++;
        if (retryCount <= 5) {
          _log('INFO', '重试SSDP搜索 $retryCount/5');
          await _sendSearchRequests();
        } else {
          timer.cancel();
          _log('INFO', 'SSDP搜索完成，发现 ${_discoveredLocations.length} 个设备位置');
          
          // iOS: SSDP广播可能无效，启动子网扫描
          if (Platform.isIOS && _discoveredLocations.isEmpty) {
            _log('INFO', 'iOS: 未发现设备，启动子网扫描...');
            await _scanSubnet();
          }
        }
      });

    } catch (e) {
      _log('ERROR', 'SSDP发现错误: $e');
    }
  }

  Future<void> _getNetworkInfo() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      // Prefer WiFi interfaces
      for (final interface in interfaces) {
        final name = interface.name.toLowerCase();
        if (name.contains('en0') || name.contains('en1') ||
            name.contains('wlan') || name.contains('wifi')) {
          for (final addr in interface.addresses) {
            if (!addr.isLoopback) {
              _localIp = addr.address;
              final parts = _localIp!.split('.');
              if (parts.length == 4) {
                _subnetBroadcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
              }
              _log('INFO', '使用WiFi接口 ${interface.name}: $_localIp');
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
    // iOS专用策略：必须使用anyIPv4，不能绑定到特定IP
    // iOS对绑定特定IP后发送组播有严格限制
    if (Platform.isIOS) {
      return await _createIOSSocket();
    }

    // Android/其他平台策略
    // Strategy 1: Bind to local IP
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

    // Strategy 3: Bind to SSDP port
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

  /// iOS专用Socket创建 - 使用更宽松的配置
  Future<RawDatagramSocket?> _createIOSSocket() async {
    _log('INFO', 'iOS: 使用专用Socket策略');
    
    // iOS上使用anyIPv4，不加入组播组（iOS组播需要特殊权限）
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;
      socket.readEventsEnabled = true;
      _log('INFO', 'iOS: Socket创建成功，端口 ${socket.port}');
      // iOS上不尝试加入组播，避免触发权限问题
      return socket;
    } catch (e) {
      _log('ERROR', 'iOS: Socket创建失败: $e');
    }
    
    return null;
  }

  void _tryJoinMulticast(RawDatagramSocket socket) {
    try {
      socket.joinMulticast(InternetAddress(multicastAddress));
      _log('INFO', '已加入组播组 $multicastAddress');
    } catch (e) {
      _log('WARN', '加入组播失败(iOS正常): $e');
    }
  }

  Future<void> _sendSearchRequests() async {
    if (_socket == null) return;

    // iOS上跳过组播地址239.255.255.250，它会导致"No route to host"错误
    // 只使用广播地址和子网广播
    final List<InternetAddress> targets;
    if (Platform.isIOS) {
      targets = [
        InternetAddress(broadcastAddress), // 255.255.255.255
        if (_subnetBroadcast != null) InternetAddress(_subnetBroadcast!),
      ];
      _log('INFO', 'iOS: 跳过组播，只使用广播地址');
    } else {
      targets = [
        InternetAddress(multicastAddress),
        InternetAddress(broadcastAddress),
        if (_subnetBroadcast != null) InternetAddress(_subnetBroadcast!),
      ];
    }

    int sentCount = 0;
    int errorCount = 0;
    for (final st in searchTargets) {
      final message = _buildMSearchMessage(st);
      final data = message.codeUnits;

      for (final address in targets) {
        for (var i = 0; i < 2; i++) {
          try {
            _socket!.send(data, address, ssdpPort);
            sentCount++;
          } catch (e) {
            errorCount++;
            if (errorCount <= 3) {
              _log('WARN', '发送失败到 ${address.address}: $e');
            }
          }
          await Future.delayed(const Duration(milliseconds: 30));
        }
      }
    }
    _log('INFO', '发送M-SEARCH到 ${targets.length} 个地址, 共 $sentCount 个包' + 
        (errorCount > 0 ? ', $errorCount 个失败' : ''));
  }


  String _buildMSearchMessage(String searchTarget) {
    return 'M-SEARCH * HTTP/1.1\r\n'
        'HOST: $multicastAddress:$ssdpPort\r\n'
        'MAN: "ssdp:discover"\r\n'
        'MX: 3\r\n'
        'ST: $searchTarget\r\n'
        'USER-AGENT: UPnP/1.0 DLNADOC/1.50\r\n'
        '\r\n';
  }

  /// Handle SSDP response - extract LOCATION header and fetch device description
  /// [sourceIp] is the IP address that sent the response
  final Set<String> _probedIPs = {}; // 已探测过的IP，避免重复
  
  void _handleSSDPResponse(String response, String sourceIp) async {
    // 调试：打印响应前150字符
    final preview = response.length > 150 ? response.substring(0, 150) : response;
    _log('DEBUG', 'SSDP响应内容: ${preview.replaceAll('\r\n', ' | ')}');
    
    // 放宽验证：接受任何包含HTTP响应或NOTIFY的内容
    final upperResponse = response.toUpperCase();
    final isValidResponse = upperResponse.contains('HTTP/') || 
                           upperResponse.contains('NOTIFY') ||
                           upperResponse.contains('LOCATION');
    
    if (!isValidResponse) {
      _log('DEBUG', '响应格式无效，跳过');
      return;
    }

    final headers = _parseHeaders(response);
    final location = headers['location'];

    if (location != null && location.isNotEmpty) {
      // 标准处理：有LOCATION头
      if (_discoveredLocations.contains(location)) {
        return; // Already processed
      }

      _discoveredLocations.add(location);
      _log('INFO', 'SSDP发现设备URL: $location');

      // Fetch device description from the LOCATION URL
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
    } else {
      // iOS特殊处理：没有LOCATION头，直接探测源IP
      if (Platform.isIOS && !_probedIPs.contains(sourceIp)) {
        _probedIPs.add(sourceIp);
        _log('INFO', 'iOS: 响应无LOCATION头，尝试直接探测 $sourceIp');
        // 异步探测，不阻塞
        _probeDeviceByHTTP(sourceIp);
      }
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

  /// Fetch device description from URL
  Future<List<DLNADevice>> _fetchDeviceDescription(String location) async {
    final devices = <DLNADevice>[];

    try {
      final client = HttpClient();
      // iOS需要更短的超时，避免长时间阻塞
      client.connectionTimeout = Duration(seconds: Platform.isIOS ? 3 : 5);
      // iOS上禁用证书验证（本地网络设备通常没有有效证书）
      client.badCertificateCallback = (cert, host, port) => true;

      final uri = Uri.parse(location);
      _log('DEBUG', '正在连接: ${uri.host}:${uri.port}');
      
      final request = await client.getUrl(uri).timeout(
        Duration(seconds: Platform.isIOS ? 5 : 8),
        onTimeout: () {
          throw TimeoutException('连接超时: $location');
        },
      );
      request.headers.set('User-Agent', 'UPnP/1.0 DLNADOC/1.50');
      request.headers.set('Accept', '*/*');
      request.headers.set('Connection', 'close');

      final response = await request.close().timeout(
        Duration(seconds: Platform.isIOS ? 5 : 8),
        onTimeout: () {
          throw TimeoutException('响应超时: $location');
        },
      );

      if (response.statusCode != 200) {
        _log('WARN', 'HTTP ${response.statusCode} from $location');
        client.close();
        return devices;
      }

      final body = await response.transform(utf8.decoder).join();
      client.close();

      final document = XmlDocument.parse(body);
      final deviceElements = document.findAllElements('device');
      if (deviceElements.isEmpty) return devices;

      final rootDevice = deviceElements.first;
      final baseUrl = _getBaseUrl(location);

      // Parse root device and embedded devices
      final allDevices = [rootDevice, ...rootDevice.findAllElements('device')];

      for (final device in allDevices) {
        final parsed = _parseDevice(device, location, baseUrl);
        if (parsed != null) {
          devices.add(parsed);
        }
      }

      _log('INFO', '从 $location 解析到 ${devices.length} 个设备');
    } on TimeoutException catch (e) {
      _log('ERROR', '请求超时: $e');
    } on SocketException catch (e) {
      _log('ERROR', '网络连接失败: ${e.message} (${e.osError?.errorCode})');
      if (Platform.isIOS) {
        _log('WARN', 'iOS提示: 请确认已授予本地网络访问权限');
      }
    } catch (e) {
      _log('ERROR', '解析设备描述失败: $e');
    }

    return devices;
  }

  /// Discover device by direct URL (user provides complete description.xml URL)
  Future<List<DLNADevice>> discoverDeviceByURL(String url) async {
    _log('INFO', '手动发现设备URL: $url');

    if (_discoveredLocations.contains(url)) {
      _log('WARN', '设备已存在: $url');
      return [];
    }

    try {
      final devices = await _fetchDeviceDescription(url);

      for (final device in devices) {
        if (device.canPlayMedia || device.canBrowseMedia) {
          if (!_discoveredLocations.contains(url)) {
            _discoveredLocations.add(url);
            _deviceController.add(device);
            _log('INFO', '手动添加设备成功: ${device.friendlyName}');
          }
        }
      }

      if (devices.isEmpty) {
        _log('WARN', '未能从URL解析到有效设备');
      }

      return devices;
    } catch (e) {
      _log('ERROR', '手动发现失败: $e');
      return [];
    }
  }

  /// Probe device by IP - send unicast M-SEARCH to device's SSDP port
  /// This triggers the device to respond with its LOCATION
  Future<void> probeDeviceByIP(String ip) async {
    _log('INFO', '探测设备IP: $ip');

    try {
      // Create a temporary socket for probing
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;
      socket.readEventsEnabled = true;

      final completer = Completer<void>();
      Timer? timeoutTimer;

      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket.receive();
          if (datagram != null) {
            final response = String.fromCharCodes(datagram.data);
            final sourceIp = datagram.address.address;
            _log('DEBUG', '探测响应 from $sourceIp');
            _handleSSDPResponse(response, sourceIp);
          }
        }
      });

      // Send unicast M-SEARCH to the specific IP
      for (final st in searchTargets) {
        final message = _buildMSearchMessage(st);
        try {
          socket.send(message.codeUnits, InternetAddress(ip), ssdpPort);
          _log('DEBUG', '发送M-SEARCH到 $ip:$ssdpPort (ST: $st)');
        } catch (e) {
          _log('ERROR', '发送到 $ip 失败: $e');
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }

      // Wait for responses
      timeoutTimer = Timer(const Duration(seconds: 5), () {
        if (!completer.isCompleted) {
          completer.complete();
        }
      });

      await completer.future;
      timeoutTimer.cancel();
      socket.close();

      _log('INFO', '探测 $ip 完成');
    } catch (e) {
      _log('ERROR', '探测设备失败: $e');
    }
    
    // iOS专用: 优先使用原生网络API
    if (Platform.isIOS) {
      await _probeDeviceByNative(ip);
    }
  }

  /// iOS专用: 使用原生URLSession探测设备（绕过Dart socket限制）
  Future<void> _probeDeviceByNative(String ip) async {
    _log('INFO', 'iOS: 使用原生网络API探测 $ip');
    
    try {
      // 首先测试TCP连接
      _log('DEBUG', 'iOS Native: 测试TCP连接到 $ip:49152');
      final connected = await IOSNativeNetwork.checkConnection(ip, 49152);
      _log('INFO', 'iOS Native: TCP连接${connected ? "成功" : "失败"}');
      
      if (connected) {
        // TCP连接成功，尝试获取设备描述
        final url = await IOSNativeNetwork.probeDeviceDescription(ip);
        if (url != null) {
          _log('INFO', 'iOS Native: 发现设备 $url');
          // 使用原生网络获取设备描述并解析
          await _fetchDeviceDescriptionNative(url);
        }
      }
    } on NetworkException catch (e) {
      _log('ERROR', 'iOS Native: ${e.code} - ${e.message}');
      // 原生网络失败，回退到Dart HTTP
      _log('INFO', 'iOS: 回退到Dart HTTP探测');
      await _probeDeviceByHTTP(ip);
    } catch (e) {
      _log('ERROR', 'iOS Native: 未知错误 $e');
      await _probeDeviceByHTTP(ip);
    }
  }

  /// 使用原生网络获取设备描述
  Future<void> _fetchDeviceDescriptionNative(String url) async {
    try {
      final response = await IOSNativeNetwork.fetchUrl(url);
      final body = response['body'] as String?;
      
      if (body != null && body.isNotEmpty) {
        _log('INFO', 'iOS Native: 获取到设备描述 (${body.length} bytes)');
        
        // 解析XML
        final document = XmlDocument.parse(body);
        final deviceElements = document.findAllElements('device');
        if (deviceElements.isEmpty) return;
        
        final rootDevice = deviceElements.first;
        final baseUrl = _getBaseUrl(url);
        
        final allDevices = [rootDevice, ...rootDevice.findAllElements('device')];
        
        for (final device in allDevices) {
          final parsed = _parseDevice(device, url, baseUrl);
          if (parsed != null) {
            if (parsed.canPlayMedia || parsed.canBrowseMedia) {
              if (!_discoveredLocations.contains(url)) {
                _discoveredLocations.add(url);
                _log('INFO', 'iOS Native: 添加设备 ${parsed.friendlyName}');
                _deviceController.add(parsed);
              }
            }
          }
        }
      }
    } catch (e) {
      _log('ERROR', 'iOS Native: 解析设备描述失败: $e');
    }
  }


  /// iOS专用: 通过HTTP直接探测设备
  /// 当SSDP无法工作时，直接尝试访问常见的DLNA描述文件端口
  Future<void> _probeDeviceByHTTP(String ip) async {
    _log('INFO', 'iOS: 尝试HTTP直接探测 $ip');
    
    // 常见的DLNA/UPnP端口 - 49152是您设备使用的端口，放在最前面
    const ports = [49152, 49153, 49154, 8060, 1400, 7000, 8008, 8443, 52323];
    // 常见的描述文件路径
    const paths = [
      '/description.xml',
      '/rootDesc.xml', 
      '/DeviceDescription.xml',
      '/upnp/description.xml',
      '/dmr/description.xml',
    ];
    
    int attemptCount = 0;
    int errorCount = 0;
    
    for (final port in ports) {
      for (final path in paths) {
        attemptCount++;
        final url = 'http://$ip:$port$path';
        
        // 对于已知的端口49152，增加详细日志
        final isKnownPort = port == 49152 && path == '/description.xml';
        if (isKnownPort) {
          _log('DEBUG', 'iOS: 测试已知URL: $url');
        }
        
        try {
          final client = HttpClient();
          client.connectionTimeout = const Duration(seconds: 3);
          client.badCertificateCallback = (cert, host, port) => true;
          
          final uri = Uri.parse(url);
          
          if (isKnownPort) {
            _log('DEBUG', 'iOS: 正在连接 $url ...');
          }
          
          final request = await client.getUrl(uri).timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              if (isKnownPort) {
                _log('WARN', 'iOS: getUrl超时 $url');
              }
              throw TimeoutException('getUrl超时');
            },
          );
          
          request.headers.set('User-Agent', 'UPnP/1.0');
          request.headers.set('Connection', 'close');
          
          if (isKnownPort) {
            _log('DEBUG', 'iOS: 等待响应 $url ...');
          }
          
          final response = await request.close().timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              if (isKnownPort) {
                _log('WARN', 'iOS: 响应超时 $url');
              }
              throw TimeoutException('响应超时');
            },
          );
          
          if (isKnownPort) {
            _log('DEBUG', 'iOS: 收到响应 HTTP ${response.statusCode}');
          }
          
          if (response.statusCode == 200) {
            final body = await response.transform(utf8.decoder).join();
            client.close();
            
            _log('INFO', 'iOS: HTTP 200 from $url (${body.length} bytes)');
            
            // 检查是否是有效的UPnP设备描述
            if (body.contains('<device>') || body.contains('<root')) {
              _log('INFO', 'iOS: 在 $url 发现设备!');
              
              // 添加到已发现列表并处理
              if (!_discoveredLocations.contains(url)) {
                _discoveredLocations.add(url);
                final devices = await _fetchDeviceDescription(url);
                for (final device in devices) {
                  if (device.canPlayMedia || device.canBrowseMedia) {
                    _log('INFO', 'iOS: 添加设备 ${device.friendlyName}');
                    _deviceController.add(device);
                  }
                }
              }
              return; // 找到设备后返回
            }
          } else {
            if (isKnownPort) {
              _log('WARN', 'iOS: HTTP ${response.statusCode} from $url');
            }
          }
          client.close();
        } on SocketException catch (e) {
          errorCount++;
          // 对于已知端口或前几个错误，输出详细日志
          if (isKnownPort || errorCount <= 3) {
            _log('ERROR', 'iOS: SocketException $url: ${e.message} (errno=${e.osError?.errorCode})');
          }
        } on TimeoutException catch (e) {
          errorCount++;
          if (isKnownPort) {
            _log('WARN', 'iOS: Timeout $url: $e');
          }
        } catch (e) {
          errorCount++;
          if (isKnownPort || errorCount <= 3) {
            _log('ERROR', 'iOS: Exception $url: $e');
          }
        }
      }
      
      // 每个端口测试完后，如果是已知端口且全部失败，给出提示
      if (ports.indexOf(port) == 0 && errorCount > 0) {
        _log('WARN', 'iOS: 端口$port全部路径测试失败，可能是网络权限问题');
      }
    }
    _log('INFO', 'iOS: HTTP探测 $ip 完成，尝试 $attemptCount 个URL，$errorCount 个失败');
  }

  /// iOS专用：扫描子网内的设备
  /// 由于某些设备不响应SSDP广播，需要主动扫描
  Future<void> _scanSubnet() async {
    if (_localIp == null) {
      _log('WARN', 'iOS: 无法获取本地IP，跳过子网扫描');
      return;
    }

    final parts = _localIp!.split('.');
    if (parts.length != 4) return;

    final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
    _log('INFO', 'iOS: 开始扫描子网 $subnet.x');

    // 常见的DLNA设备IP段（机顶盒、智能电视通常在这些范围）
    // 优先扫描常见的设备IP：100-200 范围
    final priorityRanges = [
      [100, 200], // 常见DHCP分配范围
      [2, 50],    // 静态IP常见范围
      [200, 254], // 其他设备
    ];

    int scannedCount = 0;
    int foundCount = 0;

    for (final range in priorityRanges) {
      for (int i = range[0]; i <= range[1]; i++) {
        final ip = '$subnet.$i';
        
        // 跳过本机IP和已探测的IP
        if (ip == _localIp || _probedIPs.contains(ip)) continue;
        
        // 跳过网关（通常是.1）
        if (i == 1) continue;
        
        scannedCount++;
        
        // 快速TCP连接测试
        final hasDevice = await _quickTcpProbe(ip, 49152);
        if (hasDevice) {
          _log('INFO', 'iOS: 发现潜在设备 $ip');
          foundCount++;
          _probedIPs.add(ip);
          await _probeDeviceByHTTP(ip);
        }
        
        // 每扫描50个IP输出一次进度
        if (scannedCount % 50 == 0) {
          _log('DEBUG', 'iOS: 已扫描 $scannedCount 个IP，发现 $foundCount 个潜在设备');
        }
        
        // 如果已经找到足够多的设备，可以提前结束
        if (foundCount >= 5) {
          _log('INFO', 'iOS: 已找到 $foundCount 个设备，停止扫描');
          return;
        }
      }
    }

    _log('INFO', 'iOS: 子网扫描完成，共扫描 $scannedCount 个IP，发现 $foundCount 个潜在设备');
  }

  /// 快速TCP端口探测
  Future<bool> _quickTcpProbe(String ip, int port) async {
    try {
      final socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(milliseconds: 200), // 非常短的超时
      );
      socket.destroy();
      return true;
    } catch (e) {
      return false;
    }
  }

  DLNADevice? _parseDevice(XmlElement device, String location, String baseUrl) {
    final deviceType = device.findElements('deviceType').firstOrNull?.innerText ?? '';

    // Accept MediaRenderer and MediaServer devices
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

    // Need at least one usable service
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
