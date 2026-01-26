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
                    'Devices',
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
                    label: Text(provider.isScanning ? 'Scanning...' : 'Scan'),
                  ),
                ],
              ),
            ),

            if (provider.devices.isEmpty && !provider.isScanning)
              const Padding(
                padding: EdgeInsets.all(32.0),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.tv_off, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'No devices found',
                        style: TextStyle(color: Colors.grey),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Make sure your TV/device is on the same network',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                        textAlign: TextAlign.center,
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
                      _buildSectionHeader(context, 'Renderers (DMR)', Icons.tv),
                      ...renderers.map((device) => _DeviceListTile(
                            device: device,
                            isSelected: provider.selectedRenderer == device,
                            onTap: () => provider.selectRenderer(device),
                            showType: true,
                          )),
                    ],

                    // Servers section (for browsing)
                    if (servers.isNotEmpty) ...[
                      _buildSectionHeader(context, 'Media Servers (DMS)', Icons.storage),
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
      child: ListTile(
        leading: Stack(
          children: [
            Icon(
              device.type == DLNADeviceType.renderer ? Icons.tv : Icons.storage,
              color: isSelected ? colorScheme.primary : null,
              size: 32,
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
        title: Text(
          device.friendlyName,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (device.manufacturer != null)
              Text(device.manufacturer!, style: const TextStyle(fontSize: 12)),
            if (device.modelName != null)
              Text(device.modelName!, style: const TextStyle(fontSize: 12)),
            if (showType)
              Row(
                children: [
                  _buildCapabilityChip(context, device.typeLabel, colorScheme.tertiary),
                  if (device.canPlayMedia) ...[
                    const SizedBox(width: 4),
                    _buildCapabilityChip(context, 'Play', Colors.green),
                  ],
                  if (device.canBrowseMedia) ...[
                    const SizedBox(width: 4),
                    _buildCapabilityChip(context, 'Browse', Colors.blue),
                  ],
                ],
              ),
          ],
        ),
        trailing: isSelected
            ? Icon(Icons.check_circle, color: colorScheme.primary)
            : const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  Widget _buildCapabilityChip(BuildContext context, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }
}
