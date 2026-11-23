package com.doctruyen.reader.ui.reader

import android.graphics.Bitmap
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.BookmarkBorder
import androidx.compose.material.icons.filled.ColorLens
import androidx.compose.material.icons.filled.FormatSize
import androidx.compose.material.icons.filled.Headphones
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.PictureAsPdf
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material.icons.filled.SwapVert
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.doctruyen.reader.data.model.FontFamilyType
import com.doctruyen.reader.data.model.PdfPageContent
import com.doctruyen.reader.data.model.ReaderSettings
import com.doctruyen.reader.data.model.ViewMode
import com.doctruyen.reader.tts.TtsState
import kotlinx.coroutines.flow.distinctUntilChanged

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReaderScreen(
    bookId: Long,
    viewModel: ReaderViewModel,
    onBack: () -> Unit
) {
    val book by viewModel.book.collectAsState()
    val settings by viewModel.settings.collectAsState()
    val currentPage by viewModel.currentPage.collectAsState()
    val cachedPages by viewModel.cachedPages.collectAsState()
    val isLoadingPage by viewModel.isLoadingPage.collectAsState()
    val bookmarks by viewModel.bookmarks.collectAsState()
    val outline by viewModel.outline.collectAsState()
    val ttsState by viewModel.ttsState.collectAsState()

    var controlsVisible by remember { mutableStateOf(true) }
    var showTypographySheet by remember { mutableStateOf(false) }
    var showThemeSheet by remember { mutableStateOf(false) }
    var showTocDialog by remember { mutableStateOf(false) }

    LaunchedEffect(bookId) {
        viewModel.loadBook(bookId)
    }

    BackHandler {
        viewModel.stopTts()
        onBack()
    }

    val totalPages = book?.pageCount ?: 1
    val isCurrentPageBookmarked = bookmarks.any { it.pageIndex == currentPage }

    // Color definitions from settings
    val activeBgColor = Color(settings.activeBackgroundColorHex)
    val activeTextColor = Color(settings.activeTextColorHex)

    val activeFontFamily = when (settings.fontFamily) {
        FontFamilyType.SYSTEM -> FontFamily.Default
        FontFamilyType.SERIF -> FontFamily.Serif
        FontFamilyType.SANS_SERIF -> FontFamily.SansSerif
        FontFamilyType.MONOSPACE -> FontFamily.Monospace
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(activeBgColor)
    ) {
        // Main reading content area
        Box(modifier = Modifier.fillMaxSize()) {
            androidx.compose.runtime.key(bookId) {
                if (settings.viewMode == ViewMode.REFLOW) {
                    if (settings.isContinuousScroll) {
                        // Continuous Vertical Scroll Mode
                        ContinuousReflowView(
                            bookId = bookId,
                            totalPages = totalPages,
                            cachedPages = cachedPages,
                            settings = settings,
                            textColor = activeTextColor,
                            fontFamily = activeFontFamily,
                            viewModel = viewModel,
                            currentPage = currentPage,
                            ttsState = ttsState,
                            onToggleControls = { controlsVisible = !controlsVisible }
                        )
                    } else {
                        // Page by Page with Swipe & Tap Gesture Navigation
                        SinglePageReflowView(
                            bookId = bookId,
                            pageContent = cachedPages[currentPage],
                            currentPage = currentPage,
                            totalPages = totalPages,
                            settings = settings,
                            textColor = activeTextColor,
                            fontFamily = activeFontFamily,
                            isLoading = isLoadingPage,
                            ttsState = ttsState,
                            onPrevPage = {
                                if (currentPage > 0) viewModel.onPageChanged(currentPage - 1)
                            },
                            onNextPage = {
                                if (currentPage < totalPages - 1) viewModel.onPageChanged(currentPage + 1)
                            },
                            onToggleControls = { controlsVisible = !controlsVisible }
                        )
                    }
                } else {
                    // Original Page View (Bitmaps)
                    OriginalPageView(
                        filePath = book?.filePath,
                        currentPage = currentPage,
                        totalPages = totalPages,
                        viewModel = viewModel,
                        onPrevPage = {
                            if (currentPage > 0) viewModel.onPageChanged(currentPage - 1)
                        },
                        onNextPage = {
                            if (currentPage < totalPages - 1) viewModel.onPageChanged(currentPage + 1)
                        },
                        onToggleControls = { controlsVisible = !controlsVisible }
                    )
                }
            }
        }

        // Animated Top App Bar (with statusBarsPadding to clear notch / camera cutout)
        AnimatedVisibility(
            visible = controlsVisible,
            enter = slideInVertically(initialOffsetY = { -it }) + fadeIn(),
            exit = slideOutVertically(targetOffsetY = { -it }) + fadeOut(),
            modifier = Modifier.align(Alignment.TopCenter)
        ) {
            Surface(
                color = MaterialTheme.colorScheme.surface.copy(alpha = 0.98f),
                shadowElevation = 6.dp,
                modifier = Modifier.fillMaxWidth()
            ) {
                Box(modifier = Modifier.statusBarsPadding()) {
                    TopAppBar(
                        title = {
                            Text(
                                text = book?.title ?: "Đang tải...",
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                fontSize = 17.sp,
                                fontWeight = FontWeight.SemiBold
                            )
                        },
                        navigationIcon = {
                            IconButton(onClick = {
                                viewModel.stopTts()
                                onBack()
                            }) {
                                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Trở về thư viện")
                            }
                        },
                        actions = {
                            // Switch between Reflow & Original view
                            IconButton(onClick = {
                                val newMode = if (settings.viewMode == ViewMode.REFLOW) ViewMode.ORIGINAL_PAGE else ViewMode.REFLOW
                                viewModel.setViewMode(newMode)
                            }) {
                                Icon(
                                    if (settings.viewMode == ViewMode.REFLOW) Icons.Default.PictureAsPdf else Icons.AutoMirrored.Filled.MenuBook,
                                    contentDescription = if (settings.viewMode == ViewMode.REFLOW) "Xem trang gốc" else "Chế độ đọc chữ"
                                )
                            }

                            // TTS Audiobook reading
                            IconButton(onClick = { viewModel.toggleTts() }) {
                                Icon(
                                    Icons.Default.Headphones,
                                    contentDescription = if (ttsState.isPlaying) "Tạm dừng đọc TTS" else "Nghe sách nói (TTS)",
                                    tint = if (ttsState.isPlaying) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface
                                )
                            }

                            // Bookmark current page
                            IconButton(onClick = {
                                viewModel.addBookmarkForCurrentPage()
                            }) {
                                Icon(
                                    if (isCurrentPageBookmarked) Icons.Default.Bookmark else Icons.Default.BookmarkBorder,
                                    contentDescription = "Đánh dấu trang",
                                    tint = if (isCurrentPageBookmarked) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface
                                )
                            }

                            // Table of Contents
                            IconButton(onClick = { showTocDialog = true }) {
                                Icon(Icons.AutoMirrored.Filled.List, contentDescription = "Mục lục")
                            }
                        },
                        colors = TopAppBarDefaults.topAppBarColors(
                            containerColor = Color.Transparent
                        )
                    )
                }
            }
        }

        // Animated Bottom Control Bar (with navigationBarsPadding to CLEAR 3 system buttons!)
        AnimatedVisibility(
            visible = controlsVisible && !ttsState.isPlaying && !ttsState.isPaused,
            enter = slideInVertically(initialOffsetY = { it }) + fadeIn(),
            exit = slideOutVertically(targetOffsetY = { it }) + fadeOut(),
            modifier = Modifier.align(Alignment.BottomCenter)
        ) {
            Surface(
                color = MaterialTheme.colorScheme.surface.copy(alpha = 0.98f),
                shadowElevation = 12.dp,
                shape = RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .navigationBarsPadding() // FIX: Pushes controls above 3 Android system navigation buttons!
                        .padding(horizontal = 20.dp, vertical = 10.dp)
                ) {
                    // Page progress info (Clean & compact, no slider)
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(bottom = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text(
                            text = "Trang ${currentPage + 1} / $totalPages",
                            fontWeight = FontWeight.SemiBold,
                            fontSize = 13.sp,
                            color = MaterialTheme.colorScheme.primary
                        )
                        val progressPercent = if (totalPages > 0) ((currentPage + 1) * 100 / totalPages) else 0
                        Text(
                            text = "$progressPercent%",
                            fontSize = 12.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }

                    // Action buttons: Typography (Aa), Theme (Color), View Mode, Scroll Mode
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceEvenly,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        FilledTonalIconButton(onClick = { showTypographySheet = true }) {
                            Icon(Icons.Default.FormatSize, contentDescription = "Cỡ chữ & Font")
                        }

                        FilledTonalIconButton(onClick = { showThemeSheet = true }) {
                            Icon(Icons.Default.ColorLens, contentDescription = "Màu nền & Màu chữ")
                        }

                        FilledTonalIconButton(onClick = { showTocDialog = true }) {
                            Icon(Icons.AutoMirrored.Filled.List, contentDescription = "Mục lục & Đánh dấu")
                        }

                        FilledTonalIconButton(onClick = {
                            val newMode = if (settings.viewMode == ViewMode.REFLOW) ViewMode.ORIGINAL_PAGE else ViewMode.REFLOW
                            viewModel.setViewMode(newMode)
                        }) {
                            Icon(Icons.Default.Layers, contentDescription = "Đổi chế độ xem")
                        }

                        // Quick Toggle: Cuộn dọc liên tục vs Lật từng trang
                        FilledTonalIconButton(onClick = {
                            viewModel.setContinuousScroll(!settings.isContinuousScroll)
                        }) {
                            Icon(
                                if (settings.isContinuousScroll) Icons.Default.SwapVert else Icons.Default.SwapHoriz,
                                contentDescription = if (settings.isContinuousScroll) "Đang cuộn dọc" else "Đang lật trang",
                                tint = MaterialTheme.colorScheme.primary
                            )
                        }
                    }
                }
            }
        }

        // TTS Floating Audio Player (Shows when playing or paused)
        TtsPlayerBar(
            ttsState = ttsState,
            onTogglePlay = { viewModel.toggleTts() },
            onPrevious = { viewModel.previousTtsParagraph() },
            onNext = { viewModel.nextTtsParagraph() },
            onStop = { viewModel.stopTts() },
            onSetSpeed = { viewModel.setTtsSpeechRate(it) },
            modifier = Modifier.align(Alignment.BottomCenter)
        )
    }

    // Bottom Sheets & Dialogs
    if (showTypographySheet) {
        TypographyBottomSheet(
            settings = settings,
            onFontSizeChange = { viewModel.setFontSize(it) },
            onLineHeightChange = { viewModel.setLineHeight(it) },
            onFontFamilyChange = { viewModel.setFontFamily(it) },
            onJustifyChange = { viewModel.setJustified(it) },
            onPaddingChange = { viewModel.setPadding(it) },
            onContinuousScrollChange = { viewModel.setContinuousScroll(it) },
            onDismiss = { showTypographySheet = false }
        )
    }

    if (showThemeSheet) {
        ThemeBottomSheet(
            settings = settings,
            onPresetSelect = { viewModel.setThemePreset(it) },
            onCustomColorsChange = { bg, text ->
                viewModel.setCustomColors(bg, text)
            },
            onDismiss = { showThemeSheet = false }
        )
    }

    if (showTocDialog) {
        TableOfContentsDialog(
            outline = outline,
            bookmarks = bookmarks,
            totalPageCount = totalPages,
            currentPage = currentPage,
            onSelectPage = { pageIdx ->
                viewModel.onPageChanged(pageIdx)
            },
            onDeleteBookmark = { bmId ->
                viewModel.deleteBookmark(bmId)
            },
            onDismiss = { showTocDialog = false }
        )
    }
}

