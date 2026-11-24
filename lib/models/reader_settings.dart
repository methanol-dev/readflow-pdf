import 'package:flutter/material.dart';

// Persisted by index: append new values at the end, never reorder.
enum FontFamilyType { system, serif, sansSerif, monospace }

// Persisted by index: append new values at the end, never reorder.
enum ViewMode { reflow, originalPage }

// Persisted by index: append new values at the end, never reorder.
enum ReaderThemePreset {
  classicWhite(background: Color(0xFFFFFFFF), text: Color(0xFF212121)),
  sepia(background: Color(0xFFFBF0D9), text: Color(0xFF5F4B32)),
  darkNight(background: Color(0xFF1E1E1E), text: Color(0xFFD6D6D6)),
  amoledBlack(background: Color(0xFF000000), text: Color(0xFFCCCCCC)),
  forestGreen(background: Color(0xFFE8F5E9), text: Color(0xFF1B5E20)),
  custom;

  const ReaderThemePreset({this.background, this.text});

  /// Fixed colors of the preset; null for [custom], which uses the colors
  /// stored in [ReaderSettings].
  final Color? background;
  final Color? text;
}

class ReaderSettings {
  final double fontSize;
  final double lineHeightMultiplier;
  final FontFamilyType fontFamily;
  final bool isJustified;
  final int horizontalPadding;
  final bool isContinuousScroll;
  final ViewMode viewMode;
  final ReaderThemePreset themePreset;
  final int customBgColorHex;
  final int customTextColorHex;

  const ReaderSettings({
    this.fontSize = 18.0,
    this.lineHeightMultiplier = 1.7,
    this.fontFamily = FontFamilyType.system,
    this.isJustified = true,
    this.horizontalPadding = 18,
    this.isContinuousScroll = false,
    this.viewMode = ViewMode.reflow,
    this.themePreset = ReaderThemePreset.sepia,
    this.customBgColorHex = 0xFFFBF0D9,
    this.customTextColorHex = 0xFF5F4B32,
  });

  Color get backgroundColor => themePreset.background ?? Color(customBgColorHex);

  Color get textColor => themePreset.text ?? Color(customTextColorHex);

  String? get fontFamilyName {
    switch (fontFamily) {
      case FontFamilyType.system:
        return null;
      case FontFamilyType.serif:
        return 'serif';
      case FontFamilyType.sansSerif:
        return 'sans-serif';
      case FontFamilyType.monospace:
        return 'monospace';
    }
  }

  ReaderSettings copyWith({
    double? fontSize,
    double? lineHeightMultiplier,
    FontFamilyType? fontFamily,
    bool? isJustified,
    int? horizontalPadding,
    bool? isContinuousScroll,
    ViewMode? viewMode,
    ReaderThemePreset? themePreset,
    int? customBgColorHex,
    int? customTextColorHex,
  }) {
    return ReaderSettings(
      fontSize: fontSize ?? this.fontSize,
      lineHeightMultiplier: lineHeightMultiplier ?? this.lineHeightMultiplier,
      fontFamily: fontFamily ?? this.fontFamily,
      isJustified: isJustified ?? this.isJustified,
      horizontalPadding: horizontalPadding ?? this.horizontalPadding,
      isContinuousScroll: isContinuousScroll ?? this.isContinuousScroll,
      viewMode: viewMode ?? this.viewMode,
      themePreset: themePreset ?? this.themePreset,
      customBgColorHex: customBgColorHex ?? this.customBgColorHex,
      customTextColorHex: customTextColorHex ?? this.customTextColorHex,
    );
  }
}
