import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/cast_provider.dart';
import '../widgets/device_list.dart';
import '../widgets/media_browser.dart';
import '../widgets/local_media_browser.dart';
import '../widgets/playback_control.dart';
import '../widgets/url_cast_dialog.dart';
import '../services/local_network_permission.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAndScan();
    });
  }

  Future<void> _initializeAndScan() async {
    // On iOS, request local network permission first
    if (Platform.isIOS) {
      final hasPermission = await LocalNetworkPermission.requestPermission();
      if (!hasPermission && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('请在设置中允许本地网络访问'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      // Wait a bit for permission dialog to be handled
      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (mounted) {
      context.read<CastProvider>().startScan();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('局域网投屏'),
        centerTitle: true,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.devices), text: '设备'),
            Tab(icon: Icon(Icons.video_library), text: '本地'),
            Tab(icon: Icon(Icons.folder), text: '浏览'),
          ],
        ),
        actions: [
          Consumer<CastProvider>(
            builder: (context, provider, child) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (provider.selectedRenderer != null)
                    Chip(
                      avatar: const Icon(Icons.tv, size: 16),
                      label: Text(
                        provider.selectedRenderer!.friendlyName,
                        style: const TextStyle(fontSize: 12),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) {
                      switch (value) {
                        case 'url':
                          _showUrlCastDialog();
                          break;
                        case 'settings':
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const SettingsScreen()),
                          );
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'url',
                        child: ListTile(
                          leading: Icon(Icons.link),
                          title: Text('URL投屏'),
                          contentPadding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'settings',
                        child: ListTile(
                          leading: Icon(Icons.settings),
                          title: Text('设置'),
                          contentPadding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                DeviceListWidget(),
                LocalMediaBrowserWidget(),
                MediaBrowserWidget(),
              ],
            ),
          ),
          const PlaybackControlWidget(),
        ],
      ),
      floatingActionButton: Consumer<CastProvider>(
        builder: (context, provider, child) {
          final hasRenderer = provider.selectedRenderer != null;
          return FloatingActionButton.extended(
            onPressed: hasRenderer ? () => _selectAndCastMedia(context) : null,
            backgroundColor: hasRenderer ? null : Colors.grey,
            icon: const Icon(Icons.add),
            label: const Text('本地文件'),
          );
        },
      ),
    );
  }

  void _showUrlCastDialog() {
    showDialog(
      context: context,
      builder: (context) => const UrlCastDialog(),
    );
  }

  Future<void> _selectAndCastMedia(BuildContext context) async {
    final provider = context.read<CastProvider>();

    if (provider.selectedRenderer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择播放设备')),
      );
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v', 'ts',
          'mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a', 'wma',
          'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp',
        ],
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final filePath = file.path;
        final fileName = file.name;

        if (filePath != null) {
          final success = await provider.castMedia(filePath, fileName);

          if (context.mounted) {
            if (success) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('正在投屏: $fileName'),
                  backgroundColor: Colors.green,
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(provider.error ?? '投屏失败'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('错误: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