/**
 * Page-by-page reader with:
 * 1. Horizontal swipe gesture (vuốt qua để sang trang)
 * 2. Tap zones (chạm phải sang trang, chạm trái về trước, chạm giữa mở menu)
 * 3. End-of-page interactive card (tự next khi cuộn hết)
 */
@Composable
private fun SinglePageReflowView(
    bookId: Long,
    pageContent: PdfPageContent?,
    currentPage: Int,
    totalPages: Int,
    settings: ReaderSettings,
    textColor: Color,
    fontFamily: FontFamily,
    isLoading: Boolean,
    ttsState: TtsState,
    onPrevPage: () -> Unit,
    onNextPage: () -> Unit,
    onToggleControls: () -> Unit
) {
    val listState = remember(bookId, currentPage) { androidx.compose.foundation.lazy.LazyListState() }
    var dragDistanceX by remember { mutableFloatStateOf(0f) }

    // Reset scroll when page changes
    LaunchedEffect(bookId, currentPage) {
        listState.scrollToItem(0)
    }

    // Auto-scroll to follow TTS speech cursor
    LaunchedEffect(ttsState.currentPage, ttsState.currentParagraphIndex) {
        if ((ttsState.isPlaying || ttsState.isPaused) &&
            ttsState.currentPage == currentPage &&
            ttsState.currentParagraphIndex >= 0
        ) {
            val itemIndex = ttsState.currentParagraphIndex + 1
            listState.animateScrollToItem(itemIndex.coerceAtLeast(0))
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            // 1. Horizontal Swipe Gesture to turn page
            .pointerInput(currentPage) {
                detectHorizontalDragGestures(
                    onDragEnd = {
                        if (dragDistanceX < -60f) {
                            onNextPage()
                        } else if (dragDistanceX > 60f) {
                            onPrevPage()
                        }
                        dragDistanceX = 0f
                    },
                    onHorizontalDrag = { _, dragAmount ->
                        dragDistanceX += dragAmount
                    }
                )
            }
            // 2. Tap Zones: Left 22% = Prev, Right 22% = Next, Middle 56% = Toggle Menu
            .pointerInput(Unit) {
                detectTapGestures(
                    onTap = { offset ->
                        val screenWidth = size.width
                        val x = offset.x
                        when {
                            x < screenWidth * 0.22f -> onPrevPage()
                            x > screenWidth * 0.78f -> onNextPage()
                            else -> onToggleControls()
                        }
                    }
                )
            }
    ) {
        LazyColumn(
            state = listState,
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = settings.horizontalPaddingDp.dp)
        ) {
            // Header spacing so content is not obscured by top bar
            item {
                Spacer(modifier = Modifier.height(76.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = "Trang ${currentPage + 1} / $totalPages",
                        fontSize = 11.sp,
                        color = textColor.copy(alpha = 0.5f),
                        fontFamily = fontFamily
                    )
                    Text(
                        text = "Vuốt hoặc chạm mép để lật trang",
                        fontSize = 11.sp,
                        color = textColor.copy(alpha = 0.5f),
                        fontFamily = fontFamily
                    )
                }
                Spacer(modifier = Modifier.height(16.dp))
            }

            if (pageContent != null && pageContent.paragraphs.isNotEmpty()) {
                items(pageContent.paragraphs.size) { pIndex ->
                    val paragraph = pageContent.paragraphs[pIndex]
                    val isSpeaking = (ttsState.isPlaying || ttsState.isPaused) &&
                            ttsState.currentPage == currentPage &&
                            ttsState.currentParagraphIndex == pIndex

                    Text(
                        text = paragraph,
                        color = if (isSpeaking) MaterialTheme.colorScheme.primary else textColor,
                        fontWeight = if (isSpeaking) FontWeight.SemiBold else FontWeight.Normal,
                        fontSize = settings.fontSizeSp.sp,
                        lineHeight = (settings.fontSizeSp * settings.lineHeightMultiplier).sp,
                        fontFamily = fontFamily,
                        textAlign = if (settings.isJustified) TextAlign.Justify else TextAlign.Start,
                        modifier = Modifier
                            .fillMaxWidth()
                            .then(
                                if (isSpeaking) Modifier
                                    .background(
                                        MaterialTheme.colorScheme.primary.copy(alpha = 0.12f),
                                        shape = RoundedCornerShape(8.dp)
                                    )
                                    .padding(horizontal = 8.dp, vertical = 4.dp)
                                else Modifier
                            )
                            .padding(bottom = (settings.fontSizeSp * 0.7f).dp)
                    )
                }
            } else if (!isLoading) {
                item {
                    Box(
                        contentAlignment = Alignment.Center,
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(280.dp)
                    ) {
                        Text(
                            text = "Trang này không có văn bản hoặc là file scan.\n(Bạn có thể bấm biểu tượng PDF ở góc trên để xem ảnh gốc)",
                            textAlign = TextAlign.Center,
                            color = textColor.copy(alpha = 0.6f),
                            fontSize = 14.sp
                        )
                    }
                }
            }

            // End-of-page interactive card: Quick-next when reaching bottom of page!
            if (currentPage < totalPages - 1) {
                item {
                    Spacer(modifier = Modifier.height(16.dp))
                    Card(
                        onClick = onNextPage,
                        colors = CardDefaults.cardColors(
                            containerColor = textColor.copy(alpha = 0.08f)
                        ),
                        shape = RoundedCornerShape(12.dp),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(16.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.Center
                        ) {
                            Text(
                                text = "Hết trang ${currentPage + 1} • Chạm để sang Trang ${currentPage + 2}",
                                color = textColor,
                                fontWeight = FontWeight.Bold,
                                fontSize = 14.sp
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Icon(
                                Icons.AutoMirrored.Filled.ArrowForward,
                                contentDescription = null,
                                tint = textColor,
                                modifier = Modifier.size(18.dp)
                            )
                        }
                    }
                }
            }

            // Bottom navigation arrows & padding
            item {
                Spacer(modifier = Modifier.height(20.dp))
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(bottom = 120.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    if (currentPage > 0) {
                        Surface(
                            onClick = onPrevPage,
                            shape = RoundedCornerShape(20.dp),
                            color = textColor.copy(alpha = 0.12f)
                        ) {
                            Row(
                                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(
                                    Icons.AutoMirrored.Filled.ArrowBack,
                                    contentDescription = null,
                                    tint = textColor,
                                    modifier = Modifier.size(16.dp)
                                )
                                Spacer(modifier = Modifier.width(6.dp))
                                Text("Trang trước", color = textColor, fontSize = 13.sp)
                            }
                        }
                    } else {
                        Spacer(modifier = Modifier.width(1.dp))
                    }

                    if (currentPage < totalPages - 1) {
                        Surface(
                            onClick = onNextPage,
                            shape = RoundedCornerShape(20.dp),
                            color = textColor.copy(alpha = 0.12f)
                        ) {
                            Row(
                                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text("Trang sau", color = textColor, fontSize = 13.sp)
                                Spacer(modifier = Modifier.width(6.dp))
                                Icon(
                                    Icons.AutoMirrored.Filled.ArrowForward,
                                    contentDescription = null,
                                    tint = textColor,
                                    modifier = Modifier.size(16.dp)
                                )
                            }
                        }
                    }
                }
            }
        }

        if (isLoading) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier.fillMaxSize()
            ) {
                CircularProgressIndicator(color = textColor.copy(alpha = 0.8f))
            }
        }
    }
}

