package com.doctruyen.reader.data

import android.content.Context
import android.content.SharedPreferences
import com.doctruyen.reader.data.model.FontFamilyType
import com.doctruyen.reader.data.model.ReaderSettings
import com.doctruyen.reader.data.model.ReaderThemePreset
import com.doctruyen.reader.data.model.ViewMode
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

class SettingsRepository(context: Context) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences("reader_settings_prefs", Context.MODE_PRIVATE)

    private val _settings = MutableStateFlow(loadSettings())
    val settings: StateFlow<ReaderSettings> = _settings.asStateFlow()

    private fun loadSettings(): ReaderSettings {
        val fontSize = prefs.getFloat(KEY_FONT_SIZE, 18f)
        val lineHeight = prefs.getFloat(KEY_LINE_HEIGHT, 1.5f)
        val fontType = try {
            FontFamilyType.valueOf(prefs.getString(KEY_FONT_FAMILY, FontFamilyType.SERIF.name)!!)
        } catch (e: Exception) {
            FontFamilyType.SERIF
        }
        val themePreset = try {
            ReaderThemePreset.valueOf(prefs.getString(KEY_THEME_PRESET, ReaderThemePreset.SEPIA.name)!!)
        } catch (e: Exception) {
            ReaderThemePreset.SEPIA
        }
        val customBg = prefs.getLong(KEY_CUSTOM_BG, 0xFFFBF0D9)
        val customText = prefs.getLong(KEY_CUSTOM_TEXT, 0xFF3C3836)
        val isJustified = prefs.getBoolean(KEY_IS_JUSTIFIED, true)
        val paddingDp = prefs.getInt(KEY_PADDING_DP, 16)
        val isContinuous = prefs.getBoolean(KEY_IS_CONTINUOUS, true)
        val viewMode = try {
            ViewMode.valueOf(prefs.getString(KEY_VIEW_MODE, ViewMode.REFLOW.name)!!)
        } catch (e: Exception) {
            ViewMode.REFLOW
        }

        return ReaderSettings(
            fontSizeSp = fontSize,
            lineHeightMultiplier = lineHeight,
            fontFamily = fontType,
            themePreset = themePreset,
            customBackgroundHex = customBg,
            customTextHex = customText,
            isJustified = isJustified,
            horizontalPaddingDp = paddingDp,
            viewMode = viewMode,
            isContinuousScroll = isContinuous
        )
    }

    fun updateFontSize(sizeSp: Float) {
        val clamped = sizeSp.coerceIn(12f, 36f)
        prefs.edit().putFloat(KEY_FONT_SIZE, clamped).apply()
        _settings.update { it.copy(fontSizeSp = clamped) }
    }

    fun updateLineHeight(multiplier: Float) {
        val clamped = multiplier.coerceIn(1.1f, 2.2f)
        prefs.edit().putFloat(KEY_LINE_HEIGHT, clamped).apply()
        _settings.update { it.copy(lineHeightMultiplier = clamped) }
    }

    fun updateFontFamily(fontFamily: FontFamilyType) {
        prefs.edit().putString(KEY_FONT_FAMILY, fontFamily.name).apply()
        _settings.update { it.copy(fontFamily = fontFamily) }
    }

    fun updateThemePreset(preset: ReaderThemePreset) {
        prefs.edit().putString(KEY_THEME_PRESET, preset.name).apply()
        _settings.update { it.copy(themePreset = preset) }
    }

    fun updateCustomColors(backgroundHex: Long, textHex: Long) {
        prefs.edit()
            .putLong(KEY_CUSTOM_BG, backgroundHex)
            .putLong(KEY_CUSTOM_TEXT, textHex)
            .putString(KEY_THEME_PRESET, ReaderThemePreset.CUSTOM.name)
            .apply()
        _settings.update {
            it.copy(
                themePreset = ReaderThemePreset.CUSTOM,
                customBackgroundHex = backgroundHex,
                customTextHex = textHex
            )
        }
    }

    fun updateJustification(isJustified: Boolean) {
        prefs.edit().putBoolean(KEY_IS_JUSTIFIED, isJustified).apply()
        _settings.update { it.copy(isJustified = isJustified) }
    }

    fun updatePadding(paddingDp: Int) {
        prefs.edit().putInt(KEY_PADDING_DP, paddingDp).apply()
        _settings.update { it.copy(horizontalPaddingDp = paddingDp) }
    }

    fun updateViewMode(viewMode: ViewMode) {
        prefs.edit().putString(KEY_VIEW_MODE, viewMode.name).apply()
        _settings.update { it.copy(viewMode = viewMode) }
    }

    fun updateContinuousScroll(isContinuous: Boolean) {
        prefs.edit().putBoolean(KEY_IS_CONTINUOUS, isContinuous).apply()
        _settings.update { it.copy(isContinuousScroll = isContinuous) }
    }

    companion object {
        private const val KEY_FONT_SIZE = "key_font_size"
        private const val KEY_LINE_HEIGHT = "key_line_height"
        private const val KEY_FONT_FAMILY = "key_font_family"
        private const val KEY_THEME_PRESET = "key_theme_preset"
        private const val KEY_CUSTOM_BG = "key_custom_bg"
        private const val KEY_CUSTOM_TEXT = "key_custom_text"
        private const val KEY_IS_JUSTIFIED = "key_is_justified"
        private const val KEY_PADDING_DP = "key_padding_dp"
        private const val KEY_VIEW_MODE = "key_view_mode"
        private const val KEY_IS_CONTINUOUS = "key_is_continuous"
    }
}
