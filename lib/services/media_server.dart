import 'dart:io';
import 'dart:async';

import '../models/media_item.dart';

class MediaServer {
  HttpServer? _server;
  String? _currentFilePath;
  int _port = 0;

  String? get serverAddress =>
      _server != null ? 'http://${_localIp ?? 'localhost'}:$_port' : null;

  String? _localIp;

  Future<String?> startServer(String filePath) async {
    await stopServer();
    _currentFilePath = filePath;

    try {
      _localIp = await _getLocalIp();
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      _port = _server!.port;

      _server!.listen(_handleRequest);

      final fileName = filePath.split(Platform.pathSeparator).last;
      final encodedName = Uri.encodeComponent(fileName);
      return 'http://$_localIp:$_port/media/$encodedName';
    } catch (e) {
      print('Media server error: $e');
      return null;
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (_currentFilePath == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final file = File(_currentFilePath!);
    if (!await file.exists()) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    try {
      final fileLength = await file.length();
      final ext = _currentFilePath!.split('.').last;
      final mediaType = MediaItem.getTypeFromExtension(ext);
      final mimeType = MediaItem.getMimeType(ext, mediaType);

      final rangeHeader = request.headers.value('range');

      if (rangeHeader != null) {
        // Handle range request for seeking support
        final rangeMatch = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(rangeHeader);
        if (rangeMatch != null) {
          final startStr = rangeMatch.group(1);
          final endStr = rangeMatch.group(2);

          final start = startStr?.isNotEmpty == true ? int.parse(startStr!) : 0;
          final end = endStr?.isNotEmpty == true
              ? int.parse(endStr!)
              : fileLength - 1;

          final contentLength = end - start + 1;

          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set('Content-Type', mimeType);
          request.response.headers.set('Content-Length', contentLength);
          request.response.headers
              .set('Content-Range', 'bytes $start-$end/$fileLength');
          request.response.headers.set('Accept-Ranges', 'bytes');

          final stream = file.openRead(start, end + 1);
          await request.response.addStream(stream);
        }
      } else {
        // Full file request
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.set('Content-Type', mimeType);
        request.response.headers.set('Content-Length', fileLength);
        request.response.headers.set('Accept-Ranges', 'bytes');

        await request.response.addStream(file.openRead());
      }
    } catch (e) {
      print('Error serving file: $e');
      request.response.statusCode = HttpStatus.internalServerError;
    }

    await request.response.close();
  }

  Future<String?> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback && addr.address.startsWith('192.168')) {
            return addr.address;
          }
        }
      }

      // Fallback to first non-loopback address
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      print('Error getting local IP: $e');
    }
    return null;
  }

  Future<void> stopServer() async {
    await _server?.close(force: true);
    _server = null;
    _currentFilePath = null;
  }

  void dispose() {
    stopServer();
  }
}
