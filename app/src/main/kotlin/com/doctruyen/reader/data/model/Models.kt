package com.doctruyen.reader.data.model

data class Book(
    val id: Long = 0,
    val title: String,
    val uri: String,
    val filePath: String,
    val pageCount: Int,
    val lastReadPage: Int = 0,
    val lastReadOffset: Float = 0f,
    val coverPath: String? = null,
    val lastReadTime: Long = System.currentTimeMillis(),
    val fileSize: Long = 0L
)

data class Bookmark(
    val id: Long = 0,
    val bookId: Long,
    val pageIndex: Int,
    val title: String,
    val timestamp: Long = System.currentTimeMillis()
)

data class PdfPageContent(
    val pageIndex: Int,
    val paragraphs: List<String>,
    val rawText: String
)

enum class FontFamilyType(val displayName: String) {
    SYSTEM("Hệ thống"),
    SERIF("Serif (Sách)"),
    SANS_SERIF("Sans-Serif"),
    MONOSPACE("Monospace")
}

enum class ReaderThemePreset(
    val displayName: String,
    val backgroundHex: Long,
    val textHex: Long
) {
    SEPIA("Giấy ngà", 0xFFFBF0D9, 0xFF3C3836),
    OLED("OLED Đen", 0xFF000000, 0xFFE0E0E0),
    WARM_DARK("Đêm ấm", 0xFF1C1C1E, 0xFFD6CDBF),
    PAPER_WHITE("Trắng giấy", 0xFFFAFAFA, 0xFF1A1A1A),
    EYE_CARE("Xanh dịu", 0xFFE4F0E8, 0xFF2D3E33),
    CUSTOM("Tự chọn", 0xFFFBF0D9, 0xFF3C3836)
}

enum class ViewMode {
    REFLOW,
    ORIGINAL_PAGE
}

data class ReaderSettings(
    val fontSizeSp: Float = 18f,
    val lineHeightMultiplier: Float = 1.5f,
    val fontFamily: FontFamilyType = FontFamilyType.SERIF,
    val themePreset: ReaderThemePreset = ReaderThemePreset.SEPIA,
    val customBackgroundHex: Long = 0xFFFBF0D9,
    val customTextHex: Long = 0xFF3C3836,
    val isJustified: Boolean = true,
    val horizontalPaddingDp: Int = 16,
    val viewMode: ViewMode = ViewMode.REFLOW,
    val isContinuousScroll: Boolean = true
) {
    val activeBackgroundColorHex: Long
        get() = if (themePreset == ReaderThemePreset.CUSTOM) customBackgroundHex else themePreset.backgroundHex

    val activeTextColorHex: Long
        get() = if (themePreset == ReaderThemePreset.CUSTOM) customTextHex else themePreset.textHex
}
