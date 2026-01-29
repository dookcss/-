import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/cast_provider.dart';

class LocalMediaBrowserWidget extends StatelessWidget {
  const LocalMediaBrowserWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CastProvider>(
      builder: (context, provider, child) {
        if (provider.localDirectory == null) {
          return _buildEmptyState(context, provider);
        }

        return Column(
          children: [
            // 路径导航栏
            _buildNavigationBar(context, provider),

            // 文件列表
            Expanded(
              child: provider.isLoadingLocalFiles
                  ? const Center(child: CircularProgressIndicator())
                  : provider.localFiles.isEmpty
                      ? _buildNoFilesState(context)
                      : RefreshIndicator(
                          onRefresh: provider.loadLocalFiles,
                          child: ListView.builder(
                            itemCount: provider.localFiles.length,
                            itemBuilder: (context, index) {
                              final file = provider.localFiles[index];
                              return _LocalFileListTile(
                                file: file,
                                onTap: () => _handleFileTap(context, provider, file),
                                onCast: !file.isDirectory
                                    ? () => _handleCast(context, provider, file)
                                    : null,
                              );
                            },
                          ),
                        ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context, CastProvider provider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.folder_open,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '选择视频目录',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '选择手机中的视频文件夹来浏览和投屏',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _selectDirectory(context, provider),
            icon: const Icon(Icons.folder),
            label: const Text('选择目录'),
          ),
        ],
      ),
    );
  }

  Widget _buildNoFilesState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.movie_creation_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '没有视频文件',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '当前目录下没有找到视频文件',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationBar(BuildContext context, CastProvider provider) {
    final dirName = provider.localDirectory!.split('/').last;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: provider.goUpLocalDirectory,
            tooltip: '返回上级',
          ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: () => _selectDirectory(context, provider),
            tooltip: '选择目录',
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              dirName.isEmpty ? '根目录' : dirName,
              style: const TextStyle(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: provider.loadLocalFiles,
            tooltip: '刷新',
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: provider.clearLocalDirectory,
            tooltip: '关闭目录',
          ),
        ],
      ),
    );
  }

  Future<void> _selectDirectory(BuildContext context, CastProvider provider) async {
    try {
      final result = await FilePicker.platform.getDirectoryPath();
      if (result != null) {
        await provider.selectLocalDirectory(result);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('选择目录失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _handleFileTap(BuildContext context, CastProvider provider, LocalFileItem file) {
    if (file.isDirectory) {
      provider.enterLocalDirectory(file.path);
    } else {
      _handleCast(context, provider, file);
    }
  }

  void _handleCast(BuildContext context, CastProvider provider, LocalFileItem file) async {
    if (provider.selectedRenderer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先选择播放设备'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final success = await provider.castMedia(file.path, file.name);
    if (context.mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('正在投屏: ${file.name}'),
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

class _LocalFileListTile extends StatelessWidget {
  final LocalFileItem file;
  final VoidCallback onTap;
  final VoidCallback? onCast;

  const _LocalFileListTile({
    required this.file,
    required this.onTap,
    this.onCast,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        leading: _buildLeadingIcon(context),
        title: Text(
          file.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: file.isDirectory
            ? const Text('文件夹')
            : Text(file.sizeDisplay),
        trailing: _buildTrailing(context),
        onTap: onTap,
      ),
    );
  }

  Widget _buildLeadingIcon(BuildContext context) {
    if (file.isDirectory) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.folder, color: Colors.amber),
      );
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.movie, color: Colors.red),
    );
  }

  Widget _buildTrailing(BuildContext context) {
    if (file.isDirectory) {
      return const Icon(Icons.chevron_right);
    }

    return IconButton(
      icon: const Icon(Icons.cast),
      color: Theme.of(context).colorScheme.primary,
      onPressed: onCast,
      tooltip: '投屏到电视',
    );
  }
}
