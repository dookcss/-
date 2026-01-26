import 'dart:io';
import 'package:network_info_plus/network_info_plus.dart';

class LocalNetworkPermission {
  static final NetworkInfo _networkInfo = NetworkInfo();

  /// Triggers the iOS local network permission dialog
  /// On iOS 14+, accessing local network info will prompt for permission
  static Future<bool> requestPermission() async {
    if (!Platform.isIOS) return true;

    try {
      // Method 1: Try to get WiFi name (triggers permission on iOS)
      final wifiName = await _networkInfo.getWifiName();
      print('LocalNetworkPermission: WiFi name: $wifiName');

      // Method 2: Try to get WiFi BSSID
      final wifiBSSID = await _networkInfo.getWifiBSSID();
      print('LocalNetworkPermission: WiFi BSSID: $wifiBSSID');

      // Method 3: Try to get WiFi IP
      final wifiIP = await _networkInfo.getWifiIP();
      print('LocalNetworkPermission: WiFi IP: $wifiIP');

      // Method 4: Send a UDP packet to trigger network access
      await _triggerNetworkAccess();

      return true;
    } catch (e) {
      print('LocalNetworkPermission: Error requesting permission: $e');
      return false;
    }
  }

  /// Send a simple UDP broadcast to trigger local network permission
  static Future<void> _triggerNetworkAccess() async {
    try {
      // Create a UDP socket and send a broadcast
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );

      socket.broadcastEnabled = true;

      // Send a simple SSDP M-SEARCH to trigger network dialog
      const message = 'M-SEARCH * HTTP/1.1\r\n'
          'HOST: 239.255.255.250:1900\r\n'
          'MAN: "ssdp:discover"\r\n'
          'MX: 1\r\n'
          'ST: ssdp:all\r\n'
          '\r\n';

      socket.send(
        message.codeUnits,
        InternetAddress('239.255.255.250'),
        1900,
      );

      // Also try broadcast address
      socket.send(
        message.codeUnits,
        InternetAddress('255.255.255.255'),
        1900,
      );

      // Wait a moment for the permission dialog to potentially appear
      await Future.delayed(const Duration(milliseconds: 500));

      socket.close();
      print('LocalNetworkPermission: UDP trigger sent');
    } catch (e) {
      print('LocalNetworkPermission: UDP trigger error: $e');
    }
  }

  /// Get current WiFi IP address
  static Future<String?> getWifiIP() async {
    try {
      return await _networkInfo.getWifiIP();
    } catch (e) {
      return null;
    }
  }

  /// Check if we're connected to WiFi
  static Future<bool> isConnectedToWifi() async {
    try {
      final ip = await _networkInfo.getWifiIP();
      return ip != null && ip.isNotEmpty;
    } catch (e) {
      return false;
    }
  }
}
