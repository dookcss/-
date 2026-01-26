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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Available Devices',
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
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: provider.devices.length,
                  itemBuilder: (context, index) {
                    final device = provider.devices[index];
                    final isSelected = provider.selectedDevice == device;

                    return _DeviceListTile(
                      device: device,
                      isSelected: isSelected,
                      onTap: () => provider.selectDevice(device),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DeviceListTile extends StatelessWidget {
  final DLNADevice device;
  final bool isSelected;
  final VoidCallback onTap;

  const _DeviceListTile({
    required this.device,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: isSelected ? Theme.of(context).primaryColor.withValues(alpha: 0.1) : null,
      child: ListTile(
        leading: Icon(
          Icons.tv,
          color: isSelected ? Theme.of(context).primaryColor : null,
          size: 32,
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
          ],
        ),
        trailing: isSelected
            ? const Icon(Icons.check_circle, color: Colors.green)
            : const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
