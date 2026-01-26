import 'package:shared_preferences/shared_preferences.dart';

/// 保存需要扫描的设备IP地址
class DeviceIPStorage {
  static const String _key = 'saved_device_ips';
  
  /// 获取所有保存的IP地址
  static Future<List<String>> getSavedIPs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? [];
  }
  
  /// 添加IP地址
  static Future<bool> addIP(String ip) async {
    if (!_isValidIP(ip)) return false;
    
    final prefs = await SharedPreferences.getInstance();
    final ips = prefs.getStringList(_key) ?? [];
    
    // 避免重复
    if (!ips.contains(ip)) {
      ips.add(ip);
      await prefs.setStringList(_key, ips);
    }
    return true;
  }
  
  /// 删除IP地址
  static Future<void> removeIP(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    final ips = prefs.getStringList(_key) ?? [];
    ips.remove(ip);
    await prefs.setStringList(_key, ips);
  }
  
  /// 清空所有IP地址
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
  
  /// 验证IP地址格式
  static bool _isValidIP(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    
    for (final part in parts) {
      final num = int.tryParse(part);
      if (num == null || num < 0 || num > 255) return false;
    }
    return true;
  }
  
  /// 验证IP地址格式（公开方法）
  static bool isValidIP(String ip) => _isValidIP(ip);
}
