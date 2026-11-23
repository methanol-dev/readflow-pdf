package com.doctruyen.reader.data

import android.content.Context
import android.net.Uri
import com.doctruyen.reader.data.db.AppDbHelper
import com.doctruyen.reader.data.model.Book
import com.doctruyen.reader.data.model.Bookmark
import com.doctruyen.reader.data.model.PdfPageContent
import com.doctruyen.reader.pdf.PdfEngine
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import java.io.File

class BookRepository(private val context: Context) {

    private val dbHelper = AppDbHelper(context)
    private val _books = MutableStateFlow<List<Book>>(emptyList())
    val books: StateFlow<List<Book>> = _books.asStateFlow()

    suspend fun refreshBooks() = withContext(Dispatchers.IO) {
        val list = dbHelper.getAllBooks()
        _books.value = list
    }

    suspend fun importPdfBook(uri: Uri): Book = withContext(Dispatchers.IO) {
        val result = PdfEngine.importPdf(context, uri)
        val newBook = Book(
            title = result.title,
            uri = uri.toString(),
            filePath = result.filePath,
            pageCount = result.pageCount,
            lastReadPage = 0,
            lastReadOffset = 0f,
            coverPath = result.coverPath,
            lastReadTime = System.currentTimeMillis(),
            fileSize = result.fileSize
        )
        val id = dbHelper.insertBook(newBook)
        val inserted = newBook.copy(id = id)
        refreshBooks()
        inserted
    }

    suspend fun createSampleBook(): Book = withContext(Dispatchers.IO) {
        val sampleFile = PdfEngine.createSampleStoryPdf(context)
        val sampleUri = Uri.fromFile(sampleFile)
        val result = PdfEngine.importPdf(context, sampleUri)
        val sampleBook = Book(
            title = "Dế Mèn Phiêu Lưu Ký (Mẫu)",
            uri = sampleUri.toString(),
            filePath = result.filePath,
            pageCount = result.pageCount,
            lastReadPage = 0,
            lastReadOffset = 0f,
            coverPath = result.coverPath,
            lastReadTime = System.currentTimeMillis(),
            fileSize = result.fileSize
        )
        val id = dbHelper.insertBook(sampleBook)
        val inserted = sampleBook.copy(id = id)
        refreshBooks()
        inserted
    }

    suspend fun getBook(id: Long): Book? = withContext(Dispatchers.IO) {
        dbHelper.getBookById(id)
    }

    suspend fun updateProgress(bookId: Long, lastPage: Int, lastOffset: Float = 0f) = withContext(Dispatchers.IO) {
        dbHelper.updateBookProgress(bookId, lastPage, lastOffset)
        refreshBooks()
    }

    suspend fun deleteBook(book: Book) = withContext(Dispatchers.IO) {
        try {
            File(book.filePath).delete()
            book.coverPath?.let { File(it).delete() }
        } catch (ignored: Exception) {}

        dbHelper.deleteBook(book.id)
        refreshBooks()
    }

    suspend fun getPageContent(filePath: String, pageIndex: Int): PdfPageContent {
        return PdfEngine.getPageContent(context, filePath, pageIndex)
    }

    suspend fun renderPageBitmap(filePath: String, pageIndex: Int, targetWidth: Int) =
        PdfEngine.renderPageBitmap(filePath, pageIndex, targetWidth)

    suspend fun getOutline(filePath: String) =
        PdfEngine.extractOutline(context, filePath)

    suspend fun addBookmark(bookId: Long, pageIndex: Int, title: String): Bookmark = withContext(Dispatchers.IO) {
        val bm = Bookmark(
            bookId = bookId,
            pageIndex = pageIndex,
            title = title,
            timestamp = System.currentTimeMillis()
        )
        val id = dbHelper.addBookmark(bm)
        bm.copy(id = id)
    }

    suspend fun getBookmarks(bookId: Long): List<Bookmark> = withContext(Dispatchers.IO) {
        dbHelper.getBookmarksForBook(bookId)
    }

    suspend fun deleteBookmark(bookmarkId: Long) = withContext(Dispatchers.IO) {
        dbHelper.deleteBookmark(bookmarkId)
    }
}
