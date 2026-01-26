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
    'upnp:rootdevice',
  ];

  RawDatagramSocket? _socket;
  final StreamController<DLNADevice> _deviceController =
      StreamController<DLNADevice>.broadcast();

  Stream<DLNADevice> get deviceStream => _deviceController.stream;

  final Set<String> _discoveredLocations = {};

  Future<void> startDiscovery() async {
    await stopDiscovery();
    _discoveredLocations.clear();

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );

      _socket!.broadcastEnabled = true;
      _socket!.multicastLoopback = true;

      try {
        _socket!.joinMulticast(InternetAddress(ssdpAddress));
      } catch (e) {
        // Multicast join may fail on some platforms
      }

      _socket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _socket!.receive();
          if (datagram != null) {
            _handleResponse(String.fromCharCodes(datagram.data));
          }
        }
      });

      await _sendSearchRequests();
    } catch (e) {
      print('SSDP discovery error: $e');
    }
  }

  Future<void> _sendSearchRequests() async {
    final address = InternetAddress(ssdpAddress);

    for (final target in searchTargets) {
      final searchMessage = '''M-SEARCH * HTTP/1.1\r
HOST: $ssdpAddress:$ssdpPort\r
MAN: "ssdp:discover"\r
MX: 3\r
ST: $target\r
\r
''';
      final data = searchMessage.codeUnits;

      for (var i = 0; i < 2; i++) {
        _socket?.send(data, address, ssdpPort);
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
  }

  void _handleResponse(String response) async {
    if (!response.contains('HTTP/1.1 200 OK') &&
        !response.toLowerCase().contains('notify')) {
      return;
    }

    final headers = _parseHeaders(response);
    final location = headers['location'];

    if (location == null) return;
    if (_discoveredLocations.contains(location)) return;

    _discoveredLocations.add(location);

    try {
      final devices = await _fetchDeviceDescriptions(location);
      for (final device in devices) {
        if (device.canPlayMedia || device.canBrowseMedia) {
          _deviceController.add(device);
        }
      }
    } catch (e) {
      print('Failed to fetch device description: $e');
    }
  }

  Map<String, String> _parseHeaders(String response) {
    final headers = <String, String>{};
    final lines = response.split('\r\n');

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
      final response = await http.get(Uri.parse(location)).timeout(
            const Duration(seconds: 5),
          );

      if (response.statusCode != 200) return devices;

      final document = XmlDocument.parse(response.body);
      final rootDevice = document.findAllElements('device').first;
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
      print('Error parsing device description: $e');
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
    _socket?.close();
    _socket = null;
  }

  void dispose() {
    stopDiscovery();
    _deviceController.close();
  }
}
