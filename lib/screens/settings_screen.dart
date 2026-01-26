import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../providers/cast_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final NetworkInfo _networkInfo = NetworkInfo();
  String? _wifiName;
  String? _wifiBSSID;
  String? _wifiIP;
  List<NetworkInterfaceInfo> _interfaces = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNetworkInfo();
  }

  Future<void> _loadNetworkInfo() async {
    setState(() => _isLoading = true);

    try {
      // Get WiFi info
      _wifiName = await _networkInfo.getWifiName();
      _wifiBSSID = await _networkInfo.getWifiBSSID();
      _wifiIP = await _networkInfo.getWifiIP();
    } catch (e) {
      print('Failed to get WiFi info: $e');
    }

    try {
      // Get all network interfaces
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      _interfaces = interfaces.map((interface) {
        final addresses = interface.addresses
            .where((a) => !a.isLoopback)
            .map((a) => a.address)
            .toList();
        return NetworkInterfaceInfo(
          name: interface.name,
          addresses: addresses,
        );
      }).toList();
    } catch (e) {
      print('Failed to get interfaces: $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadNetworkInfo,
            tooltip: '刷新网络信息',
          ),
        ],
      ),
      body: Consumer<CastProvider>(
        builder: (context, provider, child) {
          return ListView(
            children: [
              // Network Info Section
              _buildSectionHeader(context, '网络信息'),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                ListTile(
                  leading: const Icon(Icons.wifi),
                  title: const Text('WiFi名称'),
                  subtitle: Text(_wifiName ?? '未获取 (需要定位权限)'),
                ),
                ListTile(
                  leading: const Icon(Icons.router),
                  title: const Text('WiFi BSSID'),
                  subtitle: Text(_wifiBSSID ?? '未获取'),
                ),
                ListTile(
                  leading: const Icon(Icons.lan),
                  title: const Text('WiFi IP'),
                  subtitle: Text(_wifiIP ?? '未获取'),
                ),
                const Divider(),
                _buildSectionHeader(context, '网络接口'),
                if (_interfaces.isEmpty)
                  const ListTile(
                    leading: Icon(Icons.error_outline, color: Colors.red),
                    title: Text('未检测到网络接口'),
                    subtitle: Text('请检查WiFi连接'),
                  )
                else
                  ..._interfaces.map((interface) => Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _getInterfaceIcon(interface.name),
                                color: _isWifiInterface(interface.name)
                                    ? Colors.green
                                    : Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                interface.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _isWifiInterface(interface.name)
                                      ? Colors.green
                                      : null,
                                ),
                              ),
                              if (_isWifiInterface(interface.name))
                                Container(
                                  margin: const EdgeInsets.only(left: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'WiFi',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ...interface.addresses.map((addr) => Padding(
                            padding: const EdgeInsets.only(left: 32),
                            child: Row(
                              children: [
                                const Icon(Icons.arrow_right, size: 16),
                                Text(
                                  addr,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '→ ${_getSubnetBroadcast(addr)}',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          )),
                        ],
                      ),
                    ),
                  )),
              ],
              const Divider(),

              // Device Settings Section
              _buildSectionHeader(context, '设备设置'),
              SwitchListTile(
                title: const Text('自动选择播放设备'),
                subtitle: const Text('发现设备时自动选择第一个播放设备'),
                value: provider.autoSelectRenderer,
                onChanged: (value) {
                  provider.setAutoSelectRenderer(value);
                },
                secondary: const Icon(Icons.tv),
              ),
              const Divider(),

              // Scan Settings Section
              _buildSectionHeader(context, '扫描设置'),
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('重新扫描设备'),
                subtitle: const Text('搜索网络中的DLNA设备'),
                onTap: () {
                  provider.startScan();
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('开始扫描设备...')),
                  );
                },
              ),
              const Divider(),

              // Status Section
              _buildSectionHeader(context, '当前状态'),
              ListTile(
                leading: const Icon(Icons.devices),
                title: const Text('已发现设备'),
                subtitle: Text('${provider.devices.length} 台设备'),
              ),
              ListTile(
                leading: const Icon(Icons.tv),
                title: const Text('播放设备'),
                subtitle: Text(provider.selectedRenderer?.friendlyName ?? '未选择'),
              ),
              ListTile(
                leading: const Icon(Icons.storage),
                title: const Text('媒体服务器'),
                subtitle: Text(provider.selectedServer?.friendlyName ?? '未选择'),
              ),
              const Divider(),

              // About Section
              _buildSectionHeader(context, '关于'),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('版本'),
                subtitle: const Text('1.0.3'),
              ),
              ListTile(
                leading: const Icon(Icons.phone_iphone),
                title: const Text('平台'),
                subtitle: Text(Platform.operatingSystem),
              ),

              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  bool _isWifiInterface(String name) {
    final lower = name.toLowerCase();
    return lower.contains('en0') ||
        lower.contains('en1') ||
        lower.contains('wlan') ||
        lower.contains('wifi');
  }

  IconData _getInterfaceIcon(String name) {
    if (_isWifiInterface(name)) {
      return Icons.wifi;
    }
    if (name.toLowerCase().contains('lo')) {
      return Icons.loop;
    }
    return Icons.settings_ethernet;
  }

  String _getSubnetBroadcast(String ip) {
    final parts = ip.split('.');
    if (parts.length == 4) {
      return '${parts[0]}.${parts[1]}.${parts[2]}.255';
    }
    return '?';
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class NetworkInterfaceInfo {
  final String name;
  final List<String> addresses;

  NetworkInterfaceInfo({required this.name, required this.addresses});
}
