import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/cast_provider.dart';
import '../widgets/device_list.dart';
import '../widgets/media_browser.dart';
import '../widgets/playback_control.dart';

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
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CastProvider>().startScan();
    });
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
        title: const Text('DLNA Cast'),
        centerTitle: true,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.devices), text: 'Devices'),
            Tab(icon: Icon(Icons.folder), text: 'Browse'),
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
                  const SizedBox(width: 8),
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
            label: const Text('Local File'),
          );
        },
      ),
    );
  }

  Future<void> _selectAndCastMedia(BuildContext context) async {
    final provider = context.read<CastProvider>();

    if (provider.selectedRenderer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a renderer device first')),
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

          if (!success && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(provider.error ?? 'Failed to cast media'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
