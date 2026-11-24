import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/book.dart';
import '../models/bookmark.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('readflow.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Text extraction changed (spacing and paragraphs now follow the page
      // layout), so pages cached by the old extractor are stale.
      await db.delete('page_cache');
    }
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE books (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        file_path TEXT NOT NULL UNIQUE,
        page_count INTEGER NOT NULL,
        last_read_page INTEGER NOT NULL DEFAULT 0,
        last_read_time INTEGER NOT NULL,
        file_size_bytes INTEGER NOT NULL DEFAULT 0,
        cover_path TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE bookmarks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id INTEGER NOT NULL,
        page_index INTEGER NOT NULL,
        title TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (book_id) REFERENCES books (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE page_cache (
        book_id INTEGER NOT NULL,
        page_index INTEGER NOT NULL,
        content TEXT NOT NULL,
        PRIMARY KEY (book_id, page_index),
        FOREIGN KEY (book_id) REFERENCES books (id) ON DELETE CASCADE
      )
    ''');
  }

  // --- Books ---
  Future<int> insertBook(Book book) async {
    final db = await instance.database;
    return await db.insert(
      'books',
      book.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Book>> getBooks() async {
    final db = await instance.database;
    final result = await db.query('books', orderBy: 'last_read_time DESC');
    return result.map((map) => Book.fromMap(map)).toList();
  }

  Future<Book?> getBook(int id) async {
    final db = await instance.database;
    final result = await db.query('books', where: 'id = ?', whereArgs: [id]);
    if (result.isNotEmpty) {
      return Book.fromMap(result.first);
    }
    return null;
  }

  Future<Book?> getBookByPath(String path) async {
    final db = await instance.database;
    final result = await db.query('books', where: 'file_path = ?', whereArgs: [path]);
    if (result.isNotEmpty) {
      return Book.fromMap(result.first);
    }
    return null;
  }

  Future<int> updateProgress(int bookId, int pageIndex) async {
    final db = await instance.database;
    return await db.update(
      'books',
      {
        'last_read_page': pageIndex,
        'last_read_time': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }

  Future<int> deleteBook(int id) async {
    final db = await instance.database;
    // Foreign keys are not enforced, so child rows are removed explicitly.
    return db.transaction((txn) async {
      await txn.delete('page_cache', where: 'book_id = ?', whereArgs: [id]);
      await txn.delete('bookmarks', where: 'book_id = ?', whereArgs: [id]);
      return txn.delete('books', where: 'id = ?', whereArgs: [id]);
    });
  }

  // --- Bookmarks ---
  Future<int> insertBookmark(Bookmark bookmark) async {
    final db = await instance.database;
    return await db.insert('bookmarks', bookmark.toMap());
  }

  Future<List<Bookmark>> getBookmarks(int bookId) async {
    final db = await instance.database;
    final result = await db.query(
      'bookmarks',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'page_index ASC',
    );
    return result.map((map) => Bookmark.fromMap(map)).toList();
  }

  Future<int> deleteBookmark(int id) async {
    final db = await instance.database;
    return await db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  }

  // --- Page Cache ---
  Future<void> cachePage(int bookId, int pageIndex, String content) async {
    final db = await instance.database;
    await db.insert(
      'page_cache',
      {
        'book_id': bookId,
        'page_index': pageIndex,
        'content': content,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getCachedPage(int bookId, int pageIndex) async {
    final db = await instance.database;
    final result = await db.query(
      'page_cache',
      columns: ['content'],
      where: 'book_id = ? AND page_index = ?',
      whereArgs: [bookId, pageIndex],
      limit: 1,
    );
    return result.isEmpty ? null : result.first['content'] as String;
  }
}