/**
 * Continuous Vertical Scroll reader:
 * All pages flow seamlessly one after another.
 * Automatically saves reading progress as user scrolls down!
 */
@Composable
private fun ContinuousReflowView(
    bookId: Long,
    totalPages: Int,
    cachedPages: Map<Int, PdfPageContent>,
    settings: ReaderSettings,
    textColor: Color,
    fontFamily: FontFamily,
    viewModel: ReaderViewModel,
    currentPage: Int,
    ttsState: TtsState,
    onToggleControls: () -> Unit
) {
    val listState = remember(bookId) {
        androidx.compose.foundation.lazy.LazyListState(
            firstVisibleItemIndex = currentPage.coerceIn(0, (totalPages - 1).coerceAtLeast(0))
        )
    }

    // Follow TTS page changes in continuous mode
    LaunchedEffect(ttsState.currentPage) {
        if ((ttsState.isPlaying || ttsState.isPaused) && ttsState.currentPage in 0 until totalPages) {
            listState.animateScrollToItem(ttsState.currentPage)
        }
    }

    // Automatically update current page and pre-load adjacent pages as the user scrolls
    LaunchedEffect(listState, bookId) {
        snapshotFlow { listState.firstVisibleItemIndex }
            .distinctUntilChanged()
            .collect { visibleIndex ->
                val safeIndex = visibleIndex.coerceIn(0, (totalPages - 1).coerceAtLeast(0))
                if (safeIndex != currentPage) {
                    viewModel.onPageChanged(safeIndex)
                }
                viewModel.loadPageContent(safeIndex)
                viewModel.loadPageContent(safeIndex + 1)
            }
    }

    LazyColumn(
        state = listState,
        contentPadding = androidx.compose.foundation.layout.PaddingValues(top = 76.dp, bottom = 140.dp),
        modifier = Modifier
            .fillMaxSize()
            .pointerInput(Unit) {
                detectTapGestures(onTap = { onToggleControls() })
            }
            .padding(horizontal = settings.horizontalPaddingDp.dp)
    ) {
        items(totalPages) { pageIdx ->
            val page = cachedPages[pageIdx]

            // Elegant page divider between pages
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 16.dp),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "─── Trang ${pageIdx + 1} / $totalPages ───",
                    fontSize = 12.sp,
                    color = textColor.copy(alpha = 0.5f),
                    fontFamily = fontFamily,
                    fontWeight = FontWeight.Medium
                )
            }

            if (page != null && page.paragraphs.isNotEmpty()) {
                for ((pIndex, paragraph) in page.paragraphs.withIndex()) {
                    val isSpeaking = (ttsState.isPlaying || ttsState.isPaused) &&
                            ttsState.currentPage == pageIdx &&
                            ttsState.currentParagraphIndex == pIndex

                    Text(
                        text = paragraph,
                        color = if (isSpeaking) MaterialTheme.colorScheme.primary else textColor,
                        fontWeight = if (isSpeaking) FontWeight.SemiBold else FontWeight.Normal,
                        fontSize = settings.fontSizeSp.sp,
                        lineHeight = (settings.fontSizeSp * settings.lineHeightMultiplier).sp,
                        fontFamily = fontFamily,
                        textAlign = if (settings.isJustified) TextAlign.Justify else TextAlign.Start,
                        modifier = Modifier
                            .fillMaxWidth()
                            .then(
                                if (isSpeaking) Modifier
                                    .background(
                                        MaterialTheme.colorScheme.primary.copy(alpha = 0.12f),
                                        shape = RoundedCornerShape(8.dp)
                                    )
                                    .padding(horizontal = 8.dp, vertical = 4.dp)
                                else Modifier
                            )
                            .padding(bottom = (settings.fontSizeSp * 0.7f).dp)
                    )
                }
            } else {
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 24.dp)
                ) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(24.dp),
                        color = textColor.copy(alpha = 0.6f)
                    )
                }
            }
        }

        item {
            Spacer(modifier = Modifier.height(140.dp))
        }
    }
}

