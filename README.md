# ReadFlow - Trình Đọc Truyện & Sách Nói PDF Đa Nền Tảng (Android & iOS)

**ReadFlow** là ứng dụng đọc sách và nghe sách nói PDF mã nguồn mở, tối ưu trải nghiệm đọc tiếng Việt với công nghệ dàn trang thông minh (**Reflow Mode**) và trình phát sách nói (**TTS Audiobook**) đọc liên tục toàn bộ tác phẩm trên cả **Android** và **iOS**.

---

## 🌟 Tính Năng Nổi Bật

### 1. 📖 Chế độ đọc chữ thông minh (Reflow Engine)
- Bóc tách văn bản trực tiếp từ file PDF, tự động sửa lỗi ngắt dòng, gạch nối từ tiếng Việt.
- Dàn trang vừa vặn với mọi kích thước màn hình điện thoại (Android & iPhone).
- Hỗ trợ chuyển đổi nhanh giữa **Chế độ đọc chữ (Reflow)** và **Xem trang gốc PDF (Pinch-to-Zoom)**.

### 2. 🎧 Sách nói Audiobook TTS Đa nền tảng (Continuous Whole-Book Reader)
- **Đọc liên tục không giới hạn**: Tự động đọc tuần tự từng đoạn và **tự động chuyển trang tiếp theo** khi đọc hết trang hiện tại cho đến hết toàn bộ file PDF.
- **Thanh điều khiển Mini-Player hiện đại**: Tạm dừng, phát tiếp, nhảy đoạn kế tiếp, lùi đoạn trước, tùy chỉnh tốc độ đọc (`0.5x`, `0.75x`, `1.0x`, `1.25x`, `1.5x`, `2.0x`).
- **Tô sáng (Highlight) trực quan**: Tự động làm nổi bật đoạn văn bản đang đọc và cuộn màn hình theo giọng đọc.
- **Giọng đọc Tiếng Việt chuẩn**: Tự động sử dụng Google Speech Services (Android) hoặc Apple AVSpeechSynthesizer (iOS).

### 3. 🎨 Cá nhân hóa hiển thị & Bảo vệ mắt (Eye-Care Themes)
- 5 bộ màu bảo vệ mắt: **Giấy vàng Sepia**, **Trắng tinh khôi**, **Đêm tối dịu mắt**, **Đen tuyền AMOLED**, **Xanh lá thư giãn**.
- Công cụ chọn màu tùy chỉnh tự do cho nền và chữ.
- Tùy chỉnh kích thước chữ (12 - 34 pt), khoảng cách giãn dòng (1.2x - 2.6x), kiểu font (Mặc định, Có chân Serif, Không chân Sans, Đơn cách Mono), căn lề hai bên (Justify).
- Hỗ trợ cả 2 chế độ: **Lật từng trang (Vuốt ngang/Chạm viền)** hoặc **Cuộn dọc liên tục như đọc báo**.

### 4. 📑 Mục lục & Đánh dấu trang
- Tự động trích xuất Mục lục (Table of Contents / Bookmarks) tích hợp sẵn trong file PDF.
- Đánh dấu trang yêu thích (Bookmark) không giới hạn.

---

## 🛠️ Công Nghệ & Kiến Trúc (Version 3)

- **Framework**: [Flutter](https://flutter.dev) (Dart 3.x)
- **PDF Engine**: [Syncfusion Flutter PDF](https://pub.dev/packages/syncfusion_flutter_pdf) & [pdfx](https://pub.dev/packages/pdfx)
- **Audio Engine**: [flutter_tts](https://pub.dev/packages/flutter_tts)
- **Local Database**: SQLite qua [sqflite](https://pub.dev/packages/sqflite) & [shared_preferences](https://pub.dev/packages/shared_preferences)
- **File Management**: [file_picker](https://pub.dev/packages/file_picker) & [path_provider](https://pub.dev/packages/path_provider)
- **CI/CD Build**: GitHub Actions (tự động biên dịch ra `.apk` cho Android và `.ipa` cho iOS)

---

## 📲 Hướng Dẫn Cài Đặt

### Android
- Tải file `ReadFlow-v3.0.0-Android.apk` từ mục [Releases](https://github.com/methanol-dev/readflow-pdf/releases) và cài đặt trực tiếp lên máy.

### iOS (iPhone / iPad)
- Tải file `ReadFlow-v3.0.0-iOS.ipa` từ mục [Releases](https://github.com/methanol-dev/readflow-pdf/releases).
- Sử dụng công cụ cài đặt sideload miễn phí từ máy tính (như [Sideloadly](https://sideloadly.io/) hoặc [AltStore](https://altstore.io/)):
  1. Cắm cáp iPhone vào máy tính Windows.
  2. Mở Sideloadly, kéo file `.ipa` vào và nhập Apple ID của bạn.
  3. Bấm **Start** để cài đặt trực tiếp lên iPhone.
