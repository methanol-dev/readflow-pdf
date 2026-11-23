package com.doctruyen.reader.ui.reader

import android.app.Application
import android.graphics.Bitmap
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.doctruyen.reader.data.BookRepository
import com.doctruyen.reader.data.SettingsRepository
import com.doctruyen.reader.data.model.Book
import com.doctruyen.reader.data.model.Bookmark
import com.doctruyen.reader.data.model.FontFamilyType
import com.doctruyen.reader.data.model.PdfPageContent
import com.doctruyen.reader.data.model.ReaderSettings
import com.doctruyen.reader.data.model.ReaderThemePreset
import com.doctruyen.reader.data.model.ViewMode
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class ReaderViewModel(application: Application) : AndroidViewModel(application) {

    private val bookRepository = BookRepository(application)
    private val settingsRepository = SettingsRepository(application)

    val settings: StateFlow<ReaderSettings> = settingsRepository.settings

    private val _book = MutableStateFlow<Book?>(null)
    val book: StateFlow<Book?> = _book.asStateFlow()

    private val _currentPage = MutableStateFlow(0)
    val currentPage: StateFlow<Int> = _currentPage.asStateFlow()

    private val _isLoadingPage = MutableStateFlow(false)
    val isLoadingPage: StateFlow<Boolean> = _isLoadingPage.asStateFlow()

    // Cache of extracted pages for fast scrolling
    private val pageCache = mutableMapOf<Int, PdfPageContent>()
    private val _cachedPages = MutableStateFlow<Map<Int, PdfPageContent>>(emptyMap())
    val cachedPages: StateFlow<Map<Int, PdfPageContent>> = _cachedPages.asStateFlow()

    private val _bookmarks = MutableStateFlow<List<Bookmark>>(emptyList())
    val bookmarks: StateFlow<List<Bookmark>> = _bookmarks.asStateFlow()

    private val _outline = MutableStateFlow<List<Pair<String, Int>>>(emptyList())
    val outline: StateFlow<List<Pair<String, Int>>> = _outline.asStateFlow()

    fun loadBook(bookId: Long) {
        // If already loaded in this ViewModel, don't re-trigger anything
        if (_book.value?.id == bookId && _cachedPages.value.isNotEmpty()) {
            return
        }

        // Reset previous book state to prevent remembering/showing the wrong book!
        pageCache.clear()
        _cachedPages.value = emptyMap()
        _bookmarks.value = emptyList()
        _outline.value = emptyList()
        _isLoadingPage.value = false

        viewModelScope.launch {
            val loaded = bookRepository.getBook(bookId) ?: return@launch
            _book.value = loaded
            _currentPage.value = loaded.lastReadPage

            // 1. Immediately load all cached pages from DB/RAM specifically for THIS book
            val cached = bookRepository.loadCachedPagesFromDb(bookId)
            if (cached.isNotEmpty()) {
                pageCache.putAll(cached)
                _cachedPages.value = pageCache.toMap()
            }

            // 2. Only show loading spinner if current page is truly not yet extracted
            if (!pageCache.containsKey(loaded.lastReadPage)) {
                loadPageContent(loaded.lastReadPage)
            }

            // Preload adjacent pages in background
            preloadAdjacentPages(loaded.lastReadPage, loaded.pageCount)

            // Load bookmarks & outline in background
            _bookmarks.value = bookRepository.getBookmarks(bookId)
            _outline.value = bookRepository.getOutline(loaded.filePath)
        }
    }

    fun onPageChanged(pageIndex: Int) {
        val currentBook = _book.value ?: return
        val clamped = pageIndex.coerceIn(0, (currentBook.pageCount - 1).coerceAtLeast(0))
        _currentPage.value = clamped

        // Save progress to database
        viewModelScope.launch {
            bookRepository.updateProgress(currentBook.id, clamped)
        }

        loadPageContent(clamped)
        preloadAdjacentPages(clamped, currentBook.pageCount)
    }

    fun loadPageContent(pageIndex: Int) {
        val currentBook = _book.value ?: return
        if (pageIndex < 0 || pageIndex >= currentBook.pageCount) return

        if (pageCache.containsKey(pageIndex)) return

        viewModelScope.launch {
            if (_currentPage.value == pageIndex) {
                _isLoadingPage.value = true
            }
            try {
                val content = bookRepository.getPageContent(currentBook.id, currentBook.filePath, pageIndex)
                pageCache[pageIndex] = content
                _cachedPages.value = pageCache.toMap()
            } finally {
                if (_currentPage.value == pageIndex) {
                    _isLoadingPage.value = false
                }
            }
        }
    }

    private fun preloadAdjacentPages(centerIndex: Int, totalPages: Int) {
        viewModelScope.launch(Dispatchers.IO) {
            val currentBook = _book.value ?: return@launch
            val indicesToPreload = listOf(centerIndex - 1, centerIndex + 1, centerIndex + 2)
            for (idx in indicesToPreload) {
                if (idx in 0 until totalPages && !pageCache.containsKey(idx)) {
                    val content = bookRepository.getPageContent(currentBook.id, currentBook.filePath, idx)
                    pageCache[idx] = content
                }
            }
            _cachedPages.value = pageCache.toMap()
        }
    }

    suspend fun renderOriginalPage(pageIndex: Int, targetWidth: Int): Bitmap? {
        val currentBook = _book.value ?: return null
        return bookRepository.renderPageBitmap(currentBook.filePath, pageIndex, targetWidth)
    }

    fun addBookmarkForCurrentPage(title: String? = null) {
        val currentBook = _book.value ?: return
        val pageIdx = _currentPage.value
        val defaultTitle = title ?: "Trang ${pageIdx + 1}"

        viewModelScope.launch {
            bookRepository.addBookmark(currentBook.id, pageIdx, defaultTitle)
            _bookmarks.value = bookRepository.getBookmarks(currentBook.id)
        }
    }

    fun deleteBookmark(bookmarkId: Long) {
        val currentBook = _book.value ?: return
        viewModelScope.launch {
            bookRepository.deleteBookmark(bookmarkId)
            _bookmarks.value = bookRepository.getBookmarks(currentBook.id)
        }
    }

    // Settings actions
    fun setFontSize(sizeSp: Float) = settingsRepository.updateFontSize(sizeSp)
    fun setLineHeight(multiplier: Float) = settingsRepository.updateLineHeight(multiplier)
    fun setFontFamily(fontFamily: FontFamilyType) = settingsRepository.updateFontFamily(fontFamily)
    fun setThemePreset(preset: ReaderThemePreset) = settingsRepository.updateThemePreset(preset)
    fun setCustomColors(bgHex: Long, textHex: Long) = settingsRepository.updateCustomColors(bgHex, textHex)
    fun setJustified(justified: Boolean) = settingsRepository.updateJustification(justified)
    fun setPadding(paddingDp: Int) = settingsRepository.updatePadding(paddingDp)
    fun setViewMode(viewMode: ViewMode) = settingsRepository.updateViewMode(viewMode)
    fun setContinuousScroll(isContinuous: Boolean) = settingsRepository.updateContinuousScroll(isContinuous)
}