@Composable
private fun OriginalPageView(
    filePath: String?,
    currentPage: Int,
    totalPages: Int,
    viewModel: ReaderViewModel,
    onPrevPage: () -> Unit,
    onNextPage: () -> Unit,
    onToggleControls: () -> Unit
) {
    val configuration = LocalConfiguration.current
    val density = LocalDensity.current
    val screenWidthPx = with(density) { configuration.screenWidthDp.dp.roundToPx() }

    var bitmap by remember { mutableStateOf<Bitmap?>(null) }
    var isLoading by remember { mutableStateOf(true) }

    var scale by remember { mutableFloatStateOf(1f) }
    var offsetX by remember { mutableFloatStateOf(0f) }
    var offsetY by remember { mutableFloatStateOf(0f) }

    var dragX by remember { mutableFloatStateOf(0f) }

    LaunchedEffect(filePath, currentPage) {
        if (!filePath.isNullOrEmpty()) {
            isLoading = true
            scale = 1f
            offsetX = 0f
            offsetY = 0f
            bitmap = viewModel.renderOriginalPage(currentPage, (screenWidthPx * 1.5f).toInt())
            isLoading = false
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .pointerInput(Unit) {
                detectTapGestures(
                    onTap = { offset ->
                        val screenWidth = size.width
                        val x = offset.x
                        when {
                            x < screenWidth * 0.22f -> onPrevPage()
                            x > screenWidth * 0.78f -> onNextPage()
                            else -> onToggleControls()
                        }
                    }
                )
            }
            .pointerInput(currentPage) {
                detectHorizontalDragGestures(
                    onDragEnd = {
                        if (scale <= 1.05f) {
                            if (dragX < -60f) onNextPage()
                            else if (dragX > 60f) onPrevPage()
                        }
                        dragX = 0f
                    },
                    onHorizontalDrag = { _, dragAmount ->
                        if (scale <= 1.05f) {
                            dragX += dragAmount
                        }
                    }
                )
            }
            .pointerInput(Unit) {
                detectTransformGestures { _, pan, zoom, _ ->
                    scale = (scale * zoom).coerceIn(1f, 4f)
                    if (scale > 1f) {
                        offsetX += pan.x
                        offsetY += pan.y
                    } else {
                        offsetX = 0f
                        offsetY = 0f
                    }
                }
            }
    ) {
        if (bitmap != null) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(vertical = 60.dp)
            ) {
                Image(
                    bitmap = bitmap!!.asImageBitmap(),
                    contentDescription = "Trang $currentPage",
                    contentScale = ContentScale.Fit,
                    modifier = Modifier
                        .fillMaxSize()
                        .graphicsLayer(
                            scaleX = scale,
                            scaleY = scale,
                            translationX = offsetX,
                            translationY = offsetY
                        )
                )
            }
        } else if (isLoading) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier.fillMaxSize()
            ) {
                CircularProgressIndicator()
            }
        } else {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier.fillMaxSize()
            ) {
                Text("Không thể tải trang gốc của PDF")
            }
        }
    }
}
