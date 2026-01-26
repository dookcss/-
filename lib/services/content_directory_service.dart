import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import '../models/dlna_device.dart';
import '../models/didl_content.dart';

class ContentDirectoryService {
  static const String contentDirectoryService =
      'urn:schemas-upnp-org:service:ContentDirectory:1';

  Future<BrowseResult?> browse(
    DLNADevice device, {
    String objectId = '0',
    int startIndex = 0,
    int requestCount = 50,
    String browseFlag = 'BrowseDirectChildren',
  }) async {
    if (device.contentDirectoryUrl == null) return null;

    final soapBody = '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:Browse xmlns:u="$contentDirectoryService">
      <ObjectID>$objectId</ObjectID>
      <BrowseFlag>$browseFlag</BrowseFlag>
      <Filter>*</Filter>
      <StartingIndex>$startIndex</StartingIndex>
      <RequestedCount>$requestCount</RequestedCount>
      <SortCriteria></SortCriteria>
    </u:Browse>
  </s:Body>
</s:Envelope>''';

    try {
      final response = await http.post(
        Uri.parse(device.contentDirectoryUrl!),
        headers: {
          'Content-Type': 'text/xml; charset=utf-8',
          'SOAPACTION': '"$contentDirectoryService#Browse"',
        },
        body: soapBody,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        print('Browse failed with status: ${response.statusCode}');
        return null;
      }

      return _parseBrowseResponse(response.body);
    } catch (e) {
      print('Browse error: $e');
      return null;
    }
  }

  BrowseResult? _parseBrowseResponse(String responseBody) {
    try {
      final document = XmlDocument.parse(responseBody);

      // Get Result element which contains DIDL-Lite XML
      final resultElement = document.findAllElements('Result').firstOrNull;
      final totalMatchesStr =
          document.findAllElements('TotalMatches').firstOrNull?.innerText ?? '0';
      final numberReturnedStr =
          document.findAllElements('NumberReturned').firstOrNull?.innerText ?? '0';

      final totalMatches = int.tryParse(totalMatchesStr) ?? 0;
      final numberReturned = int.tryParse(numberReturnedStr) ?? 0;

      if (resultElement == null) {
        return BrowseResult(
          items: [],
          totalMatches: totalMatches,
          numberReturned: numberReturned,
        );
      }

      // Parse DIDL-Lite content
      final didlXml = resultElement.innerText;
      final items = _parseDIDL(didlXml);

      return BrowseResult(
        items: items,
        totalMatches: totalMatches,
        numberReturned: numberReturned,
      );
    } catch (e) {
      print('Parse browse response error: $e');
      return null;
    }
  }

  List<DIDLContent> _parseDIDL(String didlXml) {
    final items = <DIDLContent>[];

    try {
      final document = XmlDocument.parse(didlXml);

      // Parse containers (folders)
      for (final container in document.findAllElements('container')) {
        items.add(_parseContainer(container));
      }

      // Parse items (media files)
      for (final item in document.findAllElements('item')) {
        items.add(_parseItem(item));
      }
    } catch (e) {
      print('Parse DIDL error: $e');
    }

    return items;
  }

  DIDLContent _parseContainer(XmlElement element) {
    final id = element.getAttribute('id') ?? '';
    final parentId = element.getAttribute('parentID') ?? '0';
    final childCountStr = element.getAttribute('childCount') ?? '0';
    final childCount = int.tryParse(childCountStr) ?? 0;

    final title = element.findAllElements('title').firstOrNull?.innerText ?? 'Unknown';
    final albumArtUrl = element.findAllElements('albumArtURI').firstOrNull?.innerText;

    return DIDLContent(
      id: id,
      parentId: parentId,
      title: title,
      type: ContentType.container,
      albumArtUrl: albumArtUrl,
      childCount: childCount,
    );
  }

  DIDLContent _parseItem(XmlElement element) {
    final id = element.getAttribute('id') ?? '';
    final parentId = element.getAttribute('parentID') ?? '0';

    final title = element.findAllElements('title').firstOrNull?.innerText ?? 'Unknown';
    final upnpClass = element.findAllElements('class').firstOrNull?.innerText ?? '';
    final albumArtUrl = element.findAllElements('albumArtURI').firstOrNull?.innerText;
    final artist = element.findAllElements('artist').firstOrNull?.innerText ??
        element.findAllElements('creator').firstOrNull?.innerText;
    final album = element.findAllElements('album').firstOrNull?.innerText;

    // Parse res element for URL and metadata
    String? url;
    String? mimeType;
    int? duration;
    int? size;
    String? resolution;

    final resElement = element.findAllElements('res').firstOrNull;
    if (resElement != null) {
      url = resElement.innerText;
      mimeType = resElement.getAttribute('protocolInfo')?.split(':').elementAtOrNull(2);
      resolution = resElement.getAttribute('resolution');

      final sizeStr = resElement.getAttribute('size');
      if (sizeStr != null) {
        size = int.tryParse(sizeStr);
      }

      final durationStr = resElement.getAttribute('duration');
      if (durationStr != null) {
        duration = _parseDuration(durationStr);
      }
    }

    // Determine content type from upnpClass
    final type = _getContentType(upnpClass, mimeType);

    return DIDLContent(
      id: id,
      parentId: parentId,
      title: title,
      type: type,
      url: url,
      mimeType: mimeType,
      albumArtUrl: albumArtUrl,
      artist: artist,
      album: album,
      duration: duration,
      size: size,
      resolution: resolution,
    );
  }

  ContentType _getContentType(String upnpClass, String? mimeType) {
    final lowerClass = upnpClass.toLowerCase();

    if (lowerClass.contains('video')) return ContentType.video;
    if (lowerClass.contains('audio') || lowerClass.contains('music')) {
      return ContentType.audio;
    }
    if (lowerClass.contains('image') || lowerClass.contains('photo')) {
      return ContentType.image;
    }

    // Fallback to mime type
    if (mimeType != null) {
      if (mimeType.startsWith('video')) return ContentType.video;
      if (mimeType.startsWith('audio')) return ContentType.audio;
      if (mimeType.startsWith('image')) return ContentType.image;
    }

    return ContentType.unknown;
  }

  int? _parseDuration(String durationStr) {
    try {
      // Format: H+:MM:SS.F+ or H+:MM:SS
      final parts = durationStr.split(':');
      if (parts.length >= 3) {
        final hours = int.parse(parts[0]);
        final minutes = int.parse(parts[1]);
        final secondsPart = parts[2].split('.')[0];
        final seconds = int.parse(secondsPart);
        return hours * 3600 + minutes * 60 + seconds;
      }
    } catch (e) {
      // ignore parse errors
    }
    return null;
  }

  Future<DIDLContent?> getMetadata(DLNADevice device, String objectId) async {
    final result = await browse(
      device,
      objectId: objectId,
      browseFlag: 'BrowseMetadata',
    );

    return result?.items.firstOrNull;
  }
}
