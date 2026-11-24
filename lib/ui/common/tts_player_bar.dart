import 'package:flutter/material.dart';
import '../../services/tts_service.dart';

class TtsPlayerBar extends StatelessWidget {
  final TtsState state;
  final VoidCallback onTogglePlay;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onStop;
  final ValueChanged<double> onSetSpeed;

  const TtsPlayerBar({
    super.key,
    required this.state,
    required this.onTogglePlay,
    required this.onPrevious,
    required this.onNext,
    required this.onStop,
    required this.onSetSpeed,
  });

  @override
  Widget build(BuildContext context) {
    if (!state.isPlaying && !state.isPaused) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.98),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top row: Info & Speed & Close
            Row(
              children: [
                Icon(
                  Icons.headphones_rounded,
                  size: 20,
                  color: state.isPlaying ? theme.colorScheme.primary : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Trang ${state.currentPage + 1} • Đoạn ${state.currentParagraphIndex + 1}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Speed selection dropdown
                PopupMenuButton<double>(
                  initialValue: state.speechRate,
                  tooltip: 'Tốc độ đọc',
                  onSelected: onSetSpeed,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.speed_rounded, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          '${state.speechRate}x',
                          style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  itemBuilder: (context) => [
                    0.5,
                    0.75,
                    1.0,
                    1.25,
                    1.5,
                    2.0,
                  ].map((speed) {
                    return PopupMenuItem<double>(
                      value: speed,
                      child: Text('${speed}x ${speed == 1.0 ? "(Chuẩn)" : ""}'),
                    );
                  }).toList(),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: onStop,
                  tooltip: 'Tắt sách nói',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Current text preview
            if (state.currentText.isNotEmpty)
              Text(
                state.currentText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            const SizedBox(height: 6),
            // Controls row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.skip_previous_rounded),
                  iconSize: 28,
                  onPressed: onPrevious,
                  tooltip: 'Đoạn trước',
                ),
                const SizedBox(width: 16),
                IconButton.filled(
                  onPressed: onTogglePlay,
                  icon: Icon(
                    state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                  tooltip: state.isPlaying ? 'Tạm dừng' : 'Tiếp tục đọc',
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.skip_next_rounded),
                  iconSize: 28,
                  onPressed: onNext,
                  tooltip: 'Đoạn sau',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
