import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/reader_settings.dart';

class SettingsService {
  static final SettingsService instance = SettingsService._init();
  final ValueNotifier<ReaderSettings> settings = ValueNotifier(const ReaderSettings());

  SettingsService._init();

  static const _keyFontSize = 'fontSize';
  static const _keyLineHeight = 'lineHeight';
  static const _keyFontFamily = 'fontFamily';
  static const _keyJustified = 'isJustified';
  static const _keyPadding = 'horizontalPadding';
  static const _keyContinuous = 'isContinuousScroll';
  static const _keyViewMode = 'viewMode';
  static const _keyThemePreset = 'themePreset';
  static const _keyCustomBg = 'customBgColor';
  static const _keyCustomText = 'customTextColor';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final fontSize = prefs.getDouble(_keyFontSize) ?? 18.0;
    final lineHeight = prefs.getDouble(_keyLineHeight) ?? 1.7;
    final fontFamilyIndex = prefs.getInt(_keyFontFamily) ?? FontFamilyType.system.index;
    final isJustified = prefs.getBool(_keyJustified) ?? true;
    final padding = prefs.getInt(_keyPadding) ?? 18;
    final isContinuous = prefs.getBool(_keyContinuous) ?? false;
    final viewModeIndex = prefs.getInt(_keyViewMode) ?? ViewMode.reflow.index;
    final themePresetIndex = prefs.getInt(_keyThemePreset) ?? ReaderThemePreset.sepia.index;
    final customBg = prefs.getInt(_keyCustomBg) ?? 0xFFFBF0D9;
    final customText = prefs.getInt(_keyCustomText) ?? 0xFF5F4B32;

    settings.value = ReaderSettings(
      fontSize: fontSize,
      lineHeightMultiplier: lineHeight,
      fontFamily: FontFamilyType.values[fontFamilyIndex.clamp(0, FontFamilyType.values.length - 1)],
      isJustified: isJustified,
      horizontalPadding: padding,
      isContinuousScroll: isContinuous,
      viewMode: ViewMode.values[viewModeIndex.clamp(0, ViewMode.values.length - 1)],
      themePreset: ReaderThemePreset.values[themePresetIndex.clamp(0, ReaderThemePreset.values.length - 1)],
      customBgColorHex: customBg,
      customTextColorHex: customText,
    );
  }

  Future<void> update(ReaderSettings newSettings) async {
    settings.value = newSettings;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyFontSize, newSettings.fontSize);
    await prefs.setDouble(_keyLineHeight, newSettings.lineHeightMultiplier);
    await prefs.setInt(_keyFontFamily, newSettings.fontFamily.index);
    await prefs.setBool(_keyJustified, newSettings.isJustified);
    await prefs.setInt(_keyPadding, newSettings.horizontalPadding);
    await prefs.setBool(_keyContinuous, newSettings.isContinuousScroll);
    await prefs.setInt(_keyViewMode, newSettings.viewMode.index);
    await prefs.setInt(_keyThemePreset, newSettings.themePreset.index);
    await prefs.setInt(_keyCustomBg, newSettings.customBgColorHex);
    await prefs.setInt(_keyCustomText, newSettings.customTextColorHex);
  }
}
