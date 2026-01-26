import 'dart:async';
import 'dart:io';

import 'package:xml/xml.dart';
import 'package:http/http.dart' as http;
import '../models/dlna_device.dart';

class SSDPService {
  static const String ssdpAddress = '239.255.255.250';
  static const int ssdpPort = 1900;

  static const List<String> searchTargets = [
    'ssdp:all',
    'urn:schemas-upnp-org:device:MediaRenderer:1',
    'urn:schemas-upnp-org:device:MediaServer:1',
    'urn:schemas-upnp-org:service:AVTransport:1',
    'urn:schemas-upnp-org:service:ContentDirectory:1',
    'urn:schemas-upnp-org:service:RenderingControl:1',
    'upnp:rootdevice',
  ];

  RawDatagramSocket? _socket;
  final StreamController<DLNADevice> _deviceController =
      StreamController<DLNADevice>.broadcast();

  Stream<DLNADevice> get deviceStream => _deviceController.stream;

  final Set<String> _discoveredLocations = {};
  Timer? _searchTimer;

  Future<void> startDiscovery() async {
    await stopDiscovery();
    _discoveredLocations.clear();

    try {
      // Get local IP address for iOS compatibility
      final localIp = await _getLocalIpAddress();
      print('SSDP: Local IP address: $localIp');

      // Try to bind to local IP first (better for iOS), fallback to anyIPv4
      try {
        if (localIp != null) {
          _socket = await RawDatagramSocket.bind(
            InternetAddress(localIp),
            0,
            reuseAddress: true,
            reusePort: true,
          );
          print('SSDP: Bound to local IP: $localIp');
        } else {
          throw Exception('No local IP');
        }
      } catch (e) {
        print('SSDP: Failed to bind to local IP, trying anyIPv4: $e');
        _socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          0,
          reuseAddress: true,
          reusePort: true,
        );
      }

      _socket!.broadcastEnabled = true;
      _socket!.multicastLoopback = true;
      _socket!.readEventsEnabled = true;

      // Try to join multicast group (may fail on iOS)
      try {
        _socket!.joinMulticast(InternetAddress(ssdpAddress));
        print('SSDP: Joined multicast group');
      } catch (e) {
        print('SSDP: Could not join multicast group (normal on iOS): $e');
      }

      // Also try with network interface (helps on some iOS devices)
      try {
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
          includeLoopback: false,
        );
        for (final interface in interfaces) {
          try {
            _socket!.joinMulticast(InternetAddress(ssdpAddress), interface);
            print('SSDP: Joined multicast on interface: ${interface.name}');
          } catch (e) {
            // Ignore interface-specific errors
          }
        }
      } catch (e) {
        print('SSDP: Could not enumerate interfaces: $e');
      }

      _socket!.listen(
        (event) {
          if (event == RawSocketEvent.read) {
            final datagram = _socket!.receive();
            if (datagram != null) {
              _handleResponse(String.fromCharCodes(datagram.data));
            }
          }
        },
        onError: (error) {
          print('SSDP: Socket error: $error');
        },
      );

      // Send multiple rounds of search requests
      await _sendSearchRequests();

