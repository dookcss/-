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
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.folder_open, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'Select a Media Server to browse',
                  style: TextStyle(color: Colors.grey),
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
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.folder_off, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text(
                                'This folder is empty',
                                style: TextStyle(color: Colors.grey),
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
          ),
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: provider.browseRoot,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              provider.currentTitle,
              style: const TextStyle(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: provider.refresh,
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
          content: Text('Please select a renderer device first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final success = await provider.castContent(content);
    if (!success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error ?? 'Failed to cast'),
          backgroundColor: Colors.red,
        ),
      );
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
        borderRadius: BorderRadius.circular(4),
        child: Image.network(
          content.albumArtUrl!,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 48,
            height: 48,
            color: iconColor.withValues(alpha: 0.2),
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
        borderRadius: BorderRadius.circular(4),
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
      parts.add('${content.childCount} items');
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
        tooltip: 'Cast to TV',
      );
    }

    return const SizedBox.shrink();
  }
}
