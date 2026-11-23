package com.doctruyen.reader.ui.reader

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.FormatAlignLeft
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.FormatAlignJustify
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material.icons.filled.SwapVert
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.doctruyen.reader.data.model.FontFamilyType
import com.doctruyen.reader.data.model.ReaderSettings
import com.doctruyen.reader.data.model.ReaderThemePreset

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TypographyBottomSheet(
    settings: ReaderSettings,
    onFontSizeChange: (Float) -> Unit,
    onLineHeightChange: (Float) -> Unit,
    onFontFamilyChange: (FontFamilyType) -> Unit,
    onJustifyChange: (Boolean) -> Unit,
    onPaddingChange: (Int) -> Unit,
    onContinuousScrollChange: (Boolean) -> Unit,
    onDismiss: () -> Unit
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = MaterialTheme.colorScheme.surface
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(horizontal = 24.dp, vertical = 12.dp)
        ) {
            Text(
                text = "Tùy chỉnh Văn bản & Phông chữ",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold
            )

            Spacer(modifier = Modifier.height(16.dp))

            // 1. Cỡ chữ (Font size)
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("Cỡ chữ", fontWeight = FontWeight.SemiBold)
                Text("${settings.fontSizeSp.toInt()} sp", color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Bold)
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth()
            ) {
                IconButton(
                    onClick = { onFontSizeChange(settings.fontSizeSp - 1f) },
                    enabled = settings.fontSizeSp > 12f
                ) {
                    Text("A-", fontSize = 14.sp, fontWeight = FontWeight.Bold)
                }

                Slider(
                    value = settings.fontSizeSp,
                    onValueChange = onFontSizeChange,
                    valueRange = 12f..36f,
                    steps = 23,
                    modifier = Modifier.weight(1f)
                )

                IconButton(
                    onClick = { onFontSizeChange(settings.fontSizeSp + 1f) },
                    enabled = settings.fontSizeSp < 36f
                ) {
                    Text("A+", fontSize = 20.sp, fontWeight = FontWeight.Bold)
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            // 2. Khoảng cách dòng (Line height)
            Text("Khoảng cách dòng", fontWeight = FontWeight.SemiBold)
            Spacer(modifier = Modifier.height(6.dp))
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                val heights = listOf(1.2f, 1.4f, 1.6f, 1.8f, 2.0f)
                for (h in heights) {
                    FilterChip(
                        selected = kotlin.math.abs(settings.lineHeightMultiplier - h) < 0.05f,
                        onClick = { onLineHeightChange(h) },
                        label = { Text("${h}x") }
                    )
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            // 3. Phông chữ (Font family)
            Text("Phông chữ", fontWeight = FontWeight.SemiBold)
            Spacer(modifier = Modifier.height(6.dp))
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                for (font in FontFamilyType.values()) {
                    FilterChip(
                        selected = settings.fontFamily == font,
                        onClick = { onFontFamilyChange(font) },
                        label = { Text(font.displayName) }
                    )
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            // 4. Căn lề & Lề trang
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text("Căn lề chữ", fontWeight = FontWeight.SemiBold)
                    Text(
                        if (settings.isJustified) "Căn đều 2 bên" else "Căn trái",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(
                        selected = settings.isJustified,
                        onClick = { onJustifyChange(true) },
                        label = { Icon(Icons.Default.FormatAlignJustify, contentDescription = "Căn đều") }
                    )
                    FilterChip(
                        selected = !settings.isJustified,
                        onClick = { onJustifyChange(false) },
                        label = { Icon(Icons.AutoMirrored.Filled.FormatAlignLeft, contentDescription = "Căn trái") }
                    )
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            // Kiểu chuyển trang (Lật trang vs Cuộn liên tục)
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text("Kiểu đọc", fontWeight = FontWeight.SemiBold)
                    Text(
                        if (settings.isContinuousScroll) "Cuộn liên tục (Dọc)" else "Lật trang (Vuốt ngang)",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(
                        selected = !settings.isContinuousScroll,
                        onClick = { onContinuousScrollChange(false) },
                        label = {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Default.SwapHoriz, contentDescription = null, modifier = Modifier.size(16.dp))
                                Spacer(modifier = Modifier.width(4.dp))
                                Text("Lật trang")
                            }
                        }
                    )
                    FilterChip(
                        selected = settings.isContinuousScroll,
                        onClick = { onContinuousScrollChange(true) },
                        label = {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Default.SwapVert, contentDescription = null, modifier = Modifier.size(16.dp))
                                Spacer(modifier = Modifier.width(4.dp))
                                Text("Cuộn dọc")
                            }
                        }
                    )
                }
            }

            Spacer(modifier = Modifier.height(8.dp))

            // Lề mép màn hình
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("Lề mép màn hình", fontWeight = FontWeight.SemiBold)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    val paddings = listOf(8 to "Hẹp", 16 to "Vừa", 24 to "Rộng")
                    for ((pad, label) in paddings) {
                        FilterChip(
                            selected = settings.horizontalPaddingDp == pad,
                            onClick = { onPaddingChange(pad) },
                            label = { Text(label) }
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(20.dp))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ThemeBottomSheet(
    settings: ReaderSettings,
    onPresetSelect: (ReaderThemePreset) -> Unit,
    onCustomColorsChange: (Long, Long) -> Unit,
    onDismiss: () -> Unit
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = MaterialTheme.colorScheme.surface
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(horizontal = 24.dp, vertical = 12.dp)
        ) {
            Text(
                text = "Màu nền & Màu chữ",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold
            )

            Spacer(modifier = Modifier.height(16.dp))

            // Theme Presets
            Text("Chủ đề tuyển chọn", fontWeight = FontWeight.SemiBold)
            Spacer(modifier = Modifier.height(10.dp))

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                val presets = listOf(
                    ReaderThemePreset.SEPIA,
                    ReaderThemePreset.OLED,
                    ReaderThemePreset.WARM_DARK,
                    ReaderThemePreset.PAPER_WHITE,
                    ReaderThemePreset.EYE_CARE
                )

                for (preset in presets) {
                    val isSelected = settings.themePreset == preset
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        modifier = Modifier
                            .clickable { onPresetSelect(preset) }
                            .padding(4.dp)
                    ) {
                        Box(
                            contentAlignment = Alignment.Center,
                            modifier = Modifier
                                .size(52.dp)
                                .clip(CircleShape)
                                .background(Color(preset.backgroundHex))
                                .border(
                                    width = if (isSelected) 3.dp else 1.dp,
                                    color = if (isSelected) MaterialTheme.colorScheme.primary else Color.Gray.copy(alpha = 0.5f),
                                    shape = CircleShape
                                )
                        ) {
                            Text(
                                "Aa",
                                color = Color(preset.textHex),
                                fontWeight = FontWeight.Bold,
                                fontSize = 16.sp
                            )
                        }
                        Spacer(modifier = Modifier.height(6.dp))
                        Text(
                            text = preset.displayName,
                            fontSize = 12.sp,
                            fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal,
                            color = if (isSelected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(18.dp))

            // Custom Color Palette
            Text("Tùy biến tự do (Custom Color)", fontWeight = FontWeight.SemiBold)
            Spacer(modifier = Modifier.height(8.dp))

            Text("Chọn màu nền:", style = MaterialTheme.typography.bodySmall)
            Spacer(modifier = Modifier.height(6.dp))
            val bgColors = listOf(
                0xFFFBF0D9 to "Sepia",
                0xFF000000 to "OLED",
                0xFF1C1C1E to "Đêm",
                0xFFFFFFFF to "Trắng",
                0xFFE4F0E8 to "Xanh dịu",
                0xFFFFF9C4 to "Vàng nhạt",
                0xFFF3E5F5 to "Tím nhạt",
                0xFFE0F2F1 to "Xanh ngọc"
            )
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                for ((hex, name) in bgColors) {
                    val isCurrent = settings.activeBackgroundColorHex == hex
                    Box(
                        contentAlignment = Alignment.Center,
                        modifier = Modifier
                            .size(38.dp)
                            .clip(CircleShape)
                            .background(Color(hex))
                            .border(
                                width = if (isCurrent) 2.5.dp else 1.dp,
                                color = if (isCurrent) MaterialTheme.colorScheme.primary else Color.Gray.copy(alpha = 0.4f),
                                shape = CircleShape
                            )
                            .clickable {
                                onCustomColorsChange(hex, settings.activeTextColorHex)
                            }
                    ) {
                        if (isCurrent) {
                            Icon(
                                Icons.Default.Check,
                                contentDescription = null,
                                tint = if (hex == 0xFF000000L || hex == 0xFF1C1C1EL) Color.White else Color.Black,
                                modifier = Modifier.size(18.dp)
                            )
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            Text("Chọn màu chữ:", style = MaterialTheme.typography.bodySmall)
            Spacer(modifier = Modifier.height(6.dp))
            val textColors = listOf(
                0xFF3C3836 to "Xám than",
                0xFFE0E0E0 to "Bạc sáng",
                0xFF000000 to "Đen tuyền",
                0xFFD6CDBF to "Vàng ngà",
                0xFFFFFFFF to "Trắng",
                0xFF2D3E33 to "Xanh lá đậm",
                0xFF1A237E to "Xanh tím than",
                0xFF4E342E to "Nâu đậm"
            )
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                for ((hex, name) in textColors) {
                    val isCurrent = settings.activeTextColorHex == hex
                    Box(
                        contentAlignment = Alignment.Center,
                        modifier = Modifier
                            .size(38.dp)
                            .clip(CircleShape)
                            .background(Color(hex))
                            .border(
                                width = if (isCurrent) 2.5.dp else 1.dp,
                                color = if (isCurrent) MaterialTheme.colorScheme.primary else Color.Gray.copy(alpha = 0.4f),
                                shape = CircleShape
                            )
                            .clickable {
                                onCustomColorsChange(settings.activeBackgroundColorHex, hex)
                            }
                    ) {
                        if (isCurrent) {
                            Icon(
                                Icons.Default.Check,
                                contentDescription = null,
                                tint = if (hex == 0xFF000000L || hex == 0xFF3C3836L) Color.White else Color.Black,
                                modifier = Modifier.size(18.dp)
                            )
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Preview Box
            Surface(
                color = Color(settings.activeBackgroundColorHex),
                shape = RoundedCornerShape(12.dp),
                border = androidx.compose.foundation.BorderStroke(1.dp, Color.Gray.copy(alpha = 0.3f)),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text(
                        text = "Xem trước văn bản đọc thử:",
                        fontSize = 12.sp,
                        color = Color(settings.activeTextColorHex).copy(alpha = 0.7f)
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = "Màu nền êm dịu kết hợp màu chữ tương phản vừa phải giúp mắt bạn thư giãn tối đa khi đọc truyện hàng giờ liền.",
                        color = Color(settings.activeTextColorHex),
                        fontSize = 15.sp,
                        lineHeight = 22.sp
                    )
                }
            }

            Spacer(modifier = Modifier.height(16.dp))
        }
    }
}
