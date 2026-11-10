# Abbott Event Helper (Flutter App — Windows & Android) 🏥⚡

> **Ứng dụng trợ lý chuyên nghiệp hỗ trợ thuê SIM nhận OTP, chuẩn hóa danh sách Nhân viên Y tế và tự động điền (Auto-fill) biểu mẫu đăng ký sự kiện & hội thảo Abbott dành cho Windows Desktop và Android.**

[![Flutter](https://img.shields.io/badge/Flutter-v3.0+-02569B?logo=flutter)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Android-green.svg)](https://github.com/ngoctoan150699/abbott-autofill/releases)
[![Release](https://img.shields.io/github/v/release/ngoctoan150699/abbott-autofill?color=teal)](https://github.com/ngoctoan150699/abbott-autofill/releases/latest)
[![License](https://img.shields.io/badge/License-Proprietary-blue.svg)](#)

---

## 📖 Tài liệu liên quan
- 🏠 **[README Tổng quan toàn bộ Hệ sinh thái Dự án (Flutter, Telegram Bot, Python, Extension)](../README.md)**
- 👉 **[Hướng dẫn sử dụng & Quy trình vận hành chuẩn (SOP Chi tiết)](USER_GUIDE.md)**
- 🤖 **[Thiết kế Kiến trúc & Flow Tự động hóa hoàn toàn (AUTOMATION_FLOW.md)](AUTOMATION_FLOW.md)**
- 📘 **[Đặc tả kỹ thuật kiến trúc hệ thống (PROJECT_DOC.md)](PROJECT_DOC.md)**

---

## 🎯 Ứng dụng dùng để làm những gì?

Ứng dụng **Abbott Event Helper** được thiết kế để giúp người vận hành đăng ký nhanh hàng loạt Nhân viên Y tế (Bác sĩ, Điều dưỡng, Dược sĩ...) vào cổng sự kiện trực tuyến của Abbott chỉ trong vài giây mỗi người:

1. **Mở cổng sự kiện & Tự động vượt kiểm tra vị trí GPS**: Tích hợp trình duyệt nhúng tự động giả lập tọa độ GPS tại Bệnh viện Đa khoa Tỉnh Quảng Ngãi (`15.114757, 108.791015`), giúp mở form đăng ký ở bất kỳ đâu.
2. **Thuê số điện thoại & Nhận mã OTP tự động (ViOTP & HupSMS)**:
   - Chuyển đổi linh hoạt **1-chạm** giữa **ViOTP** (`api.viotp.net`) và **HupSMS** (`hupsms.com`).
   - Hỗ trợ chọn **đa cụm Server trên HupSMS** (ưu tiên `Server 247` giá **1.500đ** ⭐ rẻ nhất, `Server 3` - **1.800đ**, `Server 2` - **3.500đ**).
   - Tự động điền SĐT vào web, tự bấm nút *"Gửi mã"*, đếm ngược **60 giây** khớp 1:1 với đồng hồ của Abbott và tự động điền mã OTP ngay khi tin nhắn về.
   - **Bảo toàn chi phí 100%**: Nếu quá 60s không có mã hoặc bấm dừng chờ, ứng dụng tự động gọi API hủy đơn để hoàn tiền ngay lập tức trên HupSMS.
3. **Chuẩn hóa danh sách & Tự động điền thông tin (Auto-fill)**:
   - Tự động chuyển đổi danh sách văn bản thô (`Họ tên - Khoa - Chức danh [- Bệnh viện]`) sang đúng chuẩn danh mục không dấu của Abbott.
   - Tự động xử lý trường **Phòng ban (Khác)** khi khoa của người tham dự không nằm trong danh sách cố định.
   - Điền tuần tự **Họ và tên**, **Vai trò** (`Nguoi tham du`), **Bệnh viện**, **Phòng ban / Khoa**, **Chức danh** và tích **Checkbox Đồng ý điều khoản** chỉ với 1 nút bấm (`Alt + F`).
4. **Quản lý Profile Bệnh viện & Sao chép 1-chạm**:
   - Lưu danh sách nhiều bệnh viện trong Profile, hỗ trợ **Gán Bệnh viện cho tất cả** danh sách bằng 1 click.
   - Cung cấp khu vực **Sao chép nhanh 1-chạm** cho từng trường (`Họ tên`, `SĐT`, `OTP`, `BV`, `Khoa`, `Chức danh`) để dự phòng thao tác tay bất cứ lúc nào.

---

## 🌟 Tính năng nổi bật

### 1. 📲 Đa nguồn SIM & OTP (ViOTP + HupSMS)
- Chuyển đổi linh hoạt **1-chạm** giữa **ViOTP** (`api.viotp.net`) và **HupSMS** (`hupsms.com`) ngay trên màn hình chính.
- **Hỗ trợ đa Server (HupSMS)**: Nhận diện và cho phép chọn nhanh các Server với mức giá khác nhau (`Server 247` giá 1.500đ rẻ nhất ⭐, `Server 3` giá 1.800đ, `Server 2` giá 3.500đ).
- **Tự động hủy đơn & Hoàn tiền thông minh**: Đếm ngược thời gian thực 60s. Sau 60s nếu không nhận được mã OTP (hoặc khi người dùng bấm **Dừng**), hệ thống tự hủy đơn để hoàn lại 100% tiền vào tài khoản HupSMS.
- **Hiển thị số dư thời gian thực**: Trực tiếp trên thanh trạng thái với chức năng bấm làm mới tức thì.

### 2. 🪄 Tự động điền dữ liệu (Auto-fill thông minh)
- **Tự động điền SĐT & Bấm Gửi mã**: Nút dán cạnh ô SĐT giúp tự điền số vào web, tự tìm bấm nút *"Gửi mã"* và kích hoạt luôn vòng lặp chờ OTP.
- **Chuẩn hóa thông tin tự động**: Họ tên, Chức danh (`Bac Sy Dieu Tri`, `Y ta/ Dieu duong`, `Y Ta Truong/ Dieu Duong Truong`...), Khoa/Phòng ban chuẩn danh mục Abbott.
- **Hỗ trợ trường Phòng ban (Khác)**: Tự động chọn mục `Khac` và điền tên khoa thực tế vào ô nhập tay **Phòng ban (Khác)**.
- **Tùy chỉnh linh hoạt**: Cho phép bật/tắt từng trường điền và điều chỉnh độ trễ (`delay ms`) cho từng bước để tương thích tối đa với tốc độ mạng.

### 3. 👥 Quản lý danh sách người & Profile Bệnh viện
- Hộp thoại **Cài đặt 3 ngăn** rộng rãi:
  - **DS Người**: Dán danh sách hàng loạt, tự động phân tích hoặc thêm/sửa/xóa từng người trực quan.
  - **Bệnh Viện**: Quản lý Profile danh sách Bệnh viện (thêm lẻ hoặc nhập hàng loạt), chọn Bệnh viện mặc định và **Gán BV cho tất cả** chỉ với 1 click.
  - **Cấu Hình**: Lưu Token ViOTP, API Key HupSMS, chọn thời gian chờ OTP (`60s` / `90s` / `120s`) và độ trễ từng trường.
- Tự động lưu toàn bộ cấu hình và danh sách vào bộ nhớ máy.

### 4. 💻 Giao diện Split-View tối ưu cho Windows Desktop & Android
- Trên **Windows Desktop**:
  - Tích hợp trình duyệt nhúng **Microsoft Edge WebView2** hiện đại bên phải.
  - Sidebar điều khiển 400px bên trái: Quản lý thẻ người tham dự, thuê số, lấy OTP, chọn nhanh bệnh viện, điền form và gửi form.
  - Hỗ trợ đầy đủ phím tắt thao tác siêu tốc (`Alt + F`, `Alt + N`, `Alt + P`, `Alt + ←`, `Alt + →`, `F5`).
- Trên **Android Mobile**:
  - Giao diện thu gọn thông minh với khung WebView phía trên và bảng điều khiển nhanh phía dưới.

---

## 🚀 Tải về & Cài đặt

### 1. Bản cài đặt sẵn (Releases)
Truy cập trang [Releases mới nhất](https://github.com/ngoctoan150699/abbott-autofill/releases/latest) để tải về:

| Nền tảng | Tệp tải về | Hướng dẫn sử dụng |
|---|---|---|
| **Windows Desktop** | `abbott_helper-windows-x64.zip` | Tải về, giải nén ra thư mục và nhấp đúp chạy file `abbott_helper.exe` |
| **Android** | `abbott_helper-v1.4.0.apk` | Tải về điện thoại và cài đặt trực tiếp file APK |

### 2. Chạy từ mã nguồn (Development)
```bash
cd abbott_flutter_app
flutter pub get
flutter run -d windows   # Chạy trên Windows Desktop
flutter run -d android   # Chạy trên thiết bị / máy ảo Android
```

---

## 📋 Quy trình vận hành chuẩn (SOP 7 Bước)

1. **Mở link**: Dán link sự kiện Abbott vào thanh địa chỉ trên ứng dụng và bấm **Mở**.
2. **Thuê số**: Bấm **`[ Lấy Số ]`** $\rightarrow$ SĐT tự động copy vào Clipboard.
3. **Điền SĐT & Gửi mã**: Bấm nút **Điền SĐT vào Web** (icon 📋 cạnh SĐT) để tự điền SĐT, tự bấm nút *"Gửi mã"* trên web và bắt đầu đếm ngược 60s chờ OTP *(Nếu quá 60s không có mã, hệ thống tự hủy hoàn tiền và bạn bấm lấy số khác)*.
4. **Xác thực OTP**: Khi có OTP, ứng dụng tự copy và tự điền vào ô Mã trên web $\rightarrow$ Bấm **Xác thực** trên web để vào biểu mẫu thông tin.
5. **Điền form**: Bấm **`[ Điền Thông Tin ]`** (hoặc nhấn **`Alt + F`**) $\rightarrow$ Tự động điền Họ tên, Vai trò, Bệnh viện, Khoa/Phòng ban, Chức danh và tích Checkbox đồng ý.
6. **Gửi form**: Kiểm tra lại thông tin và bấm **`[ Gửi Form ]`** (hoặc nút Gửi trên web).
7. **Người tiếp theo**: Bấm Back (`Alt + ←`) quay lại trang đầu $\rightarrow$ Bấm `>` (`Alt + N`) để sang người tiếp theo $\rightarrow$ Lặp lại từ Bước 2!

---

## ⌨️ Bảng phím tắt nhanh trên Windows

| Phím tắt | Chức năng |
|---|---|
| **`Alt + F`** | Tự động điền thông tin người hiện tại vào trang web |
| **`Alt + N`** | Chuyển sang người tham dự tiếp theo (**Next**) |
| **`Alt + P`** | Quay lại người tham dự trước đó (**Previous**) |
| **`Alt + ←`** | Quay lại trang trước trên trình duyệt (**Back**) |
| **`Alt + →`** | Tiến tới trang kế tiếp trên trình duyệt (**Forward**) |
| **`F5`** | Tải lại trang web sự kiện (**Reload**) |

*(Xem hướng dẫn chi tiết từng bước và cách xử lý sự cố tại [USER_GUIDE.md](USER_GUIDE.md))*
