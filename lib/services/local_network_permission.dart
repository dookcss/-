import 'dart:io';
import 'dart:async';
import 'package:network_info_plus/network_info_plus.dart';

/// 网络诊断结果
class NetworkDiagnostics {
  final bool canResolveGateway;
  final bool canPingGateway;
  final bool canBindUDP;
  final bool canSendBroadcast;
  final String? gatewayIP;
  final String? localIP;
  final List<String> errors;
  final List<String> successes;

  NetworkDiagnostics({
    required this.canResolveGateway,
    required this.canPingGateway,
    required this.canBindUDP,
    required this.canSendBroadcast,
    this.gatewayIP,
    this.localIP,
    required this.errors,
    required this.successes,
  });

  bool get isHealthy => canBindUDP && canSendBroadcast;

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('=== 网络诊断结果 ===');
    buffer.writeln('本地IP: ${localIP ?? "未知"}');
    buffer.writeln('网关IP: ${gatewayIP ?? "未知"}');
    buffer.writeln('');
    buffer.writeln('--- 测试结果 ---');
    for (final s in successes) {
      buffer.writeln('✓ $s');
    }
    for (final e in errors) {
      buffer.writeln('✗ $e');
    }
    buffer.writeln('');
    buffer.writeln('整体状态: ${isHealthy ? "正常" : "异常"}');
    return buffer.toString();
  }
}

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

  /// 运行完整的网络诊断
  /// 测试UDP绑定、广播发送、TCP连接等
  static Future<NetworkDiagnostics> runDiagnostics({String? targetIP}) async {
    final errors = <String>[];
    final successes = <String>[];
    String? localIP;
    String? gatewayIP;
    bool canBindUDP = false;
    bool canSendBroadcast = false;
    bool canResolveGateway = false;
    bool canPingGateway = false;

    // 1. 获取本地IP
    try {
      localIP = await _networkInfo.getWifiIP();
      if (localIP != null && localIP.isNotEmpty) {
        successes.add('获取本地IP成功: $localIP');
        // 计算网关IP (假设是.1)
        final parts = localIP.split('.');
        if (parts.length == 4) {
          gatewayIP = '${parts[0]}.${parts[1]}.${parts[2]}.1';
          canResolveGateway = true;
          successes.add('推测网关IP: $gatewayIP');
        }
      } else {
        errors.add('获取本地IP失败: 返回为空');
      }
    } catch (e) {
      errors.add('获取本地IP异常: $e');
    }

    // 2. 测试UDP Socket绑定
    RawDatagramSocket? udpSocket;
    try {
      udpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );
      udpSocket.broadcastEnabled = true;
      canBindUDP = true;
      successes.add('UDP Socket绑定成功，端口: ${udpSocket.port}');
    } catch (e) {
      errors.add('UDP Socket绑定失败: $e');
    }

    // 3. 测试广播发送
    if (udpSocket != null) {
      try {
        const testMessage = 'DLNA_DIAG_TEST';
        final sent = udpSocket.send(
          testMessage.codeUnits,
          InternetAddress('255.255.255.255'),
          9999,
        );
        if (sent > 0) {
          canSendBroadcast = true;
          successes.add('UDP广播发送成功: $sent 字节');
        } else {
          errors.add('UDP广播发送返回0字节');
        }
      } catch (e) {
        errors.add('UDP广播发送失败: $e');
      }
      udpSocket.close();
    }

    // 4. 测试TCP连接到目标IP或网关
    final testIP = targetIP ?? gatewayIP;
    if (testIP != null) {
      // 测试常见端口
      for (final port in [80, 1900, 49152]) {
        try {
          final socket = await Socket.connect(
            testIP,
            port,
            timeout: const Duration(seconds: 2),
          );
          socket.destroy();
          canPingGateway = true;
          successes.add('TCP连接 $testIP:$port 成功');
          break;
        } on SocketException catch (e) {
          final errno = e.osError?.errorCode ?? 0;
          if (errno == 65) {
            errors.add('TCP $testIP:$port - No route to host (errno=65)');
          } else if (errno == 61) {
            // Connection refused is actually good - means we reached the host
            canPingGateway = true;
            successes.add('TCP $testIP:$port - 主机可达 (连接被拒绝)');
            break;
          } else {
            errors.add('TCP $testIP:$port - ${e.message} (errno=$errno)');
          }
        } on TimeoutException {
          errors.add('TCP $testIP:$port - 连接超时');
        } catch (e) {
          errors.add('TCP $testIP:$port - $e');
        }
      }
    }

    // 5. iOS特定: 测试SSDP组播
    if (Platform.isIOS) {
      try {
        final ssdpSocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          0,
          reuseAddress: true,
        );
        ssdpSocket.broadcastEnabled = true;

        // iOS上跳过组播测试，直接测试广播
        const ssdpMessage = 'M-SEARCH * HTTP/1.1\r\n'
            'HOST: 239.255.255.250:1900\r\n'
            'MAN: "ssdp:discover"\r\n'
            'MX: 1\r\n'
            'ST: ssdp:all\r\n'
            '\r\n';

        // 只测试广播地址
        final sent = ssdpSocket.send(
          ssdpMessage.codeUnits,
          InternetAddress('255.255.255.255'),
          1900,
        );
        if (sent > 0) {
          successes.add('SSDP广播发送成功: $sent 字节');
        }
        ssdpSocket.close();
      } catch (e) {
        errors.add('SSDP测试失败: $e');
      }
    }

    return NetworkDiagnostics(
      canResolveGateway: canResolveGateway,
      canPingGateway: canPingGateway,
      canBindUDP: canBindUDP,
      canSendBroadcast: canSendBroadcast,
      gatewayIP: gatewayIP,
      localIP: localIP,
      errors: errors,
      successes: successes,
    );
  }

  /// 测试到指定IP的TCP连接
  static Future<String> testTCPConnection(String ip, int port) async {
    try {
      final socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(seconds: 3),
      );
      socket.destroy();
      return '连接成功';
    } on SocketException catch (e) {
      final errno = e.osError?.errorCode ?? 0;
      if (errno == 65) {
        return 'No route to host (errno=65) - iOS可能阻止了本地网络访问';
      } else if (errno == 61) {
        return '主机可达，但端口未开放 (errno=61)';
      } else if (errno == 60) {
        return '连接超时 (errno=60)';
      }
      return '${e.message} (errno=$errno)';
    } on TimeoutException {
      return '连接超时';
    } catch (e) {
      return '未知错误: $e';
    }
  }
}
