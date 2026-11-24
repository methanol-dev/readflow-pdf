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

  /// Applies [next] and persists only the fields that changed.
  Future<void> update(ReaderSettings next) async {
    final prev = settings.value;
    settings.value = next;
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      if (prev.fontSize != next.fontSize)
        prefs.setDouble(_keyFontSize, next.fontSize),
      if (prev.lineHeightMultiplier != next.lineHeightMultiplier)
        prefs.setDouble(_keyLineHeight, next.lineHeightMultiplier),
      if (prev.fontFamily != next.fontFamily)
        prefs.setInt(_keyFontFamily, next.fontFamily.index),
      if (prev.isJustified != next.isJustified)
        prefs.setBool(_keyJustified, next.isJustified),
      if (prev.horizontalPadding != next.horizontalPadding)
        prefs.setInt(_keyPadding, next.horizontalPadding),
      if (prev.isContinuousScroll != next.isContinuousScroll)
        prefs.setBool(_keyContinuous, next.isContinuousScroll),
      if (prev.viewMode != next.viewMode)
        prefs.setInt(_keyViewMode, next.viewMode.index),
      if (prev.themePreset != next.themePreset)
        prefs.setInt(_keyThemePreset, next.themePreset.index),
      if (prev.customBgColorHex != next.customBgColorHex)
        prefs.setInt(_keyCustomBg, next.customBgColorHex),
      if (prev.customTextColorHex != next.customTextColorHex)
        prefs.setInt(_keyCustomText, next.customTextColorHex),
    ]);
  }
}
