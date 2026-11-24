import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../../../models/reader_settings.dart';
import '../../../services/settings_service.dart';

class ThemeBottomSheet extends StatelessWidget {
  const ThemeBottomSheet({super.key});

  // Display order of the fixed presets, with their labels.
  static const List<(ReaderThemePreset, String, String)> _presetLabels = [
    (ReaderThemePreset.sepia, 'Giấy vàng (Bảo vệ mắt)', 'Khuyên dùng khi đọc truyện lâu'),
    (ReaderThemePreset.classicWhite, 'Trắng tinh khôi', 'Độ tương phản cao, rõ nét'),
    (ReaderThemePreset.darkNight, 'Đêm tối dịu mắt', 'Giảm chói trong bóng tối'),
    (ReaderThemePreset.amoledBlack, 'Đen tuyền AMOLED', 'Tiết kiệm pin tối đa cho màn hình OLED'),
    (ReaderThemePreset.forestGreen, 'Xanh lá tươi mát', 'Thư giãn thị giác tự nhiên'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ValueListenableBuilder<ReaderSettings>(
      valueListenable: SettingsService.instance.settings,
      builder: (context, settings, _) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Màu nền & Bảo vệ mắt',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),

                  for (final (preset, title, subtitle) in _presetLabels) ...[
                    _buildPresetItem(
                      title: title,
                      subtitle: subtitle,
                      bgColor: preset.background!,
                      textColor: preset.text!,
                      isSelected: settings.themePreset == preset,
                      onTap: () {
                        SettingsService.instance.update(
                          settings.copyWith(themePreset: preset),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 6),

                  // Tùy chỉnh màu tự do
                  OutlinedButton.icon(
                    onPressed: () => _openCustomColorDialog(context, settings),
                    icon: const Icon(Icons.colorize_rounded),
                    label: const Text('Tùy chỉnh màu nền & chữ riêng'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPresetItem({
    required String title,
    required String subtitle,
    required Color bgColor,
    required Color textColor,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? Colors.blueAccent : Colors.grey.withValues(alpha: 0.3),
            width: isSelected ? 2.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.75),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle_rounded,
                color: Colors.blueAccent,
                size: 22,
              ),
          ],
        ),
      ),
    );
  }

  void _openCustomColorDialog(BuildContext context, ReaderSettings settings) {
    Color pickerBg = Color(settings.customBgColorHex);
    Color pickerText = Color(settings.customTextColorHex);

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Chọn màu tùy chỉnh'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Màu nền:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              BlockPicker(
                pickerColor: pickerBg,
                onColorChanged: (c) => pickerBg = c,
              ),
              const Divider(height: 24),
              const Text('Màu chữ:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              BlockPicker(
                pickerColor: pickerText,
                onColorChanged: (c) => pickerText = c,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () {
              SettingsService.instance.update(
                settings.copyWith(
                  themePreset: ReaderThemePreset.custom,
                  customBgColorHex: pickerBg.toARGB32(),
                  customTextColorHex: pickerText.toARGB32(),
                ),
              );
              Navigator.pop(dialogCtx);
            },
            child: const Text('Áp dụng'),
          ),
        ],
      ),
    );
  }
}
