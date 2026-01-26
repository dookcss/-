import 'dart:io';
import 'package:flutter/services.dart';

/// iOS原生网络服务
/// 通过MethodChannel调用Swift原生代码来绕过Dart socket限制
class IOSNativeNetwork {
  static const _channel = MethodChannel('com.dlnacast/network');
  
  /// 检查当前平台是否支持原生网络
  static bool get isSupported => Platform.isIOS;
  
  /// 使用原生URLSession获取URL内容
  /// 返回包含statusCode和body的Map，或抛出异常
  static Future<Map<String, dynamic>> fetchUrl(String url) async {
    if (!Platform.isIOS) {
      throw UnsupportedError('Native network only supported on iOS');
    }
    
    try {
      final result = await _channel.invokeMethod('fetchUrl', {'url': url});
      return Map<String, dynamic>.from(result as Map);
    } on PlatformException catch (e) {
      throw NetworkException(
        code: e.code,
        message: e.message ?? 'Unknown error',
        details: e.details?.toString(),
      );
    }
  }
  
  /// 使用Network.framework测试TCP连接
  /// 成功返回true，失败抛出异常
  static Future<bool> checkConnection(String host, int port) async {
    if (!Platform.isIOS) {
      throw UnsupportedError('Native network only supported on iOS');
    }
    
    try {
      final result = await _channel.invokeMethod('checkConnection', {
        'host': host,
        'port': port,
      });
      return (result as Map)['connected'] == true;
    } on PlatformException catch (e) {
      throw NetworkException(
        code: e.code,
        message: e.message ?? 'Connection failed',
        details: e.details?.toString(),
      );
    }
  }
  
  /// 尝试获取设备描述文件
  /// 尝试多个常见端口和路径
  static Future<String?> probeDeviceDescription(String ip) async {
    if (!Platform.isIOS) return null;
    
    const ports = [49152, 49153, 49154, 8060, 1400, 7000, 8008];
    const paths = [
      '/description.xml',
      '/rootDesc.xml',
      '/DeviceDescription.xml',
      '/upnp/description.xml',
    ];
    
    for (final port in ports) {
      for (final path in paths) {
        final url = 'http://$ip:$port$path';
        try {
          print('iOS Native: Probing $url');
          final response = await fetchUrl(url);
          
          if (response['statusCode'] == 200) {
            final body = response['body'] as String?;
            if (body != null && 
                (body.contains('<device>') || body.contains('<root'))) {
              print('iOS Native: Found device at $url');
              return url;
            }
          }
        } catch (e) {
          // 忽略连接错误，继续下一个
          print('iOS Native: Failed $url - $e');
        }
      }
    }
    
    return null;
  }
}

/// 网络异常
class NetworkException implements Exception {
  final String code;
  final String message;
  final String? details;
  
  NetworkException({
    required this.code,
    required this.message,
    this.details,
  });
  
  @override
  String toString() => 'NetworkException($code): $message${details != null ? ' - $details' : ''}';
}
