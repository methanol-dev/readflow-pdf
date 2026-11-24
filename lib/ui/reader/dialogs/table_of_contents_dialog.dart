import 'package:flutter/material.dart';
import '../../../models/bookmark.dart';

class TableOfContentsDialog extends StatelessWidget {
  final List<Map<String, dynamic>> outline;
  final List<Bookmark> bookmarks;
  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onSelectPage;
  final ValueChanged<int> onDeleteBookmark;

  const TableOfContentsDialog({
    super.key,
    required this.outline,
    required this.bookmarks,
    required this.currentPage,
    required this.totalPages,
    required this.onSelectPage,
    required this.onDeleteBookmark,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: SizedBox(
          width: double.maxFinite,
          height: 480,
          child: Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(icon: Icon(Icons.list_alt_rounded), text: 'Mục lục'),
                  Tab(icon: Icon(Icons.bookmarks_rounded), text: 'Đánh dấu'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    // Tab 1: Outline
                    outline.isEmpty
                        ? const Center(
                            child: Text(
                              'File PDF này không có mục lục tích hợp sẵn.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.separated(
                            itemCount: outline.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = outline[index];
                              final title = item['title'] as String;
                              final pageIdx = item['pageIndex'] as int;
                              final isCurrent = pageIdx == currentPage;

                              return ListTile(
                                leading: CircleAvatar(
                                  radius: 14,
                                  backgroundColor: isCurrent ? Colors.blueAccent : Colors.grey.withValues(alpha: 0.2),
                                  child: Text(
                                    '${pageIdx + 1}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isCurrent ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                    color: isCurrent ? Colors.blueAccent : null,
                                  ),
                                ),
                                onTap: () {
                                  Navigator.pop(context);
                                  onSelectPage(pageIdx);
                                },
                              );
                            },
                          ),

                    // Tab 2: Bookmarks
                    bookmarks.isEmpty
                        ? const Center(
                            child: Text(
                              'Chưa có trang nào được đánh dấu.\n(Bấm biểu tượng Bookmark ở góc trên để lưu trang)',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.separated(
                            itemCount: bookmarks.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final bm = bookmarks[index];
                              return ListTile(
                                leading: const Icon(Icons.bookmark_rounded, color: Colors.blueAccent),
                                title: Text(bm.title),
                                subtitle: Text('Trang ${bm.pageIndex + 1} / $totalPages'),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                                  onPressed: () {
                                    if (bm.id != null) {
                                      onDeleteBookmark(bm.id!);
                                    }
                                  },
                                ),
                                onTap: () {
                                  Navigator.pop(context);
                                  onSelectPage(bm.pageIndex);
                                },
                              );
                            },
                          ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Đóng'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
