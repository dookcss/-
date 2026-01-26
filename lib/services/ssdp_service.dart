import 'dart:async';
import 'dart:io';

import 'package:xml/xml.dart';
import 'package:http/http.dart' as http;
import '../models/dlna_device.dart';

class SSDPService {
  static const String ssdpAddress = '239.255.255.250';
  static const int ssdpPort = 1900;

  // Search for all UPnP devices, then filter by capabilities
  static const List<String> searchTargets = [
    'ssdp:all',
    'urn:schemas-upnp-org:device:MediaRenderer:1',
    'urn:schemas-upnp-org:service:AVTransport:1',
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
        await Future.delayed(const Duration(milliseconds: 300));
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
      final device = await _fetchDeviceDescription(location);
      // Only add devices that can play media (have AVTransport service)
      if (device != null && device.canPlayMedia) {
        _deviceController.add(device);
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

  Future<DLNADevice?> _fetchDeviceDescription(String location) async {
    try {
      final response = await http.get(Uri.parse(location)).timeout(
            const Duration(seconds: 5),
          );

      if (response.statusCode != 200) return null;

      final document = XmlDocument.parse(response.body);
      final rootDevice = document.findAllElements('device').first;

      // Check main device and embedded devices
      final allDevices = [rootDevice, ...rootDevice.findAllElements('device')];

      for (final device in allDevices) {
        final deviceType =
            device.findElements('deviceType').firstOrNull?.innerText ?? '';

        String? avTransportUrl;
        String? renderingControlUrl;

        final baseUrl = _getBaseUrl(location);

        // Check services in this device
        final serviceList = device.findElements('serviceList').firstOrNull;
        if (serviceList != null) {
          for (final service in serviceList.findElements('service')) {
            final serviceType =
                service.findElements('serviceType').firstOrNull?.innerText ??
                    '';
            final controlUrl =
                service.findElements('controlURL').firstOrNull?.innerText ?? '';

            if (serviceType.contains('AVTransport')) {
              avTransportUrl = _resolveUrl(baseUrl, controlUrl);
            } else if (serviceType.contains('RenderingControl')) {
              renderingControlUrl = _resolveUrl(baseUrl, controlUrl);
            }
          }
        }

        // If this device has AVTransport, it's a renderer we can use
        if (avTransportUrl != null) {
          final friendlyName =
              device.findElements('friendlyName').firstOrNull?.innerText ??
                  'Unknown Device';
          final manufacturer =
              device.findElements('manufacturer').firstOrNull?.innerText;
          final modelName =
              device.findElements('modelName').firstOrNull?.innerText;
          final udn =
              device.findElements('UDN').firstOrNull?.innerText ?? location;

          return DLNADevice(
            usn: udn,
            friendlyName: friendlyName,
            location: location,
            deviceType: deviceType,
            manufacturer: manufacturer,
            modelName: modelName,
            avTransportUrl: avTransportUrl,
            renderingControlUrl: renderingControlUrl,
          );
        }
      }

      return null;
    } catch (e) {
      print('Error parsing device description: $e');
      return null;
    }
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
