import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../../../models/reader_settings.dart';
import '../../../services/settings_service.dart';

class ThemeBottomSheet extends StatelessWidget {
  const ThemeBottomSheet({super.key});

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

                  _buildPresetItem(
                    title: 'Giấy vàng (Bảo vệ mắt)',
                    subtitle: 'Khuyên dùng khi đọc truyện lâu',
                    bgColor: const Color(0xFFFBF0D9),
                    textColor: const Color(0xFF5F4B32),
                    isSelected: settings.themePreset == ReaderThemePreset.sepia,
                    onTap: () {
                      SettingsService.instance.update(
                        settings.copyWith(themePreset: ReaderThemePreset.sepia),
                      );
                    },
                  ),
                  const SizedBox(height: 10),

                  _buildPresetItem(
                    title: 'Trắng tinh khôi',
                    subtitle: 'Độ tương phản cao, rõ nét',
                    bgColor: const Color(0xFFFFFFFF),
                    textColor: const Color(0xFF212121),
                    isSelected: settings.themePreset == ReaderThemePreset.classicWhite,
                    onTap: () {
                      SettingsService.instance.update(
                        settings.copyWith(themePreset: ReaderThemePreset.classicWhite),
                      );
                    },
                  ),
                  const SizedBox(height: 10),

                  _buildPresetItem(
                    title: 'Đêm tối dịu mắt',
                    subtitle: 'Giảm chói trong bóng tối',
                    bgColor: const Color(0xFF1E1E1E),
                    textColor: const Color(0xFFD6D6D6),
                    isSelected: settings.themePreset == ReaderThemePreset.darkNight,
                    onTap: () {
                      SettingsService.instance.update(
                        settings.copyWith(themePreset: ReaderThemePreset.darkNight),
                      );
                    },
                  ),
                  const SizedBox(height: 10),

                  _buildPresetItem(
                    title: 'Đen tuyền AMOLED',
                    subtitle: 'Tiết kiệm pin tối đa cho màn hình OLED',
                    bgColor: const Color(0xFF000000),
                    textColor: const Color(0xFFCCCCCC),
                    isSelected: settings.themePreset == ReaderThemePreset.amoledBlack,
                    onTap: () {
                      SettingsService.instance.update(
                        settings.copyWith(themePreset: ReaderThemePreset.amoledBlack),
                      );
                    },
                  ),
                  const SizedBox(height: 10),

                  _buildPresetItem(
                    title: 'Xanh lá tươi mát',
                    subtitle: 'Thư giãn thị giác tự nhiên',
                    bgColor: const Color(0xFFE8F5E9),
                    textColor: const Color(0xFF1B5E20),
                    isSelected: settings.themePreset == ReaderThemePreset.forestGreen,
                    onTap: () {
                      SettingsService.instance.update(
                        settings.copyWith(themePreset: ReaderThemePreset.forestGreen),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

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
