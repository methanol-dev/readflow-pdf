import 'package:flutter/material.dart';
import '../../../models/reader_settings.dart';
import '../../../services/tts_service.dart';

class ReaderTopBar extends StatelessWidget {
  final String title;
  final ViewMode viewMode;
  final bool isBookmarked;
  final VoidCallback onBack;
  final VoidCallback onToggleViewMode;
  final VoidCallback onToggleTts;
  final VoidCallback onToggleBookmark;
  final VoidCallback onOpenContents;

  const ReaderTopBar({
    super.key,
    required this.title,
    required this.viewMode,
    required this.isBookmarked,
    required this.onBack,
    required this.onToggleViewMode,
    required this.onToggleTts,
    required this.onToggleBookmark,
    required this.onOpenContents,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isReflow = viewMode == ViewMode.reflow;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.98),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: onBack,
              tooltip: 'Trở về thư viện',
            ),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            IconButton(
              icon: Icon(
                isReflow ? Icons.picture_as_pdf_rounded : Icons.menu_book_rounded,
              ),
              onPressed: onToggleViewMode,
              tooltip: isReflow ? 'Xem trang gốc PDF' : 'Chế độ đọc chữ (Reflow)',
            ),
            ValueListenableBuilder<TtsState>(
              valueListenable: TtsService.instance.state,
              builder: (context, tts, _) {
                return IconButton(
                  icon: Icon(
                    Icons.headphones_rounded,
                    color: tts.isActive ? colorScheme.primary : null,
                  ),
                  onPressed: onToggleTts,
                  tooltip: 'Sách nói (TTS)',
                );
              },
            ),
            IconButton(
              icon: Icon(
                isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                color: isBookmarked ? colorScheme.primary : null,
              ),
              onPressed: onToggleBookmark,
              tooltip: 'Đánh dấu trang',
            ),
            IconButton(
              icon: const Icon(Icons.list_rounded),
              onPressed: onOpenContents,
              tooltip: 'Mục lục & Đánh dấu',
            ),
          ],
        ),
      ),
    );
  }
}
