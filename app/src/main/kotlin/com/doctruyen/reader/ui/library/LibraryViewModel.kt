package com.doctruyen.reader.ui.library

import android.app.Application
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.doctruyen.reader.data.BookRepository
import com.doctruyen.reader.data.model.Book
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class LibraryViewModel(application: Application) : AndroidViewModel(application) {

    private val repository = BookRepository(application)

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _statusMessage = MutableStateFlow<String?>(null)
    val statusMessage: StateFlow<String?> = _statusMessage.asStateFlow()

    private val _searchQuery = MutableStateFlow("")
    val searchQuery: StateFlow<String> = _searchQuery.asStateFlow()

    val filteredBooks: StateFlow<List<Book>> = combine(
        repository.books,
        _searchQuery
    ) { books, query ->
        if (query.isBlank()) books
        else books.filter { it.title.contains(query, ignoreCase = true) }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    val lastReadBook: StateFlow<Book?> = repository.books.combine(_searchQuery) { books, _ ->
        books.maxByOrNull { it.lastReadTime }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), null)

    init {
        loadBooks()
    }

    fun loadBooks() {
        viewModelScope.launch {
            _isLoading.value = true
            try {
                repository.refreshBooks()
            } catch (e: Exception) {
                _statusMessage.value = "Lỗi tải danh sách: ${e.message}"
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun updateSearch(query: String) {
        _searchQuery.value = query
    }

    fun importPdf(uri: Uri, onComplete: (Book) -> Unit) {
        viewModelScope.launch {
            _isLoading.value = true
            try {
                val book = repository.importPdfBook(uri)
                _statusMessage.value = "Đã thêm thành công: ${book.title}"
                onComplete(book)
            } catch (e: Exception) {
                _statusMessage.value = "Không thể nhập PDF: ${e.localizedMessage ?: "File bị lỗi hoặc được bảo vệ mật khẩu"}"
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun createSampleStory(onComplete: (Book) -> Unit) {
        viewModelScope.launch {
            _isLoading.value = true
            try {
                val book = repository.createSampleBook()
                _statusMessage.value = "Đã tạo sách mẫu thành công!"
                onComplete(book)
            } catch (e: Exception) {
                _statusMessage.value = "Lỗi tạo sách mẫu: ${e.message}"
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun deleteBook(book: Book) {
        viewModelScope.launch {
            try {
                repository.deleteBook(book)
                _statusMessage.value = "Đã xóa '${book.title}' khỏi thư viện"
            } catch (e: Exception) {
                _statusMessage.value = "Lỗi khi xóa: ${e.message}"
            }
        }
    }

    fun clearStatusMessage() {
        _statusMessage.value = null
    }
}
