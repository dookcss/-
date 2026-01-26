import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/cast_provider.dart';
import '../widgets/device_list.dart';
import '../widgets/playback_control.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CastProvider>().startScan();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DLNA Cast'),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Device selection section
          const Expanded(
            child: DeviceListWidget(),
          ),

          // Playback controls
          const PlaybackControlWidget(),
        ],
      ),
      floatingActionButton: Consumer<CastProvider>(
        builder: (context, provider, child) {
          final hasDevice = provider.selectedDevice != null;
          return FloatingActionButton.extended(
            onPressed: hasDevice ? () => _selectAndCastMedia(context) : null,
            backgroundColor: hasDevice ? null : Colors.grey,
            icon: const Icon(Icons.cast),
            label: const Text('Cast Media'),
          );
        },
      ),
    );
  }

  Future<void> _selectAndCastMedia(BuildContext context) async {
    final provider = context.read<CastProvider>();

    if (provider.selectedDevice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a device first')),
      );
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          // Video
          'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm',
          // Audio
          'mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a',
          // Image
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
