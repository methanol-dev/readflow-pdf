# Đọc Truyện PDF (DocTruyen PDF Reader)

Ứng dụng đọc truyện và tài liệu PDF chuyên nghiệp dành cho Android, giải quyết triệt để vấn đề mỏi mắt và chữ nhỏ khi đọc file PDF trên điện thoại.

## Tính năng nổi bật

### 1. Tùy biến Typography & Giao diện chuyên sâu
- **Cỡ chữ linh hoạt**: Thanh trượt từ 12sp đến 36sp kèm nút tăng giảm nhanh.
- **Khoảng cách dòng**: Tùy chọn `1.2x`, `1.4x`, `1.6x`, `1.8x`, `2.0x`.
- **Bộ font chữ chất lượng**:
  - *Serif (Sách)*: Chuẩn font sách văn học, tiểu thuyết kinh điển.
  - *Sans-Serif*: Hiện đại, tài liệu học thuật.
  - *Hệ thống* và *Monospace*.
- **Căn lề**: Căn đều 2 bên (Justified) hoặc Căn trái.
- **Lề mép màn hình**: Tùy chỉnh lề hẹp, vừa, rộng chống dính mép màn hình cong.

### 2. Hệ thống Theme & Bảng màu phong phú
- **5 Theme cài sẵn**:
  - **Giấy ngà (Sepia)**: Nền vàng ấm (`#FBF0D9`), chữ than chì (`#3C3836`) — êm mắt tuyệt đối.
  - **OLED Đen**: Nền đen tuyệt đối (`#000000`), chữ xám sáng (`#E0E0E0`) — tối ưu pin AMOLED.
  - **Đêm ấm (Warm Dark)**: Nền than chì (`#1C1C1E`), chữ ngà dịu.
  - **Trắng giấy (Paper White)**: Nền trắng sạch (`#FAFAFA`), chữ xám đen.
  - **Xanh dịu (Eye Care)**: Nền xanh lá nhạt (`#E4F0E8`), chữ xanh rừng chống mỏi mắt.
- **Tùy biến tự do (Custom Color)**: Bảng chọn màu nền và màu chữ độc lập theo ý thích.

### 3. Trải nghiệm chuyển trang thông minh
- **Vuốt ngang lật trang (Horizontal Swipe)**: Vuốt trái để sang trang sau, vuốt phải để về trang trước.
- **Chạm mép màn hình (Tap Zones)**: Chạm 20% cạnh phải để next, 20% cạnh trái để prev, giữa màn hình để mở menu.
- **Thẻ hành động chuyển trang**: Tự xuất hiện khi cuộn hết nội dung của trang.
- **Chế độ Cuộn dọc liên tục (Continuous Scroll)**: Đọc xuyên suốt từ đầu đến cuối sách không cần ngắt quãng lật trang.
- **Dual-Mode**: Chuyển đổi 1 chạm giữa **Chế độ đọc chữ (Reflow)** và **Xem trang in gốc (Original PDF)** có hỗ trợ phóng to/thu nhỏ (pinch-to-zoom).

### 4. Quản lý Thư viện & Trạng thái đọc
- Nhớ vị trí trang đọc dở chính xác cho từng cuốn sách.
- Trích xuất bìa sách tự động từ trang đầu tiên của file PDF.
- Hỗ trợ Bookmark trang yêu thích và Mục lục (Table of Contents) tự động.
- Tự sao lưu file vào bộ nhớ an toàn của app.

## Công nghệ sử dụng
- **Ngôn ngữ**: 100% Kotlin
- **UI Toolkit**: Jetpack Compose + Material 3
- **Lõi xử lý PDF**: Apache PDFBox-Android + Android Native PdfRenderer
- **Lưu trữ**: SQLite OpenHelper + SharedPreferences
- **Kiến trúc**: Clean Architecture + MVI/MVVM + StateFlow / Coroutines

## Cài đặt
Tải file `DocTruyen-PDF-Reader.apk` trong mục [Releases](https://github.com/methanol-dev/doc-truyen/releases) và cài đặt trực tiếp trên thiết bị Android (Android 8.0 Oreo trở lên).