      // Schedule additional search rounds for better iOS discovery
      _searchTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
        if (timer.tick <= 3) {
          await _sendSearchRequests();
        } else {
          timer.cancel();
        }
      });
    } catch (e) {
      print('SSDP: Discovery error: $e');
    }
  }

  Future<String?> _getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      for (final interface in interfaces) {
        // Prefer Wi-Fi interfaces
        final lowerName = interface.name.toLowerCase();
        if (lowerName.contains('wlan') ||
            lowerName.contains('wifi') ||
            lowerName.contains('en0') ||
            lowerName.contains('en1')) {
          for (final addr in interface.addresses) {
            if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
              return addr.address;
            }
          }
        }
      }

      // Fallback: return first non-loopback IPv4
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      print('SSDP: Failed to get local IP: $e');
    }
    return null;
  }

  Future<void> _sendSearchRequests() async {
    if (_socket == null) return;

    final address = InternetAddress(ssdpAddress);

    for (final target in searchTargets) {
      final searchMessage = 'M-SEARCH * HTTP/1.1\r\n'
          'HOST: $ssdpAddress:$ssdpPort\r\n'
          'MAN: "ssdp:discover"\r\n'
          'MX: 5\r\n'
          'ST: $target\r\n'
          'USER-AGENT: iOS/DLNA-Cast DLNADOC/1.50 UPnP/1.0\r\n'
          '\r\n';
      final data = searchMessage.codeUnits;

      // Send each request multiple times with small delay
      for (var i = 0; i < 3; i++) {
        try {
          _socket?.send(data, address, ssdpPort);
        } catch (e) {
          print('SSDP: Send error: $e');
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
    print('SSDP: Search requests sent for ${searchTargets.length} targets');
  }

  void _handleResponse(String response) async {
    // Accept both M-SEARCH responses and NOTIFY messages
    if (!response.contains('HTTP/1.1 200') &&
        !response.toUpperCase().contains('NOTIFY')) {
      return;
    }

    final headers = _parseHeaders(response);
    final location = headers['location'];

    if (location == null || location.isEmpty) return;
    if (_discoveredLocations.contains(location)) return;

    _discoveredLocations.add(location);
    print('SSDP: Found device at: $location');

    try {
      final devices = await _fetchDeviceDescriptions(location);
      for (final device in devices) {
        if (device.canPlayMedia || device.canBrowseMedia) {
          print('SSDP: Added device: ${device.friendlyName} (${device.typeLabel})');
          _deviceController.add(device);
        }
      }
    } catch (e) {
      print('SSDP: Failed to fetch device description: $e');
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

  Future<List<DLNADevice>> _fetchDeviceDescriptions(String location) async {
    final devices = <DLNADevice>[];

    try {
      final response = await http.get(
        Uri.parse(location),
        headers: {
          'User-Agent': 'iOS/DLNA-Cast DLNADOC/1.50 UPnP/1.0',
          'Accept': '*/*',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        print('SSDP: HTTP ${response.statusCode} for $location');
        return devices;
      }

      final document = XmlDocument.parse(response.body);
      final deviceElements = document.findAllElements('device');
      if (deviceElements.isEmpty) return devices;

      final rootDevice = deviceElements.first;
      final baseUrl = _getBaseUrl(location);

      // Check main device and embedded devices
      final allDevices = [rootDevice, ...rootDevice.findAllElements('device')];

      for (final device in allDevices) {
        final parsedDevice = _parseDevice(device, location, baseUrl);
        if (parsedDevice != null) {
          devices.add(parsedDevice);
        }
      }
    } catch (e) {
      print('SSDP: Error parsing device description: $e');
    }

    return devices;
  }

  DLNADevice? _parseDevice(XmlElement device, String location, String baseUrl) {
    final deviceType =
        device.findElements('deviceType').firstOrNull?.innerText ?? '';

    // Only process MediaRenderer and MediaServer devices
    if (!deviceType.contains('MediaRenderer') &&
        !deviceType.contains('MediaServer')) {
      return null;
    }

    String? avTransportUrl;
    String? renderingControlUrl;
    String? contentDirectoryUrl;

    // Parse services
    final serviceList = device.findElements('serviceList').firstOrNull;
    if (serviceList != null) {
      for (final service in serviceList.findElements('service')) {
        final serviceType =
            service.findElements('serviceType').firstOrNull?.innerText ?? '';
        final controlUrl =
            service.findElements('controlURL').firstOrNull?.innerText ?? '';

        if (serviceType.contains('AVTransport')) {
          avTransportUrl = _resolveUrl(baseUrl, controlUrl);
        } else if (serviceType.contains('RenderingControl')) {
          renderingControlUrl = _resolveUrl(baseUrl, controlUrl);
        } else if (serviceType.contains('ContentDirectory')) {
          contentDirectoryUrl = _resolveUrl(baseUrl, controlUrl);
        }
      }
    }

    // Must have at least one useful service
    if (avTransportUrl == null && contentDirectoryUrl == null) {
      return null;
    }

    final friendlyName =
        device.findElements('friendlyName').firstOrNull?.innerText ??
            'Unknown Device';
    final manufacturer =
        device.findElements('manufacturer').firstOrNull?.innerText;
    final modelName =
        device.findElements('modelName').firstOrNull?.innerText;
    final udn = device.findElements('UDN').firstOrNull?.innerText ?? location;

    // Parse DLNA version from X_DLNADOC element
    String? dlnaVersion;
    String? dlnaCapabilities;

    // Try different ways to find DLNA doc (handles namespaces)
    final dlnaDocElements = device.findAllElements('X_DLNADOC');
    if (dlnaDocElements.isNotEmpty) {
      dlnaVersion = dlnaDocElements.first.innerText;
    }

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
  }
}
