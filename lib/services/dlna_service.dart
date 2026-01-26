import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import '../models/dlna_device.dart';

class DLNAService {
  static const String avTransportService =
      'urn:schemas-upnp-org:service:AVTransport:1';
  static const String renderingControlService =
      'urn:schemas-upnp-org:service:RenderingControl:1';

  Future<bool> setMediaUrl(
    DLNADevice device,
    String mediaUrl,
    String title, {
    String mimeType = 'video/mp4',
  }) async {
    if (device.avTransportUrl == null) return false;

    final metadata = _buildDIDLMetadata(mediaUrl, title, mimeType);

    final soapBody = '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:SetAVTransportURI xmlns:u="$avTransportService">
      <InstanceID>0</InstanceID>
      <CurrentURI><![CDATA[$mediaUrl]]></CurrentURI>
      <CurrentURIMetaData><![CDATA[$metadata]]></CurrentURIMetaData>
    </u:SetAVTransportURI>
  </s:Body>
</s:Envelope>''';

    return await _sendSoapRequest(
      device.avTransportUrl!,
      '$avTransportService#SetAVTransportURI',
      soapBody,
    );
  }

  Future<bool> play(DLNADevice device) async {
    if (device.avTransportUrl == null) return false;

    final soapBody = '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:Play xmlns:u="$avTransportService">
      <InstanceID>0</InstanceID>
      <Speed>1</Speed>
    </u:Play>
  </s:Body>
</s:Envelope>''';

    return await _sendSoapRequest(
      device.avTransportUrl!,
      '$avTransportService#Play',
      soapBody,
    );
  }

  Future<bool> pause(DLNADevice device) async {
    if (device.avTransportUrl == null) return false;

    final soapBody = '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:Pause xmlns:u="$avTransportService">
      <InstanceID>0</InstanceID>
    </u:Pause>
  </s:Body>
</s:Envelope>''';

    return await _sendSoapRequest(
      device.avTransportUrl!,
      '$avTransportService#Pause',
      soapBody,
    );
  }

  Future<bool> stop(DLNADevice device) async {
    if (device.avTransportUrl == null) return false;

    final soapBody = '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:Stop xmlns:u="$avTransportService">
      <InstanceID>0</InstanceID>
    </u:Stop>
  </s:Body>
</s:Envelope>''';

    return await _sendSoapRequest(
      device.avTransportUrl!,
      '$avTransportService#Stop',
      soapBody,
    );
  }

  Future<bool> seek(DLNADevice device, Duration position) async {
    if (device.avTransportUrl == null) return false;

    final target = _formatDuration(position);

    final soapBody = '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:Seek xmlns:u="$avTransportService">
      <InstanceID>0</InstanceID>
      <Unit>REL_TIME</Unit>
      <Target>$target</Target>
    </u:Seek>
  </s:Body>
</s:Envelope>''';

    return await _sendSoapRequest(
      device.avTransportUrl!,
      '$avTransportService#Seek',
      soapBody,
    );
  }

  Future<bool> setVolume(DLNADevice device, int volume) async {
    if (device.renderingControlUrl == null) return false;

    final clampedVolume = volume.clamp(0, 100);

    final soapBody = '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:SetVolume xmlns:u="$renderingControlService">
      <InstanceID>0</InstanceID>
      <Channel>Master</Channel>
      <DesiredVolume>$clampedVolume</DesiredVolume>
    </u:SetVolume>
  </s:Body>
</s:Envelope>''';

    return await _sendSoapRequest(
      device.renderingControlUrl!,
      '$renderingControlService#SetVolume',
      soapBody,
    );
  }

  Future<Map<String, dynamic>?> getPositionInfo(DLNADevice device) async {
    if (device.avTransportUrl == null) return null;

    final soapBody = '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:GetPositionInfo xmlns:u="$avTransportService">
      <InstanceID>0</InstanceID>
    </u:GetPositionInfo>
  </s:Body>
</s:Envelope>''';

    try {
      final response = await http.post(
        Uri.parse(device.avTransportUrl!),
        headers: {
          'Content-Type': 'text/xml; charset=utf-8',
          'SOAPACTION': '"$avTransportService#GetPositionInfo"',
        },
        body: soapBody,
      );

      if (response.statusCode == 200) {
        final document = XmlDocument.parse(response.body);
        final trackDuration = document
            .findAllElements('TrackDuration')
            .firstOrNull
            ?.innerText;
        final relTime =
            document.findAllElements('RelTime').firstOrNull?.innerText;

        return {
          'duration': _parseDuration(trackDuration ?? '0:00:00'),
          'position': _parseDuration(relTime ?? '0:00:00'),
        };
      }
    } catch (e) {
      print('GetPositionInfo error: $e');
    }
    return null;
  }

  Future<bool> _sendSoapRequest(
    String url,
    String soapAction,
    String body,
  ) async {
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'text/xml; charset=utf-8',
          'SOAPACTION': '"$soapAction"',
        },
        body: body,
      );

      return response.statusCode == 200;
    } catch (e) {
      print('SOAP request error: $e');
      return false;
    }
  }

  String _buildDIDLMetadata(String url, String title, String mimeType) {
    final upnpClass = mimeType.startsWith('video')
        ? 'object.item.videoItem'
        : mimeType.startsWith('audio')
            ? 'object.item.audioItem'
            : 'object.item.imageItem';

    return '''&lt;DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/"&gt;
  &lt;item id="0" parentID="-1" restricted="1"&gt;
    &lt;dc:title&gt;$title&lt;/dc:title&gt;
    &lt;upnp:class&gt;$upnpClass&lt;/upnp:class&gt;
    &lt;res protocolInfo="http-get:*:$mimeType:*"&gt;$url&lt;/res&gt;
  &lt;/item&gt;
&lt;/DIDL-Lite&gt;''';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  Duration _parseDuration(String duration) {
    try {
      final parts = duration.split(':');
      if (parts.length == 3) {
        final hours = int.parse(parts[0]);
        final minutes = int.parse(parts[1]);
        final secondsParts = parts[2].split('.');
        final seconds = int.parse(secondsParts[0]);
        return Duration(hours: hours, minutes: minutes, seconds: seconds);
      }
    } catch (e) {
      // ignore parsing errors
    }
    return Duration.zero;
  }
}
