import 'package:flutter/material.dart';
import '../../../models/reader_settings.dart';
import '../../../services/settings_service.dart';
import '../sheets/theme_sheet.dart';
import '../sheets/typography_sheet.dart';

class ReaderBottomBar extends StatelessWidget {
  final int currentPage;
  final int pageCount;
  final ReaderSettings settings;
  final VoidCallback onToggleViewMode;

  const ReaderBottomBar({
    super.key,
    required this.currentPage,
    required this.pageCount,
    required this.settings,
    required this.onToggleViewMode,
  });

  void _showSheet(BuildContext context, Widget sheet) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => sheet,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.98),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Trang ${currentPage + 1} / $pageCount',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: colorScheme.primary,
                    ),
                  ),
                  Text(
                    '${(currentPage + 1) * 100 ~/ pageCount}%',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton.filledTonal(
                    icon: const Icon(Icons.format_size_rounded),
                    onPressed: () => _showSheet(context, const TypographyBottomSheet()),
                    tooltip: 'Cỡ chữ & Font',
                  ),
                  IconButton.filledTonal(
                    icon: const Icon(Icons.color_lens_rounded),
                    onPressed: () => _showSheet(context, const ThemeBottomSheet()),
                    tooltip: 'Màu nền & Theme',
                  ),
                  IconButton.filledTonal(
                    icon: const Icon(Icons.layers_rounded),
                    onPressed: onToggleViewMode,
                    tooltip: 'Đổi chế độ xem',
                  ),
                  IconButton.filledTonal(
                    icon: Icon(
                      settings.isContinuousScroll
                          ? Icons.swap_vert_rounded
                          : Icons.swap_horiz_rounded,
                    ),
                    onPressed: () {
                      SettingsService.instance.update(
                        settings.copyWith(isContinuousScroll: !settings.isContinuousScroll),
                      );
                    },
                    tooltip: settings.isContinuousScroll ? 'Đang cuộn dọc' : 'Đang lật trang',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
