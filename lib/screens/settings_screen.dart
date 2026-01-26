import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../providers/cast_provider.dart';
import '../services/ssdp_service.dart';

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
  final TextEditingController _ipController = TextEditingController();
  StreamSubscription<SSDPLogEntry>? _logSubscription;
  final List<SSDPLogEntry> _displayLogs = [];

  @override
  void initState() {
    super.initState();
    _loadNetworkInfo();
    _initLogSubscription();
  }

  void _initLogSubscription() {
    final provider = context.read<CastProvider>();
    _displayLogs.addAll(provider.ssdpLogs);
    _logSubscription = provider.ssdpLogStream.listen((log) {
      if (mounted) {
        setState(() {
          _displayLogs.add(log);
          if (_displayLogs.length > 100) {
            _displayLogs.removeAt(0);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _logSubscription?.cancel();
    _ipController.dispose();
    super.dispose();
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

              // Manual Device Discovery Section
              _buildSectionHeader(context, '手动添加设备'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ipController,
                        decoration: const InputDecoration(
                          hintText: '输入设备IP地址',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: provider.isManualDiscovering
                          ? null
                          : () => _manualDiscoverDevice(provider),
                      child: provider.isManualDiscovering
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('添加'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '提示: 如果自动扫描找不到设备，可以手动输入设备IP地址',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
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

              // SSDP Debug Log Section
              _buildSectionHeader(context, 'SSDP调试日志'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_displayLogs.length} 条日志',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('清空'),
                      onPressed: () {
                        provider.clearSsdpLogs();
                        setState(() {
                          _displayLogs.clear();
                        });
                      },
                    ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _displayLogs.isEmpty
                    ? const Center(
                        child: Text(
                          '暂无日志\n点击"重新扫描设备"开始',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: _displayLogs.length,
                        itemBuilder: (context, index) {
                          final log = _displayLogs[_displayLogs.length - 1 - index];
                          return Text(
                            log.toString(),
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: _getLogColor(log.level),
                            ),
                          );
                        },
                      ),
              ),
              const Divider(),

              // About Section
              _buildSectionHeader(context, '关于'),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('版本'),
                subtitle: const Text('1.0.4'),
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

  Color _getLogColor(String level) {
    switch (level) {
      case 'ERROR':
        return Colors.red;
      case 'WARN':
        return Colors.orange;
      case 'INFO':
        return Colors.green;
      case 'DEBUG':
        return Colors.grey;
      default:
        return Colors.white;
    }
  }

  Future<void> _manualDiscoverDevice(CastProvider provider) async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入IP地址')),
      );
      return;
    }

    // Simple IP validation
    final parts = ip.split('.');
    if (parts.length != 4 || parts.any((p) => int.tryParse(p) == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('IP地址格式不正确')),
      );
      return;
    }

    final success = await provider.discoverDeviceByIP(ip);

    if (mounted) {
      if (success) {
        _ipController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('设备添加成功'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('未找到DLNA设备，请检查IP地址'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
