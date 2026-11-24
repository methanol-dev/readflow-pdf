import 'package:flutter/material.dart';
import '../../../models/reader_settings.dart';
import '../../../services/settings_service.dart';

class TypographyBottomSheet extends StatelessWidget {
  const TypographyBottomSheet({super.key});

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
                    'Cài đặt hiển thị & Font chữ',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),

                  // Cỡ chữ (Font Size)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Cỡ chữ'),
                      Text(
                        '${settings.fontSize.toInt()} pt',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Slider(
                    value: settings.fontSize,
                    min: 12.0,
                    max: 34.0,
                    divisions: 22,
                    label: '${settings.fontSize.toInt()}',
                    onChanged: (val) {
                      SettingsService.instance.update(settings.copyWith(fontSize: val));
                    },
                  ),

                  // Giãn dòng (Line Height)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Khoảng cách dòng'),
                      Text(
                        '${settings.lineHeightMultiplier.toStringAsFixed(1)}x',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Slider(
                    value: settings.lineHeightMultiplier,
                    min: 1.2,
                    max: 2.6,
                    divisions: 14,
                    label: settings.lineHeightMultiplier.toStringAsFixed(1),
                    onChanged: (val) {
                      SettingsService.instance.update(settings.copyWith(lineHeightMultiplier: val));
                    },
                  ),

                  // Kiểu font chữ (Font Family)
                  const Text('Kiểu font chữ'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Mặc định'),
                        selected: settings.fontFamily == FontFamilyType.system,
                        onSelected: (_) {
                          SettingsService.instance.update(settings.copyWith(fontFamily: FontFamilyType.system));
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Có chân (Serif)'),
                        selected: settings.fontFamily == FontFamilyType.serif,
                        onSelected: (_) {
                          SettingsService.instance.update(settings.copyWith(fontFamily: FontFamilyType.serif));
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Không chân (Sans)'),
                        selected: settings.fontFamily == FontFamilyType.sansSerif,
                        onSelected: (_) {
                          SettingsService.instance.update(settings.copyWith(fontFamily: FontFamilyType.sansSerif));
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Đơn cách (Mono)'),
                        selected: settings.fontFamily == FontFamilyType.monospace,
                        onSelected: (_) {
                          SettingsService.instance.update(settings.copyWith(fontFamily: FontFamilyType.monospace));
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Căn đều chữ & Lề
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Căn đều hai bên (Justify)'),
                    value: settings.isJustified,
                    onChanged: (val) {
                      SettingsService.instance.update(settings.copyWith(isJustified: val));
                    },
                  ),

                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Chế độ cuộn dọc liên tục'),
                    subtitle: const Text('Cuộn như trang báo thay vì lật từng trang'),
                    value: settings.isContinuousScroll,
                    onChanged: (val) {
                      SettingsService.instance.update(settings.copyWith(isContinuousScroll: val));
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
