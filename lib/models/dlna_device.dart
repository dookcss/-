enum DLNADeviceType { renderer, server, unknown }

class DLNADevice {
  final String usn;
  final String friendlyName;
  final String location;
  final String deviceType;
  final String? manufacturer;
  final String? modelName;
  final String? dlnaVersion;
  final String? dlnaCapabilities;
  final String? avTransportUrl;
  final String? renderingControlUrl;
  final String? contentDirectoryUrl;

  DLNADevice({
    required this.usn,
    required this.friendlyName,
    required this.location,
    required this.deviceType,
    this.manufacturer,
    this.modelName,
    this.dlnaVersion,
    this.dlnaCapabilities,
    this.avTransportUrl,
    this.renderingControlUrl,
    this.contentDirectoryUrl,
  });

  bool get canPlayMedia => avTransportUrl != null;
  bool get canBrowseMedia => contentDirectoryUrl != null;

  DLNADeviceType get type {
    if (deviceType.contains('MediaRenderer')) return DLNADeviceType.renderer;
    if (deviceType.contains('MediaServer')) return DLNADeviceType.server;
    return DLNADeviceType.unknown;
  }

  String get typeLabel {
    switch (type) {
      case DLNADeviceType.renderer:
        return 'DMR';
      case DLNADeviceType.server:
        return 'DMS';
      case DLNADeviceType.unknown:
        return 'Unknown';
    }
  }

  String get versionDisplay {
    if (dlnaVersion != null && dlnaVersion!.isNotEmpty) {
      return dlnaVersion!;
    }
    return typeLabel;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DLNADevice &&
          runtimeType == other.runtimeType &&
          usn == other.usn;

  @override
  int get hashCode => usn.hashCode;

  @override
  String toString() => 'DLNADevice(name: $friendlyName, type: $deviceType)';
}
