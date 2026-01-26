class DLNADevice {
  final String usn;
  final String friendlyName;
  final String location;
  final String deviceType;
  final String? manufacturer;
  final String? modelName;
  final String? avTransportUrl;
  final String? renderingControlUrl;

  DLNADevice({
    required this.usn,
    required this.friendlyName,
    required this.location,
    required this.deviceType,
    this.manufacturer,
    this.modelName,
    this.avTransportUrl,
    this.renderingControlUrl,
  });

  bool get canPlayMedia => avTransportUrl != null;

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
