import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/audio_player_service.dart';

/// 현재 재생 큐(Queue) 목록을 확인하고 드래그 앤 드롭으로 순서를 바꾸거나
/// 개별 트랙 삭제/선택 재생할 수 있는 바텀 시트입니다.
class QueueBottomSheet extends StatelessWidget {
  const QueueBottomSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF151924),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => const DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.68,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: _buildSheet,
      ),
    );
  }

  static Widget _buildSheet(
    BuildContext context,
    ScrollController scrollController,
  ) {
    return _QueueSheetContent(scrollController: scrollController);
  }

  @override
  Widget build(BuildContext context) {
    return _QueueSheetContent(scrollController: ScrollController());
  }
}

class _QueueSheetContent extends StatelessWidget {
  final ScrollController scrollController;

  const _QueueSheetContent({required this.scrollController});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<AudioPlayerService>();
    final queue = player.queue;

    return Column(
      children: [
        const SizedBox(height: 10),
        Container(
          width: 42,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 14, 10),
          child: Row(
            children: [
              const Icon(Icons.queue_music_rounded, color: Colors.tealAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '재생 대기열 (${queue.length}곡)',
                  style: const TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.shuffle_rounded,
                  color: player.isShuffle ? Colors.tealAccent : Colors.white54,
                ),
                tooltip: '셔플 토글',
                onPressed: player.toggleShuffle,
              ),
              IconButton(
                icon: Icon(
                  player.repeatMode == AudioRepeatMode.one
                      ? Icons.repeat_one_rounded
                      : Icons.repeat_rounded,
                  color: player.repeatMode != AudioRepeatMode.off
                      ? Colors.tealAccent
                      : Colors.white54,
                ),
                tooltip: player.repeatMode.label,
                onPressed: player.cycleRepeatMode,
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Colors.white12),
        Expanded(
          child: queue.isEmpty
              ? const Center(
                  child: Text(
                    '재생 대기열이 비어 있습니다.',
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : ReorderableListView.builder(
                  scrollController: scrollController,
                  itemCount: queue.length,
                  onReorder: player.reorderQueue,
                  itemBuilder: (context, index) {
                    final item = queue[index];
                    final isCurrent = index == player.currentIndex;

                    return ListTile(
                      key: ValueKey('${item.uniqueKey}_$index'),
                      selected: isCurrent,
                      selectedTileColor: Colors.tealAccent.withAlpha(20),
                      leading: isCurrent
                          ? const Icon(
                              Icons.graphic_eq_rounded,
                              color: Colors.tealAccent,
                            )
                          : Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 13,
                              ),
                            ),
                      title: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isCurrent ? Colors.tealAccent : Colors.white,
                          fontWeight:
                              isCurrent ? FontWeight.bold : FontWeight.normal,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        '${item.artist} • ${item.cloudBadgeLabel}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11.5,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: Colors.white38,
                            ),
                            onPressed: () => player.removeQueueItemAt(index),
                          ),
                          const Icon(
                            Icons.drag_handle_rounded,
                            color: Colors.white30,
                          ),
                        ],
                      ),
                      onTap: () => player.skipToQueueIndex(index),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
