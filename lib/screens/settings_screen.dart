import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cast_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        centerTitle: true,
      ),
      body: Consumer<CastProvider>(
        builder: (context, provider, child) {
          return ListView(
            children: [
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

              // About Section
              _buildSectionHeader(context, '关于'),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('版本'),
                subtitle: const Text('1.0.2'),
              ),
              ListTile(
                leading: const Icon(Icons.code),
                title: const Text('应用名称'),
                subtitle: const Text('局域网投屏'),
              ),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('功能说明'),
                subtitle: const Text('支持DLNA/UPNP协议投屏到智能电视'),
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

              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
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
