import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cast_provider.dart';

class UrlCastDialog extends StatefulWidget {
  const UrlCastDialog({super.key});

  @override
  State<UrlCastDialog> createState() => _UrlCastDialogState();
}

class _UrlCastDialogState extends State<UrlCastDialog> {
  final _urlController = TextEditingController();
  final _titleController = TextEditingController();
  String _selectedType = 'video/mp4';
  bool _isLoading = false;

  final List<Map<String, String>> _mediaTypes = [
    {'label': '视频 (MP4)', 'value': 'video/mp4'},
    {'label': '视频 (MKV)', 'value': 'video/x-matroska'},
    {'label': '视频 (AVI)', 'value': 'video/avi'},
    {'label': '视频 (WebM)', 'value': 'video/webm'},
    {'label': '音频 (MP3)', 'value': 'audio/mpeg'},
    {'label': '音频 (AAC)', 'value': 'audio/aac'},
    {'label': '音频 (FLAC)', 'value': 'audio/flac'},
    {'label': '图片 (JPEG)', 'value': 'image/jpeg'},
    {'label': '图片 (PNG)', 'value': 'image/png'},
  ];

  @override
  void dispose() {
    _urlController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CastProvider>();
    final hasRenderer = provider.selectedRenderer != null;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.link, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          const Text('URL投屏'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!hasRenderer)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '请先选择播放设备',
                        style: TextStyle(color: Colors.orange, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

            // URL Input
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: '媒体URL',
                hintText: 'http://example.com/video.mp4',
                prefixIcon: const Icon(Icons.link),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
              ),
              keyboardType: TextInputType.url,
              enabled: !_isLoading,
            ),
            const SizedBox(height: 16),

            // Title Input
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: '标题 (可选)',
                hintText: '输入媒体标题',
                prefixIcon: const Icon(Icons.title),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
              ),
              enabled: !_isLoading,
            ),
            const SizedBox(height: 16),

            // Media Type Selection
            DropdownButtonFormField<String>(
              initialValue: _selectedType,
              decoration: InputDecoration(
                labelText: '媒体类型',
                prefixIcon: const Icon(Icons.video_library),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
              ),
              items: _mediaTypes.map((type) {
                return DropdownMenuItem(
                  value: type['value'],
                  child: Text(type['label']!),
                );
              }).toList(),
              onChanged: _isLoading
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() {
                          _selectedType = value;
                        });
                      }
                    },
            ),

            if (hasRenderer) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.tv,
                      color: Theme.of(context).colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '投屏到: ${provider.selectedRenderer!.friendlyName}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: (!hasRenderer || _isLoading) ? null : _castUrl,
          icon: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cast),
          label: Text(_isLoading ? '投屏中...' : '投屏'),
        ),
      ],
    );
  }

  Future<void> _castUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请输入媒体URL'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validate URL format
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请输入有效的HTTP/HTTPS URL'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final provider = context.read<CastProvider>();
    final title = _titleController.text.trim().isNotEmpty
        ? _titleController.text.trim()
        : _extractTitleFromUrl(url);

    final success = await provider.castUrl(url, title, _selectedType);

    if (mounted) {
      setState(() {
        _isLoading = false;
      });

      if (success) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('正在投屏: $title'),
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

  String _extractTitleFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;
      if (pathSegments.isNotEmpty) {
        return Uri.decodeComponent(pathSegments.last);
      }
    } catch (_) {}
    return 'URL媒体';
  }
}
