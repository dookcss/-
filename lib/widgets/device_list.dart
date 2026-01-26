import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cast_provider.dart';
import '../models/dlna_device.dart';

class DeviceListWidget extends StatelessWidget {
  const DeviceListWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CastProvider>(
      builder: (context, provider, child) {
        final renderers = provider.renderers;
        final servers = provider.servers;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with scan button
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '设备列表',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  ElevatedButton.icon(
                    onPressed: provider.isScanning ? null : provider.startScan,
                    icon: provider.isScanning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: Text(provider.isScanning ? '扫描中...' : '扫描'),
                  ),
                ],
              ),
            ),

            if (provider.devices.isEmpty && !provider.isScanning)
              Expanded(
                child: Center(
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
                          Icons.tv_off,
                          size: 48,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        '未发现设备',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '请确保电视/设备与手机在同一网络',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      OutlinedButton.icon(
                        onPressed: provider.startScan,
                        icon: const Icon(Icons.refresh),
                        label: const Text('重新扫描'),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView(
                  children: [
                    // Renderers section (for playback)
                    if (renderers.isNotEmpty) ...[
                      _buildSectionHeader(context, '播放设备 (DMR)', Icons.tv),
                      ...renderers.map((device) => _DeviceListTile(
                            device: device,
                            isSelected: provider.selectedRenderer == device,
                            onTap: () => provider.selectRenderer(device),
                            showType: true,
                          )),
                    ],

                    // Servers section (for browsing)
                    if (servers.isNotEmpty) ...[
                      _buildSectionHeader(context, '媒体服务器 (DMS)', Icons.storage),
                      ...servers.map((device) => _DeviceListTile(
                            device: device,
                            isSelected: provider.selectedServer == device,
                            onTap: () => provider.selectServer(device),
                            showType: true,
                          )),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceListTile extends StatelessWidget {
  final DLNADevice device;
  final bool isSelected;
  final VoidCallback onTap;
  final bool showType;

  const _DeviceListTile({
    required this.device,
    required this.isSelected,
    required this.onTap,
    this.showType = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: isSelected ? colorScheme.primaryContainer : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(color: colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Device icon with version badge
              Stack(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? colorScheme.primary.withValues(alpha: 0.2)
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      device.type == DLNADeviceType.renderer ? Icons.tv : Icons.storage,
                      color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                      size: 28,
                    ),
                  ),
                  if (device.dlnaVersion != null)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: colorScheme.secondary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          device.versionDisplay,
                          style: TextStyle(
                            fontSize: 8,
                            color: colorScheme.onSecondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              // Device info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.friendlyName,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (device.manufacturer != null || device.modelName != null)
                      Text(
                        [device.manufacturer, device.modelName]
                            .where((s) => s != null)
                            .join(' - '),
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (showType)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          children: [
                            _buildCapabilityChip(context, device.typeLabel, colorScheme.tertiary),
                            if (device.canPlayMedia) ...[
                              const SizedBox(width: 4),
                              _buildCapabilityChip(context, '播放', Colors.green),
                            ],
                            if (device.canBrowseMedia) ...[
                              const SizedBox(width: 4),
                              _buildCapabilityChip(context, '浏览', Colors.blue),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              // Selection indicator
              if (isSelected)
                Icon(Icons.check_circle, color: colorScheme.primary, size: 24)
              else
                Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCapabilityChip(BuildContext context, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
