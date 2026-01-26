import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cast_provider.dart';

class PlaybackControlWidget extends StatelessWidget {
  const PlaybackControlWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CastProvider>(
      builder: (context, provider, child) {
        if (provider.currentMedia == null &&
            provider.playbackState == PlaybackState.idle) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Media info
              if (provider.currentMedia != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    children: [
                      const Icon(Icons.movie, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              provider.currentMedia!.name,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              provider.selectedRenderer?.friendlyName ?? 'Unknown Device',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // Progress bar
              if (provider.duration.inSeconds > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    children: [
                      Slider(
                        value: provider.position.inSeconds.toDouble(),
                        max: provider.duration.inSeconds.toDouble(),
                        onChanged: (value) {
                          provider.seek(Duration(seconds: value.toInt()));
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_formatDuration(provider.position)),
                            Text(_formatDuration(provider.duration)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // Control buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Stop button
                  IconButton(
                    icon: const Icon(Icons.stop),
                    iconSize: 32,
                    onPressed: provider.stop,
                  ),

                  const SizedBox(width: 16),

                  // Play/Pause button
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(
                        provider.isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                      ),
                      iconSize: 40,
                      onPressed: provider.isPlaying ? provider.pause : provider.play,
                    ),
                  ),

                  const SizedBox(width: 16),

                  // Volume control
                  PopupMenuButton<int>(
                    icon: const Icon(Icons.volume_up, size: 32),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        enabled: false,
                        child: StatefulBuilder(
                          builder: (context, setState) {
                            return Column(
                              children: [
                                const Text('Volume'),
                                Slider(
                                  value: provider.volume.toDouble(),
                                  max: 100,
                                  onChanged: (value) {
                                    provider.setVolume(value.toInt());
                                    setState(() {});
                                  },
                                ),
                                Text('${provider.volume}%'),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Loading indicator
              if (provider.playbackState == PlaybackState.loading)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(),
                ),

              // Error message
              if (provider.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    provider.error!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
