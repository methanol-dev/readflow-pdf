# ReadFlow: Smart PDF E-Reader with Text Reflow for Android

[![GitHub release](https://img.shields.io/github/v/release/methanol-dev/readflow-pdf?color=blue&label=Latest%20Release)](https://github.com/methanol-dev/readflow-pdf/releases)
[![Platform](https://img.shields.io/badge/Platform-Android%208.0%2B-green.svg)](https://android.com)
[![Kotlin](https://img.shields.io/badge/Kotlin-2.2%2B-purple.svg)](https://kotlinlang.org)
[![Compose](https://img.shields.io/badge/Jetpack%20Compose-Material%203-4285F4.svg)](https://developer.android.com/jetpack/compose)
[![License](https://img.shields.io/badge/License-Apache%202.0-orange.svg)](LICENSE)

> **ReadFlow** là ứng dụng đọc sách và tài liệu PDF chuyên nghiệp dành cho Android, giải quyết triệt để vấn đề chữ nhỏ, mỏi mắt và khó đọc trên màn hình điện thoại bằng công nghệ **Smart Text Reflow (tương tự Liquid Mode của Adobe)** cùng hệ thống tùy biến Typography và bảng màu cao cấp.

---

## 🌟 Tính năng nổi bật (Key Features)

### 1. Tùy biến Phông chữ & Văn bản (Typography Customization)
- **Cỡ chữ linh hoạt (Font Size)**: Thanh trượt mượt mà từ `12sp` đến `36sp` kèm nút tinh chỉnh nhanh `A-` / `A+`.
- **Khoảng cách dòng (Line Spacing / Height)**: Các nấc tiêu chuẩn đọc sách `1.2x`, `1.4x`, `1.6x`, `1.8x`, `2.0x`.
- **Bộ font chữ chất lượng cao**:
  - *Serif (Sách)*: Chuẩn font sách văn học kinh điển, tạo cảm giác như đọc sách giấy.
  - *Sans-Serif*: Hiện đại, tài liệu học thuật.
  - *Hệ thống* và *Monospace*.
- **Căn lề chuẩn mực**: Căn đều 2 bên (Justified) hoặc Căn trái.
- **Lề mép màn hình (Padding)**: Hẹp (8dp), Vừa (16dp), Rộng (24dp) chống dính mép màn hình cong.

### 2. Hệ thống Theme & Bảng màu (Eye-care Themes & Custom Color)
- **5 Theme thiết kế sẵn**:
  - **Giấy ngà (Sepia)**: Nền vàng ấm (`#FBF0D9`), chữ than chì (`#3C3836`) — êm mắt tuyệt đối khi đọc lâu.
  - **OLED Đen**: Nền đen tuyệt đối (`#000000`), chữ xám sáng (`#E0E0E0`) — tiết kiệm pin tối đa cho màn AMOLED.
  - **Đêm ấm (Warm Dark)**: Nền than chì (`#1C1C1E`), chữ ngà dịu — lọc ánh sáng xanh ban đêm.
  - **Trắng giấy (Paper White)**: Nền trắng sạch (`#FAFAFA`), chữ xám đen chuẩn mực.
  - **Xanh dịu (Eye Care)**: Nền xanh lá pastel (`#E4F0E8`), chữ xanh rừng đậm chống mỏi mắt.
- **Tự chọn màu tự do (Custom Color Picker)**: Tự do phối màu nền và màu chữ bất kỳ theo sở thích cá nhân.

### 3. Trải nghiệm Chuyển trang & Đọc sách Mượt mà (Gesture Navigation)
- **Vuốt ngang lật trang (Horizontal Swipe)**: Vuốt sang trái để qua trang sau, vuốt sang phải để về trang trước.
- **Chạm mép màn hình 1 tay (Tap Zones)**: Chạm 20% cạnh phải để Next, 20% cạnh trái để Prev, vùng giữa để mở thanh công cụ.
- **Tự động chuyển trang khi cuộn hết**: Thẻ hành động nhanh xuất hiện ở cuối trang, chỉ 1 chạm là sang trang mới.
- **Chế độ Cuộn dọc liên tục (Continuous Vertical Scroll)**: Đọc từ đầu đến cuối sách không cần lật trang, cuộn mượt mà như webtoon.
- **Dual-View Mode (Chế độ xem kép)**: Bấm 1 nút để chuyển tức thì giữa **Chế độ đọc chữ (Reflow)** và **Xem trang in gốc (Original PDF)** với tính năng phóng to / thu nhỏ (Pinch-to-zoom).
- **Tránh che khuất 3 phím hệ thống**: Toàn bộ thanh điều khiển dưới được tối ưu Insets, không bao giờ bị 3 phím Back, Home, Recents che khuất.

### 4. Quản lý Thư viện & Trạng thái đọc (Local Persistence)
- Tự động nhớ vị trí trang đọc dở cho từng cuốn sách (lưu trong SQLite).
- Tự động trích xuất trang đầu tiên làm ảnh bìa (Book Cover Thumbnail).
- Đánh dấu trang yêu thích (Bookmarks) và Mục lục (Table of Contents / Outline).
- Tự sao lưu file vào bộ nhớ an toàn của app.
- Hỗ trợ "Open with ReadFlow" khi mở file PDF từ Zalo, Telegram, Google Drive hoặc File Manager.

---

## 🛠 Kiến trúc & Công nghệ (Tech Stack)

* **Language**: 100% Kotlin
* **UI Framework**: Jetpack Compose + Material 3 Design
* **PDF Core**: Apache PDFBox-Android (Text extraction & Normalization) + Android Native `PdfRenderer` (Crisp page bitmaps)
* **Architecture**: Clean Architecture + MVI/MVVM + Kotlin Coroutines & StateFlow
* **Database & Storage**: SQLite OpenHelper + SharedPreferences

---

## 📥 Cài đặt ứng dụng (Download APK)

Tải file APK phiên bản mới nhất tại:
👉 **[Download ReadFlow APK (GitHub Releases)](https://github.com/methanol-dev/readflow-pdf/releases/latest)**

---

## 📄 License
Phát hành theo giấy phép [Apache License 2.0](LICENSE).
