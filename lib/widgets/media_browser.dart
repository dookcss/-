import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cast_provider.dart';
import '../models/didl_content.dart';

class MediaBrowserWidget extends StatelessWidget {
  const MediaBrowserWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CastProvider>(
      builder: (context, provider, child) {
        if (provider.selectedServer == null) {
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
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '请选择媒体服务器',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '在设备页面选择一个媒体服务器来浏览内容',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            // Navigation bar
            _buildNavigationBar(context, provider),

            // Content list
            Expanded(
              child: provider.isBrowsing
                  ? const Center(child: CircularProgressIndicator())
                  : provider.currentContents.isEmpty
                      ? Center(
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
                                  Icons.folder_off,
                                  size: 40,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '此文件夹为空',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: provider.refresh,
                          child: ListView.builder(
                            itemCount: provider.currentContents.length,
                            itemBuilder: (context, index) {
                              final content = provider.currentContents[index];
                              return _ContentListTile(
                                content: content,
                                onTap: () => _handleContentTap(context, provider, content),
                                onCast: content.isPlayable
                                    ? () => _handleCast(context, provider, content)
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

  Widget _buildNavigationBar(BuildContext context, CastProvider provider) {
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
            onPressed: provider.canGoBack ? provider.goBack : null,
            tooltip: '返回',
          ),
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: provider.browseRoot,
            tooltip: '根目录',
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              provider.currentTitle == 'Root' ? '根目录' : provider.currentTitle,
              style: const TextStyle(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: provider.refresh,
            tooltip: '刷新',
          ),
        ],
      ),
    );
  }

  void _handleContentTap(BuildContext context, CastProvider provider, DIDLContent content) {
    if (content.isContainer) {
      provider.browseContainer(content);
    } else if (content.isPlayable) {
      _handleCast(context, provider, content);
    }
  }

  void _handleCast(BuildContext context, CastProvider provider, DIDLContent content) async {
    if (provider.selectedRenderer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先选择播放设备'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final success = await provider.castContent(content);
    if (context.mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('正在投屏: ${content.title}'),
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

class _ContentListTile extends StatelessWidget {
  final DIDLContent content;
  final VoidCallback onTap;
  final VoidCallback? onCast;

  const _ContentListTile({
    required this.content,
    required this.onTap,
    this.onCast,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        leading: _buildLeadingIcon(colorScheme),
        title: Text(
          content.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: _buildSubtitle(),
        trailing: _buildTrailing(context),
        onTap: onTap,
      ),
    );
  }

  Widget _buildLeadingIcon(ColorScheme colorScheme) {
    IconData iconData;
    Color iconColor;

    switch (content.type) {
      case ContentType.container:
        iconData = Icons.folder;
        iconColor = Colors.amber;
        break;
      case ContentType.video:
        iconData = Icons.movie;
        iconColor = Colors.red;
        break;
      case ContentType.audio:
        iconData = Icons.music_note;
        iconColor = Colors.purple;
        break;
      case ContentType.image:
        iconData = Icons.image;
        iconColor = Colors.green;
        break;
      case ContentType.unknown:
        iconData = Icons.insert_drive_file;
        iconColor = Colors.grey;
        break;
    }

    // Show thumbnail if available
    if (content.albumArtUrl != null && !content.isContainer) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          content.albumArtUrl!,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(iconData, color: iconColor),
          ),
        ),
      );
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(iconData, color: iconColor),
    );
  }

  Widget? _buildSubtitle() {
    final parts = <String>[];

    if (content.artist != null) {
      parts.add(content.artist!);
    }
    if (content.album != null) {
      parts.add(content.album!);
    }
    if (content.durationDisplay.isNotEmpty) {
      parts.add(content.durationDisplay);
    }
    if (content.sizeDisplay.isNotEmpty) {
      parts.add(content.sizeDisplay);
    }
    if (content.resolution != null) {
      parts.add(content.resolution!);
    }
    if (content.isContainer && content.childCount > 0) {
      parts.add('${content.childCount} 项');
    }

    if (parts.isEmpty) return null;

    return Text(
      parts.join(' | '),
      style: const TextStyle(fontSize: 12),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildTrailing(BuildContext context) {
    if (content.isContainer) {
      return const Icon(Icons.chevron_right);
    }

    if (content.isPlayable) {
      return IconButton(
        icon: const Icon(Icons.cast),
        color: Theme.of(context).colorScheme.primary,
        onPressed: onCast,
        tooltip: '投屏到电视',
      );
    }

    return const SizedBox.shrink();
  }
}
