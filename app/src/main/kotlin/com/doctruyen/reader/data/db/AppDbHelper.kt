package com.doctruyen.reader.data.db

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import com.doctruyen.reader.data.model.Book
import com.doctruyen.reader.data.model.Bookmark

class AppDbHelper(context: Context) : SQLiteOpenHelper(context, DATABASE_NAME, null, DATABASE_VERSION) {

    companion object {
        const val DATABASE_NAME = "doctruyen.db"
        const val DATABASE_VERSION = 2

        const val TABLE_BOOKS = "books"
        const val COL_BOOK_ID = "id"
        const val COL_BOOK_TITLE = "title"
        const val COL_BOOK_URI = "uri"
        const val COL_BOOK_FILE_PATH = "file_path"
        const val COL_BOOK_PAGE_COUNT = "page_count"
        const val COL_BOOK_LAST_PAGE = "last_read_page"
        const val COL_BOOK_LAST_OFFSET = "last_read_offset"
        const val COL_BOOK_COVER_PATH = "cover_path"
        const val COL_BOOK_LAST_TIME = "last_read_time"
        const val COL_BOOK_FILE_SIZE = "file_size"

        const val TABLE_BOOKMARKS = "bookmarks"
        const val COL_BM_ID = "id"
        const val COL_BM_BOOK_ID = "book_id"
        const val COL_BM_PAGE_INDEX = "page_index"
        const val COL_BM_TITLE = "title"
        const val COL_BM_TIMESTAMP = "timestamp"

        const val TABLE_PAGE_CACHE = "page_cache"
        const val COL_PC_BOOK_ID = "book_id"
        const val COL_PC_PAGE_INDEX = "page_index"
        const val COL_PC_PARAGRAPHS = "paragraphs"
        const val COL_PC_RAW_TEXT = "raw_text"
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS $TABLE_BOOKS (
                $COL_BOOK_ID INTEGER PRIMARY KEY AUTOINCREMENT,
                $COL_BOOK_TITLE TEXT NOT NULL,
                $COL_BOOK_URI TEXT NOT NULL,
                $COL_BOOK_FILE_PATH TEXT NOT NULL,
                $COL_BOOK_PAGE_COUNT INTEGER NOT NULL,
                $COL_BOOK_LAST_PAGE INTEGER DEFAULT 0,
                $COL_BOOK_LAST_OFFSET REAL DEFAULT 0.0,
                $COL_BOOK_COVER_PATH TEXT,
                $COL_BOOK_LAST_TIME INTEGER DEFAULT 0,
                $COL_BOOK_FILE_SIZE INTEGER DEFAULT 0
            )
            """.trimIndent()
        )

        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS $TABLE_BOOKMARKS (
                $COL_BM_ID INTEGER PRIMARY KEY AUTOINCREMENT,
                $COL_BM_BOOK_ID INTEGER NOT NULL,
                $COL_BM_PAGE_INDEX INTEGER NOT NULL,
                $COL_BM_TITLE TEXT NOT NULL,
                $COL_BM_TIMESTAMP INTEGER NOT NULL,
                FOREIGN KEY ($COL_BM_BOOK_ID) REFERENCES $TABLE_BOOKS($COL_BOOK_ID) ON DELETE CASCADE
            )
            """.trimIndent()
        )

        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS $TABLE_PAGE_CACHE (
                $COL_PC_BOOK_ID INTEGER NOT NULL,
                $COL_PC_PAGE_INDEX INTEGER NOT NULL,
                $COL_PC_PARAGRAPHS TEXT NOT NULL,
                $COL_PC_RAW_TEXT TEXT NOT NULL,
                PRIMARY KEY ($COL_PC_BOOK_ID, $COL_PC_PAGE_INDEX)
            )
            """.trimIndent()
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2) {
            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS $TABLE_PAGE_CACHE (
                    $COL_PC_BOOK_ID INTEGER NOT NULL,
                    $COL_PC_PAGE_INDEX INTEGER NOT NULL,
                    $COL_PC_PARAGRAPHS TEXT NOT NULL,
                    $COL_PC_RAW_TEXT TEXT NOT NULL,
                    PRIMARY KEY ($COL_PC_BOOK_ID, $COL_PC_PAGE_INDEX)
                )
                """.trimIndent()
            )
        }
    }

    fun insertBook(book: Book): Long {
        val db = writableDatabase
        val values = ContentValues().apply {
            put(COL_BOOK_TITLE, book.title)
            put(COL_BOOK_URI, book.uri)
            put(COL_BOOK_FILE_PATH, book.filePath)
            put(COL_BOOK_PAGE_COUNT, book.pageCount)
            put(COL_BOOK_LAST_PAGE, book.lastReadPage)
            put(COL_BOOK_LAST_OFFSET, book.lastReadOffset)
            put(COL_BOOK_COVER_PATH, book.coverPath)
            put(COL_BOOK_LAST_TIME, book.lastReadTime)
            put(COL_BOOK_FILE_SIZE, book.fileSize)
        }
        return db.insert(TABLE_BOOKS, null, values)
    }

    fun updateBookProgress(bookId: Long, lastPage: Int, lastOffset: Float) {
        val db = writableDatabase
        val values = ContentValues().apply {
            put(COL_BOOK_LAST_PAGE, lastPage)
            put(COL_BOOK_LAST_OFFSET, lastOffset)
            put(COL_BOOK_LAST_TIME, System.currentTimeMillis())
        }
        db.update(TABLE_BOOKS, values, "$COL_BOOK_ID = ?", arrayOf(bookId.toString()))
    }

    fun getAllBooks(): List<Book> {
        val list = mutableListOf<Book>()
        val db = readableDatabase
        db.query(
            TABLE_BOOKS,
            null,
            null,
            null,
            null,
            null,
            "$COL_BOOK_LAST_TIME DESC"
        ).use { cursor ->
            val idIdx = cursor.getColumnIndexOrThrow(COL_BOOK_ID)
            val titleIdx = cursor.getColumnIndexOrThrow(COL_BOOK_TITLE)
            val uriIdx = cursor.getColumnIndexOrThrow(COL_BOOK_URI)
            val filePathIdx = cursor.getColumnIndexOrThrow(COL_BOOK_FILE_PATH)
            val pageCountIdx = cursor.getColumnIndexOrThrow(COL_BOOK_PAGE_COUNT)
            val lastPageIdx = cursor.getColumnIndexOrThrow(COL_BOOK_LAST_PAGE)
            val lastOffsetIdx = cursor.getColumnIndexOrThrow(COL_BOOK_LAST_OFFSET)
            val coverPathIdx = cursor.getColumnIndexOrThrow(COL_BOOK_COVER_PATH)
            val lastTimeIdx = cursor.getColumnIndexOrThrow(COL_BOOK_LAST_TIME)
            val sizeIdx = cursor.getColumnIndexOrThrow(COL_BOOK_FILE_SIZE)

            while (cursor.moveToNext()) {
                list.add(
                    Book(
                        id = cursor.getLong(idIdx),
                        title = cursor.getString(titleIdx),
                        uri = cursor.getString(uriIdx),
                        filePath = cursor.getString(filePathIdx),
                        pageCount = cursor.getInt(pageCountIdx),
                        lastReadPage = cursor.getInt(lastPageIdx),
                        lastReadOffset = cursor.getFloat(lastOffsetIdx),
                        coverPath = cursor.getString(coverPathIdx),
                        lastReadTime = cursor.getLong(lastTimeIdx),
                        fileSize = cursor.getLong(sizeIdx)
                    )
                )
            }
        }
        return list
    }

    fun getBookById(id: Long): Book? {
        val db = readableDatabase
        db.query(
            TABLE_BOOKS,
            null,
            "$COL_BOOK_ID = ?",
            arrayOf(id.toString()),
            null,
            null,
            null
        ).use { cursor ->
            if (cursor.moveToFirst()) {
                return Book(
                    id = cursor.getLong(cursor.getColumnIndexOrThrow(COL_BOOK_ID)),
                    title = cursor.getString(cursor.getColumnIndexOrThrow(COL_BOOK_TITLE)),
                    uri = cursor.getString(cursor.getColumnIndexOrThrow(COL_BOOK_URI)),
                    filePath = cursor.getString(cursor.getColumnIndexOrThrow(COL_BOOK_FILE_PATH)),
                    pageCount = cursor.getInt(cursor.getColumnIndexOrThrow(COL_BOOK_PAGE_COUNT)),
                    lastReadPage = cursor.getInt(cursor.getColumnIndexOrThrow(COL_BOOK_LAST_PAGE)),
                    lastReadOffset = cursor.getFloat(cursor.getColumnIndexOrThrow(COL_BOOK_LAST_OFFSET)),
                    coverPath = cursor.getString(cursor.getColumnIndexOrThrow(COL_BOOK_COVER_PATH)),
                    lastReadTime = cursor.getLong(cursor.getColumnIndexOrThrow(COL_BOOK_LAST_TIME)),
                    fileSize = cursor.getLong(cursor.getColumnIndexOrThrow(COL_BOOK_FILE_SIZE))
                )
            }
        }
        return null
    }

    fun deleteBook(id: Long) {
        val db = writableDatabase
        db.delete(TABLE_PAGE_CACHE, "$COL_PC_BOOK_ID = ?", arrayOf(id.toString()))
        db.delete(TABLE_BOOKMARKS, "$COL_BM_BOOK_ID = ?", arrayOf(id.toString()))
        db.delete(TABLE_BOOKS, "$COL_BOOK_ID = ?", arrayOf(id.toString()))
    }

    fun cachePageContent(bookId: Long, pageIndex: Int, content: com.doctruyen.reader.data.model.PdfPageContent) {
        val db = writableDatabase
        val values = ContentValues().apply {
            put(COL_PC_BOOK_ID, bookId)
            put(COL_PC_PAGE_INDEX, pageIndex)
            put(COL_PC_PARAGRAPHS, content.paragraphs.joinToString("\u001E"))
            put(COL_PC_RAW_TEXT, content.rawText)
        }
        db.insertWithOnConflict(TABLE_PAGE_CACHE, null, values, SQLiteDatabase.CONFLICT_REPLACE)
    }

    fun getCachedPageContent(bookId: Long, pageIndex: Int): com.doctruyen.reader.data.model.PdfPageContent? {
        val db = readableDatabase
        db.query(
            TABLE_PAGE_CACHE,
            null,
            "$COL_PC_BOOK_ID = ? AND $COL_PC_PAGE_INDEX = ?",
            arrayOf(bookId.toString(), pageIndex.toString()),
            null,
            null,
            null
        ).use { cursor ->
            if (cursor.moveToFirst()) {
                val paragraphsStr = cursor.getString(cursor.getColumnIndexOrThrow(COL_PC_PARAGRAPHS))
                val rawText = cursor.getString(cursor.getColumnIndexOrThrow(COL_PC_RAW_TEXT))
                val paragraphs = if (paragraphsStr.isEmpty()) emptyList() else paragraphsStr.split("\u001E")
                return com.doctruyen.reader.data.model.PdfPageContent(
                    pageIndex = pageIndex,
                    paragraphs = paragraphs,
                    rawText = rawText
                )
            }
        }
        return null
    }

    fun getAllCachedPagesForBook(bookId: Long): Map<Int, com.doctruyen.reader.data.model.PdfPageContent> {
        val map = mutableMapOf<Int, com.doctruyen.reader.data.model.PdfPageContent>()
        val db = readableDatabase
        db.query(
            TABLE_PAGE_CACHE,
            null,
            "$COL_PC_BOOK_ID = ?",
            arrayOf(bookId.toString()),
            null,
            null,
            null
        ).use { cursor ->
            val pageIdxCol = cursor.getColumnIndexOrThrow(COL_PC_PAGE_INDEX)
            val paragraphsCol = cursor.getColumnIndexOrThrow(COL_PC_PARAGRAPHS)
            val rawTextCol = cursor.getColumnIndexOrThrow(COL_PC_RAW_TEXT)
            while (cursor.moveToNext()) {
                val pageIndex = cursor.getInt(pageIdxCol)
                val paragraphsStr = cursor.getString(paragraphsCol)
                val rawText = cursor.getString(rawTextCol)
                val paragraphs = if (paragraphsStr.isEmpty()) emptyList() else paragraphsStr.split("\u001E")
                map[pageIndex] = com.doctruyen.reader.data.model.PdfPageContent(
                    pageIndex = pageIndex,
                    paragraphs = paragraphs,
                    rawText = rawText
                )
            }
        }
        return map
    }

    fun addBookmark(bookmark: Bookmark): Long {
        val db = writableDatabase
        val values = ContentValues().apply {
            put(COL_BM_BOOK_ID, bookmark.bookId)
            put(COL_BM_PAGE_INDEX, bookmark.pageIndex)
            put(COL_BM_TITLE, bookmark.title)
            put(COL_BM_TIMESTAMP, bookmark.timestamp)
        }
        return db.insert(TABLE_BOOKMARKS, null, values)
    }

    fun getBookmarksForBook(bookId: Long): List<Bookmark> {
        val list = mutableListOf<Bookmark>()
        val db = readableDatabase
        db.query(
            TABLE_BOOKMARKS,
            null,
            "$COL_BM_BOOK_ID = ?",
            arrayOf(bookId.toString()),
            null,
            null,
            "$COL_BM_PAGE_INDEX ASC"
        ).use { cursor ->
            val idIdx = cursor.getColumnIndexOrThrow(COL_BM_ID)
            val bookIdIdx = cursor.getColumnIndexOrThrow(COL_BM_BOOK_ID)
            val pageIdx = cursor.getColumnIndexOrThrow(COL_BM_PAGE_INDEX)
            val titleIdx = cursor.getColumnIndexOrThrow(COL_BM_TITLE)
            val timeIdx = cursor.getColumnIndexOrThrow(COL_BM_TIMESTAMP)

            while (cursor.moveToNext()) {
                list.add(
                    Bookmark(
                        id = cursor.getLong(idIdx),
                        bookId = cursor.getLong(bookIdIdx),
                        pageIndex = cursor.getInt(pageIdx),
                        title = cursor.getString(titleIdx),
                        timestamp = cursor.getLong(timeIdx)
                    )
                )
            }
        }
        return list
    }

    fun deleteBookmark(id: Long) {
        val db = writableDatabase
        db.delete(TABLE_BOOKMARKS, "$COL_BM_ID = ?", arrayOf(id.toString()))
    }
}
